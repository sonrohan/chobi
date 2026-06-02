import Foundation
import SwiftData

@Model
final class RepositoryEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var path: String
    var autoAnalyzeEnabled: Bool

    init(id: UUID, name: String, path: String, autoAnalyzeEnabled: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.autoAnalyzeEnabled = autoAnalyzeEnabled
    }
}

@Model
final class PullRequestEntity {
    @Attribute(.unique) var id: UUID
    var prNumber: Int
    var title: String
    var body: String?
    var baseSha: String
    var headSha: String
    var author: String
    var status: String
    var repository: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID, prNumber: Int, title: String, body: String?, baseSha: String, headSha: String,
        author: String, status: String, repository: String, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.prNumber = prNumber
        self.title = title
        self.body = body
        self.baseSha = baseSha
        self.headSha = headSha
        self.author = author
        self.status = status
        self.repository = repository
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class AnalysisRunEntity {
    @Attribute(.unique) var id: UUID
    var pullRequestId: UUID
    var baseSha: String
    var headSha: String
    var status: String
    var errorMessage: String?
    var riskScore: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID, pullRequestId: UUID, baseSha: String, headSha: String, status: String,
        errorMessage: String?, riskScore: Int, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.pullRequestId = pullRequestId
        self.baseSha = baseSha
        self.headSha = headSha
        self.status = status
        self.errorMessage = errorMessage
        self.riskScore = riskScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ChangedFileEntity {
    @Attribute(.unique) var id: UUID
    var analysisRunId: UUID
    var path: String
    var status: String
    var additions: Int
    var deletions: Int
    var classification: String
    var hunksData: Data

    var hunks: [DiffHunk] {
        get {
            (try? JSONDecoder().decode([DiffHunk].self, from: hunksData)) ?? []
        }
        set {
            hunksData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        id: UUID, analysisRunId: UUID, path: String, status: String, additions: Int, deletions: Int,
        classification: String, hunks: [DiffHunk]
    ) {
        self.id = id
        self.analysisRunId = analysisRunId
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.classification = classification
        self.hunksData = (try? JSONEncoder().encode(hunks)) ?? Data()
    }
}

@Model
final class ChangedSymbolEntity {
    @Attribute(.unique) var id: UUID
    var analysisRunId: UUID
    var changedFileId: UUID
    var name: String
    var kind: String
    var startLine: Int
    var endLine: Int
    var callers: [String]
    var callees: [String]
    var semanticType: String
    var metadata: [String: String]

    init(
        id: UUID, analysisRunId: UUID, changedFileId: UUID, name: String, kind: String,
        startLine: Int,
        endLine: Int, callers: [String], callees: [String], semanticType: String,
        metadata: [String: String]
    ) {
        self.id = id
        self.analysisRunId = analysisRunId
        self.changedFileId = changedFileId
        self.name = name
        self.kind = kind
        self.startLine = startLine
        self.endLine = endLine
        self.callers = callers
        self.callees = callees
        self.semanticType = semanticType
        self.metadata = metadata
    }
}

@Model
final class SymbolGraphNodeEntity {
    @Attribute(.unique) var id: String
    var analysisRunId: UUID
    var identityData: Data
    var definitionData: Data?
    var isChangedInPR: Bool
    var isTest: Bool
    var confidence: String

    var identity: SymbolIdentity {
        get {
            (try? JSONDecoder().decode(SymbolIdentity.self, from: identityData))
                ?? SymbolIdentity(
                    id: id,
                    scipSymbol: nil,
                    fallbackKey: id,
                    displayName: id,
                    qualifiedName: nil,
                    kind: .function
                )
        }
        set {
            identityData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var definition: SymbolLocation? {
        get {
            guard let definitionData else { return nil }
            return try? JSONDecoder().decode(SymbolLocation.self, from: definitionData)
        }
        set {
            definitionData = try? newValue.map { try JSONEncoder().encode($0) }
        }
    }

    init(
        analysisRunId: UUID,
        node: SymbolGraphNode
    ) {
        self.id = "\(analysisRunId.uuidString)::\(node.id)"
        self.analysisRunId = analysisRunId
        self.identityData = (try? JSONEncoder().encode(node.identity)) ?? Data()
        self.definitionData = try? node.definition.map { try JSONEncoder().encode($0) }
        self.isChangedInPR = node.isChangedInPR
        self.isTest = node.isTest
        self.confidence = node.confidence.rawValue
    }
}

@Model
final class SymbolGraphEdgeEntity {
    @Attribute(.unique) var id: String
    var analysisRunId: UUID
    var edgeId: String
    var callerId: String
    var calleeId: String
    var callSiteData: Data?
    var confidence: String
    var source: String

    var callSite: SymbolLocation? {
        get {
            guard let callSiteData else { return nil }
            return try? JSONDecoder().decode(SymbolLocation.self, from: callSiteData)
        }
        set {
            callSiteData = try? newValue.map { try JSONEncoder().encode($0) }
        }
    }

    init(
        analysisRunId: UUID,
        edge: SymbolGraphEdge
    ) {
        self.id = "\(analysisRunId.uuidString)::\(edge.id)"
        self.analysisRunId = analysisRunId
        self.edgeId = edge.id
        self.callerId = edge.callerId
        self.calleeId = edge.calleeId
        self.callSiteData = try? edge.callSite.map { try JSONEncoder().encode($0) }
        self.confidence = edge.confidence.rawValue
        self.source = edge.source.rawValue
    }
}

@Model
final class SymbolIndexMetadataEntity {
    @Attribute(.unique) var id: UUID
    var analysisRunId: UUID
    var repositoryKey: String
    var revision: String?
    var indexSource: String
    var indexedDocumentCount: Int
    var graphBuildTimestamp: Date
    var diagnostics: [String]
    var fallbackReason: String?

    init(
        id: UUID = UUID(),
        analysisRunId: UUID,
        repositoryKey: String,
        revision: String?,
        indexSource: String,
        indexedDocumentCount: Int,
        graphBuildTimestamp: Date = Date(),
        diagnostics: [String],
        fallbackReason: String?
    ) {
        self.id = id
        self.analysisRunId = analysisRunId
        self.repositoryKey = repositoryKey
        self.revision = revision
        self.indexSource = indexSource
        self.indexedDocumentCount = indexedDocumentCount
        self.graphBuildTimestamp = graphBuildTimestamp
        self.diagnostics = diagnostics
        self.fallbackReason = fallbackReason
    }
}

@Model
final class FindingEntity {
    @Attribute(.unique) var id: UUID
    var analysisRunId: UUID
    var changedFileId: UUID
    var severity: String
    var category: String
    var message: String
    var lineStart: Int?
    var lineEnd: Int?
    var ruleSource: String
    var evidence: String?

    init(
        id: UUID, analysisRunId: UUID, changedFileId: UUID, severity: String, category: String,
        message: String, lineStart: Int?, lineEnd: Int?, ruleSource: String, evidence: String?
    ) {
        self.id = id
        self.analysisRunId = analysisRunId
        self.changedFileId = changedFileId
        self.severity = severity
        self.category = category
        self.message = message
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.ruleSource = ruleSource
        self.evidence = evidence
    }
}
