import XCTest

@testable import Chobi

@MainActor
final class MCPRequestRouterTests: XCTestCase {

    func testUnknownToolReturnsStructuredError() async {
        let state = AppState()
        let query = AgentContextQueryService(
            stateProvider: state,
            persistence: state.coordinator.persistence
        )
        let router = MCPRequestRouter(queryService: query)

        let result = await router.callTool(name: "chobi.mutate_repo", arguments: [:])

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(result.content.first?["text"]?.contains("unsupported_query") == true)
    }

    func testInvalidRunIdReturnsArgumentError() async {
        let state = AppState()
        let query = AgentContextQueryService(
            stateProvider: state,
            persistence: state.coordinator.persistence
        )
        let router = MCPRequestRouter(queryService: query)

        let result = await router.callTool(
            name: "chobi.get_analysis_summary",
            arguments: ["runId": "not-a-uuid"]
        )

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(result.content.first?["text"]?.contains("invalid_arguments") == true)
    }

    func testMissingSymbolNameReturnsArgumentError() async {
        let state = AppState()
        let query = AgentContextQueryService(
            stateProvider: state,
            persistence: state.coordinator.persistence
        )
        let router = MCPRequestRouter(queryService: query)

        // symbolName is required — omitting it should produce an argument error
        let result = await router.callTool(
            name: "chobi.explain_symbol",
            arguments: [:]
        )

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(result.content.first?["text"]?.contains("invalid_arguments") == true)
    }

    func testToolListContainsExpectedTools() async {
        let tools = MCPRequestRouter.tools
        let names = Set(tools.map(\.name))

        XCTAssertTrue(names.contains("chobi.list_workspaces"))
        XCTAssertTrue(names.contains("chobi.get_analysis_summary"))
        XCTAssertTrue(names.contains("chobi.list_changed_files"))
        XCTAssertTrue(names.contains("chobi.explain_file"))
        XCTAssertTrue(names.contains("chobi.explain_symbol"))
        XCTAssertTrue(names.contains("chobi.get_impact_graph"))
        XCTAssertTrue(names.contains("chobi.get_review_plan"))
        XCTAssertTrue(names.contains("chobi.read_file_range"))

        // Dropped tools should not appear
        XCTAssertFalse(names.contains("chobi.get_current_review_context"))
        XCTAssertFalse(names.contains("chobi.search_review_context"))
        XCTAssertFalse(names.contains("chobi.get_profile_context"))
    }
}
