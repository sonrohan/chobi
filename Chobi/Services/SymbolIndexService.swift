import Foundation

protocol SymbolIndexServiceProtocol: Sendable {
    func indexStatus(repoPath: String, revision: String?) async -> SymbolIndexStatus
    func loadIndex(repoPath: String, revision: String?) async throws -> SymbolIndex
    func symbolGraph(
        for changedSymbols: [ChangedSymbol],
        filesById: [UUID: ChangedFile],
        repoPath: String,
        revision: String?
    ) async throws -> SymbolGraphResult
}

enum SymbolIndexError: Error {
    case unavailable(String)
}

actor SymbolIndexService: SymbolIndexServiceProtocol {
    private let provider: SCIPIndexProvider
    private var cache: [String: SymbolIndex] = [:]

    init(provider: SCIPIndexProvider) {
        self.provider = provider
    }

    func indexStatus(repoPath: String, revision: String?) async -> SymbolIndexStatus {
        provider.indexStatus(repoPath: repoPath, revision: revision)
    }

    func loadIndex(repoPath: String, revision: String?) async throws -> SymbolIndex {
        let key = "\(repoPath)#\(revision ?? "working")"
        if let cached = cache[key] { return cached }
        let index = try provider.loadIndex(repoPath: repoPath, revision: revision)
        cache[key] = index
        return index
    }

    func symbolGraph(
        for changedSymbols: [ChangedSymbol],
        filesById: [UUID: ChangedFile],
        repoPath: String,
        revision: String?
    ) async throws -> SymbolGraphResult {
        let index = try await loadIndex(repoPath: repoPath, revision: revision)
        return SCIPGraphBuilder(index: index, filesById: filesById).build(for: changedSymbols)
    }
}

struct SCIPIndexProvider: Sendable {
    nonisolated func indexStatus(repoPath: String, revision: String?) -> SymbolIndexStatus {
        guard revision == nil || revision?.isEmpty == true else {
            return .unavailable(
                reason: "SCIP indexes are currently consumed from the working tree only.")
        }
        guard let path = indexPath(repoPath: repoPath) else {
            return .unavailable(reason: "No SCIP index found at .scip/index.scip or index.scip.")
        }
        return .available(path: path.path)
    }

    nonisolated func loadIndex(repoPath: String, revision: String?) throws -> SymbolIndex {
        guard revision == nil || revision?.isEmpty == true else {
            throw SymbolIndexError.unavailable(
                "SCIP indexes are currently consumed from the working tree only.")
        }
        guard let path = indexPath(repoPath: repoPath) else {
            throw SymbolIndexError.unavailable("No SCIP index found.")
        }
        let data = try Data(contentsOf: path)
        let documents = try SCIPProtobufReader.decodeDocuments(from: data)
        guard !documents.isEmpty else {
            throw SymbolIndexError.unavailable("SCIP index did not contain readable documents.")
        }
        return SymbolIndex(sourcePath: path.path, documents: documents)
    }

    nonisolated private func indexPath(repoPath: String) -> URL? {
        let root = URL(fileURLWithPath: repoPath)
        let candidates = [
            root.appendingPathComponent(".scip/index.scip"),
            root.appendingPathComponent("index.scip"),
        ]
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }
}

private struct SCIPGraphBuilder {
    let index: SymbolIndex
    let filesById: [UUID: ChangedFile]

    nonisolated func build(for changedSymbols: [ChangedSymbol]) -> SymbolGraphResult {
        let changedPaths = Set(filesById.values.map(\.path))
        let definitions = index.definitionsBySymbol
        let documentsByPath = Dictionary(
            uniqueKeysWithValues: index.documents.map { ($0.relativePath, $0) })
        var nodesById: [String: SymbolGraphNode] = [:]
        var edgesById: [String: SymbolGraphEdge] = [:]
        var diagnostics: [String] = []

        for symbol in changedSymbols {
            guard let filePath = filesById[symbol.changedFileId]?.path else { continue }
            guard let definition = matchDefinition(symbol: symbol, filePath: filePath) else {
                diagnostics.append("No SCIP definition match for \(filePath):\(symbol.name)")
                continue
            }

            let root = node(
                definition: definition,
                fallbackKey: fallbackKey(symbol: symbol, filePath: filePath),
                isChangedInPR: true,
                changedPaths: changedPaths,
                confidence: .high
            )
            nodesById[root.id] = root

            for document in index.documents {
                for occurrence in document.occurrences
                where occurrence.symbol == definition.symbol && !occurrence.isDefinition {
                    if let callerDefinition = enclosingDefinition(
                        for: occurrence, in: document, definitions: definitions)
                    {
                        let caller = node(
                            definition: callerDefinition,
                            fallbackKey: callerDefinition.symbol,
                            isChangedInPR: changedPaths.contains(
                                callerDefinition.location.filePath),
                            changedPaths: changedPaths,
                            confidence: .high
                        )
                        guard caller.id != root.id else { continue }
                        nodesById[caller.id] = caller
                        let edge = edge(
                            callerId: caller.id,
                            calleeId: root.id,
                            callSite: occurrence.range,
                            confidence: .high,
                            source: .scip
                        )
                        edgesById[edge.id] = edge
                    } else {
                        let caller = fileLevelNode(
                            path: document.relativePath, changedPaths: changedPaths)
                        nodesById[caller.id] = caller
                        let edge = edge(
                            callerId: caller.id,
                            calleeId: root.id,
                            callSite: occurrence.range,
                            confidence: .medium,
                            source: .scip
                        )
                        edgesById[edge.id] = edge
                    }
                }
            }

            guard let rootDocument = documentsByPath[filePath] else { continue }
            for occurrence in rootDocument.occurrences
            where !occurrence.isDefinition
                && definition.location.contains(line: occurrence.range.startLine)
            {
                guard let calleeDefinition = definitions[occurrence.symbol] else { continue }
                let callee = node(
                    definition: calleeDefinition,
                    fallbackKey: calleeDefinition.symbol,
                    isChangedInPR: changedPaths.contains(calleeDefinition.location.filePath),
                    changedPaths: changedPaths,
                    confidence: .high
                )
                guard callee.id != root.id else { continue }
                nodesById[callee.id] = callee
                let outgoing = edge(
                    callerId: root.id,
                    calleeId: callee.id,
                    callSite: occurrence.range,
                    confidence: .high,
                    source: .scip
                )
                edgesById[outgoing.id] = outgoing
            }
        }

        return SymbolGraphResult(
            nodes: nodesById.values.sorted { $0.id < $1.id },
            edges: edgesById.values.sorted { $0.id < $1.id },
            source: .scip,
            confidence: edgesById.isEmpty ? .medium : .high,
            diagnostics: diagnostics
        )
    }

    nonisolated private func matchDefinition(symbol: ChangedSymbol, filePath: String)
        -> IndexedSymbolDefinition?
    {
        let candidates = index.definitionsBySymbol.values.filter {
            $0.location.filePath == filePath
        }
        if let byRange =
            candidates
            .filter({ $0.location.overlaps(startLine: symbol.startLine, endLine: symbol.endLine) })
            .min(by: { lineDistance($0, symbol) < lineDistance($1, symbol) })
        {
            return byRange
        }

        let qualifiedName = symbol.metadata["qualified_name"] ?? symbol.name
        if let byName =
            candidates
            .filter({ $0.displayName == symbol.name || $0.displayName == qualifiedName })
            .min(by: { lineDistance($0, symbol) < lineDistance($1, symbol) })
        {
            return byName
        }

        return candidates.first {
            $0.displayName.hasSuffix(".\(symbol.name)") || qualifiedName.hasSuffix($0.displayName)
        }
    }

    nonisolated private func enclosingDefinition(
        for occurrence: IndexedOccurrence,
        in document: IndexedDocument,
        definitions: [String: IndexedSymbolDefinition]
    ) -> IndexedSymbolDefinition? {
        document.occurrences
            .filter { $0.isDefinition && $0.range.contains(line: occurrence.range.startLine) }
            .compactMap { definitions[$0.symbol] }
            .sorted {
                ($0.location.endLine - $0.location.startLine)
                    < ($1.location.endLine - $1.location.startLine)
            }
            .first
    }

    nonisolated private func node(
        definition: IndexedSymbolDefinition,
        fallbackKey: String,
        isChangedInPR: Bool,
        changedPaths: Set<String>,
        confidence: GraphConfidence
    ) -> SymbolGraphNode {
        SymbolGraphNode(
            id: definition.symbol,
            identity: SymbolIdentity(
                id: definition.symbol,
                scipSymbol: definition.symbol,
                fallbackKey: fallbackKey,
                displayName: definition.displayName,
                qualifiedName: definition.displayName,
                kind: definition.kind
            ),
            definition: definition.location,
            isChangedInPR: isChangedInPR,
            isTest: isTestPath(definition.location.filePath),
            confidence: confidence
        )
    }

    nonisolated private func fileLevelNode(path: String, changedPaths: Set<String>)
        -> SymbolGraphNode
    {
        let id = "file:\(path)"
        return SymbolGraphNode(
            id: id,
            identity: SymbolIdentity(
                id: id,
                scipSymbol: nil,
                fallbackKey: id,
                displayName: URL(fileURLWithPath: path).lastPathComponent,
                qualifiedName: nil,
                kind: .module
            ),
            definition: SymbolLocation(
                filePath: path, startLine: 1, startColumn: nil, endLine: 1, endColumn: nil),
            isChangedInPR: changedPaths.contains(path),
            isTest: isTestPath(path),
            confidence: .medium
        )
    }

    nonisolated private func edge(
        callerId: String,
        calleeId: String,
        callSite: SymbolLocation?,
        confidence: GraphConfidence,
        source: GraphEdgeSource
    ) -> SymbolGraphEdge {
        let location =
            callSite.map { "\($0.filePath):\($0.startLine):\($0.startColumn ?? 0)" } ?? "unknown"
        return SymbolGraphEdge(
            id: "\(callerId)->\(calleeId)@\(location)",
            callerId: callerId,
            calleeId: calleeId,
            callSite: callSite,
            confidence: confidence,
            source: source
        )
    }

    nonisolated private func fallbackKey(symbol: ChangedSymbol, filePath: String) -> String {
        if let key = symbol.metadata["symbol_key"], !key.isEmpty { return "\(filePath)::\(key)" }
        return "\(filePath)::\(symbol.semanticType)::\(symbol.name)"
    }

    nonisolated private func lineDistance(
        _ definition: IndexedSymbolDefinition,
        _ symbol: ChangedSymbol
    ) -> Int {
        abs(definition.location.startLine - symbol.startLine)
    }

    nonisolated private func isTestPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("test") || lower.contains("spec")
    }
}

private struct SCIPProtobufReader {
    nonisolated static func decodeDocuments(from data: Data) throws -> [IndexedDocument] {
        let fields = ProtoReader(data: data).fields()
        return
            fields
            .filter { $0.number == 2 && $0.wireType == .lengthDelimited }
            .compactMap { decodeDocument($0.dataValue) }
    }

    nonisolated private static func decodeDocument(_ data: Data) -> IndexedDocument? {
        var relativePath = ""
        var occurrences: [IndexedOccurrence] = []
        var symbolInfoBySymbol: [String: (displayName: String, kind: ChangedSymbol.SymbolKind)] =
            [:]

        for field in ProtoReader(data: data).fields() {
            switch (field.number, field.wireType) {
            case (1, .lengthDelimited):
                relativePath = field.stringValue ?? ""
            case (2, .lengthDelimited):
                if let occurrence = decodeOccurrence(field.dataValue, relativePath: relativePath) {
                    occurrences.append(occurrence)
                }
            case (3, .lengthDelimited):
                if let info = decodeSymbolInformation(field.dataValue) {
                    symbolInfoBySymbol[info.symbol] = (info.displayName, info.kind)
                }
            default:
                continue
            }
        }

        guard !relativePath.isEmpty else { return nil }
        let definitions =
            occurrences
            .filter(\.isDefinition)
            .map { occurrence -> IndexedSymbolDefinition in
                let info = symbolInfoBySymbol[occurrence.symbol]
                return IndexedSymbolDefinition(
                    symbol: occurrence.symbol,
                    displayName: info?.displayName ?? fallbackDisplayName(from: occurrence.symbol),
                    kind: info?.kind ?? .function,
                    location: occurrence.range
                )
            }
        return IndexedDocument(
            relativePath: normalize(relativePath),
            occurrences: occurrences.map {
                IndexedOccurrence(
                    symbol: $0.symbol,
                    range: SymbolLocation(
                        filePath: normalize($0.range.filePath),
                        startLine: $0.range.startLine,
                        startColumn: $0.range.startColumn,
                        endLine: $0.range.endLine,
                        endColumn: $0.range.endColumn
                    ),
                    isDefinition: $0.isDefinition
                )
            },
            symbols: definitions
        )
    }

    nonisolated private static func decodeOccurrence(_ data: Data, relativePath: String)
        -> IndexedOccurrence?
    {
        var range: [Int] = []
        var symbol = ""
        var roles = 0

        for field in ProtoReader(data: data).fields() {
            switch field.number {
            case 1:
                if field.wireType == .varint {
                    range.append(Int(field.intValue))
                } else if field.wireType == .lengthDelimited {
                    range.append(contentsOf: ProtoReader(data: field.dataValue).packedInts())
                }
            case 2:
                symbol = field.stringValue ?? ""
            case 3:
                roles = Int(field.intValue)
            default:
                continue
            }
        }

        guard !symbol.isEmpty, let location = location(from: range, relativePath: relativePath)
        else {
            return nil
        }
        return IndexedOccurrence(symbol: symbol, range: location, isDefinition: roles & 1 == 1)
    }

    nonisolated private static func decodeSymbolInformation(_ data: Data) -> (
        symbol: String, displayName: String, kind: ChangedSymbol.SymbolKind
    )? {
        var symbol = ""
        var displayName = ""
        var kind = ChangedSymbol.SymbolKind.function
        for field in ProtoReader(data: data).fields() {
            switch field.number {
            case 1:
                symbol = field.stringValue ?? ""
            case 2:
                displayName = field.stringValue ?? ""
            case 3:
                kind = mapSCIPKind(Int(field.intValue))
            default:
                continue
            }
        }
        guard !symbol.isEmpty else { return nil }
        return (symbol, displayName.isEmpty ? fallbackDisplayName(from: symbol) : displayName, kind)
    }

    nonisolated private static func location(from range: [Int], relativePath: String)
        -> SymbolLocation?
    {
        guard range.count == 3 || range.count == 4 else { return nil }
        let startLine = range[0] + 1
        let startColumn = range[1] + 1
        let endLine = (range.count == 4 ? range[2] : range[0]) + 1
        let endColumn = (range.count == 4 ? range[3] : range[2]) + 1
        return SymbolLocation(
            filePath: normalize(relativePath),
            startLine: startLine,
            startColumn: startColumn,
            endLine: max(startLine, endLine),
            endColumn: endColumn
        )
    }

    nonisolated private static func normalize(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    nonisolated private static func fallbackDisplayName(from symbol: String) -> String {
        symbol.split(separator: " ").last.map(String.init) ?? symbol
    }

    nonisolated private static func mapSCIPKind(_ value: Int) -> ChangedSymbol.SymbolKind {
        switch value {
        case 4: return .module
        case 5: return .type
        case 6: return .class
        case 7: return .method
        case 8: return .property
        case 9: return .constructor
        case 10: return .function
        case 11: return .variable
        case 12: return .variable
        case 13: return .enum
        case 14: return .import
        default: return .function
        }
    }
}

private enum ProtoWireType: Int {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

private struct ProtoField {
    var number: Int
    var wireType: ProtoWireType
    var intValue: UInt64
    var dataValue: Data

    nonisolated var stringValue: String? {
        String(data: dataValue, encoding: .utf8)
    }
}

private struct ProtoReader {
    let data: Data

    nonisolated func fields() -> [ProtoField] {
        var offset = 0
        var result: [ProtoField] = []
        while offset < data.count {
            guard let key = readVarint(offset: &offset) else { break }
            let fieldNumber = Int(key >> 3)
            guard let wireType = ProtoWireType(rawValue: Int(key & 0x7)) else { break }

            switch wireType {
            case .varint:
                guard let value = readVarint(offset: &offset) else { return result }
                result.append(
                    ProtoField(
                        number: fieldNumber, wireType: wireType, intValue: value, dataValue: Data())
                )
            case .lengthDelimited:
                guard let length = readVarint(offset: &offset) else { return result }
                let end = offset + Int(length)
                guard end <= data.count else { return result }
                result.append(
                    ProtoField(
                        number: fieldNumber,
                        wireType: wireType,
                        intValue: 0,
                        dataValue: data.subdata(in: offset..<end)
                    ))
                offset = end
            case .fixed64:
                guard offset + 8 <= data.count else { return result }
                offset += 8
            case .fixed32:
                guard offset + 4 <= data.count else { return result }
                offset += 4
            }
        }
        return result
    }

    nonisolated func packedInts() -> [Int] {
        var offset = 0
        var result: [Int] = []
        while offset < data.count {
            guard let value = readVarint(offset: &offset) else { break }
            result.append(Int(value))
        }
        return result
    }

    nonisolated private func readVarint(offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.count && shift < 64 {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }
}
