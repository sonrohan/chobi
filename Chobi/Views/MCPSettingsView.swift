import SwiftUI

struct MCPSettingsView: View {
    @Bindable var viewModel: MCPSettingsViewModel
    @State private var hoveredConfiguration: MCPConfigurationTab? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            configurationSection
            Divider().padding(.horizontal, 30)
            privacySection
            Divider().padding(.horizontal, 30)
            aboutSection
            Spacer()
        }
        .padding(.top, 6)
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MCP")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.textPrimary)

            Text(
                "Connect AI tools to Chobi through a local stdio Model Context Protocol process."
            )
            .font(.system(size: 11.5))
            .foregroundColor(.textSecondary)

            Text("Choose a setup recipe")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)

            HStack(spacing: 10) {
                ForEach(MCPConfigurationTab.allCases) { tab in
                    configurationCard(tab)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(
                        viewModel.selectedConfiguration.title,
                        systemImage: viewModel.selectedConfiguration.iconName
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)

                    Spacer()

                    Button {
                        viewModel.copyConfiguration()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }

                Text(viewModel.configurationSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(viewModel.selectedConfiguration == .manual ? nil : 2)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(
                            Color.borderMuted, lineWidth: 0.5)
                    )
            }
            .padding(12)
            .background(Color.bgSidebarPanel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))

            Text(viewModel.configurationHelpText)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)

            if let copied = viewModel.copiedState {
                Text(copied)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.success)
            }

        }
        .padding(.horizontal, 30)
    }

    private func configurationCard(_ tab: MCPConfigurationTab) -> some View {
        let isSelected = viewModel.selectedConfiguration == tab
        let isHovered = hoveredConfiguration == tab

        return Button {
            viewModel.selectedConfiguration = tab
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: tab.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? .brandAccent : .textSecondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.brandAccent)
                    }
                }

                Text(tab.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Text(tab.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.brandAccent.opacity(0.10) : Color.bgSidebarPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected
                            ? Color.brandAccent.opacity(0.65)
                            : (isHovered ? Color.borderDefault : Color.borderMuted),
                        lineWidth: isSelected ? 1.2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredConfiguration = hovering ? tab : nil
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)

            Label("Read-only local context", systemImage: "checkmark.square.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textPrimary)

            Text(
                "Chobi exposes analysis summaries, review plans, changed files, symbols, call-graph impact data, and bounded file ranges. No mutation tools, network listeners, or remote calls are registered."
            )
            .font(.system(size: 11))
            .foregroundColor(.textSecondary)
            .padding(.leading, 22)
        }
        .padding(.horizontal, 30)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About MCP Integration")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
            Text(viewModel.aboutText)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 30)
    }
}
