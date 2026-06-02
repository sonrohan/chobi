import Foundation

// MARK: - Internal plumbing types used by AgentContextQueryService and AppState

enum AgentContextDetailLevel: String, Codable, CaseIterable, Sendable {
    case summary
    case standard
    case full
}

struct AgentContextOptions: Codable, Equatable, Sendable {
    var detailLevel: AgentContextDetailLevel
    var includeFiles: Bool
    var includeSymbols: Bool
    var maxItems: Int

    nonisolated init(
        detailLevel: AgentContextDetailLevel = .standard,
        includeFiles: Bool = true,
        includeSymbols: Bool = false,
        maxItems: Int = 30
    ) {
        self.detailLevel = detailLevel
        self.includeFiles = includeFiles
        self.includeSymbols = includeSymbols
        self.maxItems = max(1, maxItems)
    }
}

enum AgentContextErrorCode: String, Codable, Sendable {
    case workspaceNotSelected = "workspace_not_selected"
    case analysisNotReady = "analysis_not_ready"
    case runNotFound = "run_not_found"
    case fileNotFound = "file_not_found"
    case symbolNotFound = "symbol_not_found"
    case lineRangeTooLarge = "line_range_too_large"
    case pathOutsideWorkspace = "path_outside_workspace"
    case profileNotFound = "profile_not_found"
    case unsupportedQuery = "unsupported_query"
    case invalidArguments = "invalid_arguments"
    case invalidToken = "invalid_token"
}

struct AgentContextError: Error, Codable, Equatable, Sendable {
    var code: AgentContextErrorCode
    var message: String
}

struct AgentContextSnapshot: Sendable {
    var repositories: [GitRepository]
    var selectedRepoId: UUID?
    var selectedBranch: String?
    var selectedCommitSha: String?
    var currentDetails: AnalysisDetails?
    var pullRequests: [PullRequest]
}

@MainActor
protocol AgentContextSnapshotProviding: AnyObject {
    func agentContextSnapshot() -> AgentContextSnapshot
}
