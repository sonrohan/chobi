<p align="center">
  <img src="docs/assets/logo.svg" alt="Chobi Logo" width="200">
</p>

# Chobi

Chobi is a native macOS application designed to deliver an intelligent, localized code review and diff analysis experience. It parses changes, assesses risk, categorizes files semantically, and triages code issues entirely locally without sending data to external servers.

---

## 🚀 Technology Stack

Chobi utilizes a modern hybrid architecture:
1.  **UI/App Layer (SwiftUI)**: Built with Apple's standard native declarative UI framework, leveraging Swift 5.9+ modern concurrency (`async/await`, actors) and compile-safe data flow.
2.  **Core Analysis Engine (Rust Sidecar)**: Under `chobi-core`, a high-performance Rust service executes local static analysis, syntax tree parsing, and deterministic rules matching.

---

## 🏛️ Core Architecture Principles

The application layer strictly implements a **Modern, Standard MVVM** pattern to ensure modularity, high testability, and predictable runtime behavior:

1.  **Declarative, Passive Views**: SwiftUI Views are lightweight layout definitions. They observe state but do not coordinate operations or invoke databases/Git engines directly.
2.  **State-Retaining ViewModels (`@Observable`)**: Driven by the modern Swift `Observation` framework. ViewModels bridge the views with long-running services, surviving redraw loops when initialized inside `@State`.
3.  **Thread-Safe Services**: Long-running asynchronous operations (e.g. Git commands, sidecar communication) run in thread-safe `actor` contexts or isolated protocols, ensuring data consistency across multiple threads.
4.  **MainActor Safety**: All ViewModels and UI-state-holding classes are bound to `@MainActor` to automatically execute property mutations on the main thread, avoiding typical multi-threading rendering glitches.
5.  **Injectable Mocking for Testability**: All dependencies are passed using protocol injection, allowing view models to be fully verified in lightweight, MainActor-isolated unit test suites without launching full simulators.

For a comprehensive guide, reference:  
👉 **[macOS Architecture Guide](docs/macos_architecture_guide.md)**

---

## 📁 Repository Structure

We structure the source files by functional domain to keep the codebase highly navigable:

```
Chobi/
├── Core/                        # Immutable models, deterministic engine, and review policy
├── Services/                    # Long-running services and global coordinator (AppState)
├── ViewModels/                  # Observables managing transient view states & actions
├── Views/                       # Clean declarative layouts
└── ChobiApp.swift               # App entry point

chobi-core/                      # Rust static analysis sidecar source code
ArchitectureTests.swift          # Compile-ready unit testing harness for MVVM ViewModels
```

---

## 🎨 Style, Formatting & Commits

Chobi uses Apple's official `swift-format` engine to ensure style consistency, and enforces Conventional Commits to automate changelog generation.
*   **Indentation**: Enforced **4-space indentation** for all Swift files.
*   **Scripts**:
    *   `./scripts/format.sh`: Format Swift files locally.
    *   `./scripts/lint.sh`: Perform style check.
    *   `./scripts/setup-git-hooks.sh`: Install a pre-commit auto-formatting git hook.
*   **Commit Messages**: Follows the **Conventional Commits 1.0.0** standard (e.g. `feat(views): ...`, `fix(core): ...`).

---

## 🤖 Agentic & AI Coding Guidance

Are you an AI coding agent or an external contributor looking to extend Chobi? Please review our specialized instructions for preserving architectural boundaries, testing models, and implementing clean data flows.

👉 See **[AGENTS.md](AGENTS.md)**
