import Darwin
import Foundation
import MCP
import MacCareCore

@main
enum MacCareMCPMain {
    static func main() async {
        do {
            let service = MacCareService()
            let handler = ToolHandler(service: service)
            let server = Server(
                name: "mac-care",
                version: "0.1.0",
                title: "Mac Care",
                instructions: "Local-only macOS health and maintenance tools with a hard privacy boundary. No shell or arbitrary file access.",
                capabilities: .init(tools: .init(listChanged: false))
            )

            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: ToolDefinitions.all)
            }

            await server.withMethodHandler(CallTool.self) { params in
                await handler.call(name: params.name, arguments: params.arguments)
            }

            let transport = StdioTransport()
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
        } catch {
            let message = Data("mac-care-mcp failed to start.\n".utf8)
            try? FileHandle.standardError.write(contentsOf: message)
            Darwin.exit(1)
        }
    }
}
