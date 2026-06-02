import SwiftUI
import XCTest

@testable import Chobi

@MainActor
final class ArchitectureTests: XCTestCase {

    // MARK: - ImpactGraphViewModel Tests

    func testImpactGraphViewModelRanksAndSearchesChangedSymbols() async {
        let run = AnalysisRun(pullRequestId: UUID(), baseSha: "base", headSha: "head")
        let pr = PullRequest(
            prNumber: 8, title: "Impact graph", baseSha: "base", headSha: "head",
            author: "Rohan", repository: "test")
        let serviceFile = ChangedFile(
            analysisRunId: run.id, path: "Chobi/Services/AppState.swift",
            status: .modified, additions: 12, deletions: 3, classification: .source, hunks: [])
        let helperFile = ChangedFile(
            analysisRunId: run.id, path: "Chobi/Core/Helpers.swift",
            status: .modified, additions: 4, deletions: 1, classification: .source, hunks: [])
        let centralSymbol = ChangedSymbol(
            analysisRunId: run.id,
            changedFileId: serviceFile.id,
            name: "runAnalysis",
            kind: .method,
            startLine: 42,
            endLine: 96,
            callers: [
                "Chobi/Views/ContentView.swift:ContentView.start",
                "Tests/AppStateTests.swift:testRunAnalysis",
                "Chobi/Services/MCPRequestRouter.swift:callTool",
            ],
            callees: ["extractChangedSymbols", "triage"],
            metadata: ["qualified_name": "AppState.runAnalysis", "caller_resolution": "indexed"]
        )
        let helperSymbol = ChangedSymbol(
            analysisRunId: run.id,
            changedFileId: helperFile.id,
            name: "formatLabel",
            kind: .function,
            startLine: 8,
            endLine: 12,
            callers: [],
            callees: []
        )
        let details = AnalysisDetails(
            run: run,
            pr: pr,
            files: [serviceFile, helperFile],
            symbols: [helperSymbol, centralSymbol],
            findings: [],
            reviewTargets: [],
            changeBuckets: [],
            riskHighlights: [],
            skimTargets: [],
            riskFactors: [],
            symbolReviewGroups: []
        )

        let viewModel = ImpactGraphViewModel()
        viewModel.load(details: details)

        XCTAssertEqual(viewModel.filteredImpacts.first?.symbol.name, "runAnalysis")
        XCTAssertEqual(viewModel.selectedImpact?.symbol.name, "runAnalysis")
        XCTAssertEqual(viewModel.selectedImpact?.summary.directCallerCount, 3)
        XCTAssertEqual(viewModel.selectedImpact?.summary.directCalleeCount, 2)
        XCTAssertEqual(viewModel.selectedImpact?.summary.testReferenceCount, 1)
        XCTAssertEqual(viewModel.selectedImpact?.summary.impactLevel, .medium)
        XCTAssertEqual(viewModel.highImpactCount, 0)
        XCTAssertEqual(viewModel.totalImpactedReferenceCount, 5)
        XCTAssertEqual(viewModel.impactedFileCount, 2)
        XCTAssertEqual(viewModel.symbolsWithoutTestsCount, 0)
        XCTAssertEqual(viewModel.impacts(for: serviceFile).map(\.symbol.name), ["runAnalysis"])

        viewModel.searchText = "helper"
        XCTAssertEqual(viewModel.filteredImpacts.map(\.symbol.name), ["formatLabel"])
    }

    func testInlineImpactMarkersPreferSpecificSymbolsOverContainers() async {
        let run = AnalysisRun(pullRequestId: UUID(), baseSha: "base", headSha: "head")
        let file = ChangedFile(
            analysisRunId: run.id,
            path: "app/src/main/java/app/ummi/myapplication/ui/viewmodels/HabitViewModel.kt",
            status: .modified,
            additions: 8,
            deletions: 2,
            classification: .source,
            hunks: [
                DiffHunk(
                    oldStart: 57,
                    oldLines: 10,
                    newStart: 61,
                    newLines: 18,
                    lines: [
                        "     }",
                        " ",
                        "     // Add a new habit",
                        "-    fun addHabit(name: String, description: String) {",
                        "+    fun addHabit(",
                        "+        name: String,",
                        "+        description: String,",
                        "+        weeklyTarget: Int = 5,",
                        "+    ) {",
                        "         if (name.isBlank()) return",
                    ])
            ])
        let container = ChangedSymbol(
            analysisRunId: run.id,
            changedFileId: file.id,
            name: "HabitViewModel",
            kind: .class,
            startLine: 14,
            endLine: 140,
            callers: ["app/src/main/java/app/ummi/myapplication/MainActivity.kt:HabitViewModel"]
        )
        let method = ChangedSymbol(
            analysisRunId: run.id,
            changedFileId: file.id,
            name: "addHabit",
            kind: .method,
            startLine: 64,
            endLine: 80,
            callers: [
                "app/src/main/java/app/ummi/myapplication/ui/screens/HabitManagerScreen.kt:addHabit"
            ],
            metadata: ["qualified_name": "HabitViewModel.addHabit"]
        )
        let details = AnalysisDetails(
            run: run,
            pr: PullRequest(
                prNumber: 9,
                title: "Habit target",
                baseSha: "base",
                headSha: "head",
                author: "Rohan",
                repository: "test"),
            files: [file],
            symbols: [container, method],
            findings: [],
            reviewTargets: [],
            changeBuckets: [],
            riskHighlights: [],
            skimTargets: [],
            riskFactors: [],
            symbolReviewGroups: []
        )

        let viewModel = ImpactGraphViewModel()
        viewModel.load(details: details)

        let markers = viewModel.inlineMarkers(for: file.hunks[0], file: file, hunkIndex: 0)

        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.rootSymbolId, method.id)
        XCTAssertEqual(markers.first?.anchorLine, 64)
        XCTAssertEqual(viewModel.visibleImpacts(for: file).map(\.id), [method.id])
        XCTAssertEqual(viewModel.fileImpactIndicators[file.id]?.count, 1)
    }

    // MARK: - ReviewModeViewModel Tests

    func testReviewModeViewModelFiltersAndTracksReviewedFiles() async {
        let run = AnalysisRun(pullRequestId: UUID(), baseSha: "base", headSha: "head")
        let sourceFile = ChangedFile(
            analysisRunId: run.id, path: "Chobi/Views/DiffViewer.swift",
            status: .modified, additions: 8, deletions: 2, classification: .source, hunks: [])
        let testFile = ChangedFile(
            analysisRunId: run.id, path: "Tests/DiffViewerTests.swift",
            status: .added, additions: 12, deletions: 0, classification: .test, hunks: [])
        let badge = ReviewFileTreeBadge(
            count: 2,
            severity: .high,
            highCount: 1,
            mediumCount: 0,
            callerCount: 3,
            weakTestCount: 1
        )
        let viewModel = ReviewModeViewModel()

        viewModel.fileSearchText = "views"
        XCTAssertEqual(
            viewModel.filteredFiles(
                orderedFiles: [sourceFile, testFile], badges: [sourceFile.id: badge]
            )
            .map(\.id),
            [sourceFile.id]
        )

        viewModel.fileSearchText = ""
        viewModel.excludedClassifications = [.test]
        XCTAssertEqual(
            viewModel.filteredFiles(
                orderedFiles: [sourceFile, testFile], badges: [sourceFile.id: badge]
            )
            .map(\.id),
            [sourceFile.id]
        )

        viewModel.markReviewed(sourceFile.id)
        viewModel.showUnviewedOnly = true
        viewModel.excludedClassifications = []
        XCTAssertEqual(
            viewModel.filteredFiles(
                orderedFiles: [sourceFile, testFile], badges: [sourceFile.id: badge]
            )
            .map(\.id),
            [testFile.id]
        )
    }

    func testReviewModeViewModelActiveFileFallbackAndNavigationUnhide() async {
        let run = AnalysisRun(pullRequestId: UUID(), baseSha: "base", headSha: "head")
        let lowFile = ChangedFile(
            analysisRunId: run.id, path: "Sources/Low.swift",
            status: .modified, additions: 2, deletions: 1, classification: .source, hunks: [])
        let highFile = ChangedFile(
            analysisRunId: run.id, path: "Sources/High.swift",
            status: .modified, additions: 6, deletions: 1, classification: .source, hunks: [])
        let lowBadge = ReviewFileTreeBadge(
            count: 1, severity: .low, highCount: 0, mediumCount: 0, callerCount: 1,
            weakTestCount: 1)
        let highBadge = ReviewFileTreeBadge(
            count: 3, severity: .high, highCount: 1, mediumCount: 0, callerCount: 5,
            weakTestCount: 0)
        let viewModel = ReviewModeViewModel()
        let badges = [lowFile.id: lowBadge, highFile.id: highBadge]

        viewModel.minimumImpactFilter = .high
        let filtered = viewModel.filteredFiles(orderedFiles: [lowFile, highFile], badges: badges)
        XCTAssertEqual(filtered.map(\.id), [highFile.id])
        XCTAssertEqual(
            viewModel.activeFile(activeFileId: lowFile.id, filteredFiles: filtered)?.id,
            highFile.id
        )

        viewModel.fileSearchText = "High"
        viewModel.excludedExtensions = [".swift"]
        viewModel.markReviewed(lowFile.id)
        viewModel.showUnviewedOnly = true
        viewModel.unhideForNavigation(file: lowFile, badges: badges)

        XCTAssertEqual(viewModel.minimumImpactFilter, .all)
        XCTAssertTrue(viewModel.fileSearchText.isEmpty)
        XCTAssertFalse(viewModel.excludedExtensions.contains(".swift"))
        XCTAssertFalse(viewModel.showUnviewedOnly)
    }

    // MARK: - WorkspacePickerViewModel Tests

    func testWorkspacePickerViewModelFiltering() async {
        let appState = AppState()

        // Mock repositories list
        appState.repositories = [
            GitRepository(name: "AppEngine", path: "/repos/app-engine", autoAnalyzeEnabled: true),
            GitRepository(name: "CoreLib", path: "/repos/core-lib", autoAnalyzeEnabled: false),
            GitRepository(name: "Website", path: "/repos/website", autoAnalyzeEnabled: true),
        ]

        let viewModel = WorkspacePickerViewModel(state: appState)

        // Test "All" filter and empty query
        viewModel.filter = .all
        viewModel.query = ""
        XCTAssertEqual(viewModel.visibleRepositories.count, 3)

        // Test query fuzzy search matching names
        viewModel.query = "core"
        XCTAssertEqual(viewModel.visibleRepositories.count, 1)
        XCTAssertEqual(viewModel.visibleRepositories.first?.name, "CoreLib")

        // Test query fuzzy search matching paths
        viewModel.query = "repos/app"
        XCTAssertEqual(viewModel.visibleRepositories.count, 1)
        XCTAssertEqual(viewModel.visibleRepositories.first?.name, "AppEngine")

        // Test segment filter "Auto" (autoAnalyzeEnabled = true)
        viewModel.query = ""
        viewModel.filter = .auto
        XCTAssertEqual(viewModel.visibleRepositories.count, 2)
        XCTAssertTrue(viewModel.visibleRepositories.allSatisfy(\.autoAnalyzeEnabled))

        // Test segment filter "Manual" (autoAnalyzeEnabled = false)
        viewModel.filter = .manual
        XCTAssertEqual(viewModel.visibleRepositories.count, 1)
        XCTAssertEqual(viewModel.visibleRepositories.first?.name, "CoreLib")
    }

    // MARK: - BranchPickerViewModel Tests

    func testBranchPickerViewModelFiltering() async {
        let appState = AppState()
        appState.selectedBranch = "feature/mvvm"

        // Mock branch summaries
        appState.localBranchSummaries = [
            LocalBranchSummary(
                branch: "main", isCurrent: false, isDirty: false, aheadCount: 0, behindCount: 0,
                upstream: "origin/main", relatedPRNumber: nil, relatedPRTitle: nil,
                lastAuthor: "Alice", lastUpdated: "2 days ago"),
            LocalBranchSummary(
                branch: "feature/mvvm", isCurrent: true, isDirty: true, aheadCount: 2,
                behindCount: 0, upstream: "origin/feature/mvvm", relatedPRNumber: 42,
                relatedPRTitle: "Harden app architecture", lastAuthor: "Rohan",
                lastUpdated: "5 mins ago"),
            LocalBranchSummary(
                branch: "feature/ast", isCurrent: false, isDirty: false, aheadCount: 0,
                behindCount: 1, upstream: "origin/feature/ast", relatedPRNumber: nil,
                relatedPRTitle: nil, lastAuthor: "Bob", lastUpdated: "1 day ago"),
        ]

        let viewModel = BranchPickerViewModel(state: appState)

        // Test "All" filter and empty query
        viewModel.filter = .all
        viewModel.query = ""
        XCTAssertEqual(viewModel.visibleSummaries.count, 3)

        // Test query matching author
        viewModel.query = "Alice"
        XCTAssertEqual(viewModel.visibleSummaries.count, 1)
        XCTAssertEqual(viewModel.visibleSummaries.first?.branch, "main")

        // Test query matching related PR Title
        viewModel.query = "architecture"
        XCTAssertEqual(viewModel.visibleSummaries.count, 1)
        XCTAssertEqual(viewModel.visibleSummaries.first?.branch, "feature/mvvm")

        // Test "Dirty" branch filter
        viewModel.query = ""
        viewModel.filter = .dirty
        XCTAssertEqual(viewModel.visibleSummaries.count, 1)
        XCTAssertEqual(viewModel.visibleSummaries.first?.branch, "feature/mvvm")

        // Test "Ahead" branch filter
        viewModel.filter = .ahead
        XCTAssertEqual(viewModel.visibleSummaries.count, 1)
        XCTAssertEqual(viewModel.visibleSummaries.first?.branch, "feature/mvvm")

        // Test "Behind" branch filter
        viewModel.filter = .behind
        XCTAssertEqual(viewModel.visibleSummaries.count, 1)
        XCTAssertEqual(viewModel.visibleSummaries.first?.branch, "feature/ast")
    }

    // MARK: - CommitScopeViewModel Tests

    func testCommitScopeViewModelTimelineCycling() async {
        let appState = AppState()

        // Mock chronological commits (reverse chronological order)
        appState.commits = [
            GitCommit(sha: "sha1", author: "Alice", subject: "Initial commit", date: "May 23"),
            GitCommit(sha: "sha2", author: "Bob", subject: "Add AST parser", date: "May 24"),
            GitCommit(
                sha: "sha3", author: "Rohan", subject: "Refactor architecture", date: "May 25"),
        ]

        let viewModel = CommitScopeViewModel(state: appState)

        // Initial state: "All Changes" (selectedCommitSha is nil)
        XCTAssertNil(viewModel.selectedCommitSha)
        XCTAssertTrue(viewModel.canGoToNextCommit)
        XCTAssertFalse(viewModel.canGoToPreviousCommit)  // Can't go left of "All changes"

        // Cycle next should go to C1 ("sha1")
        await viewModel.goToNextCommit()
        XCTAssertEqual(viewModel.selectedCommitSha, "sha1")
        XCTAssertTrue(viewModel.canGoToPreviousCommit)  // Can now go left back to "All changes"
        XCTAssertTrue(viewModel.canGoToNextCommit)

        // Cycle next should go to C2 ("sha2")
        await viewModel.goToNextCommit()
        XCTAssertEqual(viewModel.selectedCommitSha, "sha2")

        // Cycle next should go to C3 ("sha3")
        await viewModel.goToNextCommit()
        XCTAssertEqual(viewModel.selectedCommitSha, "sha3")
        XCTAssertFalse(viewModel.canGoToNextCommit)  // At latest commit, cannot cycle next

        // Cycle previous should go back to C2 ("sha2")
        await viewModel.goToPreviousCommit()
        XCTAssertEqual(viewModel.selectedCommitSha, "sha2")

        // Cycle previous should go back to C1 ("sha1")
        await viewModel.goToPreviousCommit()
        XCTAssertEqual(viewModel.selectedCommitSha, "sha1")

        // Cycle previous should go back to "All Changes" (nil)
        await viewModel.goToPreviousCommit()
        XCTAssertNil(viewModel.selectedCommitSha)
    }

    // MARK: - AnalysisViewModel Tests

    func testAnalysisViewModelInitialization() async {
        let appState = AppState()

        // Mock analysis run & details
        let run = AnalysisRun(pullRequestId: UUID(), baseSha: "base", headSha: "head")
        let pr = PullRequest(
            prNumber: 5, title: "Hardening test", baseSha: "base", headSha: "head", author: "Rohan",
            repository: "test")

        let files = [
            ChangedFile(
                analysisRunId: run.id, path: "App.swift", status: .modified, additions: 10,
                deletions: 5, classification: .source, hunks: []),
            ChangedFile(
                analysisRunId: run.id, path: "AppTests.swift", status: .added, additions: 20,
                deletions: 0, classification: .test, hunks: []),
            ChangedFile(
                analysisRunId: run.id, path: "README.md", status: .modified, additions: 5,
                deletions: 0, classification: .documentation, hunks: []),
        ]

        let targets = [
            ReviewTarget(
                id: UUID(), priority: 10, severity: .medium, title: "Test Target",
                filePath: "App.swift", reason: "Critical logic modified", evidence: "",
                source: "Deterministic Rules")
        ]

        appState.analysisDetails = AnalysisDetails(
            run: run,
            pr: pr,
            files: files,
            symbols: [],
            findings: [],
            reviewTargets: targets,
            changeBuckets: [],
            riskHighlights: [],
            skimTargets: [files[2]],
            riskFactors: [],
            symbolReviewGroups: []
        )

        let viewModel = AnalysisViewModel(state: appState)

        // Default state shows all changes
        XCTAssertEqual(viewModel.bucketFiles.count, 3)  // Every changed file
    }
}
