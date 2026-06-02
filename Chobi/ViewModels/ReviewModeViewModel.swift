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
