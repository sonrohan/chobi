import Foundation

enum AgentContextBuilder {
    nonisolated static let schemaVersion = "2026-06-01"

    // MARK: - Analysis Summary

    nonisolated static func buildSummary(
        details: AnalysisDetails,
        repository: GitRepository?,
        activeBranch: String?,
        truncated: Bool = false
    ) -> MCPAnalysisSummary {
        let buckets = details.changeBuckets
            .sorted { $0.reviewOrder < $1.reviewOrder }
            .map(mapBucket)

        return MCPAnalysisSummary(
            schemaVersion: schemaVersion,
            source: "chobi",
            workspaceId: repository?.id.uuidString,
            workspaceName: repository?.name ?? details.pr.repository,
            runId: details.run.id.uuidString,
            branch: activeBranch,
            riskScore: details.run.riskScore,
            riskFactors: Array(details.riskFactors.prefix(8)),
            fileCount: details.files.count,
            additions: details.files.reduce(0) { $0 + $1.additions },
            deletions: details.files.reduce(0) { $0 + $1.deletions },
            fileClassificationCounts: count(details.files.map { $0.classification.rawValue }),
            fileStatusCounts: count(details.files.map { $0.status.rawValue }),
            findingSeverityCounts: count(details.findings.map { $0.severity.rawValue }),
            symbolCount: details.symbols.count,
            buckets: buckets,
            reviewTargetCount: details.reviewTargets.count,
            skimTargetCount: details.skimTargets.count,
            truncated: truncated,
            nextActions: [
                "chobi.list_changed_files",
                "chobi.get_review_plan",
                "chobi.explain_file",
            ]
        )
    }

    // MARK: - File List

    nonisolated static func buildFileSummaryList(
        details: AnalysisDetails,
        repository: GitRepository?,
        maxItems: Int,
        minSeverity: Severity?
    ) -> MCPFileSummaryList {
        let findingsByFile = Dictionary(grouping: details.findings, by: \.changedFileId)
        let symbolsByFile = Dictionary(grouping: details.symbols, by: \.changedFileId)
        let bucketsByFile: [UUID: [String]] = details.files.reduce(into: [:]) { result, file in
            let ids = details.changeBuckets
                .filter { $0.files.contains(file.path) }
                .map(\.id)
            result[file.id] = ids
        }

        var files = details.files.sorted { $0.path < $1.path }

        if let minSev = minSeverity {
            files = files.filter { file in
                let filefindings = findingsByFile[file.id] ?? []
                return filefindings.contains { severityRank($0.severity) >= severityRank(minSev) }
            }
        }

        let capped = Array(files.prefix(max(1, maxItems)))
        let summaries = capped.map { file -> MCPFileSummary in
            MCPFileSummary(
                id: file.id.uuidString,
                path: file.path,
                status: file.status.rawValue,
                classification: file.classification.rawValue,
                additions: file.additions,
                deletions: file.deletions,
                findingCount: findingsByFile[file.id]?.count ?? 0,
                symbolCount: symbolsByFile[file.id]?.count ?? 0,
                bucketIds: bucketsByFile[file.id] ?? []
            )
        }

        return MCPFileSummaryList(
            schemaVersion: schemaVersion,
            source: "chobi",
            workspaceId: repository?.id.uuidString,
            runId: details.run.id.uuidString,
            files: summaries,
            truncated: files.count > capped.count,
            nextActions: ["chobi.explain_file", "chobi.get_review_plan"]
        )
    }

    // MARK: - File Detail

    nonisolated static func buildFileDetail(
        file: ChangedFile,
        symbols: [ChangedSymbol],
        findings: [Finding],
        buckets: [ChangeBucket],
        highlights: [RiskHighlight],
        includeHunks: Bool,
        maxHunkLines: Int,
        detailLevel: AgentContextDetailLevel
    ) -> MCPFileDetail {
        let hunkLimit = detailLevel == .full ? file.hunks.count : min(file.hunks.count, 5)
        let hunks: [MCPHunk]
        if includeHunks {
            let mapped = file.hunks.prefix(hunkLimit).enumerated().map { index, hunk in
                mapHunk(hunk, index: index, detailLevel: detailLevel)
            }
            hunks = capHunkLines(Array(mapped), maxLines: max(0, maxHunkLines))
        } else {
            hunks = []
        }

        return MCPFileDetail(
            schemaVersion: schemaVersion,
            source: "chobi",
            id: file.id.uuidString,
            path: file.path,
            status: file.status.rawValue,
            classification: file.classification.rawValue,
            additions: file.additions,
            deletions: file.deletions,
            hunks: hunks,
            symbols: symbols.sorted { $0.startLine < $1.startLine }.map { s in
                MCPSymbolRef(
                    id: s.id.uuidString,
                    name: s.name,
                    kind: s.kind.rawValue,
                    startLine: s.startLine,
                    endLine: s.endLine
                )
            },
            findings: findings.sorted { $0.message < $1.message }.map(mapFinding),
            bucketIds: buckets.sorted { $0.reviewOrder < $1.reviewOrder }.map(\.id),
            riskHighlights: highlights.sorted { $0.title < $1.title }.map(mapRiskHighlight),
            truncated: hunkLimit < file.hunks.count,
            nextActions: ["chobi.explain_symbol", "chobi.get_impact_graph"]
        )
    }

    // MARK: - Symbol Detail

    nonisolated static func buildSymbolDetail(
        symbol: ChangedSymbol,
        filePath: String?,
        impactSummary: MCPImpactSummary?
    ) -> MCPSymbolDetail {
        MCPSymbolDetail(
            schemaVersion: schemaVersion,
            source: "chobi",
            id: symbol.id.uuidString,
            fileId: symbol.changedFileId.uuidString,
            filePath: filePath,
            name: symbol.name,
            kind: symbol.kind.rawValue,
            semanticType: symbol.semanticType,
            language: symbol.metadata["language"],
            semanticArea: symbol.metadata["semantic_area"],
            startLine: symbol.startLine,
            endLine: symbol.endLine,
            callers: symbol.callers.sorted(),
            callees: symbol.callees.sorted(),
            impactSummary: impactSummary,
            contractDeltas: symbol.metadata.filter { k, _ in k.hasPrefix("contract_") },
            behaviorDeltas: symbol.metadata.filter { k, _ in k.hasSuffix("_added") },
            nextActions: ["chobi.get_impact_graph", "chobi.read_file_range"]
        )
    }

    // MARK: - Impact Graph

    nonisolated static func buildImpactGraph(
        symbol: ChangedSymbol,
        filePath: String?,
        changedFilePaths: Set<String>
    ) -> MCPImpactGraph {
        // Parse "filePath:qualifiedName" entries from callers
        let callerNodes: [MCPGraphNode] = symbol.callers.enumerated().map { idx, raw in
            let parts = raw.components(separatedBy: ":")
            let callerPath = parts.count >= 2 ? parts[0] : raw
            let callerName = parts.count >= 2 ? parts.dropFirst().joined(separator: ":") : raw
            let isTest =
                callerPath.lowercased().contains("test")
                || callerPath.lowercased().contains("spec")
            return MCPGraphNode(
                id: "caller-\(idx)",
                name: callerName,
                filePath: callerPath,
                line: nil,
                isChangedInPR: changedFilePaths.contains(callerPath),
                isTest: isTest
            )
        }

        // Parse callee names (plain names, no file info)
        let calleeNodes: [MCPGraphNode] = symbol.callees.enumerated().map { idx, name in
            MCPGraphNode(
                id: "callee-\(idx)",
                name: name,
                filePath: filePath ?? "",
                line: nil,
                isChangedInPR: false,
                isTest: false
            )
        }

        let testRefCount = callerNodes.filter(\.isTest).count
        let uniqueCallerFiles = Set(callerNodes.map(\.filePath)).filter { !$0.isEmpty }
        let totalFileCount = uniqueCallerFiles.union(filePath.map { [$0] } ?? []).count

        let impactLevel: ImpactLevel
        let total = callerNodes.count + calleeNodes.count
        if total >= 10 || callerNodes.count >= 6 {
            impactLevel = .high
        } else if total >= 4 || callerNodes.count >= 2 {
            impactLevel = .medium
        } else {
            impactLevel = .low
        }

        let summary = MCPImpactSummary(
            directCallerCount: callerNodes.count,
            directCalleeCount: calleeNodes.count,
            transitiveCallerCount: callerNodes.count,  // flat data; no transitive traversal
            transitiveCalleeCount: calleeNodes.count,
            fileCount: totalFileCount,
            testReferenceCount: testRefCount,
            impactLevel: impactLevel.rawValue,
            confidence: symbol.metadata["caller_resolution"] == "indexed" ? "high" : "low"
        )

        return MCPImpactGraph(
            schemaVersion: schemaVersion,
            source: "chobi",
            symbolId: symbol.id.uuidString,
            symbolName: symbol.metadata["qualified_name"] ?? symbol.name,
            filePath: filePath,
            startLine: symbol.startLine,
            endLine: symbol.endLine,
            summary: summary,
            callerNodes: callerNodes,
            calleeNodes: calleeNodes,
            unresolvedCalleeNames: [],
            nextActions: ["chobi.explain_file", "chobi.read_file_range"]
        )
    }

    // MARK: - Review Plan

    nonisolated static func buildReviewPlan(
        details: AnalysisDetails,
        focus: String,
        maxItems: Int
    ) -> MCPReviewPlan {
        var targets = details.reviewTargets
            .sorted { $0.priority < $1.priority }
            .map(mapReviewTarget)
        var buckets = details.changeBuckets
            .sorted { $0.reviewOrder < $1.reviewOrder }
            .map(mapBucket)
        let highlights = details.riskHighlights
            .sorted {
                if $0.severity != $1.severity {
                    return severityRank($0.severity) > severityRank($1.severity)
                }
                return $0.title < $1.title
            }
            .map(mapRiskHighlight)
        let skimTargets = details.skimTargets
            .sorted { $0.filePath < $1.filePath }
            .map(mapSkimTarget)

        if focus != "all" {
            targets = targets.filter { targetMatchesFocus($0, focus: focus) }
            buckets = buckets.filter { bucketMatchesFocus($0, focus: focus) }
        }

        let cappedTargets = Array(targets.prefix(maxItems))
        let cappedBuckets = Array(buckets.prefix(maxItems))

        return MCPReviewPlan(
            schemaVersion: schemaVersion,
            source: "chobi",
            runId: details.run.id.uuidString,
            targets: cappedTargets,
            buckets: cappedBuckets,
            riskHighlights: Array(highlights.prefix(maxItems)),
            skimTargets: skimTargets,
            truncated: targets.count > cappedTargets.count || buckets.count > cappedBuckets.count,
            nextActions: ["chobi.explain_file", "chobi.get_impact_graph"]
        )
    }

    // MARK: - File Range

    nonisolated static func buildFileRange(
        workspaceId: String,
        path: String,
        revision: String,
        startLine: Int,
        endLine: Int,
        lines: [String]
    ) -> MCPFileRange {
        let numbered = (startLine...endLine).enumerated().compactMap {
            idx, lineNum -> MCPNumberedLine? in
            guard idx < lines.count else { return nil }
            return MCPNumberedLine(line: lineNum, text: lines[idx])
        }
        return MCPFileRange(
            schemaVersion: schemaVersion,
            source: "chobi",
            workspaceId: workspaceId,
            path: path,
            revision: revision,
            startLine: startLine,
            endLine: endLine,
            lines: numbered,
            truncated: false,
            nextActions: ["chobi.explain_symbol", "chobi.get_impact_graph"]
        )
    }

    // MARK: - Private Mapping Helpers

    nonisolated static func mapFinding(_ finding: Finding) -> MCPFinding {
        MCPFinding(
            id: finding.id.uuidString,
            severity: finding.severity.rawValue,
            category: finding.category.rawValue,
            message: finding.message,
            lineStart: finding.lineStart,
            lineEnd: finding.lineEnd,
            ruleSource: finding.ruleSource,
            evidence: finding.evidence
        )
    }

    nonisolated static func mapRiskHighlight(_ highlight: RiskHighlight) -> MCPRiskHighlight {
        MCPRiskHighlight(
            id: highlight.id,
            severity: highlight.severity.rawValue,
            category: highlight.category.rawValue,
            title: highlight.title,
            lineStart: highlight.lineStart,
            lineEnd: highlight.lineEnd,
            evidence: highlight.evidence.sorted(),
            confidence: highlight.confidence
        )
    }

    nonisolated static func mapBucket(_ bucket: ChangeBucket) -> MCPBucket {
        MCPBucket(
            id: bucket.id,
            type: bucket.type.rawValue,
            title: bucket.title,
            summary: bucket.summary,
            files: bucket.files.sorted(),
            symbols: bucket.symbols.sorted(),
            riskLevel: bucket.riskLevel.rawValue,
            riskReasons: bucket.riskReasons.sorted(),
            reviewOrder: bucket.reviewOrder
        )
    }

    private nonisolated static func mapReviewTarget(_ target: ReviewTarget) -> MCPReviewTarget {
        MCPReviewTarget(
            id: target.id.uuidString,
            priority: target.priority,
            severity: target.severity.rawValue,
            title: target.title,
            filePath: target.filePath,
            lineStart: target.lineStart,
            lineEnd: target.lineEnd,
            reason: target.reason,
            evidence: target.evidence,
            source: target.source
        )
    }

    private nonisolated static func mapSkimTarget(_ target: SkimTarget) -> MCPSkimTarget {
        MCPSkimTarget(
            id: target.id,
            filePath: target.filePath,
            reason: target.reason,
            classification: target.classification.rawValue,
            additions: target.additions,
            deletions: target.deletions
        )
    }

    private nonisolated static func mapHunk(
        _ hunk: DiffHunk,
        index: Int,
        detailLevel: AgentContextDetailLevel
    ) -> MCPHunk {
        let ranges = changedLineRanges(in: hunk)
        let previewLimit: Int
        switch detailLevel {
        case .summary: previewLimit = 0
        case .standard: previewLimit = 12
        case .full: previewLimit = 120
        }
        let preview = Array(hunk.lines.prefix(previewLimit))
        return MCPHunk(
            index: index,
            oldStart: hunk.oldStart,
            newStart: hunk.newStart,
            oldLines: hunk.oldLines,
            newLines: hunk.newLines,
            changedLineRanges: ranges,
            previewLines: preview,
            truncated: hunk.lines.count > preview.count
        )
    }

    private nonisolated static func changedLineRanges(in hunk: DiffHunk) -> [MCPLineRange] {
        var ranges: [MCPLineRange] = []
        var currentLine = hunk.newStart
        var pendingStart: Int?
        var previousAdded: Int?

        func finishPending() {
            if let start = pendingStart, let end = previousAdded {
                ranges.append(MCPLineRange(start: start, end: end))
            }
            pendingStart = nil
            previousAdded = nil
        }

        for rawLine in hunk.lines {
            if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                if pendingStart == nil { pendingStart = currentLine }
                previousAdded = currentLine
                currentLine += 1
            } else if rawLine.hasPrefix("-") {
                finishPending()
            } else {
                finishPending()
                currentLine += 1
            }
        }
        finishPending()
        return ranges
    }

    private nonisolated static func capHunkLines(_ hunks: [MCPHunk], maxLines: Int) -> [MCPHunk] {
        var remaining = maxLines
        return hunks.map { hunk in
            var copy = hunk
            if remaining <= 0 {
                copy.previewLines = []
                copy.truncated = true
                return copy
            }
            let prefix = Array(copy.previewLines.prefix(remaining))
            remaining -= prefix.count
            copy.truncated = copy.truncated || prefix.count < copy.previewLines.count
            copy.previewLines = prefix
            return copy
        }
    }

    private nonisolated static func count(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private nonisolated static func severityRank(_ severity: Severity) -> Int {
        switch severity {
        case .info: 1
        case .low: 2
        case .medium: 3
        case .high: 4
        }
    }

    private nonisolated static func targetMatchesFocus(
        _ target: MCPReviewTarget, focus: String
    ) -> Bool {
        let text = "\(target.title) \(target.reason) \(target.source)".lowercased()
        switch focus {
        case "needs_attention":
            return target.severity == "medium" || target.severity == "high"
        case "security":
            return text.contains("security") || text.contains("auth")
        case "contracts":
            return text.contains("contract") || text.contains("api")
        case "tests":
            return text.contains("test")
        default:
            return true
        }
    }

    private nonisolated static func bucketMatchesFocus(_ bucket: MCPBucket, focus: String) -> Bool {
        switch focus {
        case "security": return bucket.type == "auth-security"
        case "contracts": return bucket.type == "api-contract"
        case "tests": return bucket.type == "tests"
        default: return true
        }
    }
}
