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
        .frame(maxHeight: 600)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: showSettings)
        .animation(.easeInOut(duration: 0.25), value: appState.repositories.count)
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
        VStack(spacing: 0) {
            if appState.repositories.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(appState.repositories) { repo in
                        RepoRowView(repo: repo, appState: appState)
                    }
                }
                .padding(6)

                repoFooter
            }

            bottomBar
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

    private var repoFooter: some View {
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
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 3) {
                if appState.hotkeyEnabled && appState.hotkeyKeyCode >= 0 {
                    Text(HotkeyRecorderView.displayString(
                        keyCode: appState.hotkeyKeyCode,
                        modifiers: appState.hotkeyModifiers
                    ))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.3))
                        .cornerRadius(3)
                    Text("push all")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                Spacer()
                Button("Quit GitPush") {
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
    @State private var keySaveState: KeySaveState = .idle
    @State private var hasExistingKey = false

    enum KeySaveState: Equatable {
        case idle
        case saved
    }

    private var apiKeyPlaceholder: String {
        switch appState.aiProvider {
        case .claude: return "sk-ant-api03-..."
        case .openai: return "sk-proj-..."
        }
    }

    private var modelLabel: String {
        switch appState.aiProvider {
        case .claude: return "Uses Claude Haiku. Stored in Keychain."
        case .openai: return "Uses GPT-4o mini. Stored in Keychain."
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(appState.projectsPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("Choose…") {
                        chooseFolder()
                    }
                    .controlSize(.small)
                }
            } header: {
                Text("Projects Directory")
            }

            Section {
                Picker("Provider", selection: Binding(
                    get: { appState.aiProvider },
                    set: { newValue in
                        appState.aiProvider = newValue
                        // Load the key for the new provider
                        loadKeyForCurrentProvider()
                        keySaveState = .idle
                    }
                )) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                if hasExistingKey && apiKeyInput.isEmpty {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                            Text("Saved in Keychain")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove") {
                            appState.saveAPIKey("", for: appState.aiProvider)
                            hasExistingKey = false
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }

                HStack(spacing: 6) {
                    SecureField(apiKeyPlaceholder, text: $apiKeyInput)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKeyInput) { _, _ in
                            keySaveState = .idle
                        }
                        .onSubmit { saveKey() }

                    Button {
                        saveKey()
                    } label: {
                        Group {
                            if keySaveState == .saved {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.green)
                            } else {
                                Text("Save")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .frame(width: 40)
                    }
                    .controlSize(.small)
                    .disabled(apiKeyInput.isEmpty)
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
            }

            Section {
                Toggle("Global hotkey", isOn: $appState.hotkeyEnabled)
                    .controlSize(.small)

                if appState.hotkeyEnabled {
                    HStack {
                        Text("Shortcut")
                            .font(.system(size: 12))
                        Spacer()
                        HotkeyRecorderView(
                            keyCode: $appState.hotkeyKeyCode,
                            modifiers: $appState.hotkeyModifiers
                        )
                    }
                    Text("Commits and pushes all active repos.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("Keyboard Shortcut")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            loadKeyForCurrentProvider()
        }
        .onDisappear {
            appState.scanRepos()
        }
        .animation(.easeOut(duration: 0.2), value: keySaveState)
        .animation(.easeOut(duration: 0.2), value: hasExistingKey)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose your projects directory"
        panel.prompt = "Select"
        panel.directoryURL = URL(fileURLWithPath: appState.expandedProjectsPath)

        // Bring panel to front above the menu bar popover
        panel.level = .floating

        if panel.runModal() == .OK, let url = panel.url {
            // Use ~ shorthand if inside home directory
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            if url.path.hasPrefix(homePath) {
                appState.projectsPath = "~" + url.path.dropFirst(homePath.count)
            } else {
                appState.projectsPath = url.path
            }
        }
    }

    private func loadKeyForCurrentProvider() {
        let existingKey = appState.currentAPIKey
        hasExistingKey = !existingKey.isEmpty
        apiKeyInput = ""
        keySaveState = .idle
    }

    private func saveKey() {
        guard !apiKeyInput.isEmpty else { return }
        appState.saveAPIKey(apiKeyInput, for: appState.aiProvider)
        hasExistingKey = true
        apiKeyInput = ""
        keySaveState = .saved

        // Reset checkmark after a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            keySaveState = .idle
        }
    }
}
