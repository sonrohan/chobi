import Foundation

// MARK: - MCP output models

// chobi.list_workspaces
struct MCPWorkspace: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var pathBasename: String
    var isSelected: Bool
    var branch: String?
    var latestRunId: String?
    var latestRunStatus: String?
}

// chobi.get_analysis_summary
struct MCPAnalysisSummary: Codable, Equatable, Sendable {
    var schemaVersion: String
    var source: String
    var workspaceId: String?
    var workspaceName: String
    var runId: String
    var branch: String?
    var riskScore: Int
    var riskFactors: [String]
    var fileCount: Int
    var additions: Int
    var deletions: Int
    var fileClassificationCounts: [String: Int]
    var fileStatusCounts: [String: Int]
    var findingSeverityCounts: [String: Int]
    var symbolCount: Int
    var buckets: [MCPBucket]
    var reviewTargetCount: Int
    var skimTargetCount: Int
    var truncated: Bool
    var nextActions: [String]
}

// chobi.list_changed_files
struct MCPFileSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var path: String
    var status: String
    var classification: String
    var additions: Int
    var deletions: Int
    var findingCount: Int
    var symbolCount: Int
    var bucketIds: [String]
}

struct MCPFileSummaryList: Codable, Equatable, Sendable {
    var schemaVersion: String
    var source: String
    var workspaceId: String?
    var runId: String
    var files: [MCPFileSummary]
    var truncated: Bool
    var nextActions: [String]
}

// chobi.explain_file
struct MCPFileDetail: Codable, Equatable, Sendable {
    var schemaVersion: String
    var source: String
    var id: String
    var path: String
    var status: String
    var classification: String
    var additions: Int
    var deletions: Int
    var hunks: [MCPHunk]
    var symbols: [MCPSymbolRef]
    var findings: [MCPFinding]
    var bucketIds: [String]
    var riskHighlights: [MCPRiskHighlight]
    var truncated: Bool
    var nextActions: [String]
}

struct MCPHunk: Codable, Equatable, Sendable {
    var index: Int
    var oldStart: Int
    var newStart: Int
    var oldLines: Int
    var newLines: Int
    var changedLineRanges: [MCPLineRange]
    var previewLines: [String]
    var truncated: Bool
}

struct MCPLineRange: Codable, Equatable, Sendable {
    var start: Int
    var end: Int
}

struct MCPSymbolRef: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: String
    var startLine: Int
    var endLine: Int
}

struct MCPFinding: Codable, Equatable, Sendable {
    var id: String
    var severity: String
    var category: String
    var message: String
    var lineStart: Int?
    var lineEnd: Int?
    var ruleSource: String
    var evidence: String?
}

struct MCPRiskHighlight: Codable, Equatable, Sendable {
    var id: String
    var severity: String
    var category: String
    var title: String
    var lineStart: Int?
    var lineEnd: Int?
    var evidence: [String]
    var confidence: String
}

// chobi.explain_symbol
struct MCPSymbolDetail: Codable, Equatable, Sendable {
    var schemaVersion: String
    var source: String
    var id: String
    var fileId: String
    var filePath: String?
    var name: String
    var kind: String
    var semanticType: String
    var language: String?
    var semanticArea: String?
    var startLine: Int
    var endLine: Int
    var callers: [String]
    var callees: [String]
    var impactSummary: MCPImpactSummary?
    var contractDeltas: [String: String]
    var behaviorDeltas: [String: String]
    var nextActions: [String]
}

// chobi.get_impact_graph
struct MCPImpactGraph: Codable, Equatable, Sendable {
    var schemaVersion: String
    var source: String
    var symbolId: String
    var symbolName: String
    var filePath: String?
    var startLine: Int
    var endLine: Int
    var summary: MCPImpactSummary
    var callerNodes: [MCPGraphNode]
    var calleeNodes: [MCPGraphNode]
    var unresolvedCalleeNames: [String]
    var edges: [MCPGraphEdge]
    var rootNode: MCPGraphNode?
    var graphSource: String
    var confidence: String
    var nextActions: [String]
}

struct MCPImpactSummary: Codable, Equatable, Sendable {
    var directCallerCount: Int
    var directCalleeCount: Int
    var transitiveCallerCount: Int
    var transitiveCalleeCount: Int
    var fileCount: Int
    var testReferenceCount: Int
    var impactLevel: String
    var confidence: String
}

struct MCPGraphNode: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var filePath: String
    var line: Int?
    var isChangedInPR: Bool
    var isTest: Bool
    var definitionRange: MCPLineRange?
}

struct MCPGraphEdge: Codable, Equatable, Sendable {
    var id: String
    var callerId: String
    var calleeId: String
    var callSiteRange: MCPLineRange?
    var callSitePath: String?
    var confidence: String
    var source: String
}

// chobi.get_review_plan
struct MCPReviewPlan: Codable, Equatable, Sendable {
    var schemaVersion: String
    var source: String
    var runId: String
    var targets: [MCPReviewTarget]
    var buckets: [MCPBucket]
    var riskHighlights: [MCPRiskHighlight]
    var skimTargets: [MCPSkimTarget]
    var truncated: Bool
    var nextActions: [String]
}

struct MCPReviewTarget: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var priority: Int
    var severity: String
    var title: String
    var filePath: String
    var lineStart: Int?
    var lineEnd: Int?
    var reason: String
    var evidence: String
    var source: String
}

struct MCPBucket: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var type: String
    var title: String
    var summary: String
    var files: [String]
    var symbols: [String]
    var riskLevel: String
    var riskReasons: [String]
    var reviewOrder: Int
}

struct MCPSkimTarget: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var filePath: String
    var reason: String
    var classification: String
    var additions: Int
    var deletions: Int
}

// chobi.read_file_range
struct MCPFileRange: Codable, Equatable, Sendable {
    var schemaVersion: String
    var source: String
    var workspaceId: String
    var path: String
    var revision: String
    var startLine: Int
    var endLine: Int
    var lines: [MCPNumberedLine]
    var truncated: Bool
    var nextActions: [String]
}

struct MCPNumberedLine: Codable, Equatable, Sendable {
    var line: Int
    var text: String
}
