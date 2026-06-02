import Foundation

enum DeterministicReviewPolicy {
    static func classifyFile(_ path: String) -> ChangedFile.FileClassification {
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        if generatedFilenames.contains(filename) || generatedExtensions.contains(ext) {
            return .generated
        }
        if documentationExtensions.contains(ext) || documentationFilenames.contains(filename) {
            return .documentation
        }
        if configFilenames.contains(filename) || configExtensions.contains(ext) {
            return .config
        }
        return .source
    }

    static func effectiveFiles(files: [ChangedFile], symbols: [ChangedSymbol]) -> [ChangedFile] {
        let testFileIds = Set(
            symbols
                .filter { $0.metadata["is_test"] == "true" }
                .map(\.changedFileId)
        )
        return files.map { file in
            var copy = file
            if testFileIds.contains(file.id) {
                copy.classification = .test
            } else {
                copy.classification = classifyFile(file.path)
            }
            return copy
        }
    }

    static func bucketType(
        for file: ChangedFile, findings: [Finding], symbols: [ChangedSymbol]
    ) -> ChangeBucketType {
        switch file.classification {
        case .test:
            return .tests
        case .generated, .boilerplate:
            return .generated
        case .documentation:
            return .docs
        case .config:
            return .buildConfig
        case .source:
            break
        }

        if findings.contains(where: { $0.category == .security }) {
            return .authSecurity
        }
        if symbols.contains(where: { $0.metadata.keys.contains { $0.hasPrefix("contract_") } }) {
            return .apiContract
        }
        if symbols.contains(where: { $0.metadata["semantic_area"] == "data_persistence" }) {
            return .data
        }
        if symbols.contains(where: { $0.metadata["semantic_area"] == "ui" }) {
            return .ui
        }
        return .behavior
    }

    static func bucketTitle(for type: ChangeBucketType) -> String {
        type.displayTitle
    }

    static func symbolGroup(for symbol: ChangedSymbol) -> (id: String, label: String, icon: String)
    {
        if symbol.metadata["is_test"] == "true" {
            return ("tests", "Tests", "checkmark.seal")
        }
        switch symbol.metadata["semantic_area"] {
        case "security_authentication":
            return ("security", "Security", "lock.shield")
        case "data_persistence":
            return ("data", "Data", "cylinder")
        case "ui":
            return ("ui", "User Interface", "rectangle.on.rectangle")
        default:
            return ("behavior", "Behavior", "cpu")
        }
    }

    static let generatedOnlyDelta = -40
    static let productionChangeDelta = 10
    static let architectureFindingDelta = 20
    static let highFanInDelta = 10
    static let contractDelta = 10
    static let behaviorAddedDelta = 10
    static let testChangeDelta = -15

    private static let generatedFilenames: Set<String> = [
        "cargo.lock",
        "go.sum",
        "package-lock.json",
        "pnpm-lock.yaml",
        "poetry.lock",
        "yarn.lock",
    ]

    private static let generatedExtensions: Set<String> = [
        "lock"
    ]

    private static let documentationFilenames: Set<String> = [
        "changelog",
        "changelog.md",
        "contributing",
        "contributing.md",
        "license",
        "license.md",
        "readme",
        "readme.md",
    ]

    private static let documentationExtensions: Set<String> = [
        "adoc",
        "md",
        "rst",
        "txt",
    ]

    private static let configFilenames: Set<String> = [
        ".editorconfig",
        ".gitignore",
        ".swift-format",
        "dockerfile",
        "makefile",
    ]

    private static let configExtensions: Set<String> = [
        "conf",
        "config",
        "gradle",
        "ini",
        "json",
        "plist",
        "toml",
        "xml",
        "yaml",
        "yml",
    ]
}
