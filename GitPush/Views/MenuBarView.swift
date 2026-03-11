import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    let onPreferredSizeChange: (CGSize) -> Void
    @State private var showSettings = false
    @State private var expandedRepoIDs: Set<String> = []
    @State private var repoContentHeight: CGFloat = 0
    @State private var settingsContentHeight: CGFloat = 0

    init(
        appState: AppState,
        onPreferredSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.appState = appState
        self.onPreferredSizeChange = onPreferredSizeChange
    }

    private var activeRepoCount: Int {
        appState.repositories.filter { $0.changedFileCount > 0 || $0.unpushedCount > 0 }.count
    }

    private var statusText: String {
        switch appState.menuBarStatus {
        case .idle:
            if activeRepoCount == 0 { return "Quiet for now" }
            return "\(activeRepoCount) active repo\(activeRepoCount == 1 ? "" : "s")"
        case .committing(let repoName):
            return "Committing \(repoName)"
        case .pushing(let repoName):
            return "Pushing \(repoName)"
        case .success:
            return "Last action finished"
        case .error:
            return "Action needs attention"
        }
    }

    var body: some View {
        ZStack {
            panelBackground

            VStack(spacing: 10) {
                header
                contentArea
            }
            .padding(10)
        }
        .frame(width: 348)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            SizeReader { size in
                onPreferredSizeChange(size)
            }
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: showSettings)
    }

    private var contentArea: some View {
        ZStack(alignment: .top) {
            repoList
                .opacity(showSettings ? 0 : 1)
                .offset(x: showSettings ? -10 : 0)
                .blur(radius: showSettings ? 0.8 : 0)
                .allowsHitTesting(!showSettings)

            SettingsView(appState: appState, showSettings: $showSettings)
                .opacity(showSettings ? 1 : 0)
                .offset(x: showSettings ? 0 : 10)
                .blur(radius: showSettings ? 0 : 0.8)
                .allowsHitTesting(showSettings)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: activeContentHeight, alignment: .top)
        .clipped()
        .overlay(alignment: .top) {
            measurementLayer
        }
    }

    private var activeContentHeight: CGFloat {
        let measuredHeight = showSettings ? settingsContentHeight : repoContentHeight
        return max(measuredHeight, 1)
    }

    private var measurementLayer: some View {
        ZStack(alignment: .top) {
            repoList
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background(
                    HeightReader { repoContentHeight = $0 }
                )

            SettingsView(appState: appState, showSettings: $showSettings)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background(
                    HeightReader { settingsContentHeight = $0 }
                )
        }
        .allowsHitTesting(false)
    }

    private var panelBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.88))

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .compositingGroup()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            if showSettings {
                iconButton(systemName: "chevron.left") {
                    showSettings = false
                }
                .padding(.top, 2)
            } else {
                appGlyph
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(showSettings ? "Settings" : "GitPush")
                    .font(.system(size: 18, weight: .semibold))

                Text(showSettings ? "Preferences and AI setup" : statusText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !showSettings {
                HStack(spacing: 6) {
                    iconButton(systemName: "arrow.clockwise") {
                        appState.scanRepos()
                    }

                    iconButton(systemName: "gearshape") {
                        showSettings = true
                    }
                }
            }
        }
    }

    private var appGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
        }
        .frame(width: 36, height: 36)
        .shadow(color: Color.black.opacity(0.14), radius: 10, y: 6)
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(.regularMaterial.opacity(0.9))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    private var repoList: some View {
        VStack(spacing: 10) {
            if appState.repositories.count > 1 {
                overviewCard
            }

            if appState.repositories.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(appState.repositories) { repo in
                        RepoRowView(
                            repo: repo,
                            appState: appState,
                            isExpanded: expansionBinding(for: repo.id)
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            bottomBar
        }
    }

    private var overviewCard: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Active Repositories")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(activeRepoCount == 0 ? "Nothing pending" : "\(activeRepoCount) ready for commit or push")
                        .font(.system(size: 13.5, weight: .semibold))
                }

                Spacer(minLength: 8)

                if activeRepoCount > 0 {
                    Button {
                        Task { await appState.commitAndPushAll() }
                    } label: {
                        Label("Push All", systemImage: "arrow.up.forward.circle.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.repositories.contains { $0.operation.isInProgress })
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.82))
                }

                Text("No active repos")
                    .font(.system(size: 15, weight: .semibold))

                Text("Open a project in your editor or terminal and GitPush will surface repos with changes or unpushed commits.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var bottomBar: some View {
        GlassCard {
            HStack(spacing: 8) {
                if appState.hotkeyEnabled && appState.hotkeyKeyCode >= 0 {
                    HStack(spacing: 6) {
                        Text(HotkeyRecorderView.displayString(
                            keyCode: appState.hotkeyKeyCode,
                            modifiers: appState.hotkeyModifiers
                        ))
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        )

                        Text("Commit & push all")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Enable a global shortcut in Settings for one-step push all.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func expansionBinding(for repoID: String) -> Binding<Bool> {
        Binding(
            get: { expandedRepoIDs.contains(repoID) },
            set: { isExpanded in
                if isExpanded {
                    expandedRepoIDs = [repoID]
                } else {
                    expandedRepoIDs.remove(repoID)
                }
            }
        )
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
        case .claude: return "Claude Haiku for concise commit summaries."
        case .openai: return "GPT-4o mini for concise commit summaries."
        }
    }

    var body: some View {
        LimitedHeightScrollView(maxHeight: 470) {
            VStack(spacing: 10) {
                settingsCard(title: "Projects Directory", subtitle: "Where GitPush looks for repos you are actively working on.") {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )

                        Text(appState.projectsPath)
                            .font(.system(size: 11.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)

                        Spacer(minLength: 8)

                        Button("Choose…") {
                            chooseFolder()
                        }
                        .controlSize(.small)
                    }
                }

                settingsCard(title: "AI Commit Messages", subtitle: modelLabel) {
                    VStack(spacing: 10) {
                        Picker("Provider", selection: Binding(
                            get: { appState.aiProvider },
                            set: { newValue in
                                appState.aiProvider = newValue
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
                            HStack {
                                Label("Saved in Keychain", systemImage: "key.fill")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button("Remove") {
                                    appState.saveAPIKey("", for: appState.aiProvider)
                                    hasExistingKey = false
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.red)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }

                        HStack(spacing: 6) {
                            SecureField(apiKeyPlaceholder, text: $apiKeyInput)
                                .font(.system(size: 11.5, design: .monospaced))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
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
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.green)
                                    } else {
                                        Text("Save")
                                            .font(.system(size: 11.5, weight: .semibold))
                                    }
                                }
                                .frame(width: 46)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.accentColor.opacity(apiKeyInput.isEmpty ? 0.08 : 0.14))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(apiKeyInput.isEmpty)
                        }

                        Toggle("Auto-generate commit messages when opening a repo", isOn: $appState.autoGenerateCommitMessage)
                            .toggleStyle(.switch)
                            .font(.system(size: 11.5))
                    }
                }

                settingsCard(title: "Keyboard Shortcut", subtitle: "Commit and push all active repos from anywhere.") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable global shortcut", isOn: $appState.hotkeyEnabled)
                            .toggleStyle(.switch)
                            .font(.system(size: 11.5))

                        if appState.hotkeyEnabled {
                            HStack {
                                Text("Shortcut")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                HotkeyRecorderView(
                                    keyCode: $appState.hotkeyKeyCode,
                                    modifiers: $appState.hotkeyModifiers
                                )
                            }

                            Text("The shortcut commits and pushes every repo currently surfaced in the menu.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .onAppear {
            loadKeyForCurrentProvider()
        }
        .onDisappear {
            appState.scanRepos()
        }
        .animation(.easeOut(duration: 0.2), value: keySaveState)
        .animation(.easeOut(duration: 0.2), value: hasExistingKey)
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))

                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                content()
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose your projects directory"
        panel.prompt = "Select"
        panel.directoryURL = URL(fileURLWithPath: appState.expandedProjectsPath)
        panel.level = .floating

        if panel.runModal() == .OK, let url = panel.url {
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            keySaveState = .idle
        }
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct HeightReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    onChange(proxy.size.height)
                }
                .onChange(of: proxy.size.height) { _, newHeight in
                    onChange(newHeight)
                }
        }
    }
}

private struct SizeReader: View {
    let onChange: (CGSize) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    onChange(proxy.size)
                }
                .onChange(of: proxy.size) { _, newSize in
                    onChange(newSize)
                }
        }
    }
}

private struct LimitedHeightScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    @State private var contentHeight: CGFloat = 1

    var body: some View {
        ScrollView {
            content
                .background(
                    HeightReader { contentHeight = $0 }
                )
        }
        .scrollIndicators(.hidden)
        .frame(height: min(contentHeight, maxHeight))
    }
}
