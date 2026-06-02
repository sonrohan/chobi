# SCIP-backed Impact Graph Architecture

## Goal

Move Chobi's caller/callee and path resolution from name-based heuristics to a high-confidence symbol index, while keeping the current Tree-sitter sidecar as the local fallback and semantic classifier.

The target behavior is:

- Changed symbols still come from local diff-aware AST analysis.
- Callers, callees, file paths, and source ranges come from SCIP when available.
- The graph stores structured symbol nodes and edges instead of strings like `path:QualifiedName`.
- The UI can open source for changed and unchanged symbols with reliable line ranges.
- Repos without a usable SCIP index still get the current best-effort analysis.

## Current State

Today Chobi builds impact data in two passes:

1. `ASTAnalysisService.parseSymbols` runs `chobi-core analyze` on changed files and changed lines.
2. `chobi-core` uses Tree-sitter to extract changed declarations and direct callee names.
3. `ASTAnalysisService.symbolsWithCallerData` runs `git grep` for changed symbol names, indexes candidate files with `chobi-core index`, then inverts matching callee names into caller strings.
4. `ChangedSymbol` stores `callers: [String]` and `callees: [String]`.
5. `ImpactGraphViewModel` builds graph nodes from those strings at render time.

This is useful, but it has predictable limits:

- Symbol identity is name-based.
- Common method names collide.
- Callees usually do not have file paths or line ranges.
- Caller labels are string encoded.
- Transitive counts are direct counts in practice.
- The graph cannot reliably navigate outside changed symbols.

## Proposed Architecture

Use SCIP as an optional high-confidence symbol graph backend.

Tree-sitter remains responsible for:

- Changed symbol extraction from diff ranges.
- Semantic classification.
- Contract and behavior delta metadata.
- Fallback caller/callee extraction when no SCIP index is available.

SCIP becomes responsible for:

- Stable symbol descriptors.
- Definition locations.
- Reference locations.
- Caller/callee edge construction.
- Cross-file source navigation.
- Real transitive traversal.

## Core Components

### `SymbolIndexService`

New service actor under `Chobi/Services/`.

Responsibilities:

- Detect whether a SCIP index exists or can be generated.
- Load SCIP documents for the selected repository and revision.
- Normalize SCIP symbols into Chobi models.
- Provide definition and reference lookups.
- Cache parsed indexes per repository and revision.

Protocol shape:

```swift
protocol SymbolIndexServiceProtocol: Sendable {
    func indexStatus(repoPath: String, revision: String?) async -> SymbolIndexStatus
    func loadIndex(repoPath: String, revision: String?) async throws -> SymbolIndex
    func symbolGraph(
        for changedSymbols: [ChangedSymbol],
        filesById: [UUID: ChangedFile],
        repoPath: String,
        revision: String?
    ) async throws -> SymbolGraphResult
}
```

### `SCIPIndexProvider`

Lower-level implementation detail used by `SymbolIndexService`.

Responsibilities:

- Locate `.scip/index.scip`, `index.scip`, or configured index paths.
- Optionally run configured index commands later, but initial implementation should only consume existing indexes.
- Decode SCIP protobuf data into internal Swift records.
- Map SCIP documents to repository-relative file paths.

Initial policy:

- Do not auto-install indexers.
- Do not run arbitrary project commands.
- Treat missing index as a clean fallback condition.

### `ImpactGraphService`

New service actor under `Chobi/Services/`.

Responsibilities:

- Join changed symbols from Tree-sitter to SCIP definitions.
- Build structured graph nodes and edges.
- Fall back to `ASTAnalysisService.symbolsWithCallerData` when SCIP is unavailable.
- Compute impact summaries from graph edges.
- Return a graph model usable by app UI and MCP.

Protocol shape:

```swift
protocol ImpactGraphServiceProtocol: Sendable {
    func enrichSymbols(
        repoPath: String,
        symbols: [ChangedSymbol],
        files: [ChangedFile],
        revision: String?
    ) async -> ImpactGraphEnrichment

    func graph(
        rootSymbolId: String,
        depth: Int,
        direction: ImpactGraphDirection
    ) async throws -> ImpactGraph
}
```

## Data Model

Keep `ChangedSymbol` for compatibility, but stop treating `callers` and `callees` as the authoritative graph.

Add structured graph models under `Chobi/Core/`.

```swift
struct SymbolIdentity: Codable, Hashable, Sendable {
    var id: String
    var scipSymbol: String?
    var fallbackKey: String
    var displayName: String
    var qualifiedName: String?
    var kind: ChangedSymbol.SymbolKind
}

struct SymbolLocation: Codable, Hashable, Sendable {
    var filePath: String
    var startLine: Int
    var startColumn: Int?
    var endLine: Int
    var endColumn: Int?
}

struct SymbolGraphNode: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var identity: SymbolIdentity
    var definition: SymbolLocation?
    var isChangedInPR: Bool
    var isTest: Bool
    var confidence: GraphConfidence
}

struct SymbolGraphEdge: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var callerId: String
    var calleeId: String
    var callSite: SymbolLocation?
    var confidence: GraphConfidence
    var source: GraphEdgeSource
}

enum GraphEdgeSource: String, Codable, Sendable {
    case scip
    case treeSitterFallback
}

enum GraphConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}
```

`ChangedSymbol.metadata` should receive compatibility fields when SCIP resolves:

- `graph_source = scip`
- `scip_symbol = ...`
- `symbol_id = ...`
- `caller_resolution = scip`

The old `callers` and `callees` arrays can be populated from the structured graph for existing views and MCP responses during migration.

## SCIP Join Strategy

Changed symbols are produced from diff-aware Tree-sitter ranges. SCIP symbols are produced from whole-repo indexing. We need to join them.

Join order:

1. Same file path and range containment overlap.
2. Same file path, same display name, closest definition line.
3. Same file path, same qualified name or suffix-qualified name.
4. No SCIP match, keep Tree-sitter fallback identity.

For each `ChangedSymbol`:

- Find its likely SCIP definition.
- Store the SCIP symbol descriptor in `SymbolIdentity`.
- Use SCIP references to build incoming edges.
- Use same-symbol occurrence and enclosing definition logic to infer caller symbols.
- Use outgoing references inside the changed symbol range to build callee edges.

## Graph Construction

### Incoming callers

For a changed symbol `S`:

1. Find all SCIP reference occurrences targeting `S.scipSymbol`.
2. For each occurrence, find the enclosing definition in that document.
3. Create or reuse a caller node for the enclosing definition.
4. Add edge `caller -> S` with call-site range.

If the reference has no enclosing definition, represent it as a file-level caller node with medium confidence.

### Outgoing callees

For a changed symbol `S`:

1. Read SCIP occurrences within `S.definition` range.
2. Keep references that point to known definitions.
3. Create callee nodes for referenced symbols.
4. Add edge `S -> callee` with call-site range.

If SCIP is unavailable, use existing Tree-sitter callee names as low/medium confidence fallback edges.

### Transitive traversal

Store enough graph data to support:

- depth 1 by default
- depth 2 on demand
- callers, callees, or both
- traversal capped by node and edge limits

Traversal should be demand-driven. Do not render or materialize a whole-repo graph by default.

## Pipeline Integration

Update `ASTAnalysisService.extractChangedSymbols` flow:

1. Parse changed symbols with `chobi-core analyze`.
2. Merge contract and behavior metadata with `chobi-core compare`.
3. Ask `ImpactGraphService.enrichSymbols` for graph enrichment.
4. If SCIP succeeds, attach graph-derived compatibility caller/callee arrays and metrics.
5. If SCIP fails or is unavailable, run current `symbolsWithCallerData` fallback.
6. Persist changed symbols and graph records.

Suggested flow:

```text
Diff hunks
  -> Tree-sitter changed symbols
  -> Tree-sitter contract/behavior metadata
  -> SCIP symbol graph enrichment
      -> success: structured nodes/edges + compatibility arrays
      -> fallback: current git-grep/name inversion
  -> AnalysisDetails
  -> ImpactGraphViewModel / MCP
```

## Persistence

Add storage for graph records rather than recomputing everything in view models.

Candidate SwiftData entities:

- `SymbolGraphNodeEntity`
- `SymbolGraphEdgeEntity`
- `SymbolIndexMetadataEntity`

Minimum metadata:

- analysis run id
- repository path hash or id
- revision
- index source
- indexed document count
- graph build timestamp
- diagnostics and fallback reason

Keep `ChangedSymbolEntity.callers` and `.callees` during migration.

## UI Changes

`ImpactGraphViewModel` should stop parsing graph strings.

Instead it should:

- Load `SymbolGraphNode` and `SymbolGraphEdge` records.
- Filter by selected root, depth, and direction.
- Use `SymbolLocation` for source preview.
- Use edge call-site ranges to explain relationships.
- Mark fallback edges visually but quietly.

The graph panel can then show:

```text
Selected symbol
HabitViewModel.addHabit(...)
app/src/.../HabitViewModel.kt:L42-L64

Connection
Calls Habit.addHabit(...) at L51

Confidence
Resolved by SCIP
```

## MCP Changes

`chobi.get_impact_graph` should return structured nodes and edges.

Current response can remain backward-compatible by preserving:

- `callerNodes`
- `calleeNodes`
- `summary`

Add:

- `edges`
- `rootNode`
- `graphSource`
- `confidence`
- per-node `definitionRange`
- per-edge `callSiteRange`

`chobi.read_file_range` already has workspace path guarding and can be reused for source preview.

## Fallback Rules

Fallback is not an error. It is part of the architecture.

Use SCIP when:

- A readable SCIP index exists.
- Document paths can be mapped to repo-relative paths.
- The changed symbol can be joined to a SCIP definition.

Use Tree-sitter fallback when:

- No SCIP index exists.
- SCIP parsing fails.
- The language is unsupported by available indexers.
- The changed symbol cannot be joined confidently.

Confidence rules:

- `high`: SCIP definition and reference edge with file/range.
- `medium`: SCIP symbol match but missing enclosing caller or exact call site.
- `low`: Tree-sitter/name fallback.

## Index Availability

Initial implementation should consume existing indexes only.

Later, add profile-driven index commands:

```json
{
  "symbolIndex": {
    "type": "scip",
    "indexPath": ".scip/index.scip",
    "generateCommand": "scip-typescript index"
  }
}
```

Generation commands must be opt-in because they may require dependencies, build setup, or network access.

## Implementation Phases

### Phase 1: Models and Abstractions

- Add graph node, edge, identity, and location models.
- Add `SymbolIndexServiceProtocol`.
- Add `ImpactGraphServiceProtocol`.
- Keep current caller/callee arrays unchanged.

### Phase 2: SCIP Reader

- Locate and decode SCIP indexes.
- Normalize documents and occurrences.
- Add tests with a small fixture index.
- Report index diagnostics in analysis metrics.

### Phase 3: Changed Symbol Join

- Join Tree-sitter changed symbols to SCIP definitions.
- Store `scip_symbol` and `graph_source` metadata.
- Preserve fallback behavior for unmatched symbols.

### Phase 4: Structured Graph Enrichment

- Build incoming and outgoing edges.
- Persist graph nodes and edges.
- Populate compatibility `callers` and `callees`.
- Replace direct caller/callee scoring with graph-derived scoring.

### Phase 5: UI and MCP Migration

- Update `ImpactGraphViewModel` to consume structured graph records.
- Show call-site source ranges.
- Extend MCP graph responses with edges and ranges.
- Keep old fields until callers are migrated.

### Phase 6: Optional Index Generation

- Add profile configuration for index commands.
- Add explicit user-controlled generation.
- Cache by repository and revision.

## Testing Strategy

Unit tests:

- SCIP document path normalization.
- Occurrence-to-definition mapping.
- Changed-symbol-to-SCIP join order.
- Caller and callee edge construction.
- Fallback behavior when no index exists.
- Confidence assignment.

Integration tests:

- Small TypeScript fixture with overloaded/common method names.
- Cross-file caller/callee navigation.
- Test-file reference detection.
- Unmatched symbol fallback.
- MCP `get_impact_graph` includes structured ranges.

Build verification:

```bash
xcodebuild -project Chobi.xcodeproj -scheme Chobi -configuration Debug -quiet
```

## Open Questions

- Which SCIP indexers should Chobi support first?
- Do we want to store SCIP protobuf parsing in Swift, or introduce a small Rust helper command for decoding?
- Should graph records be persisted for every run or rebuilt from a cached index on demand?
- How should Swift projects be handled if SCIP coverage is weak?
- Should index generation be part of analysis, settings, or an explicit command?

## Recommended First Cut

Start with SCIP consumption, not generation.

Implement a `SymbolIndexService` that can read an existing index, build structured graph edges for one run, and gracefully fall back to the current name-based pipeline. That gives us better graph quality where available without making analysis setup fragile.
