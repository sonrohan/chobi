import XCTest

@testable import Chobi

@MainActor
final class AgentContextBuilderTests: XCTestCase {
    func testContextBuilderProducesDeterministicOrderAndTruncation() {
        let run = AnalysisRun(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            pullRequestId: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            baseSha: "base",
            headSha: "head",
            status: .completed,
            riskScore: 70
        )
        let pr = PullRequest(
            id: run.pullRequestId,
            prNumber: 7,
            title: "Test PR",
            baseSha: "base",
            headSha: "head",
            author: "Rohan",
            repository: "local/Chobi"
        )
        let first = ChangedFile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            analysisRunId: run.id,
            path: "Sources/B.swift",
            status: .modified,
            additions: 2,
            deletions: 1,
            classification: .source,
            hunks: []
        )
        let second = ChangedFile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
            analysisRunId: run.id,
            path: "Sources/A.swift",
            status: .modified,
            additions: 1,
            deletions: 0,
            classification: .source,
            hunks: []
        )
        let details = AnalysisDetails(
            run: run,
            pr: pr,
            files: [first, second],
            symbols: [],
            findings: [],
            reviewTargets: [],
            changeBuckets: [],
            riskHighlights: [],
            skimTargets: [],
            riskFactors: ["Production source code changed"],
            symbolReviewGroups: []
        )
        let repo = GitRepository(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            name: "Chobi",
            path: "/tmp/Chobi"
        )

        let context = AgentContextBuilder.build(
            details: details,
            repository: repo,
            options: AgentContextOptions(
                detailLevel: .standard, includeFiles: true, includeSymbols: false, maxItems: 1)
        )

        XCTAssertEqual(context.files.map(\.path), ["Sources/A.swift"])
        XCTAssertTrue(context.truncated.files)
        XCTAssertEqual(context.summary.changedFileCount, 2)
        XCTAssertEqual(context.workspace.id, repo.id.uuidString)
    }
}
