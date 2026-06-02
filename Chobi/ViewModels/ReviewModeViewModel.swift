import AppKit
import Foundation
import Observation

enum WorkspaceMode: String, Codable, CaseIterable {
    case review
    case explore
}

enum ReviewImpactFilter: String, Codable, CaseIterable {
    case all
    case medium
    case high
}

struct ReviewFileTreeBadge: Hashable {
    let count: Int
    let severity: ImpactLevel
    let highCount: Int
    let mediumCount: Int
    let callerCount: Int
    let weakTestCount: Int

    var helpText: String {
        "\(count) impact signal\(count == 1 ? "" : "s")\n\(highCount) high-impact changed symbol\(highCount == 1 ? "" : "s")\n\(callerCount) caller relationship\(callerCount == 1 ? "" : "s")\n\(weakTestCount) weak test signal\(weakTestCount == 1 ? "" : "s")"
    }
}

@Observable
@MainActor
class ReviewModeViewModel {
    var activeMode: WorkspaceMode = .review
    var selectedInlineImpactMarkerId: UUID? = nil
    var expandedInlineImpactIds: Set<UUID> = []
    var reviewedFileIds: Set<UUID> = []
    var fileSearchText: String = ""
    var excludedExtensions: Set<String> = []
    var excludedStatuses: Set<ChangedFile.FileStatus> = []
    var excludedClassifications: Set<ChangedFile.FileClassification> = []
    var showUnviewedOnly = false
    var compactFileTree = true
    var minimumImpactFilter: ReviewImpactFilter = .all
    var selectedInspectorTab = "impact"

    func orderedFiles(
        files: [ChangedFile], highlights: [RiskHighlight], analysisViewModel: AnalysisViewModel
    )
        -> [ChangedFile]
    {
        analysisViewModel.reorderFiles(files, highlights: highlights)
    }

    func filteredFiles(orderedFiles: [ChangedFile], badges: [UUID: ReviewFileTreeBadge])
        -> [ChangedFile]
    {
        orderedFiles.filter { file in
            if showUnviewedOnly && reviewedFileIds.contains(file.id) { return false }
            if excludedExtensions.contains(file.filterExtension) { return false }
            if excludedStatuses.contains(file.status) { return false }
            if excludedClassifications.contains(file.classification) { return false }
            if !passesImpactFilter(file: file, badges: badges) { return false }
            return file.matchesReviewSearch(fileSearchText)
        }
    }

    func activeFile(activeFileId: UUID?, filteredFiles: [ChangedFile]) -> ChangedFile? {
        guard let activeFileId else { return filteredFiles.first }
        return filteredFiles.first { $0.id == activeFileId } ?? filteredFiles.first
    }

    func activeFilterCount() -> Int {
        var count =
            excludedExtensions.count + excludedStatuses.count + excludedClassifications.count
        if !fileSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if showUnviewedOnly { count += 1 }
        return count
    }

    func markReviewed(_ fileId: UUID?) {
        guard let fileId else { return }
        reviewedFileIds.insert(fileId)
    }

    func toggleInlineImpactExpansion(_ impactId: UUID) {
        if expandedInlineImpactIds.contains(impactId) {
            expandedInlineImpactIds.remove(impactId)
        } else {
            expandedInlineImpactIds.insert(impactId)
        }
    }

    func shouldAutoOpenInspector(file: ChangedFile?, badges: [UUID: ReviewFileTreeBadge]) -> Bool {
        guard let file else { return false }
        return badges[file.id]?.highCount ?? 0 > 0
    }

    func copyFileContext(file: ChangedFile, impacts: [SymbolImpact], details: AnalysisDetails) {
        let findings = details.findings.filter { $0.changedFileId == file.id }
        copy(
            [
                "# File Review Context",
                "",
                "Path: `\(file.path)`",
                "Status: \(file.status.displayName)",
                "Type: \(file.classification.displayName)",
                "Diff size: +\(file.additions) / -\(file.deletions)",
                "",
                "## Impact Signals",
                impacts.isEmpty
                    ? "No caller/dependency impact signals detected."
                    : impacts.prefix(8).map(impactLine).joined(separator: "\n"),
                "",
                "## Findings",
                findings.isEmpty
                    ? "No findings for this file."
                    : findings.prefix(8).map(findingLine).joined(separator: "\n"),
                "",
                "## Diff Hunks",
                file.hunks.prefix(5).enumerated().map { index, hunk in
                    hunkLine(index: index, hunk: hunk)
                }.joined(separator: "\n"),
            ].joined(separator: "\n")
        )
    }

    func copyImpactContext(_ impact: SymbolImpact) {
        copy(
            [
                "# Impact Review Context",
                "",
                "Symbol: `\(impact.symbol.name)`",
                "Kind: \(impact.symbol.kind.rawValue)",
                "Location: `\(impact.location)`",
                "Impact: \(impact.summary.impactLevel.displayName)",
                "Callers: \(impact.summary.directCallerCount)",
                "Callees: \(impact.summary.directCalleeCount)",
                "Affected files: \(impact.summary.fileCount)",
                "Test references: \(impact.summary.testReferenceCount)",
                "",
                "## Why It Matters",
                impact.reason ?? "Review caller and callee relationships for this changed symbol.",
                "",
                "## Callers",
                boundedList(impact.symbol.callers),
                "",
                "## Callees",
                boundedList(impact.symbol.callees),
            ].joined(separator: "\n")
        )
    }

    func copyTargetContext(_ target: ReviewTarget) {
        copy(
            [
                "# Review Target Context",
                "",
                "Title: \(target.title)",
                "Severity: \(target.severity.rawValue.capitalized)",
                "Source: \(target.source)",
                "Location: `\(target.filePath)\(target.lineStart.map { ":L\($0)" } ?? "")`",
                "",
                "## Evidence",
                target.evidence.isEmpty ? "No evidence provided." : target.evidence,
            ].joined(separator: "\n")
        )
    }

    func copyFullReviewPlan(details: AnalysisDetails) {
        copy(reviewPlanText(details: details))
    }

    func reviewPlanText(details: AnalysisDetails) -> String {
        let filesById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0) })
        let findingsByFileId = Dictionary(grouping: details.findings, by: \.changedFileId)
        let symbolsByFileId = Dictionary(grouping: details.symbols, by: \.changedFileId)
        let skimPaths = Set(details.skimTargets.map(\.filePath))
        let reviewTargetFileIds = Set(details.reviewTargets.compactMap(\.changedFileId))
        let riskHighlightFilePaths = Set(details.riskHighlights.map(\.filePath))
        let highSignalFiles = details.files
            .filter { file in
                reviewTargetFileIds.contains(file.id) || riskHighlightFilePaths.contains(file.path)
                    || (findingsByFileId[file.id]?.contains { $0.severity >= .medium } ?? false)
                    || (symbolsByFileId[file.id]?.contains(where: isHighSignalSymbol) ?? false)
            }
            .sorted { lhs, rhs in
                fileReviewScore(lhs, targets: details.reviewTargets, findings: findingsByFileId)
                    > fileReviewScore(
                        rhs, targets: details.reviewTargets, findings: findingsByFileId)
            }
        let supportingFiles = details.files
            .filter { file in
                !highSignalFiles.contains { $0.id == file.id } && !skimPaths.contains(file.path)
            }
            .sorted { lhs, rhs in
                if lhs.classification != rhs.classification {
                    return lhs.classification.displayName < rhs.classification.displayName
                }
                return lhs.path < rhs.path
            }

        let reviewOrderSection =
            if details.reviewTargets.isEmpty {
                "No priority review targets were detected. Start with high-signal files, then supporting files."
            } else {
                details.reviewTargets.prefix(16).map(reviewTargetBlock).joined(separator: "\n")
            }
        let highSignalSection =
            if highSignalFiles.isEmpty {
                "No high-signal files were detected."
            } else {
                highSignalFiles.prefix(14).map {
                    fileTraceBlock(
                        $0,
                        targets: details.reviewTargets,
                        findings: findingsByFileId[$0.id] ?? [],
                        symbols: symbolsByFileId[$0.id] ?? []
                    )
                }.joined(separator: "\n")
            }
        let findingsSection =
            if details.findings.isEmpty {
                "No rule findings were reported."
            } else {
                details.findings.sorted(by: findingSort).prefix(16).map {
                    findingTraceLine($0, filesById: filesById)
                }.joined(separator: "\n")
            }
        let bucketsSection =
            if details.changeBuckets.isEmpty {
                "No semantic buckets were reported."
            } else {
                details.changeBuckets.prefix(8).map(bucketTraceBlock).joined(separator: "\n")
            }
        let supportingFilesSection =
            if supportingFiles.isEmpty {
                "No additional supporting files."
            } else {
                supportingFiles.prefix(16).map(fileSummaryLine).joined(separator: "\n")
            }
        let skimSection =
            if details.skimTargets.isEmpty {
                "No files were marked safe to skim."
            } else {
                details.skimTargets.prefix(16).map(skimLine).joined(separator: "\n")
            }
        let riskFactorsSection =
            if details.riskFactors.isEmpty {
                "No aggregate risk factors were reported."
            } else {
                details.riskFactors.prefix(10).map { "- \($0)" }.joined(separator: "\n")
            }

        let sections = [
            "# AI Review Plan",
            "",
            "Use this as an evidence index for code review. Verify claims against the diff; do not invent risk beyond the concrete signals listed here.",
            "",
            "## Change Identity",
            "- Repository: `\(details.pr.repository)`",
            "- PR: #\(details.pr.prNumber) \(details.pr.title)",
            "- Author: \(details.pr.author)",
            "- Base: `\(shortSha(details.run.baseSha))`",
            "- Head: `\(shortSha(details.run.headSha))`",
            "- Risk score: \(details.run.riskScore)",
            "- Changed files: \(details.files.count)",
            "- Changed symbols: \(details.symbols.count)",
            "- Findings: \(details.findings.count)",
            "",
            "## Review Order",
            reviewOrderSection,
            "",
            "## Blast Radius Signals",
            blastRadiusLines(details.symbols, filesById: filesById),
            "",
            "## High-Signal Files",
            highSignalSection,
            "",
            "## Findings",
            findingsSection,
            "",
            "## Change Buckets",
            bucketsSection,
            "",
            "## Supporting Files",
            supportingFilesSection,
            "",
            "## Safe To Skim",
            skimSection,
            "",
            "## Risk Factors",
            riskFactorsSection,
        ]
        return sections.joined(separator: "\n")
    }

    func resetFileFilters() {
        fileSearchText = ""
        excludedExtensions = []
        excludedStatuses = []
        excludedClassifications = []
        showUnviewedOnly = false
        minimumImpactFilter = .all
    }

    func badgeSummaries(from indicators: [UUID: FileImpactIndicator]) -> [UUID: ReviewFileTreeBadge]
    {
        Dictionary(
            uniqueKeysWithValues: indicators.compactMap { fileId, indicator in
                guard indicator.count > 0 else { return nil }
                return (fileId, indicator.reviewBadge)
            }
        )
    }

    func unhideForNavigation(file: ChangedFile, badges: [UUID: ReviewFileTreeBadge]) {
        if minimumImpactFilter != .all && !passesImpactFilter(file: file, badges: badges) {
            minimumImpactFilter = .all
        }
        excludedExtensions.remove(file.filterExtension)
        excludedStatuses.remove(file.status)
        excludedClassifications.remove(file.classification)
        if showUnviewedOnly && reviewedFileIds.contains(file.id) {
            showUnviewedOnly = false
        }
        if !fileSearchText.isEmpty && !file.matchesReviewSearch(fileSearchText) {
            fileSearchText = ""
        }
    }

    private func passesImpactFilter(file: ChangedFile, badges: [UUID: ReviewFileTreeBadge]) -> Bool
    {
        switch minimumImpactFilter {
        case .all:
            return true
        case .high:
            return badges[file.id]?.highCount ?? 0 > 0
        case .medium:
            guard let badge = badges[file.id] else { return false }
            return badge.highCount > 0 || badge.mediumCount > 0
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func boundedList(_ values: [String]) -> String {
        guard !values.isEmpty else { return "None detected." }
        return values.prefix(12).map { "- `\($0)`" }.joined(separator: "\n")
    }

    private func impactLine(_ impact: SymbolImpact) -> String {
        "- \(impact.summary.impactLevel.displayName): `\(impact.symbol.name)` at `\(impact.location)` (\(impact.summary.directCallerCount) callers, \(impact.summary.fileCount) files)"
    }

    private func findingLine(_ finding: Finding) -> String {
        "- \(finding.severity.rawValue.capitalized): \(finding.message)"
    }

    private func targetLine(_ target: ReviewTarget) -> String {
        "- \(target.severity.rawValue.capitalized): \(target.title) (`\(target.filePath)`)"
    }

    private func hunkLine(index: Int, hunk: DiffHunk) -> String {
        "- Hunk \(index + 1): @@ -\(hunk.oldStart),\(hunk.oldLines) +\(hunk.newStart),\(hunk.newLines) @@"
    }

    private func reviewTargetBlock(_ target: ReviewTarget) -> String {
        [
            "- P\(target.priority) \(target.severity.rawValue.uppercased()): \(target.title)",
            "  - Location: `\(location(target.filePath, target.lineStart, target.lineEnd))`",
            "  - Source: \(target.source)",
            "  - Reason: \(target.reason)",
            "  - Evidence: \(target.evidence.isEmpty ? "No evidence text reported." : target.evidence)",
        ].joined(separator: "\n")
    }

    private func blastRadiusLines(_ symbols: [ChangedSymbol], filesById: [UUID: ChangedFile])
        -> String
    {
        let importantSymbols =
            symbols
            .filter(isHighSignalSymbol)
            .sorted { lhs, rhs in symbolImpactScore(lhs) > symbolImpactScore(rhs) }
            .prefix(16)
        guard !importantSymbols.isEmpty else {
            return
                "No changed symbols had detected caller/callee fan-out, public surface metadata, or weak test signals."
        }
        return importantSymbols.map { symbol in
            let filePath = filesById[symbol.changedFileId]?.path ?? "unknown"
            let affectedFiles = Set(symbol.callers.map(pathPrefix)).subtracting([""])
            let testCallers = symbol.callers.filter(isTestReference).count
            return [
                "- `\(symbol.name)` (\(symbol.kind.rawValue)) at `\(location(filePath, symbol.startLine, symbol.endLine))`",
                "  - Callers: \(symbol.callers.count); callees: \(symbol.callees.count); affected caller files: \(affectedFiles.count); test callers: \(testCallers)",
                "  - Metadata: \(symbolMetadataLine(symbol))",
                "  - Top callers: \(inlineList(symbol.callers.prefix(5).map(displayName)))",
                "  - Top callees: \(inlineList(symbol.callees.prefix(5).map(displayName)))",
            ].joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func fileTraceBlock(
        _ file: ChangedFile,
        targets: [ReviewTarget],
        findings: [Finding],
        symbols: [ChangedSymbol]
    ) -> String {
        let fileTargets = targets.filter { $0.changedFileId == file.id || $0.filePath == file.path }
        let highSymbols = symbols.sorted { symbolImpactScore($0) > symbolImpactScore($1) }.prefix(8)
        let diffAnchors =
            file.hunks.isEmpty
            ? "None reported"
            : file.hunks.prefix(4).enumerated().map {
                hunkLine(index: $0.offset, hunk: $0.element)
            }.joined(separator: "; ")
        return [
            "- `\(file.path)`",
            "  - Status/type/size: \(file.status.displayName), \(file.classification.displayName), +\(file.additions) / -\(file.deletions)",
            "  - Diff anchors: \(diffAnchors)",
            "  - Review targets: \(fileTargets.isEmpty ? "None" : fileTargets.prefix(4).map(\.title).joined(separator: " | "))",
            "  - Findings: \(findings.isEmpty ? "None" : findings.sorted(by: findingSort).prefix(4).map { "\($0.severity.rawValue): \($0.message)" }.joined(separator: " | "))",
            "  - Changed symbols: \(highSymbols.isEmpty ? "None detected" : highSymbols.map(symbolInlineTrace).joined(separator: " | "))",
        ].joined(separator: "\n")
    }

    private func findingTraceLine(_ finding: Finding, filesById: [UUID: ChangedFile]) -> String {
        let filePath = filesById[finding.changedFileId]?.path ?? "unknown"
        return
            "- \(finding.severity.rawValue.uppercased()) \(finding.category.rawValue): \(finding.message) at `\(location(filePath, finding.lineStart, finding.lineEnd))`; source=\(finding.ruleSource); evidence=\(finding.evidence ?? "none")"
    }

    private func bucketTraceBlock(_ bucket: ChangeBucket) -> String {
        [
            "- \(bucket.riskLevel.rawValue.uppercased()) \(bucket.title)",
            "  - Summary: \(bucket.summary)",
            "  - Files: \(inlineList(bucket.files.prefix(8)))",
            "  - Symbols: \(inlineList(bucket.symbols.prefix(8)))",
            "  - Reasons: \(inlineList(bucket.riskReasons.prefix(5)))",
            "  - Evidence: \(inlineList(bucket.evidence.prefix(5)))",
        ].joined(separator: "\n")
    }

    private func skimLine(_ target: SkimTarget) -> String {
        "- `\(target.filePath)` (+\(target.additions) / -\(target.deletions)): \(target.reason)"
    }

    private func fileSummaryLine(_ file: ChangedFile) -> String {
        "- `\(file.path)` (\(file.status.displayName), \(file.classification.displayName), +\(file.additions) / -\(file.deletions))"
    }

    private func symbolInlineTrace(_ symbol: ChangedSymbol) -> String {
        "`\(symbol.name)` L\(symbol.startLine)-L\(symbol.endLine), callers=\(symbol.callers.count), callees=\(symbol.callees.count)"
    }

    private func symbolMetadataLine(_ symbol: ChangedSymbol) -> String {
        let keys = ["qualified_name", "semantic_area", "visibility", "is_public", "is_test"]
        let values = keys.compactMap { key -> String? in
            guard let value = symbol.metadata[key], !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }
        return values.isEmpty ? "none" : values.joined(separator: ", ")
    }

    private func isHighSignalSymbol(_ symbol: ChangedSymbol) -> Bool {
        !symbol.callers.isEmpty || !symbol.callees.isEmpty
            || symbol.metadata["visibility"] == "public"
            || symbol.metadata["is_public"] == "true"
            || symbol.metadata["is_test"] == "true"
    }

    private func symbolImpactScore(_ symbol: ChangedSymbol) -> Int {
        var score = symbol.callers.count * 100 + symbol.callees.count * 20
        if symbol.metadata["visibility"] == "public" || symbol.metadata["is_public"] == "true" {
            score += 500
        }
        if symbol.metadata["is_test"] == "true" { score -= 50 }
        return score
    }

    private func fileReviewScore(
        _ file: ChangedFile,
        targets: [ReviewTarget],
        findings: [UUID: [Finding]]
    ) -> Int {
        let targetScore = targets.filter { $0.changedFileId == file.id || $0.filePath == file.path }
            .reduce(0) { $0 + $1.severity.score * 100 + max(0, 20 - $1.priority) }
        let findingScore = (findings[file.id] ?? []).reduce(0) { $0 + $1.severity.score * 80 }
        return targetScore + findingScore + file.additions + file.deletions
    }

    private func findingSort(_ lhs: Finding, _ rhs: Finding) -> Bool {
        if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
        return lhs.message < rhs.message
    }

    private func location(_ filePath: String, _ startLine: Int?, _ endLine: Int?) -> String {
        guard let startLine else { return filePath }
        guard let endLine, endLine != startLine else { return "\(filePath):L\(startLine)" }
        return "\(filePath):L\(startLine)-L\(endLine)"
    }

    private func inlineList<S: Sequence>(_ values: S) -> String where S.Element == String {
        let cleaned = values.map { $0 }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? "none" : cleaned.map { "`\($0)`" }.joined(separator: ", ")
    }

    private func shortSha(_ sha: String) -> String {
        String(sha.prefix(12))
    }

    private func isTestReference(_ row: String) -> Bool {
        let lowercased = row.lowercased()
        return lowercased.contains("test") || lowercased.contains("spec")
    }

    private func displayName(_ row: String) -> String {
        row.components(separatedBy: ":").last ?? row
    }

    private func pathPrefix(_ row: String) -> String {
        row.components(separatedBy: ":").first ?? row
    }
}

extension ChangedFile {
    var filterExtension: String {
        let ext = URL(fileURLWithPath: path).pathExtension
        return ext.isEmpty ? "No extension" : ".\(ext)"
    }

    func matchesReviewSearch(_ text: String) -> Bool {
        let terms =
            text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { String($0).lowercased() }
        guard !terms.isEmpty else { return true }

        let haystack = "\(path) \(filename) \(classification.displayName) \(status.displayName)"
            .lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }
}

extension FileImpactIndicator {
    var reviewBadge: ReviewFileTreeBadge {
        let severity: ImpactLevel =
            if highCount > 0 {
                .high
            } else if mediumCount > 0 {
                .medium
            } else {
                .low
            }
        return ReviewFileTreeBadge(
            count: count,
            severity: severity,
            highCount: highCount,
            mediumCount: mediumCount,
            callerCount: callerCount,
            weakTestCount: weakTestCount
        )
    }
}
