import Foundation

struct MCPToolRegistration: Codable, Equatable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var description: String
    var inputSchema: [String: String]
}

struct MCPRouteResult: Codable, Equatable, Sendable {
    var content: [[String: String]]
    var isError: Bool?
}

actor MCPRequestRouter {
    private let queryService: AgentContextQueryService
    private let encoder: JSONEncoder

    init(queryService: AgentContextQueryService) {
        self.queryService = queryService
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    // MARK: - Tool Registry

    nonisolated static let tools: [MCPToolRegistration] = [
        MCPToolRegistration(
            name: "chobi.list_workspaces",
            description: "List registered Chobi workspaces and latest analysis run status.",
            inputSchema: ["includeInactive": "boolean"]
        ),
        MCPToolRegistration(
            name: "chobi.get_analysis_summary",
            description:
                "Return a compact summary of the current or a specific analysis run: risk score, file counts, bucket breakdown, and top risk factors.",
            inputSchema: ["runId": "string?"]
        ),
        MCPToolRegistration(
            name: "chobi.list_changed_files",
            description:
                "Return the list of changed files with classification, line counts, finding counts, and bucket membership.",
            inputSchema: [
                "runId": "string?", "minSeverity": "info|low|medium|high", "maxItems": "integer",
            ]
        ),
        MCPToolRegistration(
            name: "chobi.explain_file",
            description:
                "Return full context for a changed file: diff hunks, symbols, findings, risk highlights, and bucket membership.",
            inputSchema: [
                "runId": "string?",
                "path": "string",
                "includeHunks": "boolean",
                "includeSymbols": "boolean",
                "includeFindings": "boolean",
                "maxHunkLines": "integer",
            ]
        ),
        MCPToolRegistration(
            name: "chobi.explain_symbol",
            description:
                "Return context for a changed symbol: callers, callees, impact summary, contract deltas, and behavior deltas.",
            inputSchema: [
                "runId": "string?",
                "path": "string?",
                "symbolName": "string",
                "line": "integer?",
                "includeCallers": "boolean",
                "includeCallees": "boolean",
            ]
        ),
        MCPToolRegistration(
            name: "chobi.get_impact_graph",
            description:
                "Return the call graph for a changed symbol: direct callers, callees, per-node file and test metadata, and an impact level summary.",
            inputSchema: [
                "runId": "string?",
                "symbolName": "string",
                "path": "string?",
                "line": "integer?",
            ]
        ),
        MCPToolRegistration(
            name: "chobi.get_review_plan",
            description:
                "Return ordered review targets, change buckets, risk highlights, and skim targets.",
            inputSchema: ["runId": "string?", "focus": "string", "maxItems": "integer"]
        ),
        MCPToolRegistration(
            name: "chobi.read_file_range",
            description: "Read a bounded line range from a workspace file.",
            inputSchema: [
                "workspaceId": "string?",
                "path": "string",
                "startLine": "integer",
                "endLine": "integer",
                "revision": "working|base|head",
            ]
        ),
    ]

    func listTools() -> [MCPToolRegistration] {
        Self.tools
    }

    // MARK: - Tool Dispatch

    func callTool(name: String, arguments: [String: Any]) async -> MCPRouteResult {
        do {
            switch name {
            case "chobi.list_workspaces":
                return try success(
                    await queryService.listWorkspaces(
                        includeInactive: bool(arguments, "includeInactive", default: true)))

            case "chobi.get_analysis_summary":
                return try success(
                    await queryService.getAnalysisSummary(
                        runId: optionalUUID(arguments, "runId")))

            case "chobi.list_changed_files":
                let sev = optionalSeverity(arguments, "minSeverity")
                return try success(
                    await queryService.listChangedFiles(
                        runId: optionalUUID(arguments, "runId"),
                        minSeverity: sev,
                        maxItems: int(arguments, "maxItems", default: 50)
                    ))

            case "chobi.explain_file":
                return try success(
                    await queryService.explainFile(
                        runId: optionalUUID(arguments, "runId"),
                        path: requiredString(arguments, "path"),
                        includeHunks: bool(arguments, "includeHunks", default: true),
                        includeSymbols: bool(arguments, "includeSymbols", default: true),
                        includeFindings: bool(arguments, "includeFindings", default: true),
                        maxHunkLines: int(arguments, "maxHunkLines", default: 120)
                    ))

            case "chobi.explain_symbol":
                return try success(
                    await queryService.explainSymbol(
                        runId: optionalUUID(arguments, "runId"),
                        path: optionalString(arguments, "path"),
                        symbolName: requiredString(arguments, "symbolName"),
                        line: optionalInt(arguments, "line"),
                        includeCallers: bool(arguments, "includeCallers", default: true),
                        includeCallees: bool(arguments, "includeCallees", default: true)
                    ))

            case "chobi.get_impact_graph":
                return try success(
                    await queryService.getImpactGraph(
                        runId: optionalUUID(arguments, "runId"),
                        symbolName: requiredString(arguments, "symbolName"),
                        path: optionalString(arguments, "path"),
                        line: optionalInt(arguments, "line")
                    ))

            case "chobi.get_review_plan":
                return try success(
                    await queryService.getReviewPlan(
                        runId: optionalUUID(arguments, "runId"),
                        focus: string(arguments, "focus", default: "all"),
                        maxItems: int(arguments, "maxItems", default: 30)
                    ))

            case "chobi.read_file_range":
                return try success(
                    await queryService.readFileRange(
                        workspaceId: optionalUUID(arguments, "workspaceId"),
                        path: requiredString(arguments, "path"),
                        startLine: int(arguments, "startLine", default: 1),
                        endLine: int(arguments, "endLine", default: 1),
                        revision: string(arguments, "revision", default: "working")
                    ))

            default:
                throw AgentContextError(
                    code: .unsupportedQuery, message: "Unknown MCP tool: \(name)")
            }
        } catch let error as AgentContextError {
            return errorResult(error)
        } catch {
            return errorResult(
                AgentContextError(code: .invalidArguments, message: error.localizedDescription))
        }
    }

    // MARK: - Result helpers

    private func errorResult(_ error: AgentContextError) -> MCPRouteResult {
        let payload: [String: Any] = [
            "schemaVersion": AgentContextBuilder.schemaVersion,
            "source": "chobi",
            "errorCode": error.code.rawValue,
            "message": error.message,
        ]
        return MCPRouteResult(
            content: [["type": "text", "text": jsonText(payload)]], isError: true)
    }

    private func success<T: Encodable>(_ value: T) throws -> MCPRouteResult {
        MCPRouteResult(content: [["type": "text", "text": try encodeText(value)]])
    }

    private func encodeText<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonText(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    // MARK: - Argument helpers

    private func requiredString(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty else {
            throw AgentContextError(code: .invalidArguments, message: "\(key) is required.")
        }
        return value
    }

    private func optionalString(_ args: [String: Any], _ key: String) -> String? {
        args[key] as? String
    }

    private func string(_ args: [String: Any], _ key: String, default defaultValue: String)
        -> String
    {
        optionalString(args, key) ?? defaultValue
    }

    private func bool(_ args: [String: Any], _ key: String, default defaultValue: Bool) -> Bool {
        args[key] as? Bool ?? defaultValue
    }

    private func int(_ args: [String: Any], _ key: String, default defaultValue: Int) -> Int {
        if let value = args[key] as? Int { return value }
        if let value = args[key] as? Double { return Int(value) }
        return defaultValue
    }

    private func optionalInt(_ args: [String: Any], _ key: String) -> Int? {
        guard args[key] != nil else { return nil }
        return int(args, key, default: 0)
    }

    private func requiredUUID(_ args: [String: Any], _ key: String) throws -> UUID {
        guard let uuid = UUID(uuidString: try requiredString(args, key)) else {
            throw AgentContextError(code: .invalidArguments, message: "\(key) must be a UUID.")
        }
        return uuid
    }

    private func optionalUUID(_ args: [String: Any], _ key: String) throws -> UUID? {
        guard let value = optionalString(args, key), !value.isEmpty else { return nil }
        guard let uuid = UUID(uuidString: value) else {
            throw AgentContextError(code: .invalidArguments, message: "\(key) must be a UUID.")
        }
        return uuid
    }

    private func optionalSeverity(_ args: [String: Any], _ key: String) -> Severity? {
        guard let raw = optionalString(args, key) else { return nil }
        return Severity(rawValue: raw)
    }
}
