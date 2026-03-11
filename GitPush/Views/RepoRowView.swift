import SwiftUI

struct RepoRowView: View {
    let repo: Repository
    @ObservedObject var appState: AppState
    @State private var isExpanded = false
    @State private var isGeneratingMessage = false
    @State private var isHovered = false

    init(repo: Repository, appState: AppState, initiallyExpanded: Bool = false) {
        self.repo = repo
        self.appState = appState
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            expandedContent

            if case .error(let msg) = repo.operation {
                errorBanner(msg)
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(isHovered ? 0.18 : 0.11), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isExpanded)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: repo.operation)
    }

    private var expandedContent: some View {
        ExpandableReveal(isExpanded: isExpanded) {
            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, 11)

                expandedContentBody
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0.03))
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.12 : 0.07), radius: isHovered ? 14 : 10, y: 6)
    }

    private var mainRow: some View {
        HStack(alignment: .top, spacing: 10) {
            statusBadge

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repo.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)

                        Text(repo.path)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)

                    branchChip
                }

                HStack(spacing: 5) {
                    metadataChip(
                        text: "\(repo.changedFileCount) change\(repo.changedFileCount == 1 ? "" : "s")",
                        systemName: "circle.hexagongrid.fill",
                        tint: .orange,
                        isVisible: repo.changedFileCount > 0
                    )

                    metadataChip(
                        text: "\(repo.unpushedCount) unpushed",
                        systemName: "arrow.up.forward.circle.fill",
                        tint: .blue,
                        isVisible: repo.unpushedCount > 0
                    )

                    Spacer(minLength: 0)
                }
            }

            actionButtons
        }
        .padding(11)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                isExpanded.toggle()
            }
        }
    }

    private var statusBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(statusBackgroundColor)

            statusSymbol
        }
        .frame(width: 28, height: 28)
    }

    private var statusBackgroundColor: Color {
        switch repo.operation {
        case .idle:
            if repo.changedFileCount > 0 { return .orange.opacity(0.16) }
            if repo.unpushedCount > 0 { return .blue.opacity(0.16) }
            return Color.primary.opacity(0.06)
        case .committing:
            return .orange.opacity(0.16)
        case .pushing:
            return .blue.opacity(0.16)
        case .success:
            return .green.opacity(0.16)
        case .error:
            return .red.opacity(0.16)
        }
    }

    @ViewBuilder
    private var statusSymbol: some View {
        switch repo.operation {
        case .idle:
            Image(systemName: repo.changedFileCount > 0 ? "point.topleft.down.curvedto.point.bottomright.up.fill" : "arrow.up.forward.circle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(repo.changedFileCount > 0 ? .orange : .blue)
        case .committing:
            CommittingIndicator()
        case .pushing:
            PushingIndicator()
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.red)
        }
    }

    private var branchChip: some View {
        Text(repo.branch)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    @ViewBuilder
    private func metadataChip(text: String, systemName: String, tint: Color, isVisible: Bool) -> some View {
        if isVisible {
            Label(text, systemImage: systemName)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(tint.opacity(0.92))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.12))
                )
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 6) {
            if !repo.operation.isInProgress, repo.changedFileCount > 0 {
                circleActionButton(
                    systemName: "checkmark",
                    tint: .green,
                    help: "Commit"
                ) {
                    Task { await quickCommit() }
                }
            }

            if !repo.operation.isInProgress, repo.changedFileCount > 0 || repo.unpushedCount > 0 {
                circleActionButton(
                    systemName: "arrow.up",
                    tint: .accentColor,
                    help: repo.changedFileCount > 0 ? "Commit & Push" : "Push"
                ) {
                    if repo.changedFileCount > 0 {
                        Task { await quickCommitAndPush() }
                    } else {
                        Task { await pushOnly() }
                    }
                }
            }
        }
    }

    private func circleActionButton(
        systemName: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var expandedContentBody: some View {
        VStack(spacing: 10) {
            if !repo.changedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Changed Files")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    VStack(spacing: 6) {
                        ForEach(repo.changedFiles.prefix(8)) { file in
                            HStack(spacing: 6) {
                                Text(file.status)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(statusColor(file.status))
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 0) {
                                    Text(file.path)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Text(file.statusLabel)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer(minLength: 0)
                            }
                        }

                        if repo.changedFiles.count > 8 {
                            Text("and \(repo.changedFiles.count - 8) more")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Commit Message")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    Button {
                        generateMessage()
                    } label: {
                        HStack(spacing: 4) {
                            if isGeneratingMessage {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.65)
                            } else {
                                Image(systemName: appState.hasAPIKey ? "sparkles" : "text.badge.star")
                                    .font(.system(size: 9, weight: .semibold))
                            }

                            Text(appState.hasAPIKey ? "Generate" : "Auto")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill((appState.hasAPIKey ? Color.accentColor : Color.secondary).opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingMessage)
                }

                if let index = appState.repositories.firstIndex(where: { $0.id == repo.id }) {
                    ScrollView {
                        TextEditor(text: $appState.repositories[index].commitMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollDisabled(true)
                    }
                    .frame(minHeight: 58, maxHeight: 104)
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
            }

            HStack(spacing: 6) {
                Spacer()

                if repo.changedFileCount > 0 {
                    actionPill(title: "Commit", tint: .green) {
                        Task { await manualCommit() }
                    }

                    actionPill(title: "Commit & Push", tint: .accentColor) {
                        Task { await manualCommitAndPush() }
                    }
                } else if repo.unpushedCount > 0 {
                    actionPill(title: "Push", tint: .accentColor) {
                        Task { await pushOnly() }
                    }
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 10)
        .padding(.bottom, 11)
    }

    private func actionPill(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .disabled(repo.operation.isInProgress)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(message)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(2)
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.bottom, 11)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "M": return .orange
        case "A": return .green
        case "D": return .red
        case "??": return .blue
        case "R": return .purple
        default: return .secondary
        }
    }

    private func generateMessage() {
        isGeneratingMessage = true
        Task {
            await appState.generateCommitMessage(for: repo)
            isGeneratingMessage = false
        }
    }

    private func quickCommit() async {
        let hasMessage = appState.repositories.first(where: { $0.id == repo.id })
            .map { !$0.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        await appState.commitOnly(repo: repo, autoGenerate: !hasMessage)
    }

    private func quickCommitAndPush() async {
        let hasMessage = appState.repositories.first(where: { $0.id == repo.id })
            .map { !$0.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        await appState.commitAndPush(repo: repo, autoGenerate: !hasMessage)
    }

    private func pushOnly() async {
        await appState.pushOnly(repo: repo)
    }

    private func manualCommit() async {
        if let index = appState.repositories.firstIndex(where: { $0.id == repo.id }),
           appState.repositories[index].commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await appState.generateCommitMessage(for: repo)
        }
        await appState.commitOnly(repo: repo)
    }

    private func manualCommitAndPush() async {
        if let index = appState.repositories.firstIndex(where: { $0.id == repo.id }),
           appState.repositories[index].commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await appState.generateCommitMessage(for: repo)
        }
        await appState.commitAndPush(repo: repo)
    }
}

struct CommittingIndicator: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.76)
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 13, height: 13)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

struct PushingIndicator: View {
    @State private var offset: CGFloat = 3
    @State private var opacity: Double = 0.45

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.blue)
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever()) {
                    offset = -3
                    opacity = 1
                }
            }
    }
}

private struct ExpandableReveal<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder let content: Content

    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            measuredHeight = proxy.size.height
                        }
                        .onChange(of: proxy.size.height) { _, newHeight in
                            measuredHeight = newHeight
                        }
                }
            )
            .frame(height: isExpanded ? measuredHeight : 0, alignment: .top)
            .opacity(isExpanded ? 1 : 0)
            .clipped()
            .allowsHitTesting(isExpanded)
    }
}

@MainActor
private struct RepoRowPreviewHost: View {
    @StateObject private var appState: AppState
    private let initiallyExpanded: Bool

    init(initiallyExpanded: Bool) {
        let state = AppState()
        let repo = Repository(
            id: "preview-repo",
            path: "/Users/farzan/Documents/Projects/GitPush",
            name: "GitPush",
            branch: "main",
            changedFileCount: 4,
            changedFiles: [
                .init(status: "M", path: "GitPush/Views/RepoRowView.swift"),
                .init(status: "A", path: "GitPush/Views/PreviewFixtures.swift"),
                .init(status: "??", path: "docs/dropdown-motion-notes.md"),
                .init(status: "R", path: "GitPush/Views/LegacyRow.swift -> GitPush/Views/RepoRowView.swift")
            ],
            unpushedCount: 2,
            operation: .idle,
            commitMessage: "Refine the menu bar UI to feel closer to current macOS utility panels."
        )
        state.repositories = [repo]
        _appState = StateObject(wrappedValue: state)
        self.initiallyExpanded = initiallyExpanded
    }

    var body: some View {
        RepoRowView(
            repo: appState.repositories[0],
            appState: appState,
            initiallyExpanded: initiallyExpanded
        )
        .padding(12)
        .frame(width: 368)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview("Collapsed Repo Row") {
    RepoRowPreviewHost(initiallyExpanded: false)
}

#Preview("Expanded Repo Row") {
    RepoRowPreviewHost(initiallyExpanded: true)
}
