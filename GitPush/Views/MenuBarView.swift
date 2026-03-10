import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if showSettings {
                SettingsView(appState: appState, showSettings: $showSettings)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                repoList
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 320)
        .animation(.easeInOut(duration: 0.2), value: showSettings)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if showSettings {
                Button {
                    showSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(showSettings ? "Settings" : "GitPush")
                .font(.headline)

            Spacer()

            if !showSettings {
                Button {
                    appState.scanRepos()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var repoList: some View {
        Group {
            if appState.repositories.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(appState.repositories) { repo in
                            RepoRowView(repo: repo, appState: appState)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 380)

                footer
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No active repos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Open a project in your editor to see it here")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                let count = appState.repositories.filter { $0.changedFileCount > 0 }.count
                Text("\(count) repo\(count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if count > 0 {
                    Button {
                        Task { await appState.commitAndPushAll() }
                    } label: {
                        Text("Push All")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.repositories.contains { $0.operation.isInProgress })
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            HStack(spacing: 3) {
                Text("⌘⇧G")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.3))
                    .cornerRadius(3)
                Text("commit & push all")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Binding var showSettings: Bool
    @State private var apiKeyInput = ""
    @State private var pathInput = ""

    private var apiKeyPlaceholder: String {
        switch appState.aiProvider {
        case .claude: return "sk-ant-..."
        case .openai: return "sk-..."
        }
    }

    private var modelLabel: String {
        switch appState.aiProvider {
        case .claude: return "Uses Claude Haiku for commit messages."
        case .openai: return "Uses GPT-4o mini for commit messages."
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("~/Documents/Projects", text: $pathInput)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: pathInput) { _, newValue in
                        appState.projectsPath = newValue
                    }
            } header: {
                Text("Projects Directory")
            }

            Section {
                Picker("Provider", selection: Binding(
                    get: { appState.aiProvider },
                    set: { newValue in
                        appState.aiProvider = newValue
                        apiKeyInput = ""
                        appState.apiKey = ""
                    }
                )) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                SecureField(apiKeyPlaceholder, text: $apiKeyInput)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: apiKeyInput) { _, newValue in
                        appState.apiKey = newValue
                    }

                Text(modelLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("AI Commit Messages")
            }

            Section {
                Toggle("Auto-generate commit messages", isOn: $appState.autoGenerateCommitMessage)
                    .controlSize(.small)
                Toggle(isOn: $appState.hotkeyEnabled) {
                    HStack(spacing: 4) {
                        Text("Global hotkey")
                        Text("⌘⇧G")
                            .font(.system(size: 10, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary.opacity(0.5))
                            .cornerRadius(3)
                    }
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: 360)
        .onAppear {
            apiKeyInput = appState.apiKey
            pathInput = appState.projectsPath
        }
        .onDisappear {
            if !apiKeyInput.isEmpty { appState.apiKey = apiKeyInput }
            if !pathInput.isEmpty { appState.projectsPath = pathInput }
            appState.scanRepos()
        }
    }
}
