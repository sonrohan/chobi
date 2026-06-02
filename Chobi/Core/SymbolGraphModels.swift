import Foundation

struct SymbolIdentity: Codable, Hashable, Sendable {
    var id: String
    var scipSymbol: String?
    var fallbackKey: String
    var displayName: String
    var qualifiedName: String?
    var kind: ChangedSymbol.SymbolKind
}

struct SymbolLocation: Codable, Hashable, Sendable {
    var filePath: String
    var startLine: Int
    var startColumn: Int?
    var endLine: Int
    var endColumn: Int?

    nonisolated func contains(line: Int, column: Int? = nil) -> Bool {
        guard startLine <= line, line <= endLine else { return false }
        guard let column else { return true }
        if line == startLine, let startColumn, column < startColumn { return false }
        if line == endLine, let endColumn, column > endColumn { return false }
        return true
    }

    nonisolated func overlaps(startLine otherStart: Int, endLine otherEnd: Int) -> Bool {
        startLine <= otherEnd && otherStart <= endLine
    }
}

struct SymbolGraphNode: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var identity: SymbolIdentity
    var definition: SymbolLocation?
    var isChangedInPR: Bool
    var isTest: Bool
    var confidence: GraphConfidence
}

struct SymbolGraphEdge: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var callerId: String
    var calleeId: String
    var callSite: SymbolLocation?
    var confidence: GraphConfidence
    var source: GraphEdgeSource
}

enum GraphEdgeSource: String, Codable, Sendable {
    case scip
    case treeSitterFallback
}

enum GraphConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

enum SymbolIndexStatus: Codable, Hashable, Sendable {
    case available(path: String)
    case unavailable(reason: String)
    case failed(reason: String)

    nonisolated var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    nonisolated var reason: String? {
        switch self {
        case .available:
            return nil
        case .unavailable(let reason), .failed(let reason):
            return reason
        }
    }
}

struct SymbolIndex: Codable, Hashable, Sendable {
    var sourcePath: String
    var documents: [IndexedDocument]

    nonisolated var definitionsBySymbol: [String: IndexedSymbolDefinition] {
        var result: [String: IndexedSymbolDefinition] = [:]
        for document in documents {
            for symbol in document.symbols {
                result[symbol.symbol] = symbol
            }
        }
        return result
    }
}

struct IndexedDocument: Codable, Hashable, Sendable {
    var relativePath: String
    var occurrences: [IndexedOccurrence]
    var symbols: [IndexedSymbolDefinition]
}

struct IndexedOccurrence: Codable, Hashable, Sendable {
    var symbol: String
    var range: SymbolLocation
    var isDefinition: Bool
}

struct IndexedSymbolDefinition: Codable, Hashable, Sendable {
    var symbol: String
    var displayName: String
    var kind: ChangedSymbol.SymbolKind
    var location: SymbolLocation
}

struct SymbolGraphResult: Codable, Hashable, Sendable {
    var nodes: [SymbolGraphNode]
    var edges: [SymbolGraphEdge]
    var source: GraphEdgeSource
    var confidence: GraphConfidence
    var diagnostics: [String]
}

struct ImpactGraphEnrichment: Codable, Hashable, Sendable {
    var symbols: [ChangedSymbol]
    var graph: SymbolGraphResult
    var trackedFilesCount: Int
    var indexedFilesCount: Int
}
