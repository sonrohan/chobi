import AppKit
import Foundation
import Observation

enum MCPConfigurationTab: String, CaseIterable, Identifiable {
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case manual = "Manual"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .claudeCode:
            "sparkles"
        case .codex:
            "terminal"
        case .manual:
            "curlybraces.square"
        }
    }

    var title: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        case .manual:
            "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .claudeCode:
            "One terminal command"
        case .codex:
            "Register with the CLI"
        case .manual:
            "Drop-in JSON config"
        }
    }
}

@Observable
@MainActor
class MCPSettingsViewModel {
    var selectedConfiguration: MCPConfigurationTab = .claudeCode
    var copiedState: String?

    private let appExecutablePath = "/Applications/Chobi.app/Contents/MacOS/Chobi"

    init(state _: AppState) {}

    var configurationSnippet: String {
        switch selectedConfiguration {
        case .claudeCode:
            """
            claude mcp add chobi --transport stdio -- "\(appExecutablePath)" "--mcp-server"
            """
        case .codex:
            """
            codex mcp add chobi -- "\(appExecutablePath)" "--mcp-server"
            """
        case .manual:
            """
            {
              "mcpServers": {
                "chobi": {
                  "command": "\(appExecutablePath)",
                  "args": ["--mcp-server"],
                  "env": {}
                }
              }
            }
            """
        }
    }

    var configurationHelpText: String {
        switch selectedConfiguration {
        case .claudeCode:
            "Run this command in Terminal to add Chobi MCP to Claude Code."
        case .codex:
            "Run this command in Terminal to add Chobi MCP to Codex."
        case .manual:
            "Add this JSON to your AI tool's MCP configuration file."
        }
    }

    var aboutText: String {
        "MCP lets AI coding tools query Chobi's local analysis context through a stdio process. Agents can list workspaces, get analysis summaries, list and explain changed files and symbols, explore call-graph impact, retrieve the ordered review plan, and read bounded file ranges. All data is read-only and local."
    }

    func copyConfiguration() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configurationSnippet, forType: .string)
        copiedState = "Configuration copied"
    }
}
