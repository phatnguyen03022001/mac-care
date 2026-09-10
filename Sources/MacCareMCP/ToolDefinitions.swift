import MCP
import MacCareCore

struct ToolDefinitions {
    static var all: [Tool] {
        MCPToolCatalog.names.map { name in
            switch name {
            case "health_check":
                Tool(name: name, description: "Inspect filesystem capacity, memory pressure, CPU, uptime, swap, and battery health.", inputSchema: objectSchema())
            case "storage_scan":
                Tool(name: name, description: "Scan only Mac Care supported storage categories and return classified totals.", inputSchema: objectSchema())
            case "process_scan":
                Tool(name: name, description: "Inspect bounded process CPU/RAM usage without argv or environment data.", inputSchema: objectSchema([
                    "limit": integerSchema(minimum: 1, maximum: 200, description: "Maximum process rows")
                ]))
            case "app_scan":
                Tool(name: name, description: "Inventory installed applications plus bounded supporting/background software metadata from fixed system locations. Inventory is read-only and grants no uninstall authority.", inputSchema: objectSchema([
                    "limit": integerSchema(minimum: 1, maximum: 250, description: "Maximum combined application and component rows")
                ]))
            case "brew_scan":
                Tool(name: name, description: "Run fixed read-only Homebrew maintenance inspection.", inputSchema: objectSchema())
            case "cleanup_plan":
                Tool(name: name, description: "Create a short-lived cleanup plan from supported classified candidates.", inputSchema: objectSchema([
                    "max_candidates": integerSchema(minimum: 1, maximum: 200, description: "Maximum cleanup candidates")
                ]))
            case "cleanup_execute":
                Tool(name: name, description: "Execute SAFE candidate IDs from a live Mac Care cleanup plan. REVIEW and PROTECTED items cannot be approved through MCP.", inputSchema: objectSchema([
                    "plan_id": stringSchema(description: "UUID of a live cleanup plan"),
                    "candidate_ids": .object([
                        "type": "array",
                        "minItems": 1,
                        "maxItems": 200,
                        "items": .object(["type": "string", "format": "uuid"])
                    ])
                ], required: ["plan_id", "candidate_ids"]))
            case "privacy_self_test":
                Tool(name: name, description: "Run synthetic privacy-boundary checks without touching protected user data.", inputSchema: objectSchema())
            case "security_audit":
                Tool(name: name, description: "Read macOS security-control status and provide conservative recommendations for installed background items and system extensions. Recommendation does not grant mutation authority.", inputSchema: objectSchema())
            default:
                preconditionFailure("Unknown Mac Care MCP tool catalog entry")
            }
        }
    }

    private static func objectSchema(
        _ properties: [String: Value] = [:],
        required: [String] = []
    ) -> Value {
        var schema: [String: Value] = [
            "type": "object",
            "properties": .object(properties),
            "additionalProperties": false
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        return .object(schema)
    }

    private static func integerSchema(minimum: Int, maximum: Int, description: String) -> Value {
        .object([
            "type": "integer",
            "minimum": .int(minimum),
            "maximum": .int(maximum),
            "description": .string(description)
        ])
    }

    private static func stringSchema(description: String) -> Value {
        .object([
            "type": "string",
            "description": .string(description)
        ])
    }
}
