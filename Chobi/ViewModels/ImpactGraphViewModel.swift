import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
class ImpactGraphViewModel {
    var searchText: String = ""
    var selectedSymbolId: UUID? = nil
    var changedOnly: Bool = true
    var graphDepth: Int = 1
    var graphDirection: ImpactGraphDirection = .callers
    var originImpactId: UUID? = nil
    var focusedNodeId: String? = nil
    var selectedGraphNodeId: String? = nil
    private(set) var focusBackStack: [String] = []
    private(set) var focusForwardStack: [String] = []
    private(set) var selectedSourceContext: SymbolSourceContext? = nil

    private(set) var impacts: [SymbolImpact] = []
    private(set) var visibleImpactsByFileId: [UUID: [SymbolImpact]] = [:]
    private(set) var sourceSymbolCount: Int = 0

    var highImpactCount: Int {
        impacts.filter { $0.summary.impactLevel == .high }.count
    }

    var totalImpactedReferenceCount: Int {
        impacts.reduce(0) { total, impact in
            total + impact.summary.directCallerCount + impact.summary.directCalleeCount
        }
    }

    var impactedFileCount: Int {
        Set(impacts.map(\.filePath)).count
    }

    var symbolsWithoutTestsCount: Int {
        impacts.filter { $0.summary.testReferenceCount == 0 && $0.hasImpactData }.count
    }

    var topImpacts: [SymbolImpact] {
        Array(reviewQueue.prefix(3))
    }

    var reviewQueue: [SymbolImpact] {
        filteredImpacts.filter { $0.hasImpactData || $0.hasUsefulReason }
    }

    var quietReviewQueue: [SymbolImpact] {
        Array(reviewQueue.prefix(hasSearchQuery ? 8 : 5))
    }

    var filteredImpacts: [SymbolImpact] {
        let sorted = impacts.sorted { lhs, rhs in
            let leftScore = impactSortScore(lhs)
            let rightScore = impactSortScore(rhs)
            if leftScore != rightScore { return leftScore > rightScore }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sorted }

        return sorted.filter { impact in
            impact.title.lowercased().contains(query)
                || impact.symbol.name.lowercased().contains(query)
                || impact.filePath.lowercased().contains(query)
                || impact.symbol.kind.rawValue.lowercased().contains(query)
        }
    }

    var selectedImpact: SymbolImpact? {
        guard let selectedSymbolId else { return filteredImpacts.first ?? impacts.first }
        return impacts.first { $0.id == selectedSymbolId } ?? filteredImpacts.first
    }

    var originImpact: SymbolImpact? {
        guard let originImpactId else { return selectedImpact }
        return impacts.first { $0.id == originImpactId } ?? selectedImpact
    }

    var focusedNode: ImpactGraphNode? {
        visibleGraphNodes.first { $0.id == currentFocusedNodeId }
    }

    var selectedGraphNode: ImpactGraphNode? {
        guard let selectedGraphNodeId else { return focusedNode }
        return visibleGraphNodes.first { $0.id == selectedGraphNodeId } ?? focusedNode
    }

    var currentFocusedNodeId: String? {
        focusedNodeId ?? originImpact.map { nodeId(for: $0.symbol.name, filePath: $0.filePath) }
    }

    var graphPathText: String {
        guard let origin = originImpact else { return "No changed symbol selected" }
        guard let focused = focusedNode,
            focused.id != nodeId(for: origin.symbol.name, filePath: origin.filePath)
        else { return origin.symbol.name }
        return "\(origin.symbol.name) <- \(focused.title)"
    }

    var canGoBack: Bool { !focusBackStack.isEmpty }

    var canGoForward: Bool { !focusForwardStack.isEmpty }

    var visibleGraphNodes: [ImpactGraphNode] {
        guard let origin = originImpact else { return [] }
        let graphRoot = focusedImpact ?? origin
        var nodes: [ImpactGraphNode] = [
            ImpactGraphNode(
                id: nodeId(for: origin.symbol.name, filePath: origin.filePath),
                title: origin.symbol.name,
                filePath: origin.filePath,
                line: origin.symbol.startLine,
                role: .origin,
                isChangedInPR: true,
                isTest: origin.symbol.metadata["is_test"] == "true")
        ]

        let graphRootId = nodeId(for: graphRoot.symbol.name, filePath: graphRoot.filePath)
        if !nodes.contains(where: { $0.id == graphRootId }) {
            nodes.append(
                ImpactGraphNode(
                    id: graphRootId,
                    title: graphRoot.symbol.name,
                    filePath: graphRoot.filePath,
                    line: graphRoot.symbol.startLine,
                    role: .origin,
                    isChangedInPR: true,
                    isTest: graphRoot.symbol.metadata["is_test"] == "true"))
        }

        if graphDirection == .callers || graphDirection == .both {
            nodes.append(
                contentsOf: graphRoot.symbol.callers.prefix(nodeLimit).map {
                    makeRelatedNode(row: $0, role: .caller)
                })
        }
        if graphDirection == .callees || graphDirection == .both {
            nodes.append(
                contentsOf: graphRoot.symbol.callees.prefix(nodeLimit).map {
                    makeRelatedNode(row: $0, role: .callee)
                })
        }

        return Array(Dictionary(grouping: nodes, by: \.id).compactMap { $0.value.first })
    }

    private var focusedImpact: SymbolImpact? {
        guard let currentFocusedNodeId else { return nil }
        return impacts.first { impact in
            nodeId(for: impact.symbol.name, filePath: impact.filePath) == currentFocusedNodeId
                || nodeId(for: impact.qualifiedName, filePath: impact.filePath)
                    == currentFocusedNodeId
        }
    }

    var fileImpactIndicators: [UUID: FileImpactIndicator] {
        Dictionary(
            uniqueKeysWithValues: visibleImpactsByFileId.compactMap { fileId, impacts in
                guard !impacts.isEmpty else { return nil }
                return (
                    fileId,
                    FileImpactIndicator(
                        count: impacts.count,
                        highCount: impacts.filter { $0.summary.impactLevel == .high }.count,
                        mediumCount: impacts.filter { $0.summary.impactLevel == .medium }.count,
                        callerCount: impacts.reduce(0) { $0 + $1.summary.directCallerCount },
                        changedHighImpactCount: impacts.filter {
                            $0.summary.impactLevel == .high
                        }.count,
                        weakTestCount: impacts.filter {
                            $0.summary.testReferenceCount == 0 && $0.hasImpactData
                        }.count)
                )
            }
        )
    }

    var hasSearchQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var emptyStateText: String {
        if sourceSymbolCount == 0 {
            return "No changed symbols were extracted for this analysis."
        }
        if hasSearchQuery {
            return "No changed symbols match this search."
        }
        return "No caller or callee data found for changed symbols."
    }

    func load(details: AnalysisDetails) {
        sourceSymbolCount = details.symbols.count
        let filesById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0.path) })
        impacts =
            details.symbols
            .map { symbol in
                let path =
                    filesById[symbol.changedFileId] ?? symbol.metadata["file_path"] ?? "unknown"
                return SymbolImpact(
                    id: symbol.id,
                    symbol: symbol,
                    filePath: path,
                    summary: makeSummary(symbol: symbol, filePath: path),
                    reason: makeReason(symbol: symbol, filePath: path),
                    topAffectedSymbols: topAffectedSymbols(symbol: symbol)
                )
            }
            .filter { impact in
                switch impact.symbol.kind {
                case .function, .method, .class, .struct, .enum, .protocol, .extension, .property,
                    .constructor, .type:
                    true
                default:
                    impact.hasImpactData
                }
            }
        visibleImpactsByFileId = Dictionary(
            uniqueKeysWithValues: details.files.map { file in
                (file.id, visibleImpacts(for: file))
            })

        if let selectedSymbolId, impacts.contains(where: { $0.id == selectedSymbolId }) {
            return
        }
        selectedSymbolId = filteredImpacts.first?.id
        originImpactId = selectedSymbolId
        focusedNodeId = selectedImpact.map { nodeId(for: $0.symbol.name, filePath: $0.filePath) }
        selectedGraphNodeId = focusedNodeId
        updateSelectedSourceContext()
    }

    func select(_ impact: SymbolImpact) {
        selectedSymbolId = impact.id
        originImpactId = impact.id
        focusedNodeId = nodeId(for: impact.symbol.name, filePath: impact.filePath)
        selectedGraphNodeId = focusedNodeId
        focusBackStack = []
        focusForwardStack = []
        updateSelectedSourceContext()
    }

    func selectNextImpact() {
        selectAdjacentImpact(offset: 1)
    }

    func selectPreviousImpact() {
        selectAdjacentImpact(offset: -1)
    }

    func impacts(for file: ChangedFile) -> [SymbolImpact] {
        impacts
            .filter { $0.symbol.changedFileId == file.id }
            .sorted { lhs, rhs in
                if lhs.symbol.startLine != rhs.symbol.startLine {
                    return lhs.symbol.startLine < rhs.symbol.startLine
                }
                return impactSortScore(lhs) > impactSortScore(rhs)
            }
    }

    func visibleImpacts(for file: ChangedFile) -> [SymbolImpact] {
        let hunkImpacts = file.hunks.flatMap { hunk in
            displayImpacts(for: hunk, fileId: file.id)
        }
        var seen: Set<UUID> = []
        let unique = hunkImpacts.filter { impact in
            guard !seen.contains(impact.id) else { return false }
            seen.insert(impact.id)
            return true
        }
        if unique.isEmpty && file.hunks.isEmpty {
            return impacts(for: file).filter { $0.hasImpactData || $0.hasUsefulReason }
        }
        return unique.sorted { lhs, rhs in
            if lhs.symbol.startLine != rhs.symbol.startLine {
                return lhs.symbol.startLine < rhs.symbol.startLine
            }
            return impactSortScore(lhs) > impactSortScore(rhs)
        }
    }

    func inlineMarkers(for hunk: DiffHunk, file: ChangedFile, hunkIndex: Int)
        -> [InlineImpactMarker]
    {
        let hunkStart = hunk.newStart
        let hunkEnd = hunk.newStart + max(hunk.newLines - 1, 0)
        return displayImpacts(for: hunk, fileId: file.id).compactMap { impact in
            guard impact.hasImpactData || impact.hasUsefulReason else { return nil }
            let symbolStart = impact.symbol.startLine
            let anchor = max(hunkStart, symbolStart)
            guard anchor <= hunkEnd else { return nil }
            let firstHunkIndex = file.hunks.firstIndex { candidate in
                let end = candidate.newStart + max(candidate.newLines - 1, 0)
                return impact.symbol.startLine <= end && impact.symbol.endLine >= candidate.newStart
            }
            guard firstHunkIndex == nil || firstHunkIndex == hunkIndex else { return nil }
            return InlineImpactMarker(
                id: UUID(),
                rootSymbolId: impact.id,
                filePath: file.path,
                anchorLine: anchor,
                hunkIndex: hunkIndex,
                summary: usefulSummary(for: impact),
                metrics: impact.summary)
        }
    }

    func selectGraphNode(_ node: ImpactGraphNode) {
        selectedGraphNodeId = node.id
        updateSelectedSourceContext()
    }

    func focusSelectedGraphNode() {
        guard let selectedGraphNodeId else { return }
        focus(on: selectedGraphNodeId)
    }

    func focusOrigin() {
        guard let origin = originImpact else { return }
        focus(on: nodeId(for: origin.symbol.name, filePath: origin.filePath))
    }

    func focusBack() {
        guard let previous = focusBackStack.popLast() else { return }
        if let currentFocusedNodeId {
            focusForwardStack.append(currentFocusedNodeId)
        }
        focusedNodeId = previous
        selectedGraphNodeId = previous
        updateSelectedSourceContext()
    }

    func focusForward() {
        guard let next = focusForwardStack.popLast() else { return }
        if let currentFocusedNodeId {
            focusBackStack.append(currentFocusedNodeId)
        }
        focusedNodeId = next
        selectedGraphNodeId = next
        updateSelectedSourceContext()
    }

    func usefulSummary(for impact: SymbolImpact) -> String {
        if let reason = impact.reason, !reason.isEmpty { return reason }
        return
            "\(impact.summary.directCallerCount) callers · \(impact.summary.directCalleeCount) callees · View graph"
    }

    private var nodeLimit: Int {
        max(3, min(12, graphDepth * 6))
    }

    private func focus(on nodeId: String) {
        if let currentFocusedNodeId, currentFocusedNodeId != nodeId {
            focusBackStack.append(currentFocusedNodeId)
        }
        focusForwardStack = []
        focusedNodeId = nodeId
        selectedGraphNodeId = nodeId
        updateSelectedSourceContext()
    }

    private func selectAdjacentImpact(offset: Int) {
        let queue = reviewQueue
        guard !queue.isEmpty else { return }
        let currentIndex =
            selectedSymbolId.flatMap { id in queue.firstIndex { $0.id == id } } ?? 0
        let nextIndex = (currentIndex + offset + queue.count) % queue.count
        select(queue[nextIndex])
    }

    private func updateSelectedSourceContext() {
        guard let node = selectedGraphNode else {
            selectedSourceContext = nil
            return
        }
        let start = node.line ?? 1
        let end = node.isChangedInPR ? (originImpact?.symbol.endLine ?? start) : start
        selectedSourceContext = SymbolSourceContext(
            symbolName: node.title,
            filePath: node.filePath,
            startLine: start,
            endLine: end,
            excerptStartLine: max(1, start - 3),
            excerpt: "",
            isChangedInCurrentPR: node.isChangedInPR,
            changedLineNumbers: node.isChangedInPR ? Set(start...max(start, end)) : [],
            callSiteLine: node.role == .origin ? nil : node.line)
    }

    func impacts(for hunk: DiffHunk, fileId: UUID) -> [SymbolImpact] {
        impacts
            .filter { impact in
                guard impact.symbol.changedFileId == fileId else { return false }
                let hunkEnd = hunk.newStart + max(hunk.newLines - 1, 0)
                return impact.symbol.startLine <= hunkEnd && impact.symbol.endLine >= hunk.newStart
            }
            .sorted { lhs, rhs in
                if impactSortScore(lhs) != impactSortScore(rhs) {
                    return impactSortScore(lhs) > impactSortScore(rhs)
                }
                return lhs.symbol.startLine < rhs.symbol.startLine
            }
    }

    private func displayImpacts(for hunk: DiffHunk, fileId: UUID) -> [SymbolImpact] {
        let hunkImpacts = impacts(for: hunk, fileId: fileId)
        return hunkImpacts.filter { candidate in
            !isContainerImpact(candidate, shadowedBy: hunkImpacts)
        }
    }

    private func isContainerImpact(_ candidate: SymbolImpact, shadowedBy impacts: [SymbolImpact])
        -> Bool
    {
        guard isContainerKind(candidate.symbol.kind) else { return false }
        return impacts.contains { other in
            guard other.id != candidate.id else { return false }
            guard other.symbol.changedFileId == candidate.symbol.changedFileId else { return false }
            guard other.hasImpactData || other.hasUsefulReason else { return false }
            return candidate.symbol.startLine <= other.symbol.startLine
                && candidate.symbol.endLine >= other.symbol.endLine
                && candidate.symbol.startLine < other.symbol.endLine
        }
    }

    private func isContainerKind(_ kind: ChangedSymbol.SymbolKind) -> Bool {
        switch kind {
        case .class, .struct, .enum, .protocol, .extension, .type:
            true
        default:
            false
        }
    }

    private func makeSummary(symbol: ChangedSymbol, filePath: String) -> ImpactSummary {
        let callerFiles = Set(
            symbol.callers.map { caller -> String in
                caller.components(separatedBy: ":").first ?? caller
            })
        let relatedFileCount = max(1, callerFiles.union([filePath]).count)
        let testReferenceCount = symbol.callers.filter(isChangedTestCaller).count
        let directCallerCount = symbol.callers.count
        let directCalleeCount = symbol.callees.count
        let impactLevel = ImpactScorer.level(
            for: symbol,
            fileCount: relatedFileCount,
            transitiveCallerCount: directCallerCount,
            transitiveCalleeCount: directCalleeCount
        )
        let confidence: CallGraphConfidence =
            symbol.metadata["caller_resolution"] == "indexed" || !symbol.callees.isEmpty
            ? .high : .medium

        return ImpactSummary(
            directCallerCount: directCallerCount,
            directCalleeCount: directCalleeCount,
            transitiveCallerCount: directCallerCount,
            transitiveCalleeCount: directCalleeCount,
            fileCount: relatedFileCount,
            testReferenceCount: testReferenceCount,
            impactLevel: impactLevel,
            confidence: confidence
        )
    }

    private func makeReason(symbol: ChangedSymbol, filePath: String) -> String? {
        if symbol.metadata["is_test"] == "true" && !symbol.callees.isEmpty {
            return
                "Test behavior changes while exercising \(symbol.callees.prefix(2).joined(separator: ", "))."
        }
        if symbol.metadata["visibility"] == "public" || symbol.metadata["is_public"] == "true" {
            return
                "Public contract surface changed with \(symbol.callers.count) detected caller\(symbol.callers.count == 1 ? "" : "s")."
        }
        if symbol.callers.count >= 5 {
            return
                "High fan-in utility changed across \(Set(symbol.callers.map(pathPrefix)).count) files."
        }
        if symbol.callers.contains(where: isChangedTestCaller) && symbol.callers.count > 1 {
            return "Production change has direct test references and runtime callers."
        }
        return nil
    }

    private func topAffectedSymbols(symbol: ChangedSymbol) -> [String] {
        Array(symbol.callers.prefix(3).map(displayName))
    }

    private func impactSortScore(_ impact: SymbolImpact) -> Int {
        let summary = impact.summary
        let levelScore: Int
        switch summary.impactLevel {
        case .high: levelScore = 10_000
        case .medium: levelScore = 5_000
        case .low: levelScore = 1_000
        }
        return levelScore + summary.directCallerCount * 100 + summary.directCalleeCount * 10
    }

    private func makeRelatedNode(row: String, role: ImpactGraphNode.Role) -> ImpactGraphNode {
        ImpactGraphNode(
            id: nodeId(for: displayName(row), filePath: pathPrefix(row)),
            title: displayName(row),
            filePath: pathPrefix(row),
            line: lineNumber(row),
            role: role,
            isChangedInPR: impacts.contains {
                $0.symbol.name == displayName(row) || $0.qualifiedName == displayName(row)
            },
            isTest: isChangedTestCaller(row))
    }

    private func nodeId(for name: String, filePath: String) -> String {
        "\(filePath)#\(name)"
    }

    private func displayName(_ row: String) -> String {
        row.components(separatedBy: ":").last ?? row
    }

    private func pathPrefix(_ row: String) -> String {
        row.components(separatedBy: ":").first ?? row
    }

    private func lineNumber(_ row: String) -> Int? {
        let parts = row.components(separatedBy: ":")
        return parts.compactMap(Int.init).first
    }

    private func isChangedTestCaller(_ row: String) -> Bool {
        let name = displayName(row)
        return impacts.contains { impact in
            (impact.symbol.name == name || impact.qualifiedName == name)
                && impact.symbol.metadata["is_test"] == "true"
        }
    }
}

struct FileImpactIndicator: Hashable {
    let count: Int
    let highCount: Int
    let mediumCount: Int
    let callerCount: Int
    let changedHighImpactCount: Int
    let weakTestCount: Int

    var color: Color {
        if highCount > 0 { return .danger }
        if mediumCount > 0 { return .warning }
        return .success
    }

    var helpText: String {
        "\(count) impact signal\(count == 1 ? "" : "s")\n\(callerCount) callers of changed symbols\n\(changedHighImpactCount) changed high-impact symbols\n\(weakTestCount) weak test coverage signals"
    }
}
