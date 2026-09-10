# Mac Care

Mac Care is a lightweight native macOS maintenance and health application. It provides deterministic inspection and bounded cleanup without becoming a generic remote shell or requiring privileged access.

## Features

- Native SwiftUI application with Overview, Cleanup, Applications, Processes, Homebrew, and Privacy views.
- Health inspection for disk capacity, memory pressure, physical memory, swap, CPU utilization, uptime, and battery signals when available.
- Storage analysis limited to supported cache, log, trash, developer, and package-manager categories.
- Process inspection with PID, name, CPU, RSS, and uptime; command-line arguments and environment variables are not returned.
- Installed Software Inventory through `app_scan`: visible applications plus bounded supporting/background components from fixed application, Application Support, launchd, login/background-item, system-extension, and Homebrew sources.
- Homebrew inspection for version, outdated formulae/casks, cleanup preview, unused dependencies, and cache size.
- Cleanup planning and execution with explicit risk classification and candidate IDs.
- A constrained stdio MCP server exposing only semantic Mac Care capabilities.

## Architecture

`MacCareCore` owns scanners, classification, privacy policy, cleanup planning, and cleanup execution. `MacCareApp` is the native SwiftUI adapter. `MacCareMCP` is a thin MCP adapter over the same core logic.

System commands are fixed executable/argument combinations. Homebrew is resolved only from supported trusted locations, and child process stdin is isolated from MCP protocol stdin.
## Cleanup safety model

Cleanup follows `SCAN → CLASSIFY → PLAN → APPROVE → EXECUTE → VERIFY`.

- `SAFE`: regenerable, well-understood disposable data. Eligible for bounded direct deletion after selection.
- `REVIEW`: potentially user-significant data. Requires explicit approval in the native app; filesystem items are moved to Trash where appropriate.
- `PROTECTED`: inaccessible to cleanup. There is no override in v0.1.0.

Execution accepts only candidate IDs from a live Mac Care plan. Every candidate is re-resolved and its path is revalidated before mutation. The MCP surface cannot approve REVIEW candidates and never accepts arbitrary cleanup paths.

## Privacy boundary

Privacy checks run before filesystem traversal and validate both normalized paths and symlink-resolved destinations. Mac Care blocks Photos libraries/containers, Keychains, SSH and cloud credentials, browser authentication/session stores, password-manager locations, and other sensitive paths defined by `PrivacyPolicy`.

Mac Care does not read the clipboard, shell histories, process environments, credentials, or tokens. It does not automate Photos.app and does not require sudo, Full Disk Access, Accessibility, or Apple Events automation.

Privacy tests use synthetic fixtures and path-level rejection only; they do not inspect real protected user data.
## MCP

The stdio server exposes exactly these tools:

- `health_check`
- `storage_scan`
- `process_scan`
- `app_scan`
- `brew_scan`
- `cleanup_plan`
- `cleanup_execute`
- `privacy_self_test`

Inputs are bounded JSON schemas with `additionalProperties=false`. There is no generic shell, command execution, arbitrary file read/write, delete, find, or filesystem traversal tool.

`app_scan` is metadata-only and uses implementation-owned roots. It preserves visible application name, bundle ID, version, approximate installed size, and Spotlight last-used signal, while also reporting bounded nested apps/helpers, LaunchAgents/Daemons, login/background items, system extensions, and Homebrew formulae/casks/services. Inventory items are never automatic `SAFE` cleanup candidates: ordinary software is `REVIEW`, existing privacy boundaries remain `PROTECTED`, and inventory is not fed into `cleanup_plan`. Platform sources are best-effort and expose `AVAILABLE`/`PARTIAL`/`UNAVAILABLE` status instead of failing the whole scan. `app_scan` grants no uninstall or service-lifecycle authority.

Build and start the MCP server:

```sh
swift build -c release --product mac-care-mcp
.build/release/mac-care-mcp
```

The process uses stdin/stdout exclusively for MCP JSON-RPC framing. Subprocess output is captured or discarded and never inherits MCP protocol stdout.
## Build and run

Requirements: macOS 14 or later, Xcode/Swift toolchain, and Swift Package Manager.

```sh
swift test
swift build
swift build -c release
./scripts/build-app.sh
open build/MacCare.app
```

`build-app.sh` derives `AppIcon.icns` from the supplied 512×512 artwork, packages the native executable, and applies an ad-hoc development signature.

Run the bounded MCP smoke test with:

```sh
python3 scripts/mcp-smoke.py
```

## Known v0.1 limitations

Mac Care scans only explicitly supported locations instead of crawling the entire home directory. Installed Software Inventory is bounded and best-effort, so a global result limit can truncate later sources while reporting that source as partial. Application "last used" data is only a recommendation signal and depends on Spotlight metadata. Battery fields vary by hardware. Process management, automatic app uninstall, privileged cleanup, arbitrary filesystem cleanup, and PROTECTED overrides are intentionally absent. Homebrew support requires Homebrew in a supported standard installation location.

## Agent maintenance policy

Direct ChatGPT, Executor, and authorized local-tool maintenance operations are governed by [`RULES.md`](./RULES.md), the canonical operator safety policy for this repository.

The policy applies whether maintenance is performed through:

- the Mac Care MCP;
- Agent Runtime;
- Remote Desktop Commander;
- another explicitly authorized local execution surface.

The executable's existing privacy and cleanup protections remain implementation-level defense; `RULES.md` defines the broader operator authority and boundaries.
