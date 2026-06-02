import SwiftUI

// MARK: - Diff Viewer Panel

struct DiffViewerPanel: View {
    @Environment(AppState.self) private var state
    @Environment(AnalysisViewModel.self) private var viewModel
    let details: AnalysisDetails
    @Bindable var impactViewModel: ImpactGraphViewModel

    @State private var reviewViewModel = ReviewModeViewModel()
    @State private var fileSidebarWidth: CGFloat = 220
    @State private var isFilterPopoverPresented = false

    var activeFile: ChangedFile? {
        reviewViewModel.activeFile(
            activeFileId: viewModel.activeFileId, filteredFiles: filteredFiles)
    }

    var orderedFiles: [ChangedFile] {
        reviewViewModel.orderedFiles(
            files: viewModel.bucketFiles,
            highlights: details.riskHighlights,
            analysisViewModel: viewModel
        )
    }

    var fileTreeBadges: [UUID: ReviewFileTreeBadge] {
        reviewViewModel.badgeSummaries(from: impactViewModel.fileImpactIndicators)
    }

    var filteredFiles: [ChangedFile] {
        reviewViewModel.filteredFiles(orderedFiles: orderedFiles, badges: fileTreeBadges)
    }

    var activeFilterCount: Int {
        reviewViewModel.activeFilterCount()
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // File list sidebar column
                VStack(spacing: 0) {
                    // Left Header Row 1: Title and Actions
                    HStack(spacing: 6) {
                        Text("Changed Files")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("\(filteredFiles.count)/\(orderedFiles.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.textTertiary)

                        Spacer()

                        // 1. Impact Filter (Menu)
                        Menu {
                            Button {
                                reviewViewModel.minimumImpactFilter = .all
                            } label: {
                                HStack {
                                    Text("All Files")
                                    if reviewViewModel.minimumImpactFilter == .all {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button {
                                reviewViewModel.minimumImpactFilter = .medium
                            } label: {
                                HStack {
                                    Text("Medium & High Impact")
                                    if reviewViewModel.minimumImpactFilter == .medium {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button {
                                reviewViewModel.minimumImpactFilter = .high
                            } label: {
                                HStack {
                                    Text("High Impact Only")
                                    if reviewViewModel.minimumImpactFilter == .high {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "exclamationmark.shield")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(
                                    reviewViewModel.minimumImpactFilter != .all
                                        ? .brandAccent : .textSecondary
                                )
                                .frame(width: 22, height: 20)
                                .background(
                                    reviewViewModel.minimumImpactFilter != .all
                                        ? Color.brandAccent.opacity(0.10)
                                        : Color(NSColor.controlColor).opacity(0.45)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            reviewViewModel.minimumImpactFilter != .all
                                                ? Color.brandAccent.opacity(0.35)
                                                : Color.borderMuted,
                                            lineWidth: 0.5)
                                )
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .help("Filter files by impact level")
                        .frame(width: 24, height: 22)

                        // 2. Filter Popover Toggle
                        Button {
                            isFilterPopoverPresented.toggle()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 11, weight: .semibold))
                                if activeFilterCount > 0 {
                                    Text("\(activeFilterCount)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                }
                            }
                            .foregroundColor(activeFilterCount > 0 ? .brandAccent : .textSecondary)
                            .frame(width: activeFilterCount > 0 ? 32 : 22, height: 20)
                            .background(
                                activeFilterCount > 0
                                    ? Color.brandAccent.opacity(0.10)
                                    : Color(NSColor.controlColor).opacity(0.45)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        activeFilterCount > 0
                                            ? Color.brandAccent.opacity(0.35) : Color.borderMuted,
                                        lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Filter changed files")
                        .popover(isPresented: $isFilterPopoverPresented, arrowEdge: .bottom) {
                            FileFilterPopover(
                                files: orderedFiles,
                                excludedExtensions: $reviewViewModel.excludedExtensions,
                                excludedStatuses: $reviewViewModel.excludedStatuses,
                                excludedClassifications: $reviewViewModel.excludedClassifications,
                                showUnviewedOnly: $reviewViewModel.showUnviewedOnly,
                                viewedFileCount: orderedFiles.filter {
                                    reviewViewModel.reviewedFileIds.contains($0.id)
                                }.count
                            ) {
                                reviewViewModel.resetFileFilters()
                            }
                        }

                        // 3. Compact Tree Toggle
                        Button {
                            reviewViewModel.compactFileTree.toggle()
                        } label: {
                            Image(
                                systemName: reviewViewModel.compactFileTree
                                    ? "rectangle.compress.vertical" : "list.bullet.indent"
                            )
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(
                                reviewViewModel.compactFileTree ? .brandAccent : .textSecondary
                            )
                            .frame(width: 22, height: 20)
                            .background(
                                reviewViewModel.compactFileTree
                                    ? Color.brandAccent.opacity(0.10)
                                    : Color(NSColor.controlColor).opacity(0.45)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        reviewViewModel.compactFileTree
                                            ? Color.brandAccent.opacity(0.35) : Color.borderMuted,
                                        lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(
                            reviewViewModel.compactFileTree
                                ? "Show every folder level" : "Fold single-child folder chains")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Left Header Row 2: Search Field
                    FileSearchField(text: $reviewViewModel.fileSearchText)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)

                    Divider()

                    FileListSidebar(
                        files: filteredFiles,
                        activeFile: activeFile,
                        compactTree: reviewViewModel.compactFileTree,
                        impactViewModel: impactViewModel,
                        selectedImpactId: reviewViewModel.selectedInlineImpactMarkerId,
                        badges: fileTreeBadges,
                        onSelectImpact: { impact in
                            impactViewModel.select(impact)
                            reviewViewModel.selectedInlineImpactMarkerId = impact.id
                            viewModel.isImpactInspectorVisible = true
                            viewModel.jumpToImpactRoot(impact)
                        })
                }
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 480)

                // Diff content
                if let file = activeFile {
                    DiffContent(
                        file: file,
                        details: details,
                        impactViewModel: impactViewModel,
                        impactFilter: reviewViewModel.minimumImpactFilter,
                        selectedMarkerId: reviewViewModel.selectedInlineImpactMarkerId,
                        expandedImpactIds: reviewViewModel.expandedInlineImpactIds,
                        activeHunkIndex: viewModel.activeHunkIndex,
                        activeTarget: viewModel.activeTarget?.filePath == file.path
                            ? viewModel.activeTarget : nil
                    ) {
                        reviewViewModel.copyFileContext(
                            file: file,
                            impacts: impactViewModel.visibleImpacts(for: file),
                            details: details
                        )
                    } onOpenImpact: { impact in
                        impactViewModel.select(impact)
                        reviewViewModel.selectedInlineImpactMarkerId = impact.id
                        viewModel.isImpactInspectorVisible = true
                        viewModel.jumpToImpactRoot(impact)
                    } onToggleImpactExpansion: { impact in
                        reviewViewModel.toggleInlineImpactExpansion(impact.id)
                    }
                } else {
                    VStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(.textTertiary)
                        Text(
                            filteredFiles.isEmpty
                                ? "No files match the current filters"
                                : "Select a file to view its diff"
                        )
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        if filteredFiles.isEmpty && activeFilterCount > 0 {
                            Button("Clear filters") {
                                reviewViewModel.resetFileFilters()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bgCanvas)
                }

                // Right-side Impact inspector
                if viewModel.isImpactInspectorVisible {
                    ImpactExplorerSidebar(
                        reviewViewModel: reviewViewModel,
                        impactViewModel: impactViewModel,
                        details: details,
                        onClose: { viewModel.isImpactInspectorVisible = false },
                        onOpenImpact: { impact in
                            impactViewModel.select(impact)
                            viewModel.jumpToImpactRoot(impact)
                        },
                        onOpenNode: { node in
                            jumpToGraphNode(node, details: details)
                        }
                    )
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 450)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reviewViewModel.markReviewed(activeFile?.id)
            if reviewViewModel.shouldAutoOpenInspector(file: activeFile, badges: fileTreeBadges) {
                viewModel.isImpactInspectorVisible = true
            }
        }
        .onChange(of: activeFile?.id) { _, id in
            reviewViewModel.markReviewed(id)
            if reviewViewModel.shouldAutoOpenInspector(file: activeFile, badges: fileTreeBadges) {
                viewModel.isImpactInspectorVisible = true
            }
        }
        .onChange(of: filteredFiles.map(\.id)) { _, ids in
            if let activeId = viewModel.activeFileId, !ids.contains(activeId) {
                viewModel.jumpToFile(ids.first ?? activeId)
            }
        }
    }

    private func jumpToGraphNode(_ node: ImpactGraphNode, details: AnalysisDetails) {
        guard node.isChangedInPR,
            let file = details.files.first(where: { $0.path == node.filePath })
        else { return }

        if !filteredFiles.contains(where: { $0.id == file.id }) {
            reviewViewModel.unhideForNavigation(file: file, badges: fileTreeBadges)
        }

        viewModel.jumpToFile(file.id, hunkIndex: hunkIndexForLine(file: file, line: node.line))
    }

    private func hunkIndexForLine(file: ChangedFile, line: Int?) -> Int? {
        guard let line else { return nil }
        return file.hunks.firstIndex { hunk in
            line >= hunk.newStart && line <= hunk.newStart + max(hunk.newLines - 1, 0)
        }
    }
}

struct FileSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)

            TextField("Filter files...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear file search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.borderMuted, lineWidth: 0.5))
    }
}

struct FileFilterPopover: View {
    let files: [ChangedFile]
    @Binding var excludedExtensions: Set<String>
    @Binding var excludedStatuses: Set<ChangedFile.FileStatus>
    @Binding var excludedClassifications: Set<ChangedFile.FileClassification>
    @Binding var showUnviewedOnly: Bool
    let viewedFileCount: Int
    let reset: () -> Void

    var extensionCounts: [(String, Int)] {
        counted(files.map(\.filterExtension))
    }

    var statusCounts: [(ChangedFile.FileStatus, Int)] {
        ChangedFile.FileStatus.allCases.compactMap { status in
            let count = files.filter { $0.status == status }.count
            return count == 0 ? nil : (status, count)
        }
    }

    var classificationCounts: [(ChangedFile.FileClassification, Int)] {
        ChangedFile.FileClassification.allCases.compactMap { classification in
            let count = files.filter { $0.classification == classification }.count
            return count == 0 ? nil : (classification, count)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File filters")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button("Reset", action: reset)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(.brandAccent)
            }

            FilterSection(title: "Extensions") {
                ForEach(extensionCounts, id: \.0) { ext, count in
                    FilterToggleRow(
                        title: ext,
                        count: count,
                        isIncluded: !excludedExtensions.contains(ext)
                    ) {
                        toggle(ext, in: $excludedExtensions)
                    }
                }
            }

            FilterSection(title: "Status") {
                ForEach(statusCounts, id: \.0) { status, count in
                    FilterToggleRow(
                        title: status.displayName, count: count,
                        isIncluded: !excludedStatuses.contains(status)
                    ) {
                        toggle(status, in: $excludedStatuses)
                    }
                }
            }

            FilterSection(title: "Type") {
                ForEach(classificationCounts, id: \.0) { classification, count in
                    FilterToggleRow(
                        title: classification.displayName, count: count,
                        isIncluded: !excludedClassifications.contains(classification)
                    ) {
                        toggle(classification, in: $excludedClassifications)
                    }
                }
            }

            Divider()

            Button {
                showUnviewedOnly.toggle()
            } label: {
                FilterToggleRowContent(
                    title: "Unviewed only",
                    count: max(files.count - viewedFileCount, 0),
                    isIncluded: showUnviewedOnly
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 260)
        .background(Color.bgCanvas)
    }

    private func counted(_ values: [String]) -> [(String, Int)] {
        Dictionary(grouping: values, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.0 == "No extension" { return false }
                if rhs.0 == "No extension" { return true }
                return lhs.0.localizedStandardCompare(rhs.0) == .orderedAscending
            }
    }

    private func toggle<T: Hashable>(_ value: T, in binding: Binding<Set<T>>) {
        var values = binding.wrappedValue
        if values.contains(value) {
            values.remove(value)
        } else {
            values.insert(value)
        }
        binding.wrappedValue = values
    }
}

struct FilterSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .kerning(0.5)
            VStack(spacing: 2) {
                content
            }
        }
    }
}

struct FilterToggleRow: View {
    let title: String
    let count: Int
    let isIncluded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FilterToggleRowContent(title: title, count: count, isIncluded: isIncluded)
        }
        .buttonStyle(.plain)
    }
}

struct FilterToggleRowContent: View {
    let title: String
    let count: Int
    let isIncluded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textSecondary)
                .opacity(isIncluded ? 1 : 0)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlColor).opacity(0.55))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

extension ChangedFile.FileStatus: CaseIterable {
    static var allCases: [ChangedFile.FileStatus] {
        [.added, .modified, .deleted, .renamed]
    }

    var displayName: String {
        switch self {
        case .added: "Added"
        case .modified: "Modified"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        }
    }
}

extension ChangedFile.FileClassification: CaseIterable {
    static var allCases: [ChangedFile.FileClassification] {
        [.source, .test, .config, .documentation, .generated, .boilerplate]
    }

    var displayName: String {
        switch self {
        case .source: "Source"
        case .test: "Tests"
        case .config: "Config"
        case .documentation: "Docs"
        case .generated: "Generated"
        case .boilerplate: "Boilerplate"
        }
    }
}

struct DiffToolbarButton: View {
    let systemImage: String
    var isActive = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? .brandAccent : .textSecondary)
                .frame(width: 26, height: 22)
                .background(
                    isActive
                        ? Color.brandAccent.opacity(0.10)
                        : Color(NSColor.controlColor).opacity(0.45)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            isActive ? Color.brandAccent.opacity(0.35) : Color.borderMuted,
                            lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - File List Sidebar

struct FileListSidebar: View {
    @Environment(AnalysisViewModel.self) private var viewModel
    let files: [ChangedFile]
    let activeFile: ChangedFile?
    let compactTree: Bool
    let impactViewModel: ImpactGraphViewModel
    let selectedImpactId: UUID?
    let badges: [UUID: ReviewFileTreeBadge]
    let onSelectImpact: (SymbolImpact) -> Void
    var width: CGFloat = 220
    @State private var collapsedFolders: Set<String> = []
    @State private var expandedFileIds: Set<UUID> = []

    var roots: [FileTreeNode] {
        FileTreeNode.build(files: files)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(roots) { node in
                    FileTreeNodeView(
                        node: node,
                        depth: 0,
                        activeFile: activeFile,
                        collapsedFolders: $collapsedFolders,
                        expandedFileIds: $expandedFileIds,
                        compactTree: compactTree,
                        impactViewModel: impactViewModel,
                        selectedImpactId: selectedImpactId,
                        badges: badges,
                        onSelectFile: { file in
                            viewModel.jumpToFile(file.id)
                        },
                        onSelectImpact: onSelectImpact
                    )
                }

                if files.isEmpty {
                    Text("No source files in this view.")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .italic()
                        .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgSubtle)
    }
}

struct FileTreeNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    var files: [ChangedFile] = []
    var children: [FileTreeNode] = []

    var fileCount: Int {
        files.count + children.reduce(0) { $0 + $1.fileCount }
    }

    var isSingleChildDirectoryChain: Bool {
        files.isEmpty && children.count == 1
    }

    func aggregateImpact(badges: [UUID: ReviewFileTreeBadge]) -> ReviewFileTreeBadge? {
        var totalCount = 0
        var totalHighCount = 0
        var totalMediumCount = 0
        var totalCallerCount = 0
        var totalWeakTestCount = 0

        for file in files {
            if let badge = badges[file.id] {
                totalCount += badge.count
                totalHighCount += badge.highCount
                totalMediumCount += badge.mediumCount
                totalCallerCount += badge.callerCount
                totalWeakTestCount += badge.weakTestCount
            }
        }

        for child in children {
            if let badge = child.aggregateImpact(badges: badges) {
                totalCount += badge.count
                totalHighCount += badge.highCount
                totalMediumCount += badge.mediumCount
                totalCallerCount += badge.callerCount
                totalWeakTestCount += badge.weakTestCount
            }
        }

        guard totalCount > 0 else { return nil }
        let severity: ImpactLevel =
            if totalHighCount > 0 {
                .high
            } else if totalMediumCount > 0 {
                .medium
            } else {
                .low
            }
        return ReviewFileTreeBadge(
            count: totalCount,
            severity: severity,
            highCount: totalHighCount,
            mediumCount: totalMediumCount,
            callerCount: totalCallerCount,
            weakTestCount: totalWeakTestCount
        )
    }

    static func build(files: [ChangedFile]) -> [FileTreeNode] {
        var root = MutableFileTreeNode(name: "", path: "")

        for file in files.sorted(by: {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }) {
            let parts = file.path.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }
            root.insert(file: file, folders: Array(parts.dropLast()))
        }

        return root.children.values
            .map { $0.toImmutable() }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct MutableFileTreeNode {
    let name: String
    let path: String
    var files: [ChangedFile] = []
    var children: [String: MutableFileTreeNode] = [:]

    mutating func insert(file: ChangedFile, folders: [String]) {
        guard let folder = folders.first else {
            files.append(file)
            files.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
            return
        }

        let childPath = path.isEmpty ? folder : "\(path)/\(folder)"
        if children[folder] == nil {
            children[folder] = MutableFileTreeNode(name: folder, path: childPath)
        }
        children[folder]?.insert(file: file, folders: Array(folders.dropFirst()))
    }

    func toImmutable() -> FileTreeNode {
        FileTreeNode(
            id: path.isEmpty ? name : path,
            name: name,
            path: path,
            files: files,
            children: children.values
                .map { $0.toImmutable() }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }
}

struct FileTreeNodeView: View {
    let node: FileTreeNode
    let depth: Int
    let activeFile: ChangedFile?
    @Binding var collapsedFolders: Set<String>
    @Binding var expandedFileIds: Set<UUID>
    let compactTree: Bool
    let impactViewModel: ImpactGraphViewModel
    let selectedImpactId: UUID?
    let badges: [UUID: ReviewFileTreeBadge]
    let onSelectFile: (ChangedFile) -> Void
    let onSelectImpact: (SymbolImpact) -> Void

    var displayedNode: FileTreeNode {
        guard compactTree else { return node }
        var current = node
        var names = [current.name]
        while current.isSingleChildDirectoryChain, let child = current.children.first {
            current = child
            names.append(current.name)
        }
        return FileTreeNode(
            id: current.id,
            name: names.joined(separator: "/"),
            path: current.path,
            files: current.files,
            children: current.children
        )
    }

    var body: some View {
        let node = displayedNode
        let isCollapsed = collapsedFolders.contains(node.id)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isCollapsed {
                    collapsedFolders.remove(node.id)
                } else {
                    collapsedFolders.insert(node.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 10)

                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Text(node.name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    if let aggImpact = node.aggregateImpact(badges: badges) {
                        ReviewImpactBadge(badge: aggImpact)
                    } else {
                        Text("\(node.fileCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }
                }
                .padding(.leading, CGFloat(min(depth, 4)) * 12 + 8)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .overlay(alignment: .leading) {
                    let color = node.aggregateImpact(badges: badges)?.color ?? .clear
                    Rectangle()
                        .fill(color)
                        .frame(width: 3)
                }
            }
            .buttonStyle(.plain)
            .help(node.path)

            if !isCollapsed {
                ForEach(node.files) { file in
                    FileListItem(
                        file: file,
                        isActive: activeFile?.id == file.id,
                        depth: depth + 1,
                        impactViewModel: impactViewModel,
                        selectedImpactId: selectedImpactId,
                        badge: badges[file.id],
                        expandedFileIds: $expandedFileIds,
                        onSelectFile: onSelectFile,
                        onSelectImpact: onSelectImpact
                    )
                }

                ForEach(node.children) { child in
                    FileTreeNodeView(
                        node: child,
                        depth: depth + 1,
                        activeFile: activeFile,
                        collapsedFolders: $collapsedFolders,
                        expandedFileIds: $expandedFileIds,
                        compactTree: compactTree,
                        impactViewModel: impactViewModel,
                        selectedImpactId: selectedImpactId,
                        badges: badges,
                        onSelectFile: onSelectFile,
                        onSelectImpact: onSelectImpact
                    )
                }
            }
        }
    }
}

struct FileListItem: View {
    @Environment(AnalysisViewModel.self) private var viewModel
    let file: ChangedFile
    let isActive: Bool
    var depth: Int = 0
    let impactViewModel: ImpactGraphViewModel
    let selectedImpactId: UUID?
    let badge: ReviewFileTreeBadge?
    @Binding var expandedFileIds: Set<UUID>
    let onSelectFile: (ChangedFile) -> Void
    let onSelectImpact: (SymbolImpact) -> Void

    var fileTargets: [ReviewTarget] {
        viewModel.bucketTargets.filter { $0.filePath == file.path }
    }

    var topTargetSeverity: Severity? {
        fileTargets.map(\.severity).max()
    }

    var fileImpacts: [SymbolImpact] {
        impactViewModel.visibleImpacts(for: file)
    }

    var heatmapColor: Color {
        badge?.color ?? .clear
    }

    var statusColor: Color {
        switch file.status {
        case .added: .success
        case .deleted: .danger
        case .modified: .textSecondary
        case .renamed: .warning
        }
    }

    var statusBadge: String {
        switch file.status {
        case .added: "A"
        case .deleted: "D"
        case .modified: "M"
        case .renamed: "R"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // Expanded Chevron
                if !fileImpacts.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if expandedFileIds.contains(file.id) {
                                expandedFileIds.remove(file.id)
                            } else {
                                expandedFileIds.insert(file.id)
                            }
                        }
                    } label: {
                        Image(
                            systemName: expandedFileIds.contains(file.id)
                                ? "chevron.down" : "chevron.right"
                        )
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }

                Text(statusBadge)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(statusColor)
                    .frame(width: 16)

                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .brandAccent : .textTertiary)

                Text(file.filename)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isActive ? .textPrimary : .textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let badge {
                    ReviewImpactBadge(badge: badge)
                }
            }
            .padding(.leading, CGFloat(min(depth, 4)) * 12 + 10)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(isActive ? Color.brandAccent.opacity(0.08) : Color.clear)
            .overlay(alignment: .leading) {
                let barColor = isActive && heatmapColor == .clear ? Color.brandAccent : heatmapColor
                Rectangle()
                    .fill(barColor)
                    .frame(width: 3)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectFile(file)
            }
            .help(fileHelpText)

            if expandedFileIds.contains(file.id) {
                ForEach(fileImpacts) { impact in
                    SymbolListItemRow(
                        impact: impact,
                        depth: depth + 1,
                        isSelected: selectedImpactId == impact.id,
                        onTap: { onSelectImpact(impact) }
                    )
                }
            }
        }
    }

    var targetColor: Color {
        switch topTargetSeverity {
        case .high: .danger
        case .medium: .warning
        case .low: .info
        case .info, nil: .textTertiary
        }
    }

    var fileHelpText: String {
        guard let firstTarget = fileTargets.first else { return file.path }
        let severity = firstTarget.severity.rawValue.capitalized
        let extraCount = fileTargets.count - 1
        if extraCount > 0 {
            return
                "\(file.path)\nNeeds attention: \(severity) - \(firstTarget.title) (+\(extraCount) more)"
        }
        return "\(file.path)\nNeeds attention: \(severity) - \(firstTarget.title)"
    }
}

struct SymbolListItemRow: View {
    let impact: SymbolImpact
    let depth: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 12)  // Alignment with chevron

            Image(systemName: iconName)
                .font(.system(size: 10))
                .foregroundColor(isSelected ? impact.summary.impactLevel.tintColor : iconColor)

            Text(impact.symbol.name)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isSelected ? .textPrimary : .textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(impact.summary.impactLevel.displayName)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(levelColor(impact.summary.impactLevel))
                .padding(.horizontal, 4)
                .padding(.vertical, 0.5)
                .background(levelColor(impact.summary.impactLevel).opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(.leading, CGFloat(min(depth, 5)) * 12 + 10)
        .padding(.trailing, 8)
        .padding(.vertical, 3.5)
        .background(isSelected ? impact.summary.impactLevel.tintColor.opacity(0.10) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? impact.summary.impactLevel.tintColor : Color.clear)
                .frame(width: 3)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var iconName: String {
        switch impact.symbol.kind {
        case .function, .method:
            return "f.circle.fill"
        case .class:
            return "c.circle.fill"
        case .struct, .enum, .type, .protocol:
            return "s.circle.fill"
        default:
            return "square.stack.3d.down.right.fill"
        }
    }

    private var iconColor: Color {
        switch impact.symbol.kind {
        case .function, .method:
            return .brandAccent
        case .class, .struct, .type, .protocol, .enum:
            return .warning
        default:
            return .textTertiary
        }
    }

    private func levelColor(_ level: ImpactLevel) -> Color {
        switch level {
        case .high: return .danger
        case .medium: return .warning
        case .low: return .success
        }
    }
}

extension ReviewFileTreeBadge {
    var color: Color {
        switch severity {
        case .high: .danger
        case .medium: .warning
        case .low: .textSecondary
        }
    }
}

struct ReviewImpactBadge: View {
    let badge: ReviewFileTreeBadge

    var body: some View {
        Text("\(badge.count)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(badge.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(badge.color.opacity(0.10))
            .clipShape(Capsule())
            .help(badge.helpText)
    }
}

// MARK: - Diff Content

struct DiffContent: View {
    @Environment(AppState.self) private var state
    @Environment(AnalysisViewModel.self) private var viewModel
    let file: ChangedFile
    let details: AnalysisDetails
    let impactViewModel: ImpactGraphViewModel
    let impactFilter: ReviewImpactFilter
    let selectedMarkerId: UUID?
    let expandedImpactIds: Set<UUID>
    let activeHunkIndex: Int?
    let activeTarget: ReviewTarget?
    let onCopyFile: () -> Void
    let onOpenImpact: (SymbolImpact) -> Void
    let onToggleImpactExpansion: (SymbolImpact) -> Void

    var fileImpacts: [SymbolImpact] {
        let all = impactViewModel.visibleImpacts(for: file)
        if impactFilter == .high {
            return all.filter { $0.summary.impactLevel == .high }
        } else if impactFilter == .medium {
            return all.filter {
                $0.summary.impactLevel == .high || $0.summary.impactLevel == .medium
            }
        }
        return all
    }

    var activeImpactRange: ClosedRange<Int>? {
        guard let context = impactViewModel.selectedSourceContext,
            context.isChangedInCurrentPR,
            context.filePath == file.path
        else { return nil }
        return context.startLine...max(context.startLine, context.endLine)
    }

    private func hunkImpacts(_ hunk: DiffHunk) -> [SymbolImpact] {
        let all = impactViewModel.impacts(for: hunk, fileId: file.id)
        if impactFilter == .high {
            return all.filter { $0.summary.impactLevel == .high }
        } else if impactFilter == .medium {
            return all.filter {
                $0.summary.impactLevel == .high || $0.summary.impactLevel == .medium
            }
        }
        return all
    }

    private func hunkMarkers(_ hunk: DiffHunk, index: Int) -> [InlineImpactMarker] {
        let all = impactViewModel.inlineMarkers(for: hunk, file: file, hunkIndex: index)
        if impactFilter == .high {
            return all.filter { $0.metrics.impactLevel == .high }
        } else if impactFilter == .medium {
            return all.filter {
                $0.metrics.impactLevel == .high || $0.metrics.impactLevel == .medium
            }
        }
        return all
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // File path bar
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Text(file.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text("+\(file.additions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.success)
                        Text("−\(file.deletions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.danger)

                        Divider()
                            .frame(height: 12)
                            .padding(.horizontal, 4)

                        // Diff Layout Selector
                        Menu {
                            Button {
                                state.diffLayout = .unified
                            } label: {
                                if state.diffLayout == .unified {
                                    Text("✓ Unified")
                                } else {
                                    Text("Unified")
                                }
                            }
                            Button {
                                state.diffLayout = .split
                            } label: {
                                if state.diffLayout == .split {
                                    Text("✓ Split")
                                } else {
                                    Text("Split")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(
                                    systemName: state.diffLayout == .unified
                                        ? "doc.text" : "square.split.2x1"
                                )
                                .font(.system(size: 11, weight: .semibold))
                                Text(state.diffLayout == .unified ? "Unified" : "Split")
                                    .font(.system(size: 11, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.textTertiary)
                            }
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(NSColor.controlColor).opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.borderMuted, lineWidth: 0.5)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .help("Change diff layout")

                        DiffToolbarButton(
                            systemImage: "doc.on.doc",
                            help: "Copy file context"
                        ) {
                            onCopyFile()
                        }

                        DiffToolbarButton(
                            systemImage: "point.3.connected.trianglepath.dotted",
                            isActive: viewModel.isImpactInspectorVisible,
                            help: viewModel.isImpactInspectorVisible
                                ? "Hide Impact" : "Show Impact"
                        ) {
                            viewModel.isImpactInspectorVisible.toggle()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.bgSubtle)
                    .sticky()

                    Divider()

                    if !fileImpacts.isEmpty {
                        FileImpactSummary(file: file, impacts: fileImpacts)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                            .background(Color.bgCanvas)
                    }

                    // Hunks
                    ForEach(Array(file.hunks.enumerated()), id: \.offset) { idx, hunk in
                        HunkView(
                            hunk: hunk,
                            hunkIndex: idx,
                            file: file,
                            impacts: hunkImpacts(hunk),
                            markers: hunkMarkers(hunk, index: idx),
                            impactViewModel: impactViewModel,
                            selectedMarkerId: selectedMarkerId,
                            expandedImpactIds: expandedImpactIds,
                            isHighlighted: activeHunkIndex == idx,
                            activeTarget: activeTarget,
                            activeImpactRange: activeImpactRange,
                            onOpenImpact: onOpenImpact,
                            onToggleImpactExpansion: onToggleImpactExpansion
                        )
                        .id("hunk-\(file.id)-\(idx)")
                    }

                    if file.hunks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 24))
                                .foregroundColor(.textTertiary)
                            Text("No diff hunks available")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                }
            }
            .onChange(of: activeHunkIndex) { _, newIdx in
                if let idx = newIdx {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("hunk-\(file.id)-\(idx)", anchor: .center)
                    }
                }
            }
            .onChange(of: file.id) { _, _ in
                proxy.scrollTo("hunk-\(file.id)-0", anchor: .top)
            }
        }
        .background(Color.bgCanvas)
    }
}

struct FileImpactSummary: View {
    let file: ChangedFile
    let impacts: [SymbolImpact]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Impact Summary")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
            Text(
                "\(impacts.count) changed symbol\(impacts.count == 1 ? "" : "s") in \(file.filename), led by \(topNames)."
            )
            .font(.system(size: 12))
            .foregroundColor(.textSecondary)
            .lineLimit(2)
            Spacer()
        }
    }

    private var topNames: String {
        impacts.prefix(3).map(\.symbol.name).joined(separator: ", ")
    }
}

struct InlineImpactSummaryCard: View {
    let impact: SymbolImpact
    let marker: InlineImpactMarker?
    let impactViewModel: ImpactGraphViewModel?
    let isSelected: Bool
    let isExpanded: Bool
    let onOpenImpact: (SymbolImpact) -> Void
    let onToggleExpanded: (SymbolImpact) -> Void

    var body: some View {
        HStack(alignment: isExpanded ? .top : .center, spacing: 10) {
            Rectangle()
                .fill(impact.summary.impactLevel.tintColor)
                .frame(width: impact.summary.impactLevel == .high ? 3 : 2)
                .clipShape(Capsule())

            if isExpanded {
                expandedContent
            } else {
                compactContent
            }
        }
        .padding(.horizontal, isExpanded ? 9 : 7)
        .padding(.vertical, isExpanded ? 8 : 4)
        .background(Color(NSColor.controlColor).opacity(isExpanded ? 0.28 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected
                        ? impact.summary.impactLevel.tintColor.opacity(0.55) : Color.borderMuted,
                    lineWidth: isSelected ? 1 : 0.5)
        )
    }

    private var compactContent: some View {
        Button {
            onOpenImpact(impact)
        } label: {
            HStack(spacing: 6) {
                CompactImpactChip(
                    text: "\(impact.summary.impactLevel.displayName) impact",
                    color: impact.summary.impactLevel.tintColor,
                    isProminent: impact.summary.impactLevel == .high)
                if impact.summary.directCallerCount > 0 {
                    CompactImpactChip(
                        text: "\(impact.summary.directCallerCount) callers",
                        color: .textSecondary)
                }
                if impact.summary.fileCount > 1 {
                    CompactImpactChip(
                        text: "\(impact.summary.fileCount) files",
                        color: .textSecondary)
                }
                if impact.summary.testReferenceCount == 0 && impact.hasImpactData {
                    CompactImpactChip(text: "No tests", color: .warning)
                }
                Spacer(minLength: 8)
                Button {
                    onToggleExpanded(impact)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Expand inline impact detail")
            }
        }
        .buttonStyle(.plain)
        .help(expandedHelp)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                BadgeView(
                    text: "\(impact.summary.impactLevel.displayName) impact",
                    variant: impact.summary.impactLevel.badgeVariant)
                Text(impact.symbol.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    onOpenImpact(impact)
                } label: {
                    Label("Open", systemImage: "sidebar.right")
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundColor(.brandAccent)
                Button {
                    onToggleExpanded(impact)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Collapse inline impact detail")
            }

            if let reason = meaningfulReason {
                Text("Reason: \(reason)")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }

            Text("Impact: \(metricsText)")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)

            if !mostAffected.isEmpty {
                Text("Most affected: \(mostAffected)")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    init(
        impact: SymbolImpact, marker: InlineImpactMarker? = nil,
        impactViewModel: ImpactGraphViewModel? = nil, isSelected: Bool = false,
        isExpanded: Bool = false,
        onOpenImpact: @escaping (SymbolImpact) -> Void = { _ in },
        onToggleExpanded: @escaping (SymbolImpact) -> Void = { _ in }
    ) {
        self.impact = impact
        self.marker = marker
        self.impactViewModel = impactViewModel
        self.isSelected = isSelected
        self.isExpanded = isExpanded
        self.onOpenImpact = onOpenImpact
        self.onToggleExpanded = onToggleExpanded
    }

    private var meaningfulReason: String? {
        guard let reason = impact.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
            !reason.isEmpty
        else { return nil }
        return reason
    }

    private var reasonOrOwnership: String {
        meaningfulReason ?? "\(impact.symbol.kind.rawValue.capitalized) changed"
    }

    private var metricsText: String {
        "\(impact.summary.directCallerCount) callers · \(impact.summary.directCalleeCount) callees · \(impact.summary.fileCount) files"
    }

    private var mostAffected: String {
        impact.symbol.callers.prefix(3).map { caller in
            caller.components(separatedBy: ":").last ?? caller
        }
        .joined(separator: ", ")
    }

    private var expandedHelp: String {
        [
            reasonOrOwnership,
            metricsText,
            mostAffected.isEmpty ? nil : "Most affected: \(mostAffected)",
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

struct CompactImpactChip: View {
    let text: String
    let color: Color
    var isProminent = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: isProminent ? .bold : .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(isProminent ? 0.14 : 0.08))
            .clipShape(Capsule())
    }
}

struct ImpactExplorerSidebar: View {
    @Bindable var reviewViewModel: ReviewModeViewModel
    @Bindable var impactViewModel: ImpactGraphViewModel
    let details: AnalysisDetails
    let onClose: () -> Void
    let onOpenImpact: (SymbolImpact) -> Void
    let onOpenNode: (ImpactGraphNode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        impactViewModel.focusedNode?.title ?? impactViewModel.originImpact?.symbol
                            .name ?? "Impact"
                    )
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    Text(headerSubtitle)
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Navigation history buttons
                HStack(spacing: 3) {
                    Button(action: { impactViewModel.focusBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .disabled(!impactViewModel.canGoBack)
                    .buttonStyle(.plain)
                    .foregroundColor(
                        impactViewModel.canGoBack ? .textSecondary : .textTertiary.opacity(0.4)
                    )
                    .frame(width: 18, height: 18)
                    .background(Color.bgSidebarPanel.opacity(impactViewModel.canGoBack ? 1.0 : 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3).stroke(Color.borderMuted, lineWidth: 0.5)
                    )
                    .help("Go back in history")

                    Button(action: { impactViewModel.focusForward() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .disabled(!impactViewModel.canGoForward)
                    .buttonStyle(.plain)
                    .foregroundColor(
                        impactViewModel.canGoForward ? .textSecondary : .textTertiary.opacity(0.4)
                    )
                    .frame(width: 18, height: 18)
                    .background(
                        Color.bgSidebarPanel.opacity(impactViewModel.canGoForward ? 1.0 : 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3).stroke(Color.borderMuted, lineWidth: 0.5)
                    )
                    .help("Go forward in history")

                    Button(action: { impactViewModel.focusOrigin() }) {
                        Image(systemName: "house")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(Color.bgSidebarPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3).stroke(Color.borderMuted, lineWidth: 0.5)
                    )
                    .help("Reset to Origin")
                }
                .padding(.trailing, 4)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.textSecondary)
                .help("Collapse Impact")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.bgSubtle)

            Divider()

            if impactViewModel.reviewQueue.isEmpty {
                ImpactExplorerEmptyState()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ImpactExplorerRootCard(
                            impact: impactViewModel.originImpact ?? impactViewModel.reviewQueue[0],
                            viewModel: impactViewModel,
                            reviewViewModel: reviewViewModel,
                            onOpenRoot: {
                                if let impact = impactViewModel.originImpact {
                                    onOpenImpact(impact)
                                }
                            }
                        )

                        ImpactRelationshipSections(
                            viewModel: impactViewModel,
                            onOpenNode: onOpenNode
                        )

                        Divider()
                            .opacity(0.6)
                    }
                    .padding(12)
                }
                .background(Color.bgCanvas)
            }
        }
        .background(Color.bgCanvas)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.borderMuted)
                .frame(width: 1)
        }
    }

    private var headerSubtitle: String {
        guard let node = impactViewModel.focusedNode else {
            let count = impactViewModel.reviewQueue.count
            return "\(count) impacted changed symbol\(count == 1 ? "" : "s")"
        }
        let filename = (node.filePath as NSString).lastPathComponent
        let callersCount = impactViewModel.visibleGraphNodes.filter { $0.role == .caller }.count
        let calleesCount = impactViewModel.visibleGraphNodes.filter { $0.role == .callee }.count
        return "\(filename) • \(callersCount) callers, \(calleesCount) callees"
    }
}

struct ImpactExplorerEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 24))
                .foregroundColor(.textTertiary)
            Text("No impact graph available")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("Changed symbols were found, but no caller or callee relationships were detected.")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
    }
}

struct ImpactExplorerRootCard: View {
    let impact: SymbolImpact
    @Bindable var viewModel: ImpactGraphViewModel
    @Bindable var reviewViewModel: ReviewModeViewModel
    let onOpenRoot: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Visual accent bar
            Rectangle()
                .fill(impact.summary.impactLevel.tintColor)
                .frame(width: 4)
                .clipShape(Capsule())
                .padding(.vertical, 8)
                .padding(.leading, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Changed Root")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)

                HStack(spacing: 7) {
                    BadgeView(
                        text: "\(impact.summary.impactLevel.displayName) impact",
                        variant: impact.summary.impactLevel.badgeVariant)
                    Text(impact.symbol.name)
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.top, 2)

                Text(impact.location)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("Why This Matters")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                    .padding(.top, 2)

                Text(
                    impact.reason
                        ?? "Review caller and callee relationships for this changed symbol."
                )
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

                // Stats strip
                HStack(spacing: 12) {
                    Label(
                        "\(impact.summary.directCallerCount) callers",
                        systemImage: "arrow.down.left")
                    Label(
                        "\(impact.summary.directCalleeCount) callees",
                        systemImage: "arrow.down.right")
                    Label("\(impact.summary.fileCount) files", systemImage: "doc.on.doc")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.textTertiary)
                .imageScale(.small)
                .padding(.vertical, 2)

                Divider()
                    .opacity(0.6)

                // Actions toolbar
                HStack(spacing: 6) {
                    Button(action: onOpenRoot) {
                        Label("Open Root", systemImage: "target")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        reviewViewModel.copyImpactContext(impact)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(Color.bgSidebarPanel.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderMuted, lineWidth: 0.5)
        )
    }
}

struct ImpactRelationshipSections: View {
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenNode: (ImpactGraphNode) -> Void

    var callers: [ImpactGraphNode] {
        viewModel.visibleGraphNodes.filter { $0.role == .caller }
    }

    var callees: [ImpactGraphNode] {
        viewModel.visibleGraphNodes.filter { $0.role == .callee }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ImpactGraphColumn(
                title: "Callers",
                emptyText: "No changed callers detected",
                nodes: callers,
                viewModel: viewModel,
                onOpenNode: onOpenNode
            )

            ImpactGraphColumn(
                title: "Callees",
                emptyText: "No changed callees detected",
                nodes: callees,
                viewModel: viewModel,
                onOpenNode: onOpenNode
            )

            HStack {
                Spacer()
                Picker("Direction", selection: $viewModel.graphDirection) {
                    ForEach(ImpactGraphDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .labelsHidden()
                .frame(width: 96)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.bgSidebarPanel.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5)
        )
    }
}

struct ImpactGraphMap: View {
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenNode: (ImpactGraphNode) -> Void

    var callers: [ImpactGraphNode] {
        viewModel.visibleGraphNodes.filter { $0.role == .caller }
    }

    var callees: [ImpactGraphNode] {
        viewModel.visibleGraphNodes.filter { $0.role == .callee }
    }

    var origin: ImpactGraphNode? {
        viewModel.visibleGraphNodes.first { $0.role == .origin }
    }

    var body: some View {
        VStack(spacing: 6) {
            ImpactGraphColumn(
                title: "Callers",
                emptyText: "No callers detected",
                nodes: callers,
                viewModel: viewModel,
                onOpenNode: onOpenNode
            )

            if let origin {
                HStack {
                    Spacer()
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary.opacity(0.6))
                    Spacer()
                }
                .padding(.vertical, 2)

                ImpactExplorerNodeCard(
                    node: origin,
                    isFocused: origin.id == viewModel.currentFocusedNodeId,
                    isSelected: origin.id == viewModel.selectedGraphNode?.id,
                    viewModel: viewModel,
                    onOpenNode: onOpenNode
                )
            }

            if !callees.isEmpty {
                HStack {
                    Spacer()
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary.opacity(0.6))
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            ImpactGraphColumn(
                title: "Callees",
                emptyText: "No callees detected",
                nodes: callees,
                viewModel: viewModel,
                onOpenNode: onOpenNode
            )
        }
        .padding(8)
        .background(Color.bgSidebarPanel.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5)
        )
    }
}

struct GroupedFileNodes: Identifiable {
    let id: String  // filePath
    let filePath: String
    var filename: String {
        (filePath as NSString).lastPathComponent
    }
    var isTest: Bool {
        nodes.first?.isTest ?? false
    }
    let nodes: [ImpactGraphNode]
}

struct ImpactGraphColumn: View {
    let title: String
    let emptyText: String
    let nodes: [ImpactGraphNode]
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenNode: (ImpactGraphNode) -> Void

    @State private var collapsedFiles: Set<String> = []

    var groupedFiles: [GroupedFileNodes] {
        let dict = Dictionary(grouping: nodes, by: \.filePath)
        return dict.map { GroupedFileNodes(id: $0.key, filePath: $0.key, nodes: $0.value) }
            .sorted { lhs, rhs in
                if lhs.isTest != rhs.isTest {
                    return !lhs.isTest  // non-tests first
                }
                return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename)
                    == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 2)

            if nodes.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.bgSidebarPanel.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                VStack(spacing: 8) {
                    ForEach(groupedFiles) { group in
                        let isCollapsed = collapsedFiles.contains(group.filePath)

                        VStack(alignment: .leading, spacing: 4) {
                            // File Group Header Button
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if isCollapsed {
                                        collapsedFiles.remove(group.filePath)
                                    } else {
                                        collapsedFiles.insert(group.filePath)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.textTertiary)
                                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))

                                    Image(systemName: group.isTest ? "flask" : "doc.text")
                                        .font(.system(size: 10))
                                        .foregroundColor(
                                            group.isTest ? .textTertiary : .brandAccent)

                                    Text(group.filename)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()

                                    // Count Badge
                                    Text("\(group.nodes.count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.textSecondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.bgSidebarPanel)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule().stroke(Color.borderMuted, lineWidth: 0.5))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // File Group Node Rows (if expanded)
                            if !isCollapsed {
                                VStack(spacing: 2) {
                                    ForEach(group.nodes) { node in
                                        ImpactExplorerCompactNodeRow(
                                            node: node,
                                            isFocused: node.id == viewModel.currentFocusedNodeId,
                                            isSelected: node.id == viewModel.selectedGraphNode?.id,
                                            viewModel: viewModel,
                                            onOpenNode: onOpenNode
                                        )
                                    }
                                }
                                .padding(.leading, 12)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ImpactExplorerCompactNodeRow: View {
    let node: ImpactGraphNode
    let isFocused: Bool
    let isSelected: Bool
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenNode: (ImpactGraphNode) -> Void

    var body: some View {
        Button {
            viewModel.selectGraphNode(node)
            viewModel.focusSelectedGraphNode()
            onOpenNode(node)
        } label: {
            HStack(spacing: 6) {
                // Bullet / role icon
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(
                        isFocused ? .white : (node.isTest ? .textTertiary : .brandAccent)
                    )
                    .frame(width: 10)

                Text(node.title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isFocused ? .white : .textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    if node.isChangedInPR {
                        Text("PR")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(isFocused ? .white : .success)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 0.5)
                            .background(
                                isFocused ? Color.white.opacity(0.2) : Color.success.opacity(0.12)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    } else {
                        Text("Outside scope")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(isFocused ? .white.opacity(0.85) : .textTertiary)
                    }

                    if let line = node.line {
                        Text("L\(line)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(isFocused ? .white.opacity(0.8) : .textTertiary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background(
                isFocused
                    ? Color.brandAccent
                    : (isSelected ? Color.brandAccent.opacity(0.08) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4).stroke(
                    isSelected ? Color.brandAccent.opacity(0.4) : Color.clear,
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .help("\(node.filePath)\(node.line.map { ":L\($0)" } ?? "")")
    }

    private var iconName: String {
        if node.isTest { return "flask" }
        return switch node.role {
        case .origin: "dot.circle"
        case .caller: "arrow.down.left"
        case .callee: "arrow.down.right"
        }
    }
}

struct ImpactExplorerNodeCard: View {
    let node: ImpactGraphNode
    let isFocused: Bool
    let isSelected: Bool
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenNode: (ImpactGraphNode) -> Void

    var filename: String {
        (node.filePath as NSString).lastPathComponent
    }

    var body: some View {
        Button {
            viewModel.selectGraphNode(node)
            viewModel.focusSelectedGraphNode()
            onOpenNode(node)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isFocused ? .white : .brandAccent)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(node.title)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(isFocused ? .white : .textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if node.isChangedInPR {
                            Text("PR")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(isFocused ? .white : .success)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 0.5)
                                .background(
                                    isFocused
                                        ? Color.white.opacity(0.2) : Color.success.opacity(0.12)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        } else {
                            Text("Outside scope")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(isFocused ? .white.opacity(0.85) : .textTertiary)
                        }
                    }

                    Text("\(filename)\(node.line.map { ":L\($0)" } ?? "")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(isFocused ? .white.opacity(0.8) : .textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isFocused ? Color.brandAccent : Color.bgSidebarPanel.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(
                    isSelected ? Color.brandAccent.opacity(0.85) : Color.borderMuted,
                    lineWidth: isSelected ? 1.0 : 0.5))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .help("\(node.filePath)\(node.line.map { ":L\($0)" } ?? "")")
    }

    private var iconName: String {
        if node.isTest { return "flask.fill" }
        return switch node.role {
        case .origin: "dot.circle.fill"
        case .caller: "arrow.down.left"
        case .callee: "arrow.down.right"
        }
    }
}

extension ImpactLevel {
    var tintColor: Color {
        switch self {
        case .low: .success
        case .medium: .warning
        case .high: .danger
        }
    }
}

// MARK: - Hunk View

struct AlignedDiffLine: Identifiable {
    let id = UUID()
    let oldLine: NumberedDiffLine?
    let newLine: NumberedDiffLine?
}

struct HunkView: View {
    @Environment(AppState.self) private var state
    @Environment(AnalysisViewModel.self) private var viewModel
    let hunk: DiffHunk
    let hunkIndex: Int
    let file: ChangedFile
    let impacts: [SymbolImpact]
    let markers: [InlineImpactMarker]
    let impactViewModel: ImpactGraphViewModel
    let selectedMarkerId: UUID?
    let expandedImpactIds: Set<UUID>
    let isHighlighted: Bool
    let activeTarget: ReviewTarget?
    let activeImpactRange: ClosedRange<Int>?
    let onOpenImpact: (SymbolImpact) -> Void
    let onToggleImpactExpansion: (SymbolImpact) -> Void
    @State private var isCollapsed = false

    var diffLines: [NumberedDiffLine] {
        var oldLine = hunk.oldStart
        var newLine = hunk.newStart

        return hunk.lines.map { rawLine in
            let type = NumberedDiffLine.LineType(rawLine: rawLine)
            let numbered = NumberedDiffLine(
                rawLine: rawLine,
                oldLineNumber: type.showsOldLine ? oldLine : nil,
                newLineNumber: type.showsNewLine ? newLine : nil,
                type: type
            )

            if type.advancesOldLine { oldLine += 1 }
            if type.advancesNewLine { newLine += 1 }

            return numbered
        }
    }

    var alignedDiffLines: [AlignedDiffLine] {
        var aligned: [AlignedDiffLine] = []

        var pendingDeletions: [NumberedDiffLine] = []
        var pendingAdditions: [NumberedDiffLine] = []

        func flushPending() {
            let maxCount = max(pendingDeletions.count, pendingAdditions.count)
            for i in 0..<maxCount {
                let old = i < pendingDeletions.count ? pendingDeletions[i] : nil
                let new = i < pendingAdditions.count ? pendingAdditions[i] : nil
                aligned.append(AlignedDiffLine(oldLine: old, newLine: new))
            }
            pendingDeletions.removeAll()
            pendingAdditions.removeAll()
        }

        for line in diffLines {
            switch line.type {
            case .context:
                flushPending()
                aligned.append(AlignedDiffLine(oldLine: line, newLine: line))
            case .deleted:
                pendingDeletions.append(line)
            case .added:
                pendingAdditions.append(line)
            case .metadata:
                flushPending()
                aligned.append(AlignedDiffLine(oldLine: line, newLine: line))
            }
        }
        flushPending()

        return aligned
    }

    var unifiedLineNumbers: AttributedString {
        var result = AttributedString()
        for line in diffLines {
            result.append(
                lineNumberText(
                    line.oldLineNumber.map(String.init) ?? "", isTargeted: isTargeted(line)))
        }
        return result
    }

    var unifiedNewLineNumbers: AttributedString {
        var result = AttributedString()
        for line in diffLines {
            result.append(
                lineNumberText(
                    line.newLineNumber.map(String.init) ?? "", isTargeted: isTargeted(line)))
        }
        return result
    }

    var unifiedPrefixes: AttributedString {
        var result = AttributedString()
        for line in diffLines {
            let char: String
            let color: Color
            switch line.type {
            case .added:
                char = "+"
                color = Color.diffAddedFg
            case .deleted:
                char = "−"
                color = Color.danger
            case .context:
                char = " "
                color = Color.textTertiary
            case .metadata:
                char = "\\"
                color = Color.textTertiary
            }
            var attr = AttributedString(char + "\n")
            attr.foregroundColor = color
            if isTargeted(line) {
                attr.backgroundColor = Color.warning.opacity(0.22)
            }
            result.append(attr)
        }
        return result
    }

    var unifiedCode: AttributedString {
        var result = AttributedString()
        for line in diffLines {
            let lineContent = line.rawLine.isEmpty ? "" : String(line.rawLine.dropFirst())
            var attr = AttributedString(lineContent + "\n")

            switch line.type {
            case .added:
                attr.foregroundColor = Color.textPrimary
                attr.backgroundColor = Color.diffAddedBg
            case .deleted:
                attr.foregroundColor = Color.textPrimary
                attr.backgroundColor = Color.diffDeletedBg
            case .context:
                attr.foregroundColor = Color.textPrimary.opacity(0.75)
            case .metadata:
                attr.foregroundColor = Color.textTertiary
            }
            if isTargeted(line) {
                attr.foregroundColor = Color.textPrimary
                attr.backgroundColor = Color.warning.opacity(0.28)
            }
            result.append(attr)
        }
        return result
    }

    func splitLineNumbers(isLeft: Bool) -> AttributedString {
        var result = AttributedString()
        for alignedLine in alignedDiffLines {
            let line = isLeft ? alignedLine.oldLine : alignedLine.newLine
            let isTargeted = line.map { self.isTargeted($0) } ?? false
            if let line {
                let num = isLeft ? line.oldLineNumber : line.newLineNumber
                result.append(lineNumberText(num.map(String.init) ?? "", isTargeted: isTargeted))
            } else {
                result.append(lineNumberText("", isTargeted: false))
            }
        }
        return result
    }

    func splitPrefixes(isLeft: Bool) -> AttributedString {
        var result = AttributedString()
        for alignedLine in alignedDiffLines {
            let line = isLeft ? alignedLine.oldLine : alignedLine.newLine
            if let line {
                let char: String
                let color: Color
                switch line.type {
                case .added:
                    char = "+"
                    color = Color.diffAddedFg
                case .deleted:
                    char = "−"
                    color = Color.diffDeletedFg
                case .context:
                    char = " "
                    color = Color.textTertiary
                case .metadata:
                    char = "\\"
                    color = Color.textTertiary
                }
                var attr = AttributedString(char + "\n")
                attr.foregroundColor = color
                if isTargeted(line) {
                    attr.backgroundColor = Color.warning.opacity(0.22)
                }
                result.append(attr)
            } else {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    func splitCode(isLeft: Bool) -> AttributedString {
        var result = AttributedString()
        for alignedLine in alignedDiffLines {
            let line = isLeft ? alignedLine.oldLine : alignedLine.newLine
            if let line {
                let lineContent = line.rawLine.isEmpty ? "" : String(line.rawLine.dropFirst())
                var attr = AttributedString(lineContent + "\n")

                switch line.type {
                case .added:
                    attr.foregroundColor = Color.textPrimary
                    attr.backgroundColor = Color.diffAddedBg
                case .deleted:
                    attr.foregroundColor = Color.textPrimary
                    attr.backgroundColor = Color.diffDeletedBg
                case .context:
                    attr.foregroundColor = Color.textPrimary.opacity(0.75)
                case .metadata:
                    attr.foregroundColor = Color.textTertiary
                }
                if isTargeted(line) {
                    attr.foregroundColor = Color.textPrimary
                    attr.backgroundColor = Color.warning.opacity(0.28)
                }
                result.append(attr)
            } else {
                var attr = AttributedString(" \n")
                attr.backgroundColor = Color.bgSubtle.opacity(0.15)
                result.append(attr)
            }
        }
        return result
    }

    private func isTargeted(_ line: NumberedDiffLine) -> Bool {
        guard let newLineNumber = line.newLineNumber else { return false }
        if let activeTarget,
            let start = activeTarget.lineStart
        {
            let end = activeTarget.lineEnd ?? start
            if newLineNumber >= start && newLineNumber <= end { return true }
        }
        if let activeImpactRange, activeImpactRange.contains(newLineNumber) {
            return true
        }
        return false
    }

    private func lineNumberText(_ text: String, isTargeted: Bool) -> AttributedString {
        var attr = AttributedString(text + "\n")
        attr.foregroundColor = isTargeted ? Color.warning : Color.textTertiary
        if isTargeted {
            attr.backgroundColor = Color.warning.opacity(0.22)
        }
        return attr
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hunk header with expand controls in the gutter
            HStack(spacing: 0) {
                HStack(spacing: 3) {
                    Button {
                        Task {
                            await viewModel.expandHunk(
                                fileId: file.id, hunkIndex: hunkIndex, direction: .up)
                        }
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.brandAccent)
                            .frame(width: 17, height: 17)
                            .background(Color.brandAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("Expand context up (20 lines)")

                    if hunkIndex > 0 {
                        Button {
                            Task {
                                await viewModel.expandHunk(
                                    fileId: file.id, hunkIndex: hunkIndex, direction: .all)
                            }
                        } label: {
                            Image(systemName: "arrow.up.and.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.brandAccent)
                                .frame(width: 17, height: 17)
                                .background(Color.brandAccent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                        .help("Expand all context to previous hunk")
                    }

                    Button {
                        Task {
                            await viewModel.expandHunk(
                                fileId: file.id, hunkIndex: hunkIndex, direction: .down)
                        }
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.brandAccent)
                            .frame(width: 17, height: 17)
                            .background(Color.brandAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("Expand context down (20 lines)")
                }
                .frame(width: state.diffLayout == .split ? 62 : 106, alignment: .center)
                .background(Color.bgSubtle.opacity(0.85))

                Rectangle()
                    .fill(Color.borderMuted)
                    .frame(width: 1)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isCollapsed.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                        Text(
                            "@@ -\(hunk.oldStart),\(hunk.oldLines) +\(hunk.newStart),\(hunk.newLines) @@"
                        )
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.info)
                        Spacer()
                        Text("\(hunk.lines.count) lines")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.underPageBackgroundColor))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Hunk lines
            if !isCollapsed {
                if state.diffLayout == .split {
                    VStack(spacing: 0) {
                        ForEach(alignedDiffLines) { alignedLine in
                            inlineMarkerCards(for: alignedLine.newLine?.newLineNumber)
                            splitLineRow(alignedLine)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(diffLines) { line in
                            inlineMarkerCards(for: line.newLineNumber)
                            unifiedLineRow(line)
                        }
                    }
                    .background(Color.bgCanvas)
                }
            }
        }
        .overlay(alignment: .leading) {
            if isHighlighted {
                Rectangle()
                    .fill(Color.warning.opacity(0.7))
                    .frame(width: 3)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0).stroke(
                isHighlighted ? Color.warning.opacity(0.3) : Color.clear, lineWidth: 1
            ))
    }

    @ViewBuilder
    private func inlineMarkerCards(for lineNumber: Int?) -> some View {
        if let lineNumber {
            let lineMarkers = markers.filter { $0.anchorLine == lineNumber }
            if !lineMarkers.isEmpty {
                VStack(spacing: 6) {
                    ForEach(lineMarkers.prefix(3)) { marker in
                        if let impact = impacts.first(where: { $0.id == marker.rootSymbolId }) {
                            InlineImpactSummaryCard(
                                impact: impact,
                                marker: marker,
                                impactViewModel: impactViewModel,
                                isSelected: marker.rootSymbolId == selectedMarkerId,
                                isExpanded: expandedImpactIds.contains(impact.id),
                                onOpenImpact: onOpenImpact,
                                onToggleExpanded: onToggleImpactExpansion)
                        }
                    }
                }
                .padding(.leading, state.diffLayout == .split ? 72 : 118)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
                .background(Color.bgCanvas)
            }
        }
    }

    private func unifiedLineRow(_ line: NumberedDiffLine) -> some View {
        HStack(spacing: 0) {
            lineNumberColumn(
                line.oldLineNumber.map(String.init) ?? "", isTargeted: isTargeted(line)
            )
            .frame(width: 44, alignment: .trailing)
            lineNumberColumn(
                line.newLineNumber.map(String.init) ?? "", isTargeted: isTargeted(line)
            )
            .frame(width: 44, alignment: .trailing)
            prefixColumn(
                prefix(for: line), color: prefixColor(for: line), isTargeted: isTargeted(line))
            codeColumn(lineContent(for: line), line: line)
        }
        .background(Color.bgCanvas)
    }

    private func splitLineRow(_ alignedLine: AlignedDiffLine) -> some View {
        HStack(spacing: 0) {
            splitPaneLine(alignedLine.oldLine, isLeft: true)
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(Color.borderMuted)
                .frame(width: 1)
            splitPaneLine(alignedLine.newLine, isLeft: false)
                .frame(maxWidth: .infinity)
        }
        .background(Color.bgCanvas)
    }

    @ViewBuilder
    private func splitPaneLine(_ line: NumberedDiffLine?, isLeft: Bool) -> some View {
        HStack(spacing: 0) {
            if let line {
                let lineNumber = isLeft ? line.oldLineNumber : line.newLineNumber
                let targeted = isTargeted(line)
                lineNumberColumn(lineNumber.map(String.init) ?? "", isTargeted: targeted)
                    .frame(width: 44, alignment: .trailing)
                prefixColumn(prefix(for: line), color: prefixColor(for: line), isTargeted: targeted)
                codeColumn(lineContent(for: line), line: line)
            } else {
                lineNumberColumn("", isTargeted: false)
                    .frame(width: 44, alignment: .trailing)
                prefixColumn(" ", color: .textTertiary, isTargeted: false)
                Text(" ")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                    .background(Color.bgSubtle.opacity(0.15))
            }
        }
    }

    private func lineNumberColumn(_ text: String, isTargeted: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(isTargeted ? Color.warning : Color.textTertiary)
            .frame(minHeight: 17, alignment: .trailing)
            .padding(.trailing, 6)
            .background(
                isTargeted ? Color.warning.opacity(0.22) : Color.bgSubtle.opacity(0.65)
            )
            .textSelection(.disabled)
    }

    private func prefixColumn(_ text: String, color: Color, isTargeted: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(color)
            .frame(width: 18, alignment: .center)
            .frame(minHeight: 17)
            .background(
                isTargeted ? Color.warning.opacity(0.22) : Color.bgSubtle.opacity(0.65)
            )
            .textSelection(.disabled)
    }

    private func codeColumn(_ text: String, line: NumberedDiffLine) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(codeForeground(for: line))
            .lineLimit(1)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
            .background(codeBackground(for: line))
    }

    private func lineContent(for line: NumberedDiffLine) -> String {
        line.rawLine.isEmpty ? "" : String(line.rawLine.dropFirst())
    }

    private func prefix(for line: NumberedDiffLine) -> String {
        switch line.type {
        case .added: "+"
        case .deleted: "−"
        case .context: " "
        case .metadata: "\\"
        }
    }

    private func prefixColor(for line: NumberedDiffLine) -> Color {
        switch line.type {
        case .added: Color.diffAddedFg
        case .deleted: Color.danger
        case .context, .metadata: Color.textTertiary
        }
    }

    private func codeForeground(for line: NumberedDiffLine) -> Color {
        if isTargeted(line) { return Color.textPrimary }
        switch line.type {
        case .metadata:
            return Color.textTertiary
        case .context:
            return Color.textPrimary.opacity(0.75)
        case .added, .deleted:
            return Color.textPrimary
        }
    }

    private func codeBackground(for line: NumberedDiffLine) -> Color {
        if isTargeted(line) { return Color.warning.opacity(0.28) }
        switch line.type {
        case .added:
            return Color.diffAddedBg
        case .deleted:
            return Color.diffDeletedBg
        case .context, .metadata:
            return Color.clear
        }
    }
}

// MARK: - Diff Line Data Model

struct NumberedDiffLine: Identifiable {
    let id = UUID()
    enum LineType {
        case added, deleted, context, metadata

        init(rawLine: String) {
            if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                self = .added
            } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                self = .deleted
            } else if rawLine.hasPrefix("\\") {
                self = .metadata
            } else {
                self = .context
            }
        }

        var showsOldLine: Bool {
            switch self {
            case .added, .metadata: false
            case .deleted, .context: true
            }
        }

        var showsNewLine: Bool {
            switch self {
            case .deleted, .metadata: false
            case .added, .context: true
            }
        }

        var advancesOldLine: Bool { showsOldLine }
        var advancesNewLine: Bool { showsNewLine }
    }

    let rawLine: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let type: LineType
}

// MARK: - Sticky modifier (simulated via ZStack positioning)

extension View {
    func sticky() -> some View {
        self
    }
}
