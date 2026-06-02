import Foundation

// MARK: - AppState snapshot bridge

extension AppState: AgentContextSnapshotProviding {
    func agentContextSnapshot() -> AgentContextSnapshot {
        AgentContextSnapshot(
            repositories: repositories,
            selectedRepoId: selectedRepoId,
            selectedBranch: selectedBranch,
            selectedCommitSha: selectedCommitSha,
            currentDetails: analysisDetails,
            pullRequests: pullRequests
        )
    }
}

actor AgentContextQueryService {
    private let stateProvider: any AgentContextSnapshotProviding
    private let persistence: PersistenceService
    private let fileRangeLimit: Int

    init(
        stateProvider: any AgentContextSnapshotProviding,
        persistence: PersistenceService,
        fileRangeLimit: Int = 250
    ) {
        self.stateProvider = stateProvider
        self.persistence = persistence
        self.fileRangeLimit = fileRangeLimit
    }

    // MARK: - chobi.list_workspaces

    func listWorkspaces(includeInactive: Bool = true) async -> [MCPWorkspace] {
        let snapshot = await MainActor.run { stateProvider.agentContextSnapshot() }
        let prs = await persistence.allPullRequests()

        return snapshot.repositories
            .filter { includeInactive || $0.id == snapshot.selectedRepoId }
            .sorted { $0.name < $1.name }
            .map { repo in
                let repoPRs = prs.filter { $0.repository == "local/\(repo.name)" }
                let latestRun = repoPRs.compactMap(\.latestRun).sorted {
                    $0.createdAt > $1.createdAt
                }.first
                return MCPWorkspace(
                    id: repo.id.uuidString,
                    name: repo.name,
                    pathBasename: URL(fileURLWithPath: repo.path).lastPathComponent,
                    isSelected: repo.id == snapshot.selectedRepoId,
                    branch: repo.id == snapshot.selectedRepoId ? snapshot.selectedBranch : nil,
                    latestRunId: latestRun?.id.uuidString,
                    latestRunStatus: latestRun?.status.rawValue
                )
            }
    }

    // MARK: - chobi.get_analysis_summary

    func getAnalysisSummary(runId: UUID?) async throws -> MCPAnalysisSummary {
        let (details, repo, snapshot) = try await detailsForOptionalRun(runId)
        let activeBranch = repo?.id == snapshot.selectedRepoId ? snapshot.selectedBranch : nil
        return AgentContextBuilder.buildSummary(
            details: details,
            repository: repo,
            activeBranch: activeBranch
        )
    }

    // MARK: - chobi.list_changed_files

    func listChangedFiles(
        runId: UUID?,
        minSeverity: Severity?,
        maxItems: Int
    ) async throws -> MCPFileSummaryList {
        let (details, repo, _) = try await detailsForOptionalRun(runId)
        return AgentContextBuilder.buildFileSummaryList(
            details: details,
            repository: repo,
            maxItems: maxItems,
            minSeverity: minSeverity
        )
    }

    // MARK: - chobi.explain_file

    func explainFile(
        runId: UUID?,
        path: String,
        includeHunks: Bool,
        includeSymbols: Bool,
        includeFindings: Bool,
        maxHunkLines: Int
    ) async throws -> MCPFileDetail {
        let (details, _, _) = try await detailsForOptionalRun(runId)
        guard let file = details.files.first(where: { $0.path == path }) else {
            throw AgentContextError(code: .fileNotFound, message: "Changed file was not found.")
        }
        let symbols = includeSymbols ? details.symbols.filter { $0.changedFileId == file.id } : []
        let findings =
            includeFindings ? details.findings.filter { $0.changedFileId == file.id } : []
        let buckets = details.changeBuckets.filter { $0.files.contains(file.path) }
        let highlights = details.riskHighlights.filter { $0.filePath == file.path }

        return AgentContextBuilder.buildFileDetail(
            file: file,
            symbols: symbols,
            findings: findings,
            buckets: buckets,
            highlights: highlights,
            includeHunks: includeHunks,
            maxHunkLines: maxHunkLines,
            detailLevel: .full
        )
    }

    // MARK: - chobi.explain_symbol

    func explainSymbol(
        runId: UUID?,
        path: String?,
        symbolName: String,
        line: Int?,
        includeCallers: Bool,
        includeCallees: Bool
    ) async throws -> MCPSymbolDetail {
        let (details, _, _) = try await detailsForOptionalRun(runId)
        let fileById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0) })
        guard
            var symbol = details.symbols
                .filter({
                    $0.name == symbolName
                        && (path == nil || fileById[$0.changedFileId]?.path == path)
                        && (line == nil || ($0.startLine <= line! && $0.endLine >= line!))
                })
                .sorted(by: { $0.startLine < $1.startLine })
                .first
        else {
            throw AgentContextError(
                code: .symbolNotFound, message: "Changed symbol was not found.")
        }
        if !includeCallers { symbol.callers = [] }
        if !includeCallees { symbol.callees = [] }

        let filePath = fileById[symbol.changedFileId]?.path

        // Build a compact impact summary from caller/callee counts
        let impactSummary = makeImpactSummary(for: symbol, filePath: filePath)

        return AgentContextBuilder.buildSymbolDetail(
            symbol: symbol,
            filePath: filePath,
            impactSummary: impactSummary
        )
    }

    // MARK: - chobi.get_impact_graph

    func getImpactGraph(
        runId: UUID?,
        symbolName: String,
        path: String?,
        line: Int?
    ) async throws -> MCPImpactGraph {
        let (details, _, _) = try await detailsForOptionalRun(runId)
        let fileById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0) })
        guard
            let symbol = details.symbols
                .filter({
                    $0.name == symbolName
                        && (path == nil || fileById[$0.changedFileId]?.path == path)
                        && (line == nil || ($0.startLine <= line! && $0.endLine >= line!))
                })
                .sorted(by: { $0.startLine < $1.startLine })
                .first
        else {
            throw AgentContextError(
                code: .symbolNotFound, message: "Changed symbol was not found.")
        }

        let filePath = fileById[symbol.changedFileId]?.path
        let changedFilePaths = Set(details.files.map(\.path))
        let graph = await persistence.getSymbolGraph(runId: details.run.id)
        return AgentContextBuilder.buildImpactGraph(
            symbol: symbol,
            filePath: filePath,
            changedFilePaths: changedFilePaths,
            graph: graph
        )
    }

    // MARK: - chobi.get_review_plan

    func getReviewPlan(runId: UUID?, focus: String, maxItems: Int) async throws -> MCPReviewPlan {
        let (details, _, _) = try await detailsForOptionalRun(runId)
        return AgentContextBuilder.buildReviewPlan(
            details: details,
            focus: focus,
            maxItems: maxItems
        )
    }

    // MARK: - chobi.read_file_range

    func readFileRange(
        workspaceId: UUID?,
        path: String,
        startLine: Int,
        endLine: Int,
        revision: String
    ) async throws -> MCPFileRange {
        let snapshot = await MainActor.run { stateProvider.agentContextSnapshot() }
        guard
            let repo =
                workspaceId.flatMap({ id in snapshot.repositories.first { $0.id == id } })
                ?? selectedRepository(in: snapshot)
        else {
            throw AgentContextError(
                code: .workspaceNotSelected, message: "No workspace is selected.")
        }
        guard startLine > 0, endLine >= startLine else {
            throw AgentContextError(code: .invalidArguments, message: "Invalid line range.")
        }
        guard endLine - startLine + 1 <= fileRangeLimit else {
            throw AgentContextError(
                code: .lineRangeTooLarge,
                message: "File range exceeds \(fileRangeLimit) lines.")
        }

        let resolvedURL = try guardedFileURL(workspacePath: repo.path, relativePath: path)
        let content: String
        if revision == "working" {
            guard FileManager.default.isReadableFile(atPath: resolvedURL.path) else {
                throw AgentContextError(code: .fileNotFound, message: "File was not found.")
            }
            content = (try? String(contentsOf: resolvedURL, encoding: .utf8)) ?? ""
        } else if revision == "base" || revision == "head" {
            let (details, _, _) = try await detailsForOptionalRun(nil)
            let rev = revision == "base" ? details.run.baseSha : details.run.headSha
            content = GitService.fileContent(at: rev, path: path, cwd: repo.path)
        } else {
            throw AgentContextError(code: .invalidArguments, message: "Unsupported revision.")
        }
        guard !content.contains("\u{0}") else {
            throw AgentContextError(
                code: .fileNotFound, message: "Binary file content is not readable.")
        }

        let allLines = content.components(separatedBy: .newlines)
        guard startLine <= allLines.count else {
            throw AgentContextError(code: .fileNotFound, message: "Start line is outside the file.")
        }
        let cappedEnd = min(endLine, allLines.count)
        let lineTexts = Array(allLines[(startLine - 1)..<cappedEnd])

        return AgentContextBuilder.buildFileRange(
            workspaceId: repo.id.uuidString,
            path: path,
            revision: revision,
            startLine: startLine,
            endLine: cappedEnd,
            lines: lineTexts
        )
    }

    // MARK: - Private helpers

    private func detailsForOptionalRun(_ runId: UUID?) async throws -> (
        AnalysisDetails, GitRepository?, AgentContextSnapshot
    ) {
        let snapshot = await MainActor.run { stateProvider.agentContextSnapshot() }
        if let runId {
            let repo = repository(forRunId: runId, snapshot: snapshot)
            guard let details = await persistence.getAnalysisDetails(runId: runId)
            else {
                throw AgentContextError(code: .runNotFound, message: "Analysis run was not found.")
            }
            return (details, repo, snapshot)
        }
        guard let repo = selectedRepository(in: snapshot) else {
            throw AgentContextError(
                code: .workspaceNotSelected, message: "No workspace is selected.")
        }
        guard let details = snapshot.currentDetails else {
            throw AgentContextError(
                code: .analysisNotReady, message: "No completed analysis is loaded.")
        }
        return (details, repo, snapshot)
    }

    private func selectedRepository(in snapshot: AgentContextSnapshot) -> GitRepository? {
        guard let id = snapshot.selectedRepoId else { return nil }
        return snapshot.repositories.first { $0.id == id }
    }

    private func repository(forRunId runId: UUID, snapshot: AgentContextSnapshot)
        -> GitRepository?
    {
        let matchingPR = snapshot.pullRequests.first { $0.latestRun?.id == runId }
        guard let repository = matchingPR?.repository.replacingOccurrences(of: "local/", with: "")
        else { return selectedRepository(in: snapshot) }
        return snapshot.repositories.first { $0.name == repository }
            ?? selectedRepository(in: snapshot)
    }

    private func makeImpactSummary(for symbol: ChangedSymbol, filePath: String?) -> MCPImpactSummary
    {
        let callerFiles = Set(symbol.callers.compactMap { $0.components(separatedBy: ":").first })
        let fileCount = max(1, callerFiles.union(filePath.map { [$0] } ?? []).count)
        let impactLevel = ImpactScorer.level(for: symbol, fileCount: fileCount)
        return MCPImpactSummary(
            directCallerCount: symbol.callers.count,
            directCalleeCount: symbol.callees.count,
            transitiveCallerCount: symbol.callers.count,
            transitiveCalleeCount: symbol.callees.count,
            fileCount: fileCount,
            testReferenceCount: 0,
            impactLevel: impactLevel.rawValue,
            confidence: symbol.metadata["caller_resolution"] == "indexed" ? "high" : "low"
        )
    }

    private func guardedFileURL(workspacePath: String, relativePath: String) throws -> URL {
        let root = URL(fileURLWithPath: workspacePath).standardizedFileURL
        let candidate = URL(fileURLWithPath: relativePath, relativeTo: root).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            throw AgentContextError(
                code: .pathOutsideWorkspace,
                message: "Requested path resolves outside the workspace.")
        }
        return candidate
    }
}
