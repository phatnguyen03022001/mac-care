import Foundation
import MCP
import MacCareCore

struct ToolHandler: Sendable {
    let service: MacCareService

    func call(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        do {
            switch name {
            case "health_check":
                _ = try requireOnly(arguments, keys: [])
                return try success(try await service.healthCheck())
            case "storage_scan":
                _ = try requireOnly(arguments, keys: [])
                return try success(try await service.storageScan())
            case "process_scan":
                let args = try requireOnly(arguments, keys: ["limit"])
                let limit = try boundedInt(args["limit"], default: 50, range: 1...200)
                return try success(try await service.processScan(limit: limit))
            case "app_scan":
                let args = try requireOnly(arguments, keys: ["limit"])
                let limit = try boundedInt(args["limit"], default: 250, range: 1...250)
                return try success(await service.appScan(limit: limit))
            case "brew_scan":
                _ = try requireOnly(arguments, keys: [])
                return try success(await service.brewScan())
            case "cleanup_plan":
                let args = try requireOnly(arguments, keys: ["max_candidates"])
                let maxCandidates = try boundedInt(args["max_candidates"], default: 200, range: 1...200)
                return try success(try await service.cleanupPlan(maxCandidates: maxCandidates))
            case "cleanup_execute":
                let args = try requireOnly(arguments, keys: ["plan_id", "candidate_ids"])
                let planID = try requiredUUID(args["plan_id"], field: "plan_id")
                let candidateIDs = try requiredUUIDArray(args["candidate_ids"], field: "candidate_ids", maximum: 200)
                let result = try await service.cleanupExecute(
                    planID: planID,
                    candidateIDs: candidateIDs,
                    allowReview: false
                )
                return try success(result)
            case "privacy_self_test":
                _ = try requireOnly(arguments, keys: [])
                return try success(await service.privacySelfTest())
            default:
                return failure("Unsupported Mac Care tool.")
            }
        } catch let error as MCPInputError {
            return failure(error.localizedDescription)
        } catch let error as MacCareError {
            return failure(safeMessage(for: error))
        } catch {
            return failure("Mac Care could not complete this operation.")
        }
    }
}

private extension ToolHandler {
    func requireOnly(_ arguments: [String: Value]?, keys: Set<String>) throws -> [String: Value] {
        let arguments = arguments ?? [:]
        guard Set(arguments.keys).isSubset(of: keys) else {
            throw MCPInputError.invalid("Unexpected input field.")
        }
        return arguments
    }

    func boundedInt(_ value: Value?, default defaultValue: Int, range: ClosedRange<Int>) throws -> Int {
        guard let value else { return defaultValue }
        guard let integer = value.intValue, range.contains(integer) else {
            throw MCPInputError.invalid("Integer input is outside the allowed range.")
        }
        return integer
    }

    func requiredUUID(_ value: Value?, field: String) throws -> String {
        guard let raw = value?.stringValue,
              raw.count <= 64,
              UUID(uuidString: raw) != nil else {
            throw MCPInputError.invalid("\(field) must be a UUID issued by Mac Care.")
        }
        return raw
    }

    func requiredUUIDArray(_ value: Value?, field: String, maximum: Int) throws -> [String] {
        guard let values = value?.arrayValue,
              !values.isEmpty,
              values.count <= maximum else {
            throw MCPInputError.invalid("\(field) must contain 1...\(maximum) candidate UUIDs.")
        }
        return try values.map { item in
            guard let raw = item.stringValue,
                  raw.count <= 64,
                  UUID(uuidString: raw) != nil else {
                throw MCPInputError.invalid("\(field) contains an invalid candidate UUID.")
            }
            return raw
        }
    }

    func success<T: Encodable>(_ value: T) throws -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let text = String(decoding: data, as: UTF8.self)
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    func failure(_ message: String) -> CallTool.Result {
        .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }

    func safeMessage(for error: MacCareError) -> String {
        switch error {
        case .protectedPath:
            "Protected data is inaccessible to Mac Care."
        case .invalidPlan, .stalePlan, .unknownCandidate:
            "Cleanup plan or candidate is invalid, stale, or unknown. Generate a fresh plan."
        case .reviewRequiresHumanApproval:
            "REVIEW candidates require explicit approval in the native Mac Care app."
        case .unsupportedTarget:
            "Cleanup target is not supported."
        case .commandFailed:
            "A trusted fixed system operation failed."
        }
    }
}

enum MCPInputError: LocalizedError, Sendable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}
