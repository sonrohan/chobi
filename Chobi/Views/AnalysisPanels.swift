import SwiftUI

struct ImpactStat: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.textTertiary)
    }
}

// MARK: - Review Map Panel

struct ReviewMapPanel: View {
    @Environment(AnalysisViewModel.self) private var viewModel
    let details: AnalysisDetails

    var topSignals: [RiskHighlight] {
        details.riskHighlights
            .filter { $0.severity >= .medium }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.system(size: 13))
                        .foregroundColor(.brandAccent)
                    Text("Review Map")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(topSignals.count) priority signal\(topSignals.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }

                if topSignals.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.success)
                        Text("No priority signals detected.")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.controlColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 6) {
                        ForEach(topSignals) { signal in
                            SignalCard(signal: signal) {
                                viewModel.jumpToHighlight(signal)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

struct SignalCard: View {
    let signal: RiskHighlight
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    signal.severity.badgeView
                    Text(
                        signal.category.rawValue.replacingOccurrences(of: "-", with: " ")
                            .capitalized
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                }
                Text(signal.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                    Text(signal.filePath + (signal.lineStart.map { ":L\($0)" } ?? ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.brandAccent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .contentShape(Rectangle())
            .background(isHovered ? Color.brandAccent.opacity(0.06) : Color(NSColor.controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    isHovered ? Color.brandAccent.opacity(0.3) : Color.borderMuted, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Review Targets Panel

struct ReviewTargetsPanel: View {
    let targets: [ReviewTarget]

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(
                    "Current Review Queue", icon: "shield.lefthalf.filled",
                    meta: "\(targets.count) target\(targets.count == 1 ? "" : "s")")

                if targets.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No high-priority targets")
                                .font(.system(size: 12, weight: .medium))
                            Text("No priority signals detected for this view.")
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(targets.enumerated()), id: \.element.id) { idx, target in
                            ReviewTargetCard(target: target, index: idx)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

struct ReviewTargetCard: View {
    @Environment(AnalysisViewModel.self) private var viewModel
    let target: ReviewTarget
    let index: Int

    var borderColor: Color {
        switch target.severity {
        case .high: .danger
        case .medium: .warning
        case .low: .info
        case .info: .borderDefault
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        target.severity.badgeView
                        Text("#\(index + 1)")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Text("via \(target.source)")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                    Text(target.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(3)
                }
                Spacer()
                if target.changedFileId != nil {
                    Button {
                        viewModel.toggleTarget(target)
                    } label: {
                        Label(
                            viewModel.activeTargetId == target.id ? "Clear" : "View diff",
                            systemImage: viewModel.activeTargetId == target.id
                                ? "xmark" : "arrow.right"
                        )
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                    Text(
                        target.filePath
                            + (target.lineStart.map { " · L\($0)–\(target.lineEnd ?? $0)" } ?? "")
                    )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                if !target.evidence.isEmpty {
                    Text(target.evidence)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(3)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(Color.bgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    viewModel.activeTargetId == target.id
                        ? Color.warning.opacity(0.65) : Color.borderMuted,
                    lineWidth: viewModel.activeTargetId == target.id ? 1.5 : 0.5)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(borderColor)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
    }
}

// MARK: - Safe to Skim Panel

struct SafeToSkimPanel: View {
    let targets: [SkimTarget]
    @State private var isExpanded = false

    var grouped: [ChangedFile.FileClassification: [SkimTarget]] {
        Dictionary(grouping: targets, by: { $0.classification })
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                        Text("Safe to Skim")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(targets.count) file\(targets.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(12)

                if !isExpanded && !targets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(
                                grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self
                            ) { cls in
                                let items = grouped[cls]!
                                BadgeView(
                                    text: "\(items.count) \(items[0].groupName)", variant: .neutral)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                }

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self)
                        { cls in
                            let items = grouped[cls]!
                            VStack(alignment: .leading, spacing: 4) {
                                Text(items[0].groupName.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                                    .kerning(0.5)

                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) {
                                        idx, item in
                                        HStack {
                                            Image(systemName: "doc.text")
                                                .font(.system(size: 10))
                                                .foregroundColor(.textTertiary)
                                            Text(item.filePath)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.textPrimary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            Text("+\(item.additions) −\(item.deletions)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.textTertiary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        if idx < items.count - 1 { Divider() }
                                    }
                                }
                                .background(Color(NSColor.controlColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6).stroke(
                                        Color.borderMuted, lineWidth: 0.5))
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}

// MARK: - Review Debug Sheet

struct ReviewDebugSheet: View {
    let details: AnalysisDetails
    let repo: GitRepository
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ReviewDebugTab = .ast

    private var symbolsByPath: [(path: String, symbols: [ChangedSymbol])] {
        let filesById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0.path) })
        return Dictionary(
            grouping: details.symbols,
            by: { filesById[$0.changedFileId] ?? $0.metadata["file_path"] ?? "unknown" }
        )
        .map {
            (
                $0.key,
                $0.value.sorted { lhs, rhs in
                    if lhs.startLine != rhs.startLine { return lhs.startLine < rhs.startLine }
                    return lhs.name < rhs.name
                }
            )
        }
        .sorted { $0.path < $1.path }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEBUG")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 14)
                .padding(.top, 18)

            ForEach(ReviewDebugTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .frame(width: 16)
                        Text(tab.title)
                        Spacer()
                    }
                    .font(
                        .system(size: 12, weight: selectedTab == tab ? .semibold : .medium)
                    )
                    .foregroundColor(selectedTab == tab ? .textPrimary : .textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab ? Color.brandAccent.opacity(0.10) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(width: 170)
        .background(Color.bgSidebar)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "ladybug")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.brandAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Review Debug")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(repo.name)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch selectedTab {
                        case .ast:
                            astBreakdown
                        case .performance:
                            performanceBreakdown
                        case .logs:
                            LogsConsoleView()
                        }
                    }
                    .padding(18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 760, height: 620)
        .background(Color.bgCanvas)
    }

    private var astBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            DebugMetricStrip(metrics: [
                ("Files", "\(details.files.count)"),
                ("AST symbols", "\(details.symbols.count)"),
                ("Findings", "\(details.findings.count)"),
                ("Targets", "\(details.reviewTargets.count)"),
            ])

            if symbolsByPath.isEmpty {
                DebugEmptyState(text: "No AST symbols were extracted for this analysis.")
            } else {
                ForEach(symbolsByPath, id: \.path) { group in
                    DebugSection(
                        title: group.path,
                        meta: "\(group.symbols.count) symbol\(group.symbols.count == 1 ? "" : "s")"
                    ) {
                        VStack(spacing: 8) {
                            ForEach(group.symbols) { symbol in
                                DebugSymbolCard(symbol: symbol)
                            }
                        }
                    }
                }
            }
        }
    }

    private var performanceBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let metrics = state.coordinator.lastRunMetrics {
                // Headline Metric
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOTAL ANALYSIS TIME")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .kerning(0.5)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.3f", metrics.totalTime))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(.brandAccent)
                        Text("seconds")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))

                // Phase Durations
                DebugSection(title: "Analysis Pipeline Breakdown", meta: "duration of each stage") {
                    VStack(spacing: 0) {
                        PerformanceStepRow(
                            label: "Git Gather Diff",
                            duration: metrics.gitGatherDiffTime,
                            meta: "Discovered changes from base Sha",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "Diff Parsing",
                            duration: metrics.diffParsingTime,
                            meta: "Parsed \(metrics.changedFilesCount) changed files",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "Parse Changed Code Paths",
                            duration: metrics.astParseTime,
                            meta: "Extracted \(metrics.symbolsCount) symbols from changed files",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "AST Base/Head Comparison",
                            duration: metrics.astCompareTime,
                            meta: "Computed contract-deltas & behavioral updates",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "Callers & Dependencies Indexing",
                            duration: metrics.astCallGraphTime,
                            meta:
                                "Indexed \(metrics.indexedFilesCount) / \(metrics.trackedFilesCount) matching tracked files",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "Rules Engine Execution",
                            duration: metrics.rulesEngineTime,
                            meta: "Evaluated deterministic rules & calculated risk score",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "Triage Engine Derivation",
                            duration: metrics.triageEngineTime,
                            meta: "Categorized change buckets & derived review targets",
                            total: metrics.totalTime
                        )
                    }
                    .background(Color(NSColor.controlColor).opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.system(size: 32))
                        .foregroundColor(.textTertiary)
                    Text("No Performance Data")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Trigger an analysis reload or select another commit to populate timings.")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }
}

private enum ReviewDebugTab: String, CaseIterable, Identifiable {
    case ast
    case performance
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ast: "Raw AST"
        case .performance: "Performance"
        case .logs: "Logs Console"
        }
    }

    var icon: String {
        switch self {
        case .ast: "point.3.connected.trianglepath.dotted"
        case .performance: "timer"
        case .logs: "terminal"
        }
    }
}

private struct PerformanceStepRow: View {
    let label: String
    let duration: Double
    let meta: String
    let total: Double

    var percentage: Double {
        total > 0 ? (duration / total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(String(format: "%.3fs", duration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textSecondary)
            }

            HStack(spacing: 8) {
                // Modern, beautiful progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.borderMuted.opacity(0.4))
                            .frame(height: 4)
                        Capsule()
                            .fill(Color.brandAccent)
                            .frame(width: geo.size.width * CGFloat(percentage), height: 4)
                    }
                }
                .frame(height: 4)

                Text(String(format: "%.0f%%", percentage * 100))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.textTertiary)
                    .frame(width: 28, alignment: .trailing)
            }

            Text(meta)
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
        }
        .padding(10)
    }
}

private struct DebugMetricStrip: View {
    let metrics: [(String, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(metrics, id: \.0) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.0.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.textTertiary)
                    Text(metric.1)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7).stroke(Color.borderMuted, lineWidth: 0.5))
            }
        }
    }
}

private struct DebugSection<Content: View>: View {
    let title: String
    let meta: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let meta {
                    Text(meta)
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
            }
            content()
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
    }
}

private struct DebugSymbolCard: View {
    let symbol: ChangedSymbol

    private var metadataRows: [(String, String)] {
        symbol.metadata
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BadgeView(text: symbol.kind.rawValue, variant: .neutral)
                Text(symbol.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("L\(symbol.startLine)-\(symbol.endLine)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textTertiary)
            }

            HStack(spacing: 12) {
                DebugInlineValue(label: "semantic_type", value: symbol.semanticType)
                DebugInlineValue(label: "domain", value: symbol.metadata["semantic_area"] ?? "none")
                DebugInlineValue(label: "language", value: symbol.metadata["language"] ?? "unknown")
            }

            if !symbol.callees.isEmpty || !symbol.callers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !symbol.callees.isEmpty {
                        DebugKeyValueRow(
                            label: "Callees", value: symbol.callees.joined(separator: ", "))
                    }
                    if !symbol.callers.isEmpty {
                        DebugKeyValueRow(
                            label: "Callers", value: symbol.callers.joined(separator: ", "))
                    }
                }
            }

            if !metadataRows.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(metadataRows, id: \.0) { row in
                        DebugInlineValue(label: row.0, value: row.1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct DebugKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.textTertiary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct DebugEmptyState: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .foregroundColor(.textTertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct DebugInlineValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.textTertiary)
                .lineLimit(1)
            Text(value.isEmpty ? "empty" : value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Array where Element == ReviewTarget {
    fileprivate var severitySummary: String {
        let severities: [(Severity, String)] = [
            (.high, "high"),
            (.medium, "medium"),
            (.low, "low"),
            (.info, "info"),
        ]
        let parts = severities.compactMap { severity, label -> String? in
            let count = filter { $0.severity == severity }.count
            guard count > 0 else { return nil }
            return "\(count) \(label)"
        }
        if parts.isEmpty { return "0 targets" }
        return parts.joined(separator: ", ") + " target\(count == 1 ? "" : "s")"
    }
}

// MARK: - Logs Console View

struct LogsConsoleView: View {
    @State private var query = ""
    @State private var selectedTag = "All"
    @State private var selectedLevel = "All"

    private var logger: AppLogger {
        AppLogger.shared
    }

    private var availableTags: [String] {
        var tags = Array(Set(logger.entries.map { $0.tag })).sorted()
        tags.insert("All", at: 0)
        return tags
    }

    private var filteredEntries: [LogEntry] {
        logger.entries.filter { entry in
            let matchesQuery =
                query.isEmpty
                || entry.message.localizedCaseInsensitiveContains(query)
                || entry.tag.localizedCaseInsensitiveContains(query)

            let matchesTag = selectedTag == "All" || entry.tag == selectedTag

            let matchesLevel =
                selectedLevel == "All"
                || entry.level.rawValue == selectedLevel

            return matchesQuery && matchesTag && matchesLevel
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Control bar
            HStack(spacing: 8) {
                // Search field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                    TextField("Filter message...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.borderMuted, lineWidth: 0.5)
                )
                .frame(maxWidth: 180)

                // Level Filter
                Picker("Level", selection: $selectedLevel) {
                    Text("All Levels").tag("All")
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                // Tag Filter
                Picker("Tag", selection: $selectedTag) {
                    ForEach(availableTags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Spacer()

                // Copy logs button
                Button {
                    let text = filteredEntries.map { entry in
                        "[\(entry.timestamp)] [\(entry.level.rawValue)] [\(entry.tag)] \(entry.message)"
                    }.joined(separator: "\n")
                    let pasteboard = NSPasteboard.general
                    pasteboard.declareTypes([.string], owner: nil)
                    pasteboard.setString(text, forType: .string)
                } label: {
                    Label("Copy filtered logs", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy logs to clipboard")

                // Clear button
                Button {
                    logger.clear()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.bordered)
                .help("Clear console logs")
            }
            .padding(.bottom, 12)

            // Log Console Box
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if filteredEntries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 24))
                                    .foregroundColor(.textTertiary)
                                Text("No console logs match filters")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(filteredEntries) { entry in
                                LogEntryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(10)
                }
                .background(Color(NSColor.underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5)
                )
                .frame(minHeight: 380, maxHeight: 460)
                .onChange(of: filteredEntries.count) {
                    if let last = filteredEntries.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: entry.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Level Indicator Badge
            Text(entry.level.rawValue)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(entry.level.color)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(entry.level.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(width: 42, alignment: .leading)

            // Timestamp
            Text(timeString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.textTertiary)
                .frame(width: 68, alignment: .leading)

            // Tag/Category Badge
            Text(entry.tag)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.accentPurple)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.accentPurple.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            // Message
            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 1)
    }
}
