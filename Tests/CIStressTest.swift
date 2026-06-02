import Foundation

func runStressTest() {
    print("🚀 Starting triage stress test for 10,000 files on CI...")
    let runId = UUID()

    // 1. Generate 10,000 changed files of various types:
    var files: [ChangedFile] = []
    for i in 1...10000 {
        let classification: ChangedFile.FileClassification
        let path: String
        let status: ChangedFile.FileStatus = (i % 10 == 0) ? .added : .modified

        if i <= 8000 {
            classification = .source
            path = "Sources/ModuleA/File_\(i).swift"
        } else if i <= 9000 {
            classification = .test
            path = "Tests/ModuleATests/File_\(i - 8000)Tests.swift"
        } else if i <= 9500 {
            classification = .config
            path = "Configs/setting_\(i - 9000).json"
        } else {
            classification = .documentation
            path = "Docs/guide_\(i - 9500).md"
        }

        files.append(
            ChangedFile(
                id: UUID(),
                analysisRunId: runId,
                path: path,
                status: status,
                additions: 15,
                deletions: 5,
                classification: classification,
                hunks: [
                    DiffHunk(
                        oldStart: 1, oldLines: 10, newStart: 1, newLines: 20,
                        lines: ["+ added line", "- deleted line", "  unchanged line"]
                    )
                ]
            )
        )
    }

    // 2. Generate 5,000 changed symbols distributed across the source files
    var symbols: [ChangedSymbol] = []
    for i in 1...5000 {
        let fileIdx = i % 8000
        let matchedFile = files[fileIdx]

        symbols.append(
            ChangedSymbol(
                id: UUID(),
                analysisRunId: runId,
                changedFileId: matchedFile.id,
                name: "funcTestSymbol_\(i)",
                kind: .function,
                startLine: 10,
                endLine: 20,
                callers: ["caller_\(i)_1", "caller_\(i)_2"],
                callees: ["callee_\(i)_1"],
                semanticType: "function_definition",
                metadata: [
                    "symbol_key": "key_\(i)",
                    "qualified_name": "ModuleA.File.funcTestSymbol_\(i)",
                ]
            )
        )
    }

    // 3. Create simulated rule findings
    var findings: [Finding] = []
    for i in 1...500 {
        let fileIdx = i * 15
        let matchedFile = files[fileIdx]
        findings.append(
            Finding(
                id: UUID(),
                analysisRunId: runId,
                changedFileId: matchedFile.id,
                severity: (i % 3 == 0) ? .high : .medium,
                category: .architecture,
                message: "Deterministic rule violation in file \(i)",
                lineStart: 10,
                lineEnd: 15,
                ruleSource: "rules/architectural-check",
                evidence: "Symbol referenced incorrectly."
            )
        )
    }

    let start = Date()

    // 4. Execute the TriageEngine
    let result = TriageEngine.deriveTriage(
        files: files,
        symbols: symbols,
        findings: findings,
        riskScore: 75,
        profile: .generic
    )

    let duration = Date().timeIntervalSince(start)

    print("✅ CI Triage Stress Test completed successfully!")
    print("⏱️ Time taken: \(String(format: "%.4f", duration)) seconds")
    print("📊 Results:")
    print("   - Change Buckets: \(result.changeBuckets.count)")
    print("   - Review Targets: \(result.reviewTargets.count)")
    print("   - Skim Targets: \(result.skimTargets.count)")
    print("   - Risk Highlights: \(result.riskHighlights.count)")
    print("   - Symbol Review Groups: \(result.symbolReviewGroups.count)")

    assert(duration < 5.0, "Triage of 10000 files took too long")
    assert(result.changeBuckets.count > 0, "No change buckets created")
    assert(result.reviewTargets.count > 0, "No review targets identified")
    assert(result.skimTargets.count == 1000, "Should have 1000 skim targets")
    assert(result.riskHighlights.count >= 500, "Should have at least 500 risk highlights")
    assert(result.symbolReviewGroups.count > 0, "No symbol review groups created")

    print("\n🎉 ALL CI PERFORMANCE AND CORRECTNESS ASSERTIONS PASSED!")
}

func runLargeRepositoryPipelineStressTest() {
    let fileCount = 12000
    let symbolCount = 9000
    let runId = UUID()

    print("Starting large repository diff pipeline stress test...")
    let start = Date()
    let parsedFiles = DiffParser.parse(makeLargeDiff(fileCount: fileCount), profile: .generic)
    assert(parsedFiles.count == fileCount, "Parsed file count mismatch")

    let files = parsedFiles.map { parsed -> ChangedFile in
        ChangedFile(
            analysisRunId: runId,
            path: parsed.newPath ?? parsed.oldPath ?? "unknown",
            status: parsed.status,
            additions: parsed.additions,
            deletions: parsed.deletions,
            classification: parsed.classification,
            hunks: parsed.hunks
        )
    }
    let sourceFiles = files.filter { $0.classification == .source }
    let symbols = makeSymbols(runId: runId, files: sourceFiles, count: symbolCount)
    let filePathMap = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.path) })
    let fileByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })

    let ruleFindingsByPath = RulesEngine.runDeterministicRules(
        files: parsedFiles,
        symbols: symbols,
        filePathMap: filePathMap,
        profile: .generic
    )
    let findings = ruleFindingsByPath.flatMap { path, findings -> [Finding] in
        guard let file = fileByPath[path] else { return [] }
        return findings.map { finding in
            Finding(
                id: UUID(),
                analysisRunId: runId,
                changedFileId: file.id,
                severity: finding.severity,
                category: finding.category,
                message: finding.message,
                lineStart: finding.lineStart,
                lineEnd: finding.lineEnd,
                ruleSource: finding.ruleSource,
                evidence: finding.evidence
            )
        }
    }

    let triage = TriageEngine.deriveTriage(
        files: files,
        symbols: symbols,
        findings: findings,
        riskScore: 85,
        profile: .generic
    )
    let duration = Date().timeIntervalSince(start)

    print("Large pipeline time: \(String(format: "%.4f", duration)) seconds")
    print("   - Parsed files: \(parsedFiles.count)")
    print("   - Symbols: \(symbols.count)")
    print("   - Findings: \(findings.count)")
    print("   - Review targets: \(triage.reviewTargets.count)")
    print("   - Risk highlights: \(triage.riskHighlights.count)")
    print("   - Skim targets: \(triage.skimTargets.count)")

    assert(!triage.changeBuckets.isEmpty, "No change buckets created for large pipeline")
    assert(!triage.reviewTargets.isEmpty, "No review targets created for large pipeline")
    assert(!triage.symbolReviewGroups.isEmpty, "No symbol review groups created for large pipeline")
    assert(triage.skimTargets.count == 2000, "Expected 2000 skim targets")
    assert(duration < 30.0, "Large repository pipeline took too long")
}

func makeLargeDiff(fileCount: Int) -> String {
    var diff = String()
    diff.reserveCapacity(fileCount * 360)

    for i in 1...fileCount {
        let path: String
        if i <= fileCount - 2000 {
            path = "Sources/Feature\(i % 250)/Service\(i).swift"
        } else if i <= fileCount - 1000 {
            path = "Configs/generated_setting_\(i).json"
        } else {
            path = "Docs/guide_\(i).md"
        }

        diff += """
            diff --git a/\(path) b/\(path)
            index 0000000..1111111 100644
            --- a/\(path)
            +++ b/\(path)
            @@ -1,4 +1,8 @@
             final class Fixture\(i) {
            -    func oldValue() -> Int { 1 }
            +    func newValue() -> Int { \(i) }
            +    func changedBehavior() -> String { "value-\(i)" }
             }

            """
    }

    return diff
}

func makeSymbols(runId: UUID, files: [ChangedFile], count: Int) -> [ChangedSymbol] {
    (0..<count).map { index in
        let file = files[index % files.count]
        let isCritical = index % 97 == 0
        return ChangedSymbol(
            analysisRunId: runId,
            changedFileId: file.id,
            name: "changedBehavior\(index)",
            kind: .method,
            startLine: 3,
            endLine: 6,
            callers: (0..<(index % 9)).map { caller in
                "Sources/Caller\(caller).swift:call\(index)"
            },
            callees: ["dependency\(index % 31)"],
            semanticType: "function_definition",
            metadata: [
                "qualified_name": "\(file.path).changedBehavior\(index)",
                "semantic_area": isCritical ? "security_authentication" : "general",
                "caller_resolution": "indexed",
                "language": "swift",
            ]
        )
    }
}

@main
struct CITestRunner {
    static func main() {
        runStressTest()
        runLargeRepositoryPipelineStressTest()
    }
}
