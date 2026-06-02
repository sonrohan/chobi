import AppKit
import SwiftUI

// MARK: - App State

@MainActor
@Observable
class AppState {
    // Registered Workspaces & Repositories
    var repositories: [GitRepository] = []
    var selectedRepoId: UUID?

    // PRs & Runs
    var pullRequests: [PullRequest] = []
    var selectedPRId: UUID?
    var analysisDetails: AnalysisDetails?

    // Local Git State
    var localBranches: [String] = []
    var localBranchSummaries: [LocalBranchSummary] = []
    var selectedBranch: String?

    // Commit Timeline
    var commits: [GitCommit] = []
    var selectedCommitSha: String? = nil  // nil = "All Changes"

    // UI Loading & Navigation States
    var isLoadingPRs = false
    var isLoadingAnalysis = false
    var diffLayout: DiffLayout = .unified
    var isAnalyzing = false

    var analysisError: String?

    let coordinator = AnalysisCoordinator()

    // Git File Watcher
    private var isWatcherRunning = false
    private var lastGitFingerprint: String?

    // Computed Properties
    var selectedRepo: GitRepository? {
        repositories.first { $0.id == selectedRepoId }
    }

    var selectedPR: PullRequest? {
        pullRequests.first { $0.id == selectedPRId }
    }

    var selectedBranchSummary: LocalBranchSummary? {
        guard let selectedBranch else { return localBranchSummaries.first(where: \.isCurrent) }
        return localBranchSummaries.first { $0.branch == selectedBranch }
    }

    // MARK: - Core Load & Refresh

    func load() async {
        isLoadingPRs = true

        repositories = await coordinator.allRepositories()

        if selectedRepoId == nil || !repositories.contains(where: { $0.id == selectedRepoId }) {
            selectedRepoId = repositories.first?.id
        }

        await refreshActiveRepo()
        isLoadingPRs = false

        startGitWatcher()
    }

    func selectRepo(_ id: UUID) async {
        selectedRepoId = id
        lastGitFingerprint = nil
        selectedPRId = nil
        analysisDetails = nil
        commits = []
        localBranchSummaries = []
        selectedCommitSha = nil

        isLoadingPRs = true
        await refreshActiveRepo()
        isLoadingPRs = false
    }

    func renameWorkspace(id: UUID, newName: String) async {
        await coordinator.renameRepository(id: id, newName: newName)
        await load()
    }

    func setWorkspaceAutoAnalyze(id: UUID, enabled: Bool) async {
        await coordinator.setRepositoryAutoAnalyze(id: id, enabled: enabled)
        repositories = await coordinator.allRepositories()
    }

    func refreshActiveRepo() async {
        guard let repo = selectedRepo else {
            localBranches = []
            selectedBranch = nil
            pullRequests = []
            localBranchSummaries = []
            selectedPRId = nil
            commits = []
            selectedCommitSha = nil
            analysisDetails = nil
            return
        }

        // Load local branches
        localBranches = await coordinator.listLocalBranches(repoPath: repo.path)

        let activeBranch = GitService.run("git rev-parse --abbrev-ref HEAD", cwd: repo.path)
        selectedBranch = activeBranch.isEmpty ? "main" : activeBranch

        // Load Pull Requests matching this repo name
        let allPRs = await coordinator.allPullRequests()
        pullRequests = allPRs.filter { $0.repository == "local/\(repo.name)" }

        localBranchSummaries = await coordinator.listLocalBranchSummaries(
            repoPath: repo.path,
            branches: localBranches,
            currentBranch: selectedBranch ?? "main",
            remotePRs: []
        )

        if selectedPRId == nil, let first = pullRequests.first {
            selectedPRId = first.id
        }

        if let id = selectedPRId {
            await loadDetails(for: id)
        }
    }

    func refreshWorkspace() async {
        isLoadingPRs = true
        await refreshActiveRepo()
        isLoadingPRs = false
    }

    func selectPR(_ id: UUID) async {
        selectedPRId = id
        analysisDetails = nil
        selectedCommitSha = nil  // Reset timeline to "All Changes"
        await loadDetails(for: id)
    }

    func selectBranch(_ branch: String) async {
        guard let repo = selectedRepo else { return }
        isAnalyzing = true
        analysisError = nil

        // Checkout local branch
        _ = GitService.run("git checkout \(branch)", cwd: repo.path)
        selectedBranch = branch

        // Run full analysis on this branch compared to main
        if let pr = await coordinator.analyzeRepo(path: repo.path, baseRef: "main") {
            pullRequests = await coordinator.allPullRequests().filter {
                $0.repository == "local/\(repo.name)"
            }
            await selectPR(pr.id)
        } else {
            analysisError = coordinator.analysisError ?? "Branch analysis failed"
        }
        isAnalyzing = false
    }

    func loadDetails(for prId: UUID) async {
        guard let pr = pullRequests.first(where: { $0.id == prId }),
            let run = pr.latestRun
        else { return }
        isLoadingAnalysis = true

        // Fetch chronological commits for timeline
        if let repo = selectedRepo {
            commits = await coordinator.listCommits(
                repoPath: repo.path, baseRef: pr.baseSha, headRef: pr.headSha)
        } else {
            commits = []
        }

        // Analyze specific commit or full PR
        if let sha = selectedCommitSha {
            if let repo = selectedRepo {
                await analyzeSingleCommit(repoPath: repo.path, sha: sha, pr: pr, run: run)
            }
        } else {
            analysisDetails = await coordinator.getDetails(
                for: run.id, repoPath: selectedRepo?.path)
        }

        isLoadingAnalysis = false

    }

    private func analyzeSingleCommit(
        repoPath: String, sha: String, pr: PullRequest, run: AnalysisRun
    ) async {
        var metrics = PerformanceMetrics()
        let startTotal = Date()

        let startGit = Date()
        let commitDiff = GitService.run("git diff \(sha)~1..\(sha)", cwd: repoPath)
        metrics.gitGatherDiffTime = Date().timeIntervalSince(startGit)

        guard !commitDiff.isEmpty else {
            self.analysisDetails = nil
            return
        }

        let startDiff = Date()
        let parsedFiles = DiffParser.parse(commitDiff)
        metrics.diffParsingTime = Date().timeIntervalSince(startDiff)
        metrics.changedFilesCount = parsedFiles.count

        let changedFiles = parsedFiles.map { pf -> ChangedFile in
            ChangedFile(
                analysisRunId: run.id,
                path: pf.newPath ?? pf.oldPath ?? "unknown",
                status: pf.status,
                additions: pf.additions,
                deletions: pf.deletions,
                classification: pf.classification,
                hunks: pf.hunks
            )
        }

        let astService = ASTAnalysisService()
        let astResult = await astService.extractChangedSymbols(
            repoPath: repoPath,
            baseRevision: "\(sha)~1",
            headRevision: sha,
            analysisRunId: run.id,
            changedFiles: changedFiles
        )
        let allSymbols = astResult.symbols
        metrics.astParseTime = astResult.parseTime
        metrics.astCompareTime = astResult.compareTime
        metrics.astCallGraphTime = astResult.callGraphTime
        metrics.trackedFilesCount = astResult.trackedFilesCount
        metrics.indexedFilesCount = astResult.indexedFilesCount
        metrics.symbolsCount = allSymbols.count

        let startRules = Date()
        let ruleResults = RulesEngine.runDeterministicRules(
            files: parsedFiles, symbols: allSymbols,
            filePathMap: Dictionary(uniqueKeysWithValues: changedFiles.map { ($0.id, $0.path) })
        )
        var allFindings: [Finding] = []
        for (path, rulefindings) in ruleResults {
            let matchFile = changedFiles.first { $0.path == path }
            guard let fileId = matchFile?.id else { continue }
            let dbFindings = rulefindings.map { rf -> Finding in
                Finding(
                    id: UUID(), analysisRunId: run.id, changedFileId: fileId,
                    severity: rf.severity, category: rf.category, message: rf.message,
                    lineStart: rf.lineStart, lineEnd: rf.lineEnd,
                    ruleSource: rf.ruleSource, evidence: rf.evidence
                )
            }
            allFindings.append(contentsOf: dbFindings)
        }

        let breakdown = RulesEngine.calculateRiskScore(
            files: parsedFiles, symbols: allSymbols,
            findings:
                allFindings.map {
                    RulesEngine.RuleFinding(
                        severity: $0.severity, category: $0.category, message: $0.message,
                        lineStart: $0.lineStart, lineEnd: $0.lineEnd, ruleSource: $0.ruleSource,
                        evidence: $0.evidence)
                })
        metrics.rulesEngineTime = Date().timeIntervalSince(startRules)

        let startTriage = Date()
        let triage = TriageEngine.deriveTriage(
            files: changedFiles, symbols: allSymbols, findings: allFindings,
            riskScore: breakdown.score)
        metrics.triageEngineTime = Date().timeIntervalSince(startTriage)

        var mockRun = run
        mockRun.riskScore = breakdown.score

        self.analysisDetails = AnalysisDetails(
            run: mockRun, pr: pr, files: changedFiles, symbols: allSymbols, findings: allFindings,
            reviewTargets: triage.reviewTargets,
            changeBuckets: triage.changeBuckets,
            riskHighlights: triage.riskHighlights,
            skimTargets: triage.skimTargets,
            riskFactors: triage.riskFactors,
            symbolReviewGroups: triage.symbolReviewGroups
        )

        metrics.totalTime = Date().timeIntervalSince(startTotal)
        coordinator.lastRunMetrics = metrics
    }

    func selectCommit(_ sha: String?) async {
        selectedCommitSha = sha
        if let prId = selectedPRId {
            await loadDetails(for: prId)
        }
    }

    // MARK: - Local Git Directory Watcher

    func startGitWatcher() {
        guard !isWatcherRunning else { return }
        isWatcherRunning = true

        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds
                guard let self = self, self.isWatcherRunning else { break }
                await self.checkGitIndex()
            }
        }
    }

    func stopGitWatcher() {
        isWatcherRunning = false
    }

    private func checkGitIndex() async {
        guard let repo = selectedRepo else { return }

        let fingerprint = gitFingerprint(repoPath: repo.path)
        guard !fingerprint.isEmpty else { return }

        if let last = lastGitFingerprint {
            if fingerprint != last {
                lastGitFingerprint = fingerprint
                if repo.autoAnalyzeEnabled, !isAnalyzing, !isLoadingAnalysis {
                    await reRunAnalysis()
                } else {
                    await refreshActiveRepo()
                }
            }
        } else {
            lastGitFingerprint = fingerprint
        }
    }

    private func gitFingerprint(repoPath: String) -> String {
        let head = GitService.run("git rev-parse HEAD 2>/dev/null", cwd: repoPath)
        let status = GitService.run("git status --porcelain", cwd: repoPath)
        return "\(head)\n\(status)"
    }

    func analyzeRepo(path: String, baseRef: String? = nil, autoAnalyzeEnabled: Bool = true) async {
        isAnalyzing = true
        analysisError = nil

        var resolvedPath = path
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let suffix = String(path.dropFirst())
            resolvedPath = home + suffix
        }

        let repoName = URL(fileURLWithPath: resolvedPath).lastPathComponent
        let standardized = URL(fileURLWithPath: resolvedPath).standardized.path
        let existing = repositories.first {
            URL(fileURLWithPath: $0.path).standardized.path == standardized
        }

        if existing == nil {
            let newRepo = await coordinator.addRepository(
                name: repoName, path: resolvedPath, autoAnalyzeEnabled: autoAnalyzeEnabled)
            repositories = await coordinator.allRepositories()
            selectedRepoId = newRepo.id
        } else {
            selectedRepoId = existing?.id
        }

        selectedPRId = nil
        analysisDetails = nil
        commits = []
        selectedCommitSha = nil

        let analysisBaseRef = baseRef ?? defaultAnalysisBaseRef(repoPath: resolvedPath)
        if let pr = await coordinator.analyzeRepo(path: resolvedPath, baseRef: analysisBaseRef) {
            await refreshActiveRepo()
            await selectPR(pr.id)
        } else {
            analysisError = coordinator.analysisError ?? "Analysis failed"
            await refreshActiveRepo()
        }
        isAnalyzing = false
    }

    func reRunAnalysis() async {
        guard let repo = selectedRepo else { return }
        AppLogger.shared.log(
            "User triggered manual analysis rerun for repo: \(repo.name)", tag: "AppState")
        isAnalyzing = true
        analysisError = nil

        let baseRef = defaultAnalysisBaseRef(repoPath: repo.path)
        let previousSelection = selectedCommitSha
        selectedCommitSha = nil

        if let pr = await coordinator.analyzeRepo(path: repo.path, baseRef: baseRef) {
            pullRequests = await coordinator.allPullRequests().filter {
                $0.repository == "local/\(repo.name)"
            }
            selectedPRId = pr.id

            await refreshActiveRepo()

            if let previousSelection, commits.contains(where: { $0.sha == previousSelection }) {
                await selectCommit(previousSelection)
            }
        } else {
            analysisError = coordinator.analysisError ?? "Analysis failed"
        }

        isAnalyzing = false
    }

    private func defaultAnalysisBaseRef(repoPath: String) -> String? {
        if !GitService.run("git rev-parse --verify main 2>/dev/null", cwd: repoPath).isEmpty {
            return "main"
        }
        if !GitService.run("git rev-parse --verify master 2>/dev/null", cwd: repoPath).isEmpty {
            return "master"
        }
        return selectedPR?.baseSha.isEmpty == false ? selectedPR?.baseSha : nil
    }

}

enum ExpandDirection {
    case up, down, all
}
