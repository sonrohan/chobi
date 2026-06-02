import Foundation

protocol ImpactGraphServiceProtocol: Sendable {
    func enrichSymbols(
        repoPath: String,
        symbols: [ChangedSymbol],
        files: [ChangedFile],
        revision: String?
    ) async -> ImpactGraphEnrichment

    func graph(
        rootSymbolId: String,
        depth: Int,
        direction: ImpactGraphDirection
    ) async throws -> ImpactGraph
}

actor ImpactGraphService: ImpactGraphServiceProtocol {
    private let symbolIndexService: any SymbolIndexServiceProtocol
    private let fallbackService: ASTAnalysisService
    private var latestGraph: SymbolGraphResult?

    init(
        symbolIndexService: any SymbolIndexServiceProtocol,
        fallbackService: ASTAnalysisService
    ) {
        self.symbolIndexService = symbolIndexService
        self.fallbackService = fallbackService
    }

    func enrichSymbols(
        repoPath: String,
        symbols: [ChangedSymbol],
        files: [ChangedFile],
        revision: String?
    ) async -> ImpactGraphEnrichment {
        let filesById = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let status = await symbolIndexService.indexStatus(repoPath: repoPath, revision: revision)

        if status.isAvailable,
            let graph = try? await symbolIndexService.symbolGraph(
                for: symbols,
                filesById: filesById,
                repoPath: repoPath,
                revision: revision
            ),
            graph.nodes.contains(where: \.isChangedInPR)
        {
            latestGraph = graph
            return ImpactGraphEnrichment(
                symbols: attachGraphCompatibility(symbols, graph: graph, filesById: filesById),
                graph: graph,
                trackedFilesCount: GitService.trackedSourceFiles(cwd: repoPath, revision: revision)
                    .count,
                indexedFilesCount: graph.nodes.compactMap(\.definition?.filePath).reduce(
                    into: Set<String>()
                ) { $0.insert($1) }.count
            )
        }

        let fallback = await fallbackService.symbolsWithCallerData(
            repoPath: repoPath, symbols: symbols, revision: revision)
        let graph = fallbackGraph(from: fallback.symbols, filesById: filesById)
        latestGraph = graph
        return ImpactGraphEnrichment(
            symbols: fallback.symbols,
            graph: graph,
            trackedFilesCount: fallback.trackedCount,
            indexedFilesCount: fallback.indexedCount
        )
    }

    func graph(
        rootSymbolId: String,
        depth: Int,
        direction: ImpactGraphDirection
    ) async throws -> ImpactGraph {
        guard let latestGraph,
            let root = latestGraph.nodes.first(where: { $0.id == rootSymbolId })
        else {
            throw SymbolIndexError.unavailable("No structured impact graph is loaded.")
        }
        let selectedEdges = traverse(
            graph: latestGraph, rootSymbolId: rootSymbolId, depth: max(1, depth),
            direction: direction)
        let selectedNodeIds = Set(selectedEdges.flatMap { [$0.callerId, $0.calleeId] }).union([
            root.id
        ])
        let nodes = latestGraph.nodes
            .filter { selectedNodeIds.contains($0.id) }
            .map(mapNode)
        let edges = selectedEdges.map {
            CallEdge(
                id: $0.id,
                callerId: $0.callerId,
                calleeId: $0.calleeId,
                unresolvedCalleeName: nil,
                confidence: $0.confidence == .high ? .exact : .ambiguous,
                sourceFilePath: $0.callSite?.filePath ?? "",
                sourceLine: $0.callSite?.startLine
            )
        }
        let summary = ImpactSummary(
            directCallerCount: latestGraph.edges.filter { $0.calleeId == rootSymbolId }.count,
            directCalleeCount: latestGraph.edges.filter { $0.callerId == rootSymbolId }.count,
            transitiveCallerCount: selectedEdges.filter { $0.calleeId == rootSymbolId }.count,
            transitiveCalleeCount: selectedEdges.filter { $0.callerId == rootSymbolId }.count,
            fileCount: Set(nodes.map(\.filePath)).count,
            testReferenceCount: nodes.filter { $0.filePath.lowercased().contains("test") }.count,
            impactLevel: impactLevel(nodeCount: nodes.count, edgeCount: edges.count),
            confidence: latestGraph.confidence == .high ? .high : .medium
        )
        return ImpactGraph(
            root: mapNode(root),
            nodes: nodes,
            edges: edges,
            unresolvedCalls: [],
            summary: summary
        )
    }

    private func attachGraphCompatibility(
        _ symbols: [ChangedSymbol],
        graph: SymbolGraphResult,
        filesById: [UUID: ChangedFile]
    ) -> [ChangedSymbol] {
        symbols.map { symbol in
            var updated = symbol
            guard let filePath = filesById[symbol.changedFileId]?.path,
                let root = matchNode(symbol: symbol, filePath: filePath, graph: graph)
            else {
                return updated
            }

            let callers = graph.edges
                .filter { $0.calleeId == root.id }
                .compactMap { edge in graph.nodes.first { $0.id == edge.callerId } }
                .compactMap(compatibilityLabel)
                .sorted()
            let callees = graph.edges
                .filter { $0.callerId == root.id }
                .compactMap { edge in graph.nodes.first { $0.id == edge.calleeId } }
                .map(\.identity.displayName)
                .sorted()

            updated.callers = callers
            updated.callees = Array(Set(updated.callees).union(callees)).sorted()
            updated.metadata["graph_source"] = GraphEdgeSource.scip.rawValue
            updated.metadata["scip_symbol"] = root.identity.scipSymbol
            updated.metadata["symbol_id"] = root.id
            updated.metadata["caller_resolution"] = "scip"
            return updated
        }
    }

    private func fallbackGraph(
        from symbols: [ChangedSymbol],
        filesById: [UUID: ChangedFile]
    ) -> SymbolGraphResult {
        var nodesById: [String: SymbolGraphNode] = [:]
        var edges: [SymbolGraphEdge] = []

        for symbol in symbols {
            let filePath =
                filesById[symbol.changedFileId]?.path ?? symbol.metadata["file_path"] ?? ""
            let rootId = symbol.metadata["symbol_id"] ?? "\(filePath)::\(symbol.name)"
            nodesById[rootId] = SymbolGraphNode(
                id: rootId,
                identity: SymbolIdentity(
                    id: rootId,
                    scipSymbol: nil,
                    fallbackKey: rootId,
                    displayName: symbol.metadata["qualified_name"] ?? symbol.name,
                    qualifiedName: symbol.metadata["qualified_name"],
                    kind: symbol.kind
                ),
                definition: SymbolLocation(
                    filePath: filePath,
                    startLine: symbol.startLine,
                    startColumn: nil,
                    endLine: symbol.endLine,
                    endColumn: nil
                ),
                isChangedInPR: true,
                isTest: isTestPath(filePath),
                confidence: .low
            )

            for caller in symbol.callers {
                let callerParts = caller.components(separatedBy: ":")
                let callerPath = callerParts.count >= 2 ? callerParts[0] : filePath
                let callerName =
                    callerParts.count >= 2 ? callerParts.dropFirst().joined(separator: ":") : caller
                let callerId = "fallback:caller:\(caller)"
                nodesById[callerId] = SymbolGraphNode(
                    id: callerId,
                    identity: SymbolIdentity(
                        id: callerId,
                        scipSymbol: nil,
                        fallbackKey: callerId,
                        displayName: callerName,
                        qualifiedName: callerName,
                        kind: .function
                    ),
                    definition: SymbolLocation(
                        filePath: callerPath,
                        startLine: 1,
                        startColumn: nil,
                        endLine: 1,
                        endColumn: nil
                    ),
                    isChangedInPR: filesById.values.contains { $0.path == callerPath },
                    isTest: isTestPath(callerPath),
                    confidence: .low
                )
                edges.append(
                    SymbolGraphEdge(
                        id: "\(callerId)->\(rootId)",
                        callerId: callerId,
                        calleeId: rootId,
                        callSite: nil,
                        confidence: .low,
                        source: .treeSitterFallback
                    ))
            }
        }

        return SymbolGraphResult(
            nodes: nodesById.values.sorted { $0.id < $1.id },
            edges: edges.sorted { $0.id < $1.id },
            source: .treeSitterFallback,
            confidence: .low,
            diagnostics: ["SCIP unavailable; used Tree-sitter/name fallback."]
        )
    }

    private func traverse(
        graph: SymbolGraphResult,
        rootSymbolId: String,
        depth: Int,
        direction: ImpactGraphDirection
    ) -> [SymbolGraphEdge] {
        var frontier: Set<String> = [rootSymbolId]
        var visited: Set<String> = [rootSymbolId]
        var selected: [SymbolGraphEdge] = []

        for _ in 0..<depth {
            let nextEdges = graph.edges.filter { edge in
                switch direction {
                case .callers:
                    return frontier.contains(edge.calleeId)
                case .callees:
                    return frontier.contains(edge.callerId)
                case .both:
                    return frontier.contains(edge.callerId) || frontier.contains(edge.calleeId)
                }
            }
            selected.append(contentsOf: nextEdges)
            let nextNodes = Set(nextEdges.flatMap { [$0.callerId, $0.calleeId] }).subtracting(
                visited)
            guard !nextNodes.isEmpty else { break }
            visited.formUnion(nextNodes)
            frontier = nextNodes
        }

        return Array(Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) }).values)
            .sorted { $0.id < $1.id }
    }

    private func matchNode(
        symbol: ChangedSymbol,
        filePath: String,
        graph: SymbolGraphResult
    ) -> SymbolGraphNode? {
        if let id = symbol.metadata["symbol_id"] {
            return graph.nodes.first { $0.id == id }
        }
        return graph.nodes.first {
            $0.definition?.filePath == filePath
                && $0.definition?.overlaps(startLine: symbol.startLine, endLine: symbol.endLine)
                    == true
        }
    }

    private func compatibilityLabel(_ node: SymbolGraphNode) -> String? {
        guard let filePath = node.definition?.filePath else { return nil }
        return "\(filePath):\(node.identity.displayName)"
    }

    private func mapNode(_ node: SymbolGraphNode) -> SymbolNode {
        let definition = node.definition
        return SymbolNode(
            id: node.id,
            name: node.identity.displayName,
            qualifiedName: node.identity.qualifiedName ?? node.identity.displayName,
            kind: node.identity.kind,
            semanticType: node.identity.kind.rawValue,
            language: "",
            filePath: definition?.filePath ?? "",
            startLine: definition?.startLine ?? 1,
            endLine: definition?.endLine ?? definition?.startLine ?? 1,
            metadata: [
                "graph_source": node.identity.scipSymbol == nil
                    ? GraphEdgeSource.treeSitterFallback.rawValue : GraphEdgeSource.scip.rawValue
            ]
        )
    }

    private func impactLevel(nodeCount: Int, edgeCount: Int) -> ImpactLevel {
        if edgeCount >= 10 || nodeCount >= 12 { return .high }
        if edgeCount >= 4 || nodeCount >= 6 { return .medium }
        return .low
    }

    private func isTestPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("test") || lower.contains("spec")
    }
}
