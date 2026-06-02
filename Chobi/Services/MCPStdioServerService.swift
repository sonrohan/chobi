import Foundation

enum MCPStdioServerService {
    static func run() async {
        let persistence = PersistenceService()
        let snapshotProvider = await MainActor.run { AppState() }
        await snapshotProvider.load(persistence: persistence)
        let queryService = AgentContextQueryService(
            stateProvider: snapshotProvider,
            persistence: persistence
        )
        let router = MCPRequestRouter(queryService: queryService)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: input, encoding: .utf8) else { return }

        let requests = text.split(whereSeparator: \.isNewline).map(String.init)
        for requestText in requests where !requestText.trimmingCharacters(in: .whitespaces).isEmpty
        {
            let response = await handle(requestText: requestText, router: router)
            write(response)
        }
    }

    private static func handle(requestText: String, router: MCPRequestRouter) async -> [String: Any]
    {
        guard let data = requestText.data(using: .utf8),
            let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return jsonRpcError(id: nil, code: -32700, message: "Invalid JSON-RPC request.")
        }

        let id = request["id"]
        guard let method = request["method"] as? String else {
            return jsonRpcError(id: id, code: -32600, message: "Missing JSON-RPC method.")
        }

        do {
            let result: Any
            switch method {
            case "initialize":
                let appVersion = Bundle.main.appVersion
                result = [
                    "protocolVersion": "2025-06-18",
                    "serverInfo": ["name": "chobi", "version": appVersion],
                    "capabilities": [
                        "tools": [:]
                    ],
                ]
            case "tools/list":
                result = ["tools": encodableObject(await router.listTools())]
            case "tools/call":
                let params = request["params"] as? [String: Any] ?? [:]
                guard let name = params["name"] as? String else {
                    throw AgentContextError(
                        code: .invalidArguments, message: "Tool name is required.")
                }
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                let routed = await router.callTool(name: name, arguments: arguments)
                result = [
                    "content": routed.content,
                    "isError": routed.isError ?? false,
                ]
            default:
                return jsonRpcError(id: id, code: -32601, message: "Unsupported method: \(method)")
            }
            return ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        } catch let error as AgentContextError {
            return jsonRpcError(id: id, code: -32602, message: error.code.rawValue)
        } catch {
            return jsonRpcError(id: id, code: -32603, message: error.localizedDescription)
        }
    }

    private static func encodableObject<T: Encodable>(_ value: T) -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return [:]
        }
        return object
    }

    private static func jsonRpcError(id: Any?, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message,
            ],
        ]
    }

    private static func write(_ response: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: []),
            let text = String(data: data, encoding: .utf8)
        else { return }
        FileHandle.standardOutput.write(Data("\(text)\n".utf8))
    }
}

// MARK: - Lightweight AppState for MCP stdio mode

extension AppState {
    /// Loads repositories and the most recent completed analysis from persistence.
    /// Used only in the MCP stdio subprocess — not in the GUI app.
    func load(persistence: PersistenceService) async {
        repositories = await persistence.allRepositories()
        selectedRepoId = repositories.first?.id
        pullRequests = await persistence.allPullRequests()

        guard let repo = selectedRepo else { return }
        let latestRun =
            pullRequests
            .compactMap(\.latestRun)
            .sorted { $0.createdAt > $1.createdAt }
            .first
        if let run = latestRun {
            let profile = AnalysisProfileStore.load(repoPath: repo.path)
            analysisDetails = await persistence.getAnalysisDetails(
                runId: run.id, profile: profile)
        }
    }
}
