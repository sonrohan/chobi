import Foundation

// MARK: - Git Diff Parser
// Ports diff.ts from diffuse2

struct DiffParser {

    static func classifyFile(_ path: String, profile: AnalysisProfile = .generic)
        -> ChangedFile.FileClassification
    {
        profile.classifyFile(path)
    }

    struct ParsedFile {
        var oldPath: String?
        var newPath: String?
        var status: ChangedFile.FileStatus
        var additions: Int
        var deletions: Int
        var classification: ChangedFile.FileClassification
        var hunks: [DiffHunk]
    }

    static func parse(_ diffText: String, profile: AnalysisProfile = .generic) -> [ParsedFile] {
        var files: [ParsedFile] = []
        let lines = diffText.components(separatedBy: "\n")
        var current: ParsedFile?
        var currentHunk: DiffHunk?

        func commitHunk() {
            if let h = currentHunk {
                current?.hunks.append(h)
            }
            currentHunk = nil
        }

        func commitFile() {
            commitHunk()
            if let f = current, f.newPath != nil || f.oldPath != nil {
                files.append(f)
            }
            current = nil
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                commitFile()
                current = ParsedFile(
                    oldPath: nil, newPath: nil, status: .modified,
                    additions: 0, deletions: 0, classification: .source, hunks: [])
                // Parse paths from "diff --git a/foo b/foo"
                let rest = String(line.dropFirst("diff --git ".count))
                let parts = rest.components(separatedBy: " ")
                if parts.count >= 2 {
                    let a = parts[0].hasPrefix("a/") ? String(parts[0].dropFirst(2)) : parts[0]
                    let b = parts[1].hasPrefix("b/") ? String(parts[1].dropFirst(2)) : parts[1]
                    current?.oldPath = a
                    current?.newPath = b
                }
                continue
            }

            guard current != nil else { continue }

            if line.hasPrefix("new file mode") {
                current?.status = .added
                continue
            }
            if line.hasPrefix("deleted file mode") {
                current?.status = .deleted
                continue
            }
            if line.hasPrefix("rename from ") {
                current?.status = .renamed
                current?.oldPath = String(line.dropFirst("rename from ".count))
                continue
            }
            if line.hasPrefix("rename to ") {
                current?.newPath = String(line.dropFirst("rename to ".count))
                continue
            }
            if line.hasPrefix("--- a/") {
                current?.oldPath = String(line.dropFirst("--- a/".count))
                continue
            }
            if line.hasPrefix("+++ b/") {
                current?.newPath = String(line.dropFirst("+++ b/".count))
                continue
            }

            if line.hasPrefix("@@ ") {
                commitHunk()
                // Parse @@ -oldStart,oldLines +newStart,newLines @@
                let pattern = #"^@@ -(\d+),?(\d+)? \+(\d+),?(\d+)? @@"#
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let m = line[match]
                    let nums = m.matches(of: /\d+/).map { Int($0.output)! }
                    if nums.count >= 3 {
                        currentHunk = DiffHunk(
                            oldStart: nums[0], oldLines: nums.count > 1 ? nums[1] : 1,
                            newStart: nums.count > 2 ? nums[2] : 0,
                            newLines: nums.count > 3 ? nums[3] : 1,
                            lines: []
                        )
                    }
                }
                continue
            }

            if currentHunk != nil {
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    current?.additions += 1
                    currentHunk?.lines.append(line)
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    current?.deletions += 1
                    currentHunk?.lines.append(line)
                } else if line.hasPrefix(" ") {
                    currentHunk?.lines.append(line)
                }
            }
        }
        commitFile()

        // Post-process: fix status and classification
        return files.map { f in
            var file = f
            let path = f.newPath ?? f.oldPath ?? ""
            file.classification = classifyFile(path, profile: profile)
            if f.oldPath == nil && f.newPath != nil {
                file.status = .added
            } else if f.oldPath != nil && f.newPath == nil {
                file.status = .deleted
            } else if f.oldPath != f.newPath {
                file.status = .renamed
            } else {
                file.status = .modified
            }
            return file
        }
    }
}

// MARK: - Rules Engine
// Ports rules.ts from diffuse2

struct RulesEngine {

    struct RuleFinding {
        var severity: Severity
        var category: Finding.FindingCategory
        var message: String
        var lineStart: Int?
        var lineEnd: Int?
        var ruleSource: String
        var evidence: String?
    }

    struct RiskBreakdown {
        var score: Int
        var factors: [String]
    }

    // FIX 1: filePathMap resolves sym.changedFileId → file path so every
    // AST-powered rule finding is attached to the correct file.
    static func runDeterministicRules(
        files: [DiffParser.ParsedFile],
        symbols: [ChangedSymbol],
        filePathMap: [UUID: String],
        profile: AnalysisProfile = .generic
    ) -> [String: [RuleFinding]] {
        var fileFindings: [String: [RuleFinding]] = [:]

        func addFinding(_ path: String, _ finding: RuleFinding) {
            fileFindings[path, default: []].append(finding)
        }

        let missingTestsRule = profile.rules.missingTests
        let sourceClasses = Set(missingTestsRule?.sourceClassifications ?? ["source"])
        let testClasses = Set(missingTestsRule?.testClassifications ?? ["test"])
        let sourceFiles = files.filter {
            sourceClasses.contains($0.classification.rawValue) && $0.status != .deleted
        }
        let testFiles = files.filter { testClasses.contains($0.classification.rawValue) }

        func fileBaseName(_ file: DiffParser.ParsedFile) -> String {
            let path = file.newPath ?? file.oldPath ?? ""
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
        }

        func matchingTests(for source: DiffParser.ParsedFile) -> [DiffParser.ParsedFile] {
            let base = fileBaseName(source)
            guard !base.isEmpty else { return [] }
            return testFiles.filter { test in
                let testPath = (test.newPath ?? "").lowercased()
                let testBase = fileBaseName(test)
                return testBase.contains(base) || testPath.contains(base)
            }
        }

        // Missing tests for significant source changes.
        if let missingTestsRule, missingTestsRule.enabled {
            for sf in sourceFiles where sf.additions > missingTestsRule.minimumAdditions {
                if matchingTests(for: sf).isEmpty {
                    let path = sf.newPath ?? ""
                    let msg = TemplateRenderer.render(
                        missingTestsRule.message,
                        values: [
                            "additions": "\(sf.additions)",
                            "path": path,
                        ])
                    addFinding(
                        path,
                        RuleFinding(
                            severity: .low, category: .test, message: msg,
                            lineStart: firstMeaningfulAddedLine(in: sf),
                            lineEnd: nil,
                            ruleSource: "standard-conventions/testing",
                            evidence: "Modified file: \(path) (\(sf.additions) lines added)"
                        ))
                }
            }
        }

        if let schemaSync = profile.rules.schemaSync, schemaSync.enabled {
            let migrationFiles = files.filter {
                PatternMatcher.matchesAny(
                    $0.newPath ?? $0.oldPath ?? "", patterns: schemaSync.migrationPaths)
            }
            if !migrationFiles.isEmpty {
                let hasSchemaChanges = files.contains {
                    $0.classification == .source
                        && PatternMatcher.matchesAny(
                            $0.newPath ?? $0.oldPath ?? "", patterns: schemaSync.schemaPaths)
                }
                if !hasSchemaChanges {
                    for mig in migrationFiles {
                        let path = mig.newPath ?? mig.oldPath ?? ""
                        addFinding(
                            path,
                            RuleFinding(
                                severity: .low, category: .architecture,
                                message: schemaSync.message,
                                ruleSource: "database/schema-sync",
                                evidence: "Migration file: \(path)"
                            ))
                    }
                }
            }
        }

        var emittedImportViolations = Set<String>()
        for boundary in profile.rules.importBoundaries {
            for sym in symbols {
                guard let path = filePathMap[sym.changedFileId] else { continue }
                guard PatternMatcher.matchesAny(path, patterns: boundary.sourcePaths) else {
                    continue
                }

                let imports = (sym.metadata["imports"] ?? "")
                    .split(separator: ",")
                    .map { String($0) }
                let forbidden = imports.first {
                    PatternMatcher.matchesAny($0, patterns: boundary.forbiddenImports)
                }
                if let forbidden {
                    let violationKey = "\(boundary.id)::\(path)::\(forbidden)"
                    guard emittedImportViolations.insert(violationKey).inserted else { continue }
                    addFinding(
                        path,
                        RuleFinding(
                            severity: ProfileValue.severity(boundary.severity),
                            category: ProfileValue.findingCategory(boundary.category),
                            message: TemplateRenderer.render(
                                boundary.message, values: ["symbol": sym.name, "path": path]),
                            lineStart: sym.startLine,
                            lineEnd: sym.endLine,
                            ruleSource: boundary.id,
                            evidence: "Import detected by AST sidecar: \(forbidden)"
                        ))
                }
            }
        }

        for rule in profile.rules.semanticAreaFindings {
            for sym in symbols {
                guard let path = filePathMap[sym.changedFileId] else { continue }
                guard findingRule(rule, matches: sym, path: path) else { continue }
                addFinding(
                    path,
                    RuleFinding(
                        severity: ProfileValue.severity(rule.severity),
                        category: ProfileValue.findingCategory(rule.category),
                        message: TemplateRenderer.render(
                            rule.message, values: ["symbol": sym.name, "path": path]),
                        lineStart: sym.startLine,
                        lineEnd: sym.endLine,
                        ruleSource: rule.id,
                        evidence: "AST-extracted symbol '\(sym.name)' (type: \(sym.semanticType))."
                    ))
            }
        }

        for rule in profile.rules.contractFindings {
            for sym in symbols where metadataMatches(sym.metadata, equals: rule.metadataEquals) {
                guard let path = filePathMap[sym.changedFileId] else { continue }
                addFinding(
                    path,
                    RuleFinding(
                        severity: ProfileValue.severity(rule.severity),
                        category: ProfileValue.findingCategory(rule.category),
                        message: TemplateRenderer.render(
                            rule.message, values: ["symbol": sym.name, "path": path]),
                        lineStart: sym.startLine,
                        lineEnd: sym.endLine,
                        ruleSource: rule.id,
                        evidence:
                            "AST comparison detected metadata match for '\(sym.name)' (\(sym.semanticType))."
                    ))
            }
        }

        guard let coverageRule = profile.rules.symbolCoverage, coverageRule.enabled else {
            return fileFindings
        }
        let testSymbols = symbols.filter { sym in
            sym.metadata["is_test"] == "true"
                || testFiles.contains(where: { $0.newPath == filePathMap[sym.changedFileId] })
        }
        let productionSymbols = symbols.filter { sym in
            guard let path = filePathMap[sym.changedFileId] else { return false }
            return profile.classifyFile(path) == .source && sym.metadata["is_test"] != "true"
        }
        for sym in productionSymbols {
            let isRisky =
                metadataMatches(sym.metadata, equals: coverageRule.riskMetadataEquals)
                || sym.metadata.keys.contains { key in
                    coverageRule.riskMetadataPrefixes.contains { key.hasPrefix($0) }
                }
                || sym.metadata.keys.contains { key in
                    coverageRule.riskMetadataSuffixes.contains { key.hasSuffix($0) }
                }
            guard isRisky, let path = filePathMap[sym.changedFileId] else { continue }

            let normalizedName = sym.name.lowercased()
            let hasRelatedTest = testSymbols.contains { testSym in
                let testPath = (filePathMap[testSym.changedFileId] ?? "").lowercased()
                let testName = testSym.name.lowercased()
                return testName.contains(normalizedName)
                    || testPath.contains(normalizedName)
                    || testSym.callees.contains(where: {
                        $0.caseInsensitiveCompare(sym.name) == .orderedSame
                    })
            }
            if !hasRelatedTest {
                addFinding(
                    path,
                    RuleFinding(
                        severity: .low,
                        category: .test,
                        message: TemplateRenderer.render(
                            coverageRule.message, values: ["symbol": sym.name, "path": path]),
                        lineStart: sym.startLine,
                        lineEnd: sym.endLine,
                        ruleSource: "testing/symbol-coverage",
                        evidence:
                            "No changed test symbol references '\(sym.name)' by name or direct callee metadata."
                    ))
            }
        }

        return fileFindings
    }

    private static func firstMeaningfulAddedLine(in file: DiffParser.ParsedFile) -> Int? {
        for hunk in file.hunks {
            var newLine = hunk.newStart
            for rawLine in hunk.lines {
                if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                    let content = String(rawLine.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if isMeaningfulAddedLine(content) {
                        return newLine
                    }
                    newLine += 1
                } else if !rawLine.hasPrefix("-") {
                    newLine += 1
                }
            }
        }
        return nil
    }

    private static func isMeaningfulAddedLine(_ content: String) -> Bool {
        guard !content.isEmpty else { return false }
        if content.hasPrefix("import ") || content.hasPrefix("package ") { return false }
        if content.hasPrefix("//") || content.hasPrefix("/*") || content.hasPrefix("*") {
            return false
        }
        return true
    }

    static func calculateRiskScore(
        files: [DiffParser.ParsedFile],
        symbols: [ChangedSymbol],
        findings: [RuleFinding],
        profile: AnalysisProfile = .generic
    ) -> RiskBreakdown {
        var score = 0
        var factors: [String] = []
        let scoring = profile.riskScoring

        let hasProductionChanges = files.contains {
            $0.classification == .source && $0.status != .deleted
        }
        let hasTestChanges = files.contains { $0.classification == .test }
        let hasGeneratedOnly =
            !files.isEmpty && files.allSatisfy { $0.classification == .generated }

        if hasGeneratedOnly {
            score += scoring.generatedOnlyDelta
            factors.append(
                "Generated-only or formatting-only changes (\(signed(scoring.generatedOnlyDelta)))")
        } else {
            if hasProductionChanges {
                score += scoring.productionChangeDelta
                factors.append(
                    "Production source code changed (\(signed(scoring.productionChangeDelta)))")
            }

            let hasApiChanges = files.contains {
                PatternMatcher.matchesAny(
                    $0.newPath ?? $0.oldPath ?? "", patterns: scoring.apiPaths)
            }
            if hasApiChanges {
                score += scoring.apiPathDelta
                factors.append(
                    "Configured API surface files modified (\(signed(scoring.apiPathDelta)))")
            }

            let hasSensitiveChanges = files.contains {
                PatternMatcher.matchesAny(
                    $0.newPath ?? $0.oldPath ?? "", patterns: scoring.sensitivePaths)
            }
            if hasSensitiveChanges {
                score += scoring.sensitivePathDelta
                factors.append(
                    "Configured sensitive paths modified (\(signed(scoring.sensitivePathDelta)))")
            }

            if hasProductionChanges && !hasTestChanges {
                score += scoring.missingTestsDelta
                factors.append(
                    "No test file additions or updates included with source changes (\(signed(scoring.missingTestsDelta)))"
                )
            }

            let hasArchViolations = findings.contains {
                $0.severity == .high || $0.category == .architecture
            }
            if hasArchViolations {
                score += scoring.architectureFindingDelta
                factors.append(
                    "High-severity architectural rule violation found (\(signed(scoring.architectureFindingDelta)))"
                )
            }

            if symbols.contains(where: {
                $0.metadata["caller_resolution"] == "indexed" && $0.callers.count > 5
            }) {
                score += scoring.highFanInDelta
                factors.append("High fan-in symbol modified (\(signed(scoring.highFanInDelta)))")
            }

            if symbols.contains(where: {
                $0.metadata.keys.contains { $0.starts(with: "contract_") }
            }) {
                score += scoring.contractDelta
                factors.append("AST contract surface changed (\(signed(scoring.contractDelta)))")
            }

            if symbols.contains(where: { $0.metadata.keys.contains { $0.hasSuffix("_added") } }) {
                score += scoring.behaviorAddedDelta
                factors.append(
                    "AST detected newly introduced behavior (\(signed(scoring.behaviorAddedDelta)))"
                )
            }

            if hasTestChanges {
                score += scoring.testChangeDelta
                factors.append(
                    "Tests added or updated for changed production area (\(signed(scoring.testChangeDelta)))"
                )
            }
        }

        return RiskBreakdown(score: max(0, min(100, score)), factors: factors)
    }

    private static func metadataMatches(_ metadata: [String: String], equals: [String: String])
        -> Bool
    {
        equals.allSatisfy { metadata[$0.key] == $0.value }
    }

    private static func findingRule(
        _ rule: SemanticAreaFindingRule, matches symbol: ChangedSymbol, path: String
    ) -> Bool {
        if let semanticArea = rule.semanticArea, symbol.metadata["semantic_area"] != semanticArea {
            return false
        }
        if let metadataEquals = rule.metadataEquals,
            !metadataMatches(symbol.metadata, equals: metadataEquals)
        {
            return false
        }
        if let paths = rule.paths, !PatternMatcher.matchesAny(path, patterns: paths) {
            return false
        }
        if let symbolNames = rule.symbolNames,
            !PatternMatcher.matchesAny(symbol.name, patterns: symbolNames)
        {
            return false
        }
        return rule.semanticArea != nil || rule.metadataEquals != nil || rule.paths != nil
            || rule.symbolNames != nil
    }

    private static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }
}

// MARK: - Triage Engine
// Ports triage.ts from diffuse2

struct TriageEngine {

    static func deriveTriage(
        files: [ChangedFile],
        symbols: [ChangedSymbol],
        findings: [Finding],
        riskScore: Int,
        profile: AnalysisProfile = .generic
    ) -> (
        reviewTargets: [ReviewTarget],
        changeBuckets: [ChangeBucket],
        riskHighlights: [RiskHighlight],
        skimTargets: [SkimTarget],
        riskFactors: [String],
        symbolReviewGroups: [SymbolReviewGroup]
    ) {
        // Re-classify using path rules
        let effectiveFiles = files.map { f -> ChangedFile in
            var ef = f
            let pathClass = DiffParser.classifyFile(f.path, profile: profile)
            ef.classification = pathClass != .source ? pathClass : f.classification
            return ef
        }

        let fileById = Dictionary(uniqueKeysWithValues: effectiveFiles.map { ($0.id, $0) })
        let symbolsByFile = Dictionary(grouping: symbols, by: \.changedFileId)

        // Convert for rules engine
        let parsedFiles = effectiveFiles.map { f -> DiffParser.ParsedFile in
            DiffParser.ParsedFile(
                oldPath: f.status == .added ? nil : f.path,
                newPath: f.status == .deleted ? nil : f.path,
                status: f.status,
                additions: f.additions,
                deletions: f.deletions,
                classification: f.classification,
                hunks: f.hunks
            )
        }

        // Reconstruct rule findings as RuleFinding for risk calc
        let ruleFindings = findings.map {
            RulesEngine.RuleFinding(
                severity: $0.severity, category: $0.category, message: $0.message,
                lineStart: $0.lineStart, lineEnd: $0.lineEnd, ruleSource: $0.ruleSource,
                evidence: $0.evidence
            )
        }

        let riskBreakdown = RulesEngine.calculateRiskScore(
            files: parsedFiles, symbols: symbols, findings: ruleFindings, profile: profile)
        let riskFactors = riskBreakdown.factors

        // Build change buckets
        var bucketDrafts:
            [String: (
                type: ChangeBucketType, title: String, files: [String], symbols: [String],
                riskLevel: Severity, riskReasons: [String], evidence: [String]
            )] = [:]

        let findingsByPath: [String: [Finding]] = findings.reduce(into: [:]) { acc, f in
            let path = fileById[f.changedFileId]?.path ?? "unknown"
            acc[path, default: []].append(f)
        }

        for file in effectiveFiles {
            let fileFindings = findingsByPath[file.path] ?? []
            let fileSymbolsForBucket = symbolsByFile[file.id] ?? []
            let matchedRule = profile.bucketRule(
                for: file, findings: fileFindings, symbols: fileSymbolsForBucket)
            let type = matchedRule?.bucketType ?? .behavior
            let bucketKey = matchedRule?.id ?? type.rawValue
            let title = matchedRule?.title ?? type.displayTitle
            let fileSymbols = fileSymbolsForBucket.map { $0.name }
            let riskReasons = fileFindings.map { $0.message }
            let evidence = fileFindings.compactMap { $0.evidence }
            let fileRisk = maxSeverity(fileFindings.map { $0.severity })

            if var existing = bucketDrafts[bucketKey] {
                existing.files.append(file.path)
                existing.symbols.append(contentsOf: fileSymbols)
                existing.riskReasons.append(contentsOf: riskReasons)
                existing.evidence.append(contentsOf: evidence)
                existing.riskLevel = maxSeverity([existing.riskLevel, fileRisk])
                bucketDrafts[bucketKey] = existing
            } else {
                bucketDrafts[bucketKey] = (
                    type: type, title: title, files: [file.path], symbols: fileSymbols,
                    riskLevel: fileRisk, riskReasons: riskReasons, evidence: evidence
                )
            }
        }

        let bucketIdOrder = profile.buckets.map { $0.id }
        let bucketTypeOrder = profile.buckets.map { $0.bucketType }
        var changeBuckets: [ChangeBucket] = bucketDrafts.map { key, draft in
            ChangeBucket(
                id: "bucket-\(key)", type: draft.type,
                title: draft.title,
                summary:
                    "\(draft.files.count) file\(draft.files.count == 1 ? "" : "s") grouped as \(draft.title.lowercased()).",
                files: draft.files,
                symbols: Array(Set(draft.symbols)),
                riskLevel: draft.riskLevel,
                riskReasons: Array(Set(draft.riskReasons)),
                evidence: Array(Set(draft.evidence)),
                reviewOrder: 0
            )
        }.sorted {
            if $0.riskLevel != $1.riskLevel { return $0.riskLevel > $1.riskLevel }
            let aid = String($0.id.dropFirst("bucket-".count))
            let bid = String($1.id.dropFirst("bucket-".count))
            let ai =
                bucketIdOrder.firstIndex(of: aid) ?? bucketTypeOrder.firstIndex(of: $0.type) ?? 99
            let bi =
                bucketIdOrder.firstIndex(of: bid) ?? bucketTypeOrder.firstIndex(of: $1.type) ?? 99
            return ai < bi
        }.enumerated().map { idx, b in
            var b2 = b
            b2.reviewOrder = idx + 1
            return b2
        }

        let fallbackBucketId = changeBuckets.first?.id ?? "bucket-behavior"
        var bucketIdByPath: [String: String] = [:]
        for bucket in changeBuckets {
            for path in bucket.files {
                bucketIdByPath[path] = bucket.id
            }
        }
        let bucketIdForPath: (String) -> String = { path in
            bucketIdByPath[path] ?? fallbackBucketId
        }

        // Build risk highlights from findings
        let sortedFindings = findings.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return true
        }

        let ruleHighlights: [RiskHighlight] = sortedFindings.map { f in
            let path = fileById[f.changedFileId]?.path ?? "unknown"
            return RiskHighlight(
                id: "risk-\(f.id.uuidString)",
                bucketId: bucketIdForPath(path),
                severity: f.severity,
                category: riskCategoryForFinding(f),
                title: String(f.message.split(separator: ".").first ?? Substring(f.message)),
                filePath: path,
                lineStart: f.lineStart,
                lineEnd: f.lineEnd,
                evidence: [f.evidence ?? f.ruleSource].compactMap { $0.isEmpty ? nil : $0 },
                source: "rule",
                confidence: "high"
            )
        }

        let semanticHighlights = deriveSemanticHighlights(
            symbols: symbols,
            files: effectiveFiles,
            bucketIdForPath: bucketIdForPath,
            profile: profile
        )

        let riskHighlights = consolidateRiskHighlights(
            semanticHighlights + ruleHighlights,
            files: effectiveFiles
        ).sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.category.weight > $1.category.weight
        }

        // Update bucket summaries based on highlights
        changeBuckets = changeBuckets.map { bucket in
            var b = bucket
            let bHighlights = riskHighlights.filter { $0.bucketId == bucket.id }
            b.riskLevel = maxSeverity([bucket.riskLevel] + bHighlights.map { $0.severity })
            b.riskReasons = Array(Set(bHighlights.map { $0.title } + bucket.riskReasons))
            b.evidence = Array(Set(bHighlights.flatMap { $0.evidence } + bucket.evidence))
            if let first = bHighlights.first {
                b.summary =
                    "\(bucket.files.count) file\(bucket.files.count == 1 ? "" : "s") grouped by semantic area. Key signal: \(first.title)."
            }
            return b
        }.sorted {
            if $0.riskLevel != $1.riskLevel { return $0.riskLevel > $1.riskLevel }
            let aid = String($0.id.dropFirst("bucket-".count))
            let bid = String($1.id.dropFirst("bucket-".count))
            let ai =
                bucketIdOrder.firstIndex(of: aid) ?? bucketTypeOrder.firstIndex(of: $0.type) ?? 99
            let bi =
                bucketIdOrder.firstIndex(of: bid) ?? bucketTypeOrder.firstIndex(of: $1.type) ?? 99
            return ai < bi
        }.enumerated().map { idx, b in
            var b2 = b
            b2.reviewOrder = idx + 1
            return b2
        }

        // Build review targets from actionable highlights. Priority signals stay medium+;
        // targets can include low-severity AST entry points so ordinary feature work
        // still has useful reviewer navigation.
        let fileByPath = Dictionary(uniqueKeysWithValues: effectiveFiles.map { ($0.path, $0) })
        let reviewTargets: [ReviewTarget] =
            riskHighlights
            .filter { $0.severity >= .low }
            .enumerated().map { idx, h in
                let matchFile = fileByPath[h.filePath]
                return ReviewTarget(
                    id: UUID(),
                    priority: idx + 1,
                    severity: h.severity,
                    title: h.title,
                    filePath: h.filePath,
                    lineStart: h.lineStart,
                    lineEnd: h.lineEnd,
                    reason: h.title,
                    evidence: h.evidence.joined(separator: " "),
                    source: h.source,
                    changedFileId: matchFile?.id,
                    hunkIndex: matchFile.flatMap { getHunkIndex($0, lineStart: h.lineStart) }
                )
            }

        // Build skim targets
        let skimTargets: [SkimTarget] =
            effectiveFiles
            .filter { $0.classification != .source && $0.classification != .test }
            .map { f in
                let reason: String
                switch f.classification {
                case .generated: reason = "Automatically generated file or package lockfile."
                case .config: reason = "Configuration settings only."
                case .documentation: reason = "Documentation-only changes."
                default: reason = "Boilerplate or declaration-only code changes."
                }
                return SkimTarget(
                    id: "skim-\(f.id.uuidString)", filePath: f.path, reason: reason,
                    classification: f.classification, additions: f.additions, deletions: f.deletions
                )
            }

        // Build symbol-first review map (Step 1)
        let symbolReviewGroups = buildSymbolReviewGroups(
            symbols: symbols, files: effectiveFiles, profile: profile)

        return (
            reviewTargets, changeBuckets, riskHighlights, skimTargets, riskFactors,
            symbolReviewGroups
        )
    }

    // MARK: - Step 1: Symbol-first review map

    /// Group changed symbols by semantic area for the symbol-first review map.
    static func buildSymbolReviewGroups(
        symbols: [ChangedSymbol],
        files: [ChangedFile],
        profile: AnalysisProfile = .generic
    ) -> [SymbolReviewGroup] {
        let fileById = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })

        // Include symbols from source and test files; skip generated/config/docs.
        let reviewSymbols = symbols.filter { sym in
            guard let classification = fileById[sym.changedFileId]?.classification else {
                return false
            }
            return classification == .source || classification == .test
        }

        guard !reviewSymbols.isEmpty else { return [] }

        var groups: [SymbolReviewGroup] = []
        var assignedIds = Set<UUID>()

        for groupRule in profile.symbolGroups {
            let groupSymbols: [ChangedSymbol]
            if groupRule.fallback == true {
                groupSymbols = reviewSymbols.filter { !assignedIds.contains($0.id) }
            } else {
                groupSymbols = reviewSymbols.filter {
                    groupRule.matches($0) && !assignedIds.contains($0.id)
                }
            }
            if !groupSymbols.isEmpty {
                assignedIds.formUnion(groupSymbols.map { $0.id })
                groups.append(
                    SymbolReviewGroup(
                        semanticArea: groupRule.id,
                        displayLabel: groupRule.label,
                        iconName: groupRule.icon,
                        symbols: groupSymbols
                    ))
            }
        }

        return groups
    }

    // MARK: - Private helpers

    private static func maxSeverity(_ values: [Severity]) -> Severity {
        values.max() ?? .info
    }

    private static func getHunkIndex(_ file: ChangedFile, lineStart: Int?) -> Int? {
        guard let line = lineStart else { return nil }
        let idx = file.hunks.firstIndex { h in
            line >= h.newStart && line <= h.newStart + h.newLines - 1
        }
        return idx
    }

    private static func consolidateRiskHighlights(
        _ highlights: [RiskHighlight], files: [ChangedFile]
    ) -> [RiskHighlight] {
        let fileByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
        let indexedHighlights: [(index: Int, key: String, highlight: RiskHighlight)] =
            highlights.enumerated().map { index, highlight in
                let hunkIndex = fileByPath[highlight.filePath].flatMap {
                    getHunkIndex($0, lineStart: highlight.lineStart)
                }
                let lineGroup =
                    hunkIndex.map { "hunk-\($0)" } ?? highlight.lineStart.map { "line-\($0)" }
                    ?? normalizedSignalText(highlight.title)
                let key = [
                    highlight.bucketId,
                    highlight.filePath,
                    highlight.category.rawValue,
                    lineGroup,
                ].joined(separator: "|")
                return (index: index, key: key, highlight: highlight)
            }

        let grouped = Dictionary(grouping: indexedHighlights, by: \.key)

        return grouped.values.map { group in
            let ordered = group.sorted { lhs, rhs in
                if lhs.highlight.severity != rhs.highlight.severity {
                    return lhs.highlight.severity > rhs.highlight.severity
                }
                if lhs.highlight.category.weight != rhs.highlight.category.weight {
                    return lhs.highlight.category.weight > rhs.highlight.category.weight
                }
                return lhs.index < rhs.index
            }

            let primary = ordered[0].highlight
            let members = ordered.map(\.highlight)
            let mergedEvidence = uniqueStrings(
                (members.count > 1
                    ? [
                        "Includes \(members.count) related signal\(members.count == 1 ? "" : "s") in this diff block."
                    ] : []) + members.flatMap(\.evidence)
            )
            let mergedTitle =
                members.count > 1
                ? "\(primary.title) (+\(members.count - 1) related)" : primary.title

            return RiskHighlight(
                id: "signal-group-\(normalizedSignalText(ordered[0].key))",
                bucketId: primary.bucketId,
                severity: maxSeverity(members.map(\.severity)),
                category: primary.category,
                title: mergedTitle,
                filePath: primary.filePath,
                lineStart: members.compactMap(\.lineStart).min(),
                lineEnd: members.compactMap(\.lineEnd).max(),
                evidence: mergedEvidence,
                source: uniqueStrings(members.map(\.source)).joined(separator: " + "),
                confidence: members.contains { $0.confidence == "high" }
                    ? "high" : primary.confidence
            )
        }
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !value.isEmpty && seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private static func normalizedSignalText(_ value: String) -> String {
        value
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { partial, character in
                if character != "-" || partial.last != "-" {
                    partial.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func riskCategoryForFinding(_ f: Finding) -> RiskCategory {
        switch f.category {
        case .security: .security
        case .architecture: .coupling
        case .test: .testGap
        case .performance: .runtime
        default: .reviewLoad
        }
    }

    /// Converts AST-extracted symbols into `RiskHighlight` objects for the triage dashboard.
    ///
    /// Replaces the old text-sniffing approach. Every classification now comes from
    /// structured `semantic_area`, `semantic_type`, and `is_test` tags produced by
    /// the chobi-core Tree-Sitter sidecar — no substring scanning on raw diff lines.
    private static func deriveSemanticHighlights(
        symbols: [ChangedSymbol],
        files: [ChangedFile],
        bucketIdForPath: (String) -> String,
        profile: AnalysisProfile = .generic
    ) -> [RiskHighlight] {
        var highlights: [RiskHighlight] = []
        var counter = 0

        func add(
            filePath: String,
            severity: Severity,
            category: RiskCategory,
            title: String,
            lineStart: Int?,
            lineEnd: Int?,
            evidence: [String],
            confidence: String = "high",
            source: String = "ast-classifier"
        ) {
            highlights.append(
                RiskHighlight(
                    id: "semantic-\(counter)",
                    bucketId: bucketIdForPath(filePath),
                    severity: severity,
                    category: category,
                    title: title,
                    filePath: filePath,
                    lineStart: lineStart,
                    lineEnd: lineEnd,
                    evidence: evidence,
                    source: source,
                    confidence: confidence
                ))
            counter += 1
        }

        // Build a fast lookup: changedFileId → file path
        let fileById = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.path) })

        // --- Symbol-level highlights (from AST sidecar) ---
        for sym in symbols {
            let filePath = fileById[sym.changedFileId] ?? "unknown"
            for rule in profile.semanticHighlights
            where semanticHighlight(rule, matches: sym, path: filePath) {
                let values = [
                    "symbol": sym.name,
                    "path": filePath,
                    "semanticType": sym.semanticType,
                ]
                add(
                    filePath: filePath,
                    severity: ProfileValue.severity(rule.severity),
                    category: ProfileValue.riskCategory(rule.category),
                    title: TemplateRenderer.render(rule.title, values: values),
                    lineStart: sym.startLine,
                    lineEnd: sym.endLine,
                    evidence: [TemplateRenderer.render(rule.evidence, values: values)],
                    confidence: "medium",
                    source: rule.id)
            }

        }  // end for sym in symbols

        // --- File-level highlights (no sidecar data available, or non-source files) ---
        // Only fires for files that produced zero symbols (binary, unsupported language, etc.)
        let filesWithSymbols = Set(symbols.map { $0.changedFileId })
        for file in files {
            // Test files not covered by a symbol highlight
            if file.classification == .test && !filesWithSymbols.contains(file.id) {
                add(
                    filePath: file.path, severity: .info, category: .testGap,
                    title: "Tests updated",
                    lineStart: nil, lineEnd: nil,
                    evidence: ["\(file.path) adds or updates test coverage."],
                    confidence: "medium",
                    source: "file-classifier")
            }

            for rule in profile.fileHighlights
            where fileHighlight(rule, matches: file, hasSymbols: filesWithSymbols.contains(file.id))
            {
                let values = [
                    "filename": URL(fileURLWithPath: file.path).deletingPathExtension()
                        .lastPathComponent,
                    "path": file.path,
                    "additions": "\(file.additions)",
                ]
                add(
                    filePath: file.path,
                    severity: ProfileValue.severity(rule.severity),
                    category: ProfileValue.riskCategory(rule.category),
                    title: TemplateRenderer.render(rule.title, values: values),
                    lineStart: nil,
                    lineEnd: nil,
                    evidence: [TemplateRenderer.render(rule.evidence, values: values)],
                    confidence: "low",
                    source: rule.id)
            }
        }

        return highlights
    }

    private static func semanticHighlight(
        _ rule: SemanticHighlightRule, matches symbol: ChangedSymbol, path: String
    ) -> Bool {
        if let semanticArea = rule.semanticArea, symbol.metadata["semantic_area"] != semanticArea {
            return false
        }
        if let metadataEquals = rule.metadataEquals,
            !metadataEquals.allSatisfy({ symbol.metadata[$0.key] == $0.value })
        {
            return false
        }
        if let paths = rule.paths, !PatternMatcher.matchesAny(path, patterns: paths) {
            return false
        }
        if let symbolNames = rule.symbolNames,
            !PatternMatcher.matchesAny(symbol.name, patterns: symbolNames)
        {
            return false
        }
        return rule.semanticArea != nil || rule.metadataEquals != nil || rule.paths != nil
            || rule.symbolNames != nil
    }

    private static func fileHighlight(
        _ rule: FileHighlightRule, matches file: ChangedFile, hasSymbols: Bool
    ) -> Bool {
        if rule.requiresNoSymbols == true && hasSymbols {
            return false
        }
        if let minimumAdditions = rule.minimumAdditions, file.additions <= minimumAdditions {
            return false
        }
        if let classifications = rule.classifications,
            !classifications.contains(file.classification.rawValue)
        {
            return false
        }
        if let paths = rule.paths, !PatternMatcher.matchesAny(file.path, patterns: paths) {
            return false
        }
        return true
    }
}
