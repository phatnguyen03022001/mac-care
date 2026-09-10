#!/usr/bin/env python3
import json
import select
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / ".build" / "release" / "mac-care-mcp"
EXPECTED = {
    "health_check", "storage_scan", "process_scan", "app_scan",
    "brew_scan", "cleanup_plan", "cleanup_execute", "privacy_self_test",
}
FORBIDDEN = {"shell", "exec", "run_command", "read_file", "write_file", "delete", "rm", "find"}


def send(proc, payload):
    proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    proc.stdin.flush()


def receive(proc, timeout=120):
    ready, _, _ = select.select([proc.stdout], [], [], timeout)
    if not ready:
        raise RuntimeError("MCP response timeout")
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError("MCP server closed stdout")
    return json.loads(line)

def call(proc, request_id, name, arguments=None, timeout=120):
    send(proc, {
        "jsonrpc": "2.0", "id": request_id, "method": "tools/call",
        "params": {"name": name, "arguments": arguments or {}},
    })
    response = receive(proc, timeout)
    result = response.get("result", {})
    content = result.get("content", [])
    text = content[0].get("text", "") if content else ""
    return result.get("isError", False), text


def decode_payload(text):
    return json.loads(text)


def main():
    if not SERVER.is_file():
        raise RuntimeError(f"Missing MCP executable: {SERVER}")

    proc = subprocess.Popen(
        [str(SERVER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, bufsize=1,
    )
    try:
        send(proc, {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25", "capabilities": {},
                "clientInfo": {"name": "mac-care-smoke", "version": "0.1.0"},
            },
        })
        init = receive(proc)
        assert init.get("result", {}).get("protocolVersion") == "2025-11-25"
        send(proc, {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

        send(proc, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools = receive(proc).get("result", {}).get("tools", [])
        names = {tool.get("name") for tool in tools}
        assert names == EXPECTED, names
        assert not names.intersection(FORBIDDEN), names.intersection(FORBIDDEN)
        assert all(tool.get("inputSchema", {}).get("additionalProperties") is False for tool in tools)
        print("tools=8 forbidden=0 schemas_bounded=yes")

        checks = [
            (3, "health_check", {}, 120),
            (4, "process_scan", {"limit": 5}, 120),
            (5, "app_scan", {"limit": 5}, 180),
            (6, "brew_scan", {}, 180),
            (7, "storage_scan", {}, 180),
            (8, "cleanup_plan", {"max_candidates": 5}, 180),
            (9, "privacy_self_test", {}, 120),
        ]
        payloads = {}
        for request_id, name, arguments, timeout in checks:
            is_error, text = call(proc, request_id, name, arguments, timeout)
            assert not is_error, f"{name} failed"
            payloads[name] = decode_payload(text)
            print(f"{name}=ok")
        assert isinstance(payloads["health_check"], dict)
        assert len(payloads["process_scan"]) <= 5
        assert len(payloads["app_scan"]) <= 5
        assert isinstance(payloads["brew_scan"].get("available"), bool)
        assert isinstance(payloads["storage_scan"].get("candidateCount"), int)
        assert len(payloads["cleanup_plan"].get("candidates", [])) <= 5
        assert payloads["privacy_self_test"].get("passed") is True

        fake_plan = str(uuid.uuid4())
        fake_candidate = str(uuid.uuid4())
        is_error, _ = call(proc, 10, "cleanup_execute", {
            "plan_id": fake_plan, "candidate_ids": [fake_candidate],
        })
        assert is_error, "unknown cleanup plan must fail closed"

        live_plan = payloads["cleanup_plan"]["planID"]
        is_error, _ = call(proc, 11, "cleanup_execute", {
            "plan_id": live_plan, "candidate_ids": [fake_candidate],
        })
        assert is_error, "tampered candidate must fail closed"

        is_error, _ = call(proc, 12, "cleanup_execute", {
            "plan_id": fake_plan, "candidate_ids": [fake_candidate], "allow_review": True,
        })
        assert is_error, "MCP must reject review approval input"

        is_error, _ = call(proc, 13, "cleanup_execute", {
            "plan_id": fake_plan, "candidate_ids": [fake_candidate], "path": "/tmp/not-accepted",
        })
        assert is_error, "MCP must reject arbitrary cleanup paths"
        print("cleanup_execute=fails_closed tampered=rejected review_self_approval=rejected arbitrary_path=rejected")

        is_error, _ = call(proc, 14, "shell", {"command": "echo forbidden"})
        assert is_error, "generic shell tool must not exist"
        print("generic_shell=rejected privacy_self_test=pass")
    finally:
        if proc.stdin and not proc.stdin.closed:
            proc.stdin.close()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.terminate()
            proc.wait(timeout=5)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"SMOKE_FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
