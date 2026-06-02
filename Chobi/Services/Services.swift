import Combine
import Foundation
import SwiftData

// MARK: - Git Service
// Handles running git commands and analyzing local repos

actor GitService {

    enum GitError: Error, LocalizedError {
        case notAGitRepo(String)
        case noDiff(String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAGitRepo(let p): "Not a git repository: \(p)"
            case .noDiff(let msg): msg
            case .commandFailed(let msg): msg
            }
        }
    }

    static func run(_ command: String, cwd: String) -> String {
        AppLogger.shared.log("Running shell command: \(command) (cwd: \(cwd))", tag: "Git")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let result =
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        AppLogger.shared.log(
            "Command complete. Output: \(result.prefix(120))\(result.count > 120 ? "..." : "") (\(result.count) chars)",
            tag: "Git")
        return result
    }

    static func runGit(_ arguments: [String], cwd: String) -> String {
        AppLogger.shared.log(
            "Running Git: git \(arguments.joined(separator: " ")) (cwd: \(cwd))", tag: "Git")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let result =
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        AppLogger.shared.log(
            "Git complete. Output: \(result.prefix(120))\(result.count > 120 ? "..." : "") (\(result.count) chars)",
            tag: "Git")
        return result
    }

    static func fileContent(at revision: String, path filePath: String, cwd: String) -> String {
        runGit(["show", "\(revision):\(filePath)"], cwd: cwd)
    }

    static func trackedSourceFiles(cwd: String, revision: String? = nil) -> [String] {
        let output: String
        if let revision, !revision.isEmpty {
            output = runGit(["ls-tree", "-r", "--name-only", revision], cwd: cwd)
        } else {
            output = runGit(["ls-files"], cwd: cwd)
        }
        guard !output.isEmpty else { return [] }
        let supportedExtensions: Set<String> = [
            "swift", "kt", "kts", "ts", "tsx", "js", "jsx", "py", "rs",
        ]
        return output.components(separatedBy: .newlines).filter { path in
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            return supportedExtensions.contains(ext)
        }
    }

    func gatherDiff(repoPath: String, baseRef: String?) throws -> (
        diff: String, branchName: String, commitSubject: String,
        baseSha: String, headSha: String, author: String, prNumber: Int
    ) {
        // Verify it's a git repo
        let checkGit = GitService.run("git rev-parse --show-toplevel 2>/dev/null", cwd: repoPath)
        guard !checkGit.isEmpty else {
            throw GitError.notAGitRepo(repoPath)
        }

        let branchName = GitService.run("git rev-parse --abbrev-ref HEAD", cwd: repoPath)
        let commitSubject = GitService.run("git log -1 --pretty=%s", cwd: repoPath)
        let headSha = GitService.run("git rev-parse HEAD", cwd: repoPath)
        let author = GitService.run("git config user.name", cwd: repoPath)

        // Get diff
        var diff = ""
        var resolvedBaseRef = baseRef
        if let base = baseRef, !base.isEmpty {
            diff = GitService.run("git diff \(base)", cwd: repoPath)
        } else {
            // Try main, then HEAD~1
            diff = GitService.run("git diff main", cwd: repoPath)
            if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolvedBaseRef = "HEAD~1"
                diff = GitService.run("git diff HEAD~1", cwd: repoPath)
            } else {
                resolvedBaseRef = "main"
            }
        }

        if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GitError.noDiff(
                "No diff found against main or HEAD~1. Make sure you have local changes or commits."
            )
        }

        // Deterministic base SHA and PR number
        let baseSha = GitService.run("git rev-parse \(resolvedBaseRef ?? "HEAD~1")", cwd: repoPath)
            .prefix(40).description
        let prNumber = stableHash(branchName) % 1000 + 1

        return (
            diff, branchName.isEmpty ? "feature-branch" : branchName,
            commitSubject.isEmpty ? "Local analysis" : commitSubject,
            baseSha.isEmpty ? String(repeating: "0", count: 40) : baseSha,
            headSha.isEmpty ? String(repeating: "1", count: 40) : headSha,
            author.isEmpty ? "local-developer" : author,
            prNumber
        )
    }

    private func stableHash(_ s: String) -> Int {
        var hash = 0
        for ch in s.unicodeScalars {
            hash = (hash << 5) &- hash &+ Int(ch.value)
        }
        return abs(hash)
    }

    func listCommits(repoPath: String, baseRef: String, headRef: String) -> [GitCommit] {
        let format = "%H|%an|%s|%ad"
        let output = GitService.run(
            "git log --pretty=format:\"\(format)\" --reverse \(baseRef)..\(headRef)", cwd: repoPath)
        guard !output.isEmpty else { return [] }

        return output.components(separatedBy: .newlines).compactMap { line -> GitCommit? in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 4 else { return nil }
            return GitCommit(sha: parts[0], author: parts[1], subject: parts[2], date: parts[3])
        }
    }

    func diffForCommit(repoPath: String, sha: String) -> String {
        return GitService.run("git show \(sha)", cwd: repoPath)
    }

    func listLocalBranches(repoPath: String) -> [String] {
        let output = GitService.run("git branch --format=\"%(refname:short)\"", cwd: repoPath)
        guard !output.isEmpty else { return ["main"] }
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains(" ") }
    }

    func listLocalBranchSummaries(
        repoPath: String, branches: [String], currentBranch: String, remotePRs: [PullRequest]
    ) -> [LocalBranchSummary] {
        let dirty = !GitService.run("git status --porcelain", cwd: repoPath).isEmpty

        return branches.map { branch in
            let quotedBranch = shellQuote(branch)
            let upstream = resolvedUpstream(repoPath: repoPath, branch: branch)
            let counts = aheadBehindCounts(repoPath: repoPath, upstream: upstream, branch: branch)
            let last = GitService.run(
                "git log -1 --pretty=format:%an'|'%cr \(quotedBranch)", cwd: repoPath)
            let lastParts = last.components(separatedBy: "|")
            let author =
                lastParts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            let updated =
                lastParts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "unknown"
            let relatedPR = remotePRs.first { pr in
                let headBranch = pr.headSha.replacingOccurrences(of: "origin/", with: "")
                return headBranch == branch || branch == "review/pr-\(pr.prNumber)"
            }

            return LocalBranchSummary(
                branch: branch,
                isCurrent: branch == currentBranch,
                isDirty: branch == currentBranch && dirty,
                aheadCount: counts.ahead,
                behindCount: counts.behind,
                upstream: upstream,
                relatedPRNumber: relatedPR?.prNumber,
                relatedPRTitle: relatedPR?.title,
                lastAuthor: author.isEmpty ? "unknown" : author,
                lastUpdated: updated.isEmpty ? "unknown" : updated
            )
        }
    }

    private func resolvedUpstream(repoPath: String, branch: String) -> String? {
        let quotedBranch = shellQuote(branch)
        let configured = GitService.run(
            "git rev-parse --abbrev-ref \(quotedBranch)@{upstream} 2>/dev/null", cwd: repoPath)
        if !configured.isEmpty { return configured }

        let originBranch = "origin/\(branch)"
        let exists = GitService.run(
            "git rev-parse --verify --quiet \(shellQuote(originBranch))", cwd: repoPath)
        return exists.isEmpty ? nil : originBranch
    }

    private func aheadBehindCounts(repoPath: String, upstream: String?, branch: String) -> (
        ahead: Int, behind: Int
    ) {
        guard let upstream else { return (0, 0) }
        let output = GitService.run(
            "git rev-list --left-right --count \(shellQuote(upstream))...\(shellQuote(branch))",
            cwd: repoPath)
        let parts = output.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Int($0) }
        guard parts.count == 2 else { return (0, 0) }
        return (parts[1], parts[0])
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    func checkoutPR(repoPath: String, prNumber: Int, branchName: String) throws {
        let ghCheck = GitService.run("which gh", cwd: repoPath)
        if !ghCheck.isEmpty {
            let output = GitService.run("gh pr checkout \(prNumber) 2>&1", cwd: repoPath)
            if output.contains("error") || output.contains("Failed") {
                try manualCheckout(repoPath: repoPath, prNumber: prNumber, branchName: branchName)
            }
        } else {
            try manualCheckout(repoPath: repoPath, prNumber: prNumber, branchName: branchName)
        }
    }

    private func manualCheckout(repoPath: String, prNumber: Int, branchName: String) throws {
        _ = GitService.run(
            "git fetch origin pull/\(prNumber)/head:\(branchName) 2>/dev/null", cwd: repoPath)
        let output = GitService.run("git checkout \(branchName) 2>&1", cwd: repoPath)
        if output.contains("error") {
            throw GitError.commandFailed("Failed to checkout branch \(branchName): \(output)")
        }
    }

    func listRemotePRs(repoPath: String) -> [PullRequest] {
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        let ghCheck = GitService.run("which gh", cwd: repoPath)
        if !ghCheck.isEmpty {
            let output = GitService.run(
                "gh pr list --json number,title,author,headRefName,baseRefName 2>/dev/null",
                cwd: repoPath)
            if !output.isEmpty, let data = output.data(using: .utf8) {
                struct GHPR: Codable {
                    let number: Int
                    let title: String
                    struct GHAuthor: Codable { let login: String }
                    let author: GHAuthor
                    let headRefName: String
                    let baseRefName: String
                }
                if let ghprs = try? JSONDecoder().decode([GHPR].self, from: data) {
                    return ghprs.map { g -> PullRequest in
                        PullRequest(
                            prNumber: g.number,
                            title: g.title,
                            baseSha: g.baseRefName,
                            headSha: g.headRefName,
                            author: g.author.login,
                            repository: "local/\(repoName)"
                        )
                    }
                }
            }
        }

        let output = GitService.run(
            "git branch -r --format=\"%(refname:short)|%(authorname)|%(committerdate:short)\"",
            cwd: repoPath)
        guard !output.isEmpty else { return [] }
        return output.components(separatedBy: .newlines).compactMap { line -> PullRequest? in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 3, !parts[0].isEmpty else { return nil }
            let name = parts[0].replacingOccurrences(of: "origin/", with: "")
            if name == "HEAD" || name == "main" || name == "master" { return nil }

            var hash = 0
            for ch in name.unicodeScalars { hash = (hash << 5) &- hash &+ Int(ch.value) }
            let prNum = abs(hash) % 1000 + 1

            return PullRequest(
                prNumber: prNum,
                title: "Review changes from branch \(name)",
                baseSha: "main",
                headSha: parts[0],
                author: parts[1].isEmpty ? "git-developer" : parts[1],
                repository: "local/\(repoName)"
            )
        }
    }
}

// MARK: - AST Analysis Service
// Spawns the bundled chobi-core sidecar to extract semantic AST symbols.

actor ASTAnalysisService {

    // swift-format-ignore: AlwaysUseLowerCamelCase
    /// Raw JSON model matching chobi-core's AstSymbol output.
    private struct SidecarSymbol: Codable {
        let line: Int
        let end_line: Int
        let semantic_type: String
        let name: String
        let language: String
        let metadata: [String: String]
    }

    /// Locate the bundled sidecar binary. During development it falls back to the
    /// debug build next to the project so the app can be tested without a full
    /// Xcode release build.
    private func sidecarURL() -> URL? {
        // 1. App bundle (production)
        for executableName in ["chobi-core", "diffuse-core"] {
            if let url = Bundle.main.url(forAuxiliaryExecutable: executableName) {
                return url
            }
        }
        // 2. Dev fallback — sibling directory next to the .xcodeproj
        if let bundlePath = Bundle.main.bundlePath
            .components(separatedBy: "/diffuse.app").first
        {
            let candidates = [
                "chobi-core/target/debug/chobi-core",
                "chobi-core/target/release/chobi-core",
                "diffuse-core/target/debug/diffuse-core",
                "diffuse-core/target/release/diffuse-core",
            ]
            for candidate in candidates {
                let binary = URL(fileURLWithPath: bundlePath).appendingPathComponent(candidate)
                if FileManager.default.isExecutableFile(atPath: binary.path) {
                    return binary
                }
            }
        }
        return nil
    }

    /// Parse a single file and return symbols intersecting the given 1-based line numbers.
    func parseSymbols(
        for fileURL: URL,
        filePath: String,
        changedLines: [Int],
        analysisRunId: UUID,
        changedFileId: UUID
    ) async -> [ChangedSymbol] {
        guard !changedLines.isEmpty else { return [] }
        guard let helperURL = sidecarURL() else {
            AppLogger.shared.log(
                "chobi-core binary not found for symbol parsing", level: .error, tag: "AST")
            return []
        }

        let process = Process()
        process.executableURL = helperURL
        let linesArg = changedLines.map(String.init).joined(separator: ",")
        AppLogger.shared.log(
            "Running chobi-core analyze on \(filePath) (lines: \(linesArg))", tag: "AST")
        process.arguments = ["analyze", "--file", fileURL.path, "--lines", linesArg]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        var errData = Data()
        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard !data.isEmpty else {
                AppLogger.shared.log(
                    "No symbols returned by chobi-core for \(filePath)", level: .warning,
                    tag: "AST")
                return []
            }

            let sidecarSymbols = try JSONDecoder().decode([SidecarSymbol].self, from: data)
            AppLogger.shared.log(
                "Parsed \(sidecarSymbols.count) symbols successfully for \(filePath)", tag: "AST")
            return sidecarSymbols.map { s in
                var metadata = s.metadata
                metadata["language"] = s.language
                metadata["file_path"] = filePath
                if let symbolKey = metadata["symbol_key"] {
                    metadata["symbol_id"] = "\(filePath)::\(symbolKey)"
                }
                // Step 6: parse comma-separated callee names from metadata
                let calleeNames =
                    metadata["callees"].map {
                        $0.split(separator: ",")
                            .map { String($0).trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    } ?? []
                return ChangedSymbol(
                    analysisRunId: analysisRunId,
                    changedFileId: changedFileId,
                    name: s.name,
                    kind: mapSymbolKind(s.semantic_type),
                    startLine: s.line,
                    endLine: s.end_line,
                    callees: calleeNames,
                    semanticType: s.semantic_type,
                    metadata: metadata
                )
            }
        } catch {
            let errOutput = String(data: errData, encoding: .utf8) ?? ""
            AppLogger.shared.log(
                "Error parsing symbols for \(fileURL.lastPathComponent): \(error) — sidecar: \(errOutput)",
                level: .error,
                tag: "AST"
            )
            return []
        }
    }

    private func mapSymbolKind(_ semanticType: String) -> ChangedSymbol.SymbolKind {
        switch semanticType {
        case "function_definition", "function_declaration": return .function
        case "method_definition", "constructor_declaration": return .method
        case "class_declaration": return .class
        case "struct_declaration": return .struct
        case "enum_declaration": return .enum
        case "protocol_declaration", "interface_declaration": return .protocol
        case "extension_declaration": return .extension
        case "type_alias": return .type
        case "property_declaration", "variable_declaration": return .property
        case "module_declaration", "object_declaration": return .module
        case "decorated_definition": return .decorated
        default: return .function
        }
    }

    /// Parse symbols for contract-level comparison between the base and head versions of a file.
    /// Runs `chobi-core compare --base <base> --head <head> --lines <csv>` and merges
    /// the returned contract-delta metadata into the existing `ChangedSymbol` array.
    func compareSymbols(
        baseURL: URL,
        headURL: URL,
        changedLines: [Int],
        existingSymbols: inout [ChangedSymbol]
    ) async {
        guard !changedLines.isEmpty else { return }
        guard let helperURL = sidecarURL() else { return }

        let process = Process()
        process.executableURL = helperURL
        let linesArg = changedLines.map(String.init).joined(separator: ",")
        process.arguments = [
            "compare", "--base", baseURL.path, "--head", headURL.path, "--lines", linesArg,
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        var errData = Data()
        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard !data.isEmpty else { return }

            let contractSymbols = try JSONDecoder().decode([SidecarSymbol].self, from: data)

            // Merge contract-delta metadata back into the matching existing symbol records.
            for cs in contractSymbols {
                let idxByKey: Int?
                if let key = cs.metadata["symbol_key"] {
                    idxByKey = existingSymbols.firstIndex { $0.metadata["symbol_key"] == key }
                } else {
                    idxByKey = nil
                }

                let fallbackIdx = existingSymbols.firstIndex {
                    $0.name == cs.name && $0.startLine == cs.line
                }

                if let idx = idxByKey ?? fallbackIdx {
                    for (key, value) in cs.metadata
                    where key.hasPrefix("contract_") || key.hasSuffix("_added") {
                        existingSymbols[idx].metadata[key] = value
                    }
                }
            }
        } catch {
            let errOutput = String(data: errData, encoding: .utf8) ?? ""
            AppLogger.shared.log(
                "Compare error for \(headURL.lastPathComponent): \(error) — sidecar: \(errOutput)",
                level: .error,
                tag: "AST"
            )
        }
    }

    func symbolsWithCallerData(repoPath: String, symbols: [ChangedSymbol], revision: String? = nil)
        async -> (symbols: [ChangedSymbol], trackedCount: Int, indexedCount: Int)
    {
        guard !symbols.isEmpty, let helperURL = sidecarURL() else { return (symbols, 0, 0) }

        struct SymbolRef {
            let key: String
            let name: String
            let qualifiedName: String
        }

        func symbolKey(_ symbol: ChangedSymbol) -> String {
            if let key = symbol.metadata["symbol_key"], !key.isEmpty { return key }
            let scope = symbol.metadata["scope"] ?? ""
            return "\(scope)::\(symbol.semanticType)::\(symbol.name)"
        }

        func normalizedLookupName(_ value: String) -> String {
            value.replacingOccurrences(of: "::", with: ".").lowercased()
        }

        let changedRefs =
            symbols
            .filter { !$0.name.isEmpty && $0.name != "<anonymous>" }
            .map {
                SymbolRef(
                    key: symbolKey($0),
                    name: $0.name,
                    qualifiedName: $0.metadata["qualified_name"] ?? $0.name
                )
            }
        guard !changedRefs.isEmpty else { return (symbols, 0, 0) }

        AppLogger.shared.log(
            "Running optimized Call Graph analysis for \(changedRefs.count) changed symbols",
            tag: "CallGraph")

        let refsByName = Dictionary(grouping: changedRefs, by: { $0.name.lowercased() })
        var callersByKey: [String: Set<String>] = [:]

        // --- Optimized caller resolution path using single git grep filter ---
        let uniqueNames = Array(Set(changedRefs.map { $0.name })).filter { !$0.isEmpty }
        guard !uniqueNames.isEmpty else { return (symbols, 0, 0) }

        let patternContent = uniqueNames.joined(separator: "\n")
        let patternFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("diffuse-grep-patterns-\(UUID().uuidString).txt")

        var filesToScan: [String] = []
        let trackedFilesCount = GitService.trackedSourceFiles(cwd: repoPath, revision: revision)
            .count
        do {
            try patternContent.write(to: patternFileURL, atomically: true, encoding: .utf8)
            var grepArgs = ["grep", "-l", "-i", "-F", "-f", patternFileURL.path]
            if let revision, !revision.isEmpty {
                grepArgs.append(revision)
            }
            let grepOutput = GitService.runGit(grepArgs, cwd: repoPath)
            try? FileManager.default.removeItem(at: patternFileURL)

            let matchingPaths = grepOutput.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let supportedExtensions: Set<String> = [
                "swift", "kt", "kts", "ts", "tsx", "js", "jsx", "py", "rs",
            ]
            let prefixToStrip = (revision != nil && !revision!.isEmpty) ? "\(revision!):" : ""

            for path in matchingPaths {
                var cleanPath = path
                if !prefixToStrip.isEmpty && cleanPath.hasPrefix(prefixToStrip) {
                    cleanPath = String(cleanPath.dropFirst(prefixToStrip.count))
                }
                let ext = URL(fileURLWithPath: cleanPath).pathExtension.lowercased()
                if supportedExtensions.contains(ext) {
                    filesToScan.append(cleanPath)
                }
            }
            AppLogger.shared.log(
                "Git grep identified \(filesToScan.count) candidate files containing symbol references (out of \(trackedFilesCount) tracked files)",
                tag: "CallGraph")
        } catch {
            AppLogger.shared.log(
                "Git grep filter failed: \(error). Falling back to full scan of all files.",
                level: .warning, tag: "CallGraph")
            // Fallback: scan all tracked files if git grep setup fails
            filesToScan = GitService.trackedSourceFiles(cwd: repoPath, revision: revision)
        }

        var indexedCount = 0

        func matches(for callee: String) -> [SymbolRef] {
            let normalized = normalizedLookupName(callee)

            // 1. Try exact qualified match
            let exactMatches = changedRefs.filter {
                normalizedLookupName($0.qualifiedName) == normalized
                    || normalizedLookupName($0.qualifiedName).hasSuffix(".\(normalized)")
            }
            if !exactMatches.isEmpty { return exactMatches }

            // 2. Try prefix/instance variable matching
            // If callee is "viewModel.addHabit" (normalized: "viewmodel.addhabit"),
            // methodName is "addhabit" and prefix is "viewmodel".
            let components = normalized.components(separatedBy: ".")
            if components.count > 1 {
                let methodName = components.last!
                let prefix = components.dropLast().joined(separator: ".")

                let candidates = refsByName[methodName] ?? []
                let prefixMatches = candidates.filter { candidate in
                    let qual = normalizedLookupName(candidate.qualifiedName)
                    // Matches if "habitviewmodel" contains "viewmodel"
                    return qual.contains(prefix)
                }
                if !prefixMatches.isEmpty { return prefixMatches }

                // Fall back to all candidates with this method name
                return candidates
            }

            // 3. Fall back to plain name match
            return refsByName[normalized] ?? []
        }

        for relativePath in filesToScan {
            var temporaryIndexedURL: URL?
            let fileURL: URL
            if let revision, !revision.isEmpty {
                let content = GitService.fileContent(
                    at: revision, path: relativePath, cwd: repoPath)
                guard !content.isEmpty,
                    let tmp = temporarySourceURL(
                        prefix: "diffuse-index", filePath: relativePath, content: content)
                else {
                    continue
                }
                temporaryIndexedURL = tmp
                fileURL = tmp
            } else {
                fileURL = URL(fileURLWithPath: repoPath).appendingPathComponent(relativePath)
                guard FileManager.default.isReadableFile(atPath: fileURL.path) else { continue }
            }

            AppLogger.shared.log("Running chobi-core index on \(relativePath)", tag: "CallGraph")
            let process = Process()
            process.executableURL = helperURL
            process.arguments = ["index", "--file", fileURL.path]

            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                indexedCount += 1
                guard !data.isEmpty else {
                    if let temporaryIndexedURL {
                        try? FileManager.default.removeItem(at: temporaryIndexedURL)
                    }
                    continue
                }

                let indexedSymbols = try JSONDecoder().decode([SidecarSymbol].self, from: data)
                for indexed in indexedSymbols {
                    let callees =
                        indexed.metadata["callees"].map {
                            $0.split(separator: ",")
                                .map { String($0).trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        } ?? []
                    let callerName = indexed.metadata["qualified_name"] ?? indexed.name
                    let callerLabel = "\(relativePath):\(callerName)"
                    for callee in callees {
                        for match in matches(for: callee)
                        where match.name != indexed.name && match.qualifiedName != callerName {
                            callersByKey[match.key, default: []].insert(callerLabel)
                        }
                    }
                }
            } catch {}

            if let temporaryIndexedURL {
                try? FileManager.default.removeItem(at: temporaryIndexedURL)
            }
        }

        let updatedSymbols = symbols.map { symbol in
            var updated = symbol
            let callers = Array(callersByKey[symbolKey(symbol)] ?? []).sorted()
            if !callers.isEmpty {
                updated.callers = callers
                updated.metadata["caller_resolution"] = "indexed"
            }
            return updated
        }
        let totalCallersFound = callersByKey.values.reduce(0) { $0 + $1.count }
        AppLogger.shared.log(
            "Call Graph indexing complete. Found \(totalCallersFound) caller relationships across \(updatedSymbols.filter { !$0.callers.isEmpty }.count) symbols.",
            tag: "CallGraph")
        return (
            symbols: updatedSymbols, trackedCount: trackedFilesCount, indexedCount: indexedCount
        )
    }

    func extractChangedSymbols(
        repoPath: String,
        baseRevision: String,
        headRevision: String? = nil,
        analysisRunId: UUID,
        changedFiles: [ChangedFile]
    ) async -> (
        symbols: [ChangedSymbol], parseTime: Double, compareTime: Double, callGraphTime: Double,
        trackedFilesCount: Int, indexedFilesCount: Int, graph: SymbolGraphResult
    ) {
        var parseTime: Double = 0.0
        var compareTime: Double = 0.0
        var callGraphTime: Double = 0.0
        var allSymbols: [ChangedSymbol] = []

        for changedFile in changedFiles
        where changedFile.classification == .source || changedFile.classification == .test {
            guard changedFile.status != .deleted else { continue }
            let lines = changedLinesFromHunks(changedFile.hunks)
            guard !lines.isEmpty else { continue }

            var temporaryHeadURL: URL?
            let fileURL: URL
            if let headRevision {
                let headContent = GitService.fileContent(
                    at: headRevision, path: changedFile.path, cwd: repoPath)
                guard !headContent.isEmpty,
                    let tmp = temporarySourceURL(
                        prefix: "diffuse-head", filePath: changedFile.path, content: headContent)
                else {
                    continue
                }
                temporaryHeadURL = tmp
                fileURL = tmp
            } else {
                fileURL = URL(fileURLWithPath: repoPath).appendingPathComponent(changedFile.path)
            }

            let startParse = Date()
            var symbols = await parseSymbols(
                for: fileURL,
                filePath: changedFile.path,
                changedLines: lines,
                analysisRunId: analysisRunId,
                changedFileId: changedFile.id
            )
            parseTime += Date().timeIntervalSince(startParse)

            if !symbols.isEmpty {
                let baseContent = GitService.fileContent(
                    at: baseRevision, path: changedFile.path, cwd: repoPath)
                if !baseContent.isEmpty,
                    let baseTmp = temporarySourceURL(
                        prefix: "diffuse-base", filePath: changedFile.path, content: baseContent)
                {
                    let startCompare = Date()
                    await compareSymbols(
                        baseURL: baseTmp,
                        headURL: fileURL,
                        changedLines: lines,
                        existingSymbols: &symbols
                    )
                    compareTime += Date().timeIntervalSince(startCompare)
                    try? FileManager.default.removeItem(at: baseTmp)
                } else if changedFile.status == .added {
                    for index in symbols.indices {
                        symbols[index].metadata["symbol_is_new"] = "true"
                        markAddedBehaviorDeltas(symbol: &symbols[index])
                        if isContractSurface(symbols[index]) {
                            symbols[index].metadata["contract_is_new_public"] = "true"
                        }
                    }
                }
            }

            if let temporaryHeadURL {
                try? FileManager.default.removeItem(at: temporaryHeadURL)
            }

            allSymbols.append(contentsOf: symbols)
        }

        let startCallGraph = Date()
        let symbolIndexService = await SymbolIndexService(provider: SCIPIndexProvider())
        let impactGraphService = await ImpactGraphService(
            symbolIndexService: symbolIndexService,
            fallbackService: self
        )
        let callerResult = await impactGraphService.enrichSymbols(
            repoPath: repoPath,
            symbols: allSymbols,
            files: changedFiles,
            revision: headRevision
        )
        callGraphTime = Date().timeIntervalSince(startCallGraph)

        return (
            symbols: callerResult.symbols,
            parseTime: parseTime,
            compareTime: compareTime,
            callGraphTime: callGraphTime,
            trackedFilesCount: callerResult.trackedFilesCount,
            indexedFilesCount: callerResult.indexedFilesCount,
            graph: callerResult.graph
        )
    }

    private func temporarySourceURL(prefix: String, filePath: String, content: String) -> URL? {
        let ext = URL(fileURLWithPath: filePath).pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)\(suffix)")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func isContractSurface(_ symbol: ChangedSymbol) -> Bool {
        switch symbol.metadata["visibility"] {
        case "public", "open":
            return true
        case "private", "fileprivate", "internal", "protected":
            return false
        default:
            let language = symbol.metadata["language"] ?? ""
            return language == "typescript"
                || language == "javascript"
                || language == "python"
                || symbol.semanticType == "interface_declaration"
                || symbol.semanticType == "protocol_declaration"
                || symbol.semanticType == "type_alias"
        }
    }

    private func markAddedBehaviorDeltas(symbol: inout ChangedSymbol) {
        let mappings = [
            ("has_control_flow", "control_flow_added"),
            ("has_error_handling", "error_handling_added"),
            ("has_async_behavior", "async_behavior_added"),
            ("has_persistence_write", "persistence_write_added"),
            ("has_network_call", "network_call_added"),
            ("has_auth_check", "auth_check_added"),
            ("has_deletion", "deletion_added"),
            ("has_logging", "logging_added"),
        ]
        for (presenceKey, deltaKey) in mappings where symbol.metadata[presenceKey] == "true" {
            symbol.metadata[deltaKey] = "true"
        }
    }
}

/// Extract all 1-based new-side line numbers that were added or changed within a file's diff hunks.
nonisolated private func changedLinesFromHunks(_ hunks: [DiffHunk]) -> [Int] {
    var lines: [Int] = []
    for hunk in hunks {
        var currentLine = hunk.newStart
        for rawLine in hunk.lines {
            if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                lines.append(currentLine)
                currentLine += 1
            } else if !rawLine.hasPrefix("-") {
                currentLine += 1
            }
        }
    }
    return lines
}

// MARK: - Persistence Service
// Simple JSON-based persistence (no external DB dependency)

actor PersistenceService: ModelActor {

    static let sharedContainer: ModelContainer = {
        let schema = Schema([
            RepositoryEntity.self,
            PullRequestEntity.self,
            AnalysisRunEntity.self,
            ChangedFileEntity.self,
            ChangedSymbolEntity.self,
            SymbolGraphNodeEntity.self,
            SymbolGraphEdgeEntity.self,
            SymbolIndexMetadataEntity.self,
            FindingEntity.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }()

    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor

    init(container: ModelContainer) {
        self.modelContainer = container
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    init() {
        self.init(container: Self.sharedContainer)
    }

    func allPullRequests() -> [PullRequest] {
        let descriptor = FetchDescriptor<PullRequestEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let entities = try? modelContext.fetch(descriptor) else { return [] }

        return entities.map { entity in
            var pr = PullRequest(
                id: entity.id,
                prNumber: entity.prNumber,
                title: entity.title,
                body: entity.body,
                baseSha: entity.baseSha,
                headSha: entity.headSha,
                author: entity.author,
                status: entity.status,
                repository: entity.repository,
                createdAt: entity.createdAt,
                updatedAt: entity.updatedAt
            )

            // Attach latest run
            let prId = entity.id
            let runDescriptor = FetchDescriptor<AnalysisRunEntity>(
                predicate: #Predicate<AnalysisRunEntity> { $0.pullRequestId == prId },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            if let runs = try? modelContext.fetch(runDescriptor), let latestRunEntity = runs.first {
                pr.latestRun = AnalysisRun(
                    id: latestRunEntity.id,
                    pullRequestId: latestRunEntity.pullRequestId,
                    baseSha: latestRunEntity.baseSha,
                    headSha: latestRunEntity.headSha,
                    status: AnalysisRun.RunStatus(rawValue: latestRunEntity.status) ?? .queued,
                    errorMessage: latestRunEntity.errorMessage,
                    riskScore: latestRunEntity.riskScore,
                    createdAt: latestRunEntity.createdAt,
                    updatedAt: latestRunEntity.updatedAt
                )
            }

            return pr
        }
    }

    func upsertPullRequest(_ pr: PullRequest) -> PullRequest {
        let id = pr.id
        let descriptor = FetchDescriptor<PullRequestEntity>(
            predicate: #Predicate<PullRequestEntity> { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.prNumber = pr.prNumber
            existing.title = pr.title
            existing.body = pr.body
            existing.baseSha = pr.baseSha
            existing.headSha = pr.headSha
            existing.author = pr.author
            existing.status = pr.status
            existing.repository = pr.repository
            existing.updatedAt = pr.updatedAt
        } else {
            let entity = PullRequestEntity(
                id: pr.id,
                prNumber: pr.prNumber,
                title: pr.title,
                body: pr.body,
                baseSha: pr.baseSha,
                headSha: pr.headSha,
                author: pr.author,
                status: pr.status,
                repository: pr.repository,
                createdAt: pr.createdAt,
                updatedAt: pr.updatedAt
            )
            modelContext.insert(entity)
        }
        try? modelContext.save()
        return pr
    }

    func insertRun(_ run: AnalysisRun) {
        let entity = AnalysisRunEntity(
            id: run.id,
            pullRequestId: run.pullRequestId,
            baseSha: run.baseSha,
            headSha: run.headSha,
            status: run.status.rawValue,
            errorMessage: run.errorMessage,
            riskScore: run.riskScore,
            createdAt: run.createdAt,
            updatedAt: run.updatedAt
        )
        modelContext.insert(entity)
        try? modelContext.save()
    }

    func updateRun(_ run: AnalysisRun) {
        let id = run.id
        let descriptor = FetchDescriptor<AnalysisRunEntity>(
            predicate: #Predicate<AnalysisRunEntity> { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.status = run.status.rawValue
            existing.errorMessage = run.errorMessage
            existing.riskScore = run.riskScore
            existing.updatedAt = run.updatedAt
            try? modelContext.save()
        }
    }

    func insertFiles(_ files: [ChangedFile]) {
        for file in files {
            let entity = ChangedFileEntity(
                id: file.id,
                analysisRunId: file.analysisRunId,
                path: file.path,
                status: file.status.rawValue,
                additions: file.additions,
                deletions: file.deletions,
                classification: file.classification.rawValue,
                hunks: file.hunks
            )
            modelContext.insert(entity)
        }
        try? modelContext.save()
    }

    func insertSymbols(_ symbols: [ChangedSymbol]) {
        for symbol in symbols {
            let entity = ChangedSymbolEntity(
                id: symbol.id,
                analysisRunId: symbol.analysisRunId,
                changedFileId: symbol.changedFileId,
                name: symbol.name,
                kind: symbol.kind.rawValue,
                startLine: symbol.startLine,
                endLine: symbol.endLine,
                callers: symbol.callers,
                callees: symbol.callees,
                semanticType: symbol.semanticType,
                metadata: symbol.metadata
            )
            modelContext.insert(entity)
        }
        try? modelContext.save()
    }

    func insertSymbolGraph(
        _ graph: SymbolGraphResult,
        analysisRunId: UUID,
        repoPath: String,
        revision: String?
    ) {
        for node in graph.nodes {
            modelContext.insert(SymbolGraphNodeEntity(analysisRunId: analysisRunId, node: node))
        }
        for edge in graph.edges {
            modelContext.insert(SymbolGraphEdgeEntity(analysisRunId: analysisRunId, edge: edge))
        }
        let metadata = SymbolIndexMetadataEntity(
            analysisRunId: analysisRunId,
            repositoryKey: String(repoPath.hashValue),
            revision: revision,
            indexSource: graph.source.rawValue,
            indexedDocumentCount: Set(graph.nodes.compactMap(\.definition?.filePath)).count,
            diagnostics: graph.diagnostics,
            fallbackReason: graph.source == .treeSitterFallback ? graph.diagnostics.first : nil
        )
        modelContext.insert(metadata)
        try? modelContext.save()
    }

    func getSymbolGraph(runId: UUID) -> SymbolGraphResult? {
        let runIdConst = runId
        let nodeDescriptor = FetchDescriptor<SymbolGraphNodeEntity>(
            predicate: #Predicate<SymbolGraphNodeEntity> { $0.analysisRunId == runIdConst }
        )
        let edgeDescriptor = FetchDescriptor<SymbolGraphEdgeEntity>(
            predicate: #Predicate<SymbolGraphEdgeEntity> { $0.analysisRunId == runIdConst }
        )
        let metadataDescriptor = FetchDescriptor<SymbolIndexMetadataEntity>(
            predicate: #Predicate<SymbolIndexMetadataEntity> { $0.analysisRunId == runIdConst },
            sortBy: [SortDescriptor(\.graphBuildTimestamp, order: .reverse)]
        )
        let nodeEntities = (try? modelContext.fetch(nodeDescriptor)) ?? []
        guard !nodeEntities.isEmpty else { return nil }
        let edgeEntities = (try? modelContext.fetch(edgeDescriptor)) ?? []
        let metadata = (try? modelContext.fetch(metadataDescriptor).first)

        let nodes = nodeEntities.map { entity in
            SymbolGraphNode(
                id: entity.identity.id,
                identity: entity.identity,
                definition: entity.definition,
                isChangedInPR: entity.isChangedInPR,
                isTest: entity.isTest,
                confidence: GraphConfidence(rawValue: entity.confidence) ?? .low
            )
        }
        let edges = edgeEntities.map { entity in
            SymbolGraphEdge(
                id: entity.edgeId,
                callerId: entity.callerId,
                calleeId: entity.calleeId,
                callSite: entity.callSite,
                confidence: GraphConfidence(rawValue: entity.confidence) ?? .low,
                source: GraphEdgeSource(rawValue: entity.source) ?? .treeSitterFallback
            )
        }
        return SymbolGraphResult(
            nodes: nodes,
            edges: edges,
            source: metadata.flatMap { GraphEdgeSource(rawValue: $0.indexSource) }
                ?? (edges.first?.source ?? .treeSitterFallback),
            confidence: edges.contains { $0.confidence == .high } ? .high : .low,
            diagnostics: metadata?.diagnostics ?? []
        )
    }

    func insertFindings(_ findings: [Finding]) {
        for finding in findings {
            let entity = FindingEntity(
                id: finding.id,
                analysisRunId: finding.analysisRunId,
                changedFileId: finding.changedFileId,
                severity: finding.severity.rawValue,
                category: finding.category.rawValue,
                message: finding.message,
                lineStart: finding.lineStart,
                lineEnd: finding.lineEnd,
                ruleSource: finding.ruleSource,
                evidence: finding.evidence
            )
            modelContext.insert(entity)
        }
        try? modelContext.save()
    }

    func getAnalysisDetails(runId: UUID) async -> AnalysisDetails? {
        let runIdConst = runId

        let runDescriptor = FetchDescriptor<AnalysisRunEntity>(
            predicate: #Predicate<AnalysisRunEntity> { $0.id == runIdConst }
        )
        guard let runEntity = try? modelContext.fetch(runDescriptor).first else { return nil }

        let prId = runEntity.pullRequestId
        let prDescriptor = FetchDescriptor<PullRequestEntity>(
            predicate: #Predicate<PullRequestEntity> { $0.id == prId }
        )
        guard let prEntity = try? modelContext.fetch(prDescriptor).first else { return nil }

        let filesDescriptor = FetchDescriptor<ChangedFileEntity>(
            predicate: #Predicate<ChangedFileEntity> { $0.analysisRunId == runIdConst }
        )
        let fileEntities = (try? modelContext.fetch(filesDescriptor)) ?? []

        let symbolsDescriptor = FetchDescriptor<ChangedSymbolEntity>(
            predicate: #Predicate<ChangedSymbolEntity> { $0.analysisRunId == runIdConst }
        )
        let symbolEntities = (try? modelContext.fetch(symbolsDescriptor)) ?? []

        let findingsDescriptor = FetchDescriptor<FindingEntity>(
            predicate: #Predicate<FindingEntity> { $0.analysisRunId == runIdConst }
        )
        let findingEntities = (try? modelContext.fetch(findingsDescriptor)) ?? []

        let run = AnalysisRun(
            id: runEntity.id,
            pullRequestId: runEntity.pullRequestId,
            baseSha: runEntity.baseSha,
            headSha: runEntity.headSha,
            status: AnalysisRun.RunStatus(rawValue: runEntity.status) ?? .completed,
            errorMessage: runEntity.errorMessage,
            riskScore: runEntity.riskScore,
            createdAt: runEntity.createdAt,
            updatedAt: runEntity.updatedAt
        )

        let pr = PullRequest(
            id: prEntity.id,
            prNumber: prEntity.prNumber,
            title: prEntity.title,
            body: prEntity.body,
            baseSha: prEntity.baseSha,
            headSha: prEntity.headSha,
            author: prEntity.author,
            status: prEntity.status,
            repository: prEntity.repository,
            createdAt: prEntity.createdAt,
            updatedAt: prEntity.updatedAt
        )

        let files = fileEntities.map { fe in
            ChangedFile(
                id: fe.id,
                analysisRunId: fe.analysisRunId,
                path: fe.path,
                status: ChangedFile.FileStatus(rawValue: fe.status) ?? .modified,
                additions: fe.additions,
                deletions: fe.deletions,
                classification: ChangedFile.FileClassification(rawValue: fe.classification)
                    ?? .source,
                hunks: fe.hunks
            )
        }

        let symbols = symbolEntities.map { se in
            ChangedSymbol(
                id: se.id,
                analysisRunId: se.analysisRunId,
                changedFileId: se.changedFileId,
                name: se.name,
                kind: ChangedSymbol.SymbolKind(rawValue: se.kind) ?? .function,
                startLine: se.startLine,
                endLine: se.endLine,
                callers: se.callers,
                callees: se.callees,
                semanticType: se.semanticType,
                metadata: se.metadata
            )
        }

        let findings = findingEntities.map { f in
            Finding(
                id: f.id,
                analysisRunId: f.analysisRunId,
                changedFileId: f.changedFileId,
                severity: Severity(rawValue: f.severity) ?? .medium,
                category: Finding.FindingCategory(rawValue: f.category) ?? .architecture,
                message: f.message,
                lineStart: f.lineStart,
                lineEnd: f.lineEnd,
                ruleSource: f.ruleSource,
                evidence: f.evidence
            )
        }

        let triage = await TriageEngine.deriveTriage(
            files: files, symbols: symbols, findings: findings, riskScore: run.riskScore)

        return AnalysisDetails(
            run: run, pr: pr, files: files, symbols: symbols, findings: findings,
            reviewTargets: triage.reviewTargets,
            changeBuckets: triage.changeBuckets,
            riskHighlights: triage.riskHighlights,
            skimTargets: triage.skimTargets,
            riskFactors: triage.riskFactors,
            symbolReviewGroups: triage.symbolReviewGroups
        )
    }

    func getFilesForRun(_ runId: UUID) -> [ChangedFile] {
        let runIdConst = runId
        let descriptor = FetchDescriptor<ChangedFileEntity>(
            predicate: #Predicate<ChangedFileEntity> { $0.analysisRunId == runIdConst }
        )
        guard let entities = try? modelContext.fetch(descriptor) else { return [] }
        return entities.map { fe in
            ChangedFile(
                id: fe.id,
                analysisRunId: fe.analysisRunId,
                path: fe.path,
                status: ChangedFile.FileStatus(rawValue: fe.status) ?? .modified,
                additions: fe.additions,
                deletions: fe.deletions,
                classification: ChangedFile.FileClassification(rawValue: fe.classification)
                    ?? .source,
                hunks: fe.hunks
            )
        }
    }

    func getRunsForPR(_ prId: UUID) -> [AnalysisRun] {
        let prIdConst = prId
        let descriptor = FetchDescriptor<AnalysisRunEntity>(
            predicate: #Predicate<AnalysisRunEntity> { $0.pullRequestId == prIdConst },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let entities = try? modelContext.fetch(descriptor) else { return [] }
        return entities.map { re in
            AnalysisRun(
                id: re.id,
                pullRequestId: re.pullRequestId,
                baseSha: re.baseSha,
                headSha: re.headSha,
                status: AnalysisRun.RunStatus(rawValue: re.status) ?? .completed,
                errorMessage: re.errorMessage,
                riskScore: re.riskScore,
                createdAt: re.createdAt,
                updatedAt: re.updatedAt
            )
        }
    }

    func allRepositories() -> [GitRepository] {
        let descriptor = FetchDescriptor<RepositoryEntity>()
        guard let entities = try? modelContext.fetch(descriptor) else { return [] }
        return entities.map { entity in
            GitRepository(
                id: entity.id,
                name: entity.name,
                path: entity.path,
                autoAnalyzeEnabled: entity.autoAnalyzeEnabled
            )
        }
    }

    func addRepository(name: String, path: String, autoAnalyzeEnabled: Bool = true) -> GitRepository
    {
        let standardized = URL(fileURLWithPath: path).standardized.path

        let descriptor = FetchDescriptor<RepositoryEntity>()
        if let entities = try? modelContext.fetch(descriptor),
            let existing = entities.first(where: {
                URL(fileURLWithPath: $0.path).standardized.path == standardized
            })
        {
            return GitRepository(
                id: existing.id,
                name: existing.name,
                path: existing.path,
                autoAnalyzeEnabled: existing.autoAnalyzeEnabled
            )
        }

        let repo = GitRepository(name: name, path: path, autoAnalyzeEnabled: autoAnalyzeEnabled)
        let entity = RepositoryEntity(
            id: repo.id,
            name: repo.name,
            path: repo.path,
            autoAnalyzeEnabled: repo.autoAnalyzeEnabled
        )
        modelContext.insert(entity)
        try? modelContext.save()
        return repo
    }

    func deleteRepository(id: UUID) {
        let idConst = id
        let descriptor = FetchDescriptor<RepositoryEntity>(
            predicate: #Predicate<RepositoryEntity> { $0.id == idConst }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try? modelContext.save()
        }
    }

    func renameRepository(id: UUID, newName: String) {
        let idConst = id
        let descriptor = FetchDescriptor<RepositoryEntity>(
            predicate: #Predicate<RepositoryEntity> { $0.id == idConst }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = newName
            try? modelContext.save()
        }
    }

    func setRepositoryAutoAnalyze(id: UUID, enabled: Bool) {
        let idConst = id
        let descriptor = FetchDescriptor<RepositoryEntity>(
            predicate: #Predicate<RepositoryEntity> { $0.id == idConst }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.autoAnalyzeEnabled = enabled
            try? modelContext.save()
        }
    }

    func deleteAll() {
        try? modelContext.delete(model: RepositoryEntity.self)
        try? modelContext.delete(model: PullRequestEntity.self)
        try? modelContext.delete(model: AnalysisRunEntity.self)
        try? modelContext.delete(model: ChangedFileEntity.self)
        try? modelContext.delete(model: ChangedSymbolEntity.self)
        try? modelContext.delete(model: SymbolGraphNodeEntity.self)
        try? modelContext.delete(model: SymbolGraphEdgeEntity.self)
        try? modelContext.delete(model: SymbolIndexMetadataEntity.self)
        try? modelContext.delete(model: FindingEntity.self)
        try? modelContext.save()
    }
}

@MainActor
class AnalysisCoordinator: ObservableObject {

    let persistence = PersistenceService()
    let git = GitService()

    @Published var isAnalyzing = false
    @Published var analysisError: String?
    @Published var lastRunMetrics: PerformanceMetrics? = nil

    func analyzeRepo(path: String, baseRef: String? = nil) async -> PullRequest? {
        isAnalyzing = true
        analysisError = nil
        defer { isAnalyzing = false }

        AppLogger.shared.log(
            "Starting analysis pipeline for repository at path: \(path)", tag: "Pipeline")
        var metrics = PerformanceMetrics()
        let startTotal = Date()

        do {
            let startGit = Date()
            let gitInfo = try await git.gatherDiff(repoPath: path, baseRef: baseRef)
            metrics.gitGatherDiffTime = Date().timeIntervalSince(startGit)
            AppLogger.shared.log(
                "Git gather diff complete (Sha: \(gitInfo.headSha.prefix(7))). Subject: \(gitInfo.commitSubject)",
                tag: "Pipeline")

            let repoName = URL(fileURLWithPath: path).lastPathComponent

            // Upsert PR
            var pr = PullRequest(
                prNumber: gitInfo.prNumber,
                title: gitInfo.commitSubject,
                baseSha: gitInfo.baseSha,
                headSha: gitInfo.headSha,
                author: gitInfo.author,
                repository: "local/\(repoName)"
            )
            // Check for existing PR with same repo+number
            let existing = await persistence.allPullRequests()
            if let existingPR = existing.first(where: {
                $0.repository == pr.repository && $0.prNumber == pr.prNumber
            }) {
                pr = existingPR
                pr.headSha = gitInfo.headSha
                pr.updatedAt = Date()
            }
            pr = await persistence.upsertPullRequest(pr)

            // Create analysis run
            var run = AnalysisRun(
                pullRequestId: pr.id, baseSha: pr.baseSha, headSha: pr.headSha, status: .analyzing)
            await persistence.insertRun(run)

            // Parse diff
            let startDiff = Date()
            let parsedFiles = DiffParser.parse(gitInfo.diff)
            metrics.diffParsingTime = Date().timeIntervalSince(startDiff)
            metrics.changedFilesCount = parsedFiles.count
            AppLogger.shared.log(
                "Diff parsing complete. Discovered \(metrics.changedFilesCount) changed files.",
                tag: "Pipeline")

            // Create ChangedFile records
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
            await persistence.insertFiles(changedFiles)

            let astService = ASTAnalysisService()
            AppLogger.shared.log(
                "Extracting AST symbols and comparing base/head...", tag: "Pipeline")
            let astResult = await astService.extractChangedSymbols(
                repoPath: path,
                baseRevision: gitInfo.baseSha,
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
            AppLogger.shared.log(
                "AST parsing complete. Extracted \(metrics.symbolsCount) changed symbols.",
                tag: "Pipeline")

            if !allSymbols.isEmpty {
                await persistence.insertSymbols(allSymbols)
            }
            await persistence.insertSymbolGraph(
                astResult.graph,
                analysisRunId: run.id,
                repoPath: path,
                revision: nil
            )

            // FIX 1: Build file path map for deterministic rules
            let filePathMap: [UUID: String] = Dictionary(
                uniqueKeysWithValues: changedFiles.map { ($0.id, $0.path) }
            )

            // Run deterministic rules (FIX 1: pass filePathMap)
            let startRules = Date()
            AppLogger.shared.log("Executing deterministic rules engine...", tag: "Pipeline")
            let ruleResults = RulesEngine.runDeterministicRules(
                files: parsedFiles, symbols: allSymbols, filePathMap: filePathMap
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
            await persistence.insertFindings(allFindings)

            // Calculate risk score
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
            AppLogger.shared.log(
                "Rules engine complete. Found \(allFindings.count) findings. Risk score calculated: \(breakdown.score)",
                tag: "Pipeline")

            run.status = .completed
            run.riskScore = breakdown.score
            run.updatedAt = Date()
            await persistence.updateRun(run)

            pr.latestRun = run
            pr = await persistence.upsertPullRequest(pr)

            metrics.totalTime = Date().timeIntervalSince(startTotal)
            self.lastRunMetrics = metrics
            AppLogger.shared.log(
                "Analysis pipeline completed successfully in \(String(format: "%.3f", metrics.totalTime))s.",
                tag: "Pipeline")

            return pr

        } catch {
            analysisError = error.localizedDescription
            AppLogger.shared.log(
                "Analysis pipeline failed with error: \(error.localizedDescription)", level: .error,
                tag: "Pipeline")
            return nil
        }
    }

    func allPullRequests() async -> [PullRequest] {
        await persistence.allPullRequests()
    }

    func getDetails(for runId: UUID, repoPath: String? = nil) async -> AnalysisDetails? {
        await persistence.getAnalysisDetails(
            runId: runId)
    }

    func allRepositories() async -> [GitRepository] {
        await persistence.allRepositories()
    }

    func addRepository(name: String, path: String, autoAnalyzeEnabled: Bool = true) async
        -> GitRepository
    {
        await persistence.addRepository(
            name: name, path: path, autoAnalyzeEnabled: autoAnalyzeEnabled)
    }

    func deleteRepository(id: UUID) async {
        await persistence.deleteRepository(id: id)
    }

    func renameRepository(id: UUID, newName: String) async {
        await persistence.renameRepository(id: id, newName: newName)
    }

    func setRepositoryAutoAnalyze(id: UUID, enabled: Bool) async {
        await persistence.setRepositoryAutoAnalyze(id: id, enabled: enabled)
    }

    func listCommits(repoPath: String, baseRef: String, headRef: String) async -> [GitCommit] {
        await git.listCommits(repoPath: repoPath, baseRef: baseRef, headRef: headRef)
    }

    func listLocalBranches(repoPath: String) async -> [String] {
        await git.listLocalBranches(repoPath: repoPath)
    }

    func listLocalBranchSummaries(
        repoPath: String, branches: [String], currentBranch: String, remotePRs: [PullRequest]
    ) async -> [LocalBranchSummary] {
        await git.listLocalBranchSummaries(
            repoPath: repoPath, branches: branches, currentBranch: currentBranch,
            remotePRs: remotePRs)
    }

    func listRemotePRs(repoPath: String) async -> [PullRequest] {
        await git.listRemotePRs(repoPath: repoPath)
    }

    func checkoutPR(repoPath: String, prNumber: Int, branchName: String) async throws {
        try await git.checkoutPR(repoPath: repoPath, prNumber: prNumber, branchName: branchName)
    }

}
