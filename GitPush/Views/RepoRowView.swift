import SwiftUI

struct RepoRowView: View {
    let repo: Repository
    @ObservedObject var appState: AppState
    @State private var isExpanded = false
    @State private var isGeneratingMessage = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if isExpanded { expandedContent }
            if case .error(let msg) = repo.operation { errorBanner(msg) }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color(nsColor: .controlAccentColor).opacity(0.06) : .clear)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: repo.operation)
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            // Tappable area for expand/collapse
            HStack(spacing: 8) {
                statusDot
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(repo.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        Text(repo.branch)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .separatorColor).opacity(0.3))
                            .cornerRadius(3)
                    }

                    HStack(spacing: 4) {
                        if repo.changedFileCount > 0 {
                            Text("\(repo.changedFileCount) change\(repo.changedFileCount == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if repo.unpushedCount > 0 {
                            Text("\(repo.unpushedCount) unpushed")
                                .font(.caption2)
                                .foregroundStyle(.blue.opacity(0.7))
                        }
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isExpanded.toggle()
            }

            // Quick action buttons
            if !repo.operation.isInProgress {
                if repo.changedFileCount > 0 {
                    Button {
                        Task { await quickCommit() }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.green)
                    .opacity(isHovered ? 1 : 0.7)
                    .help("Commit")
                }

                if repo.changedFileCount > 0 || repo.unpushedCount > 0 {
                    Button {
                        if repo.changedFileCount > 0 {
                            Task { await quickCommitAndPush() }
                        } else {
                            Task { await pushOnly() }
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .opacity(isHovered ? 1 : 0.7)
                    .help(repo.changedFileCount > 0 ? "Commit & Push" : "Push")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusDot: some View {
        switch repo.operation {
        case .idle:
            Circle()
                .fill(repo.changedFileCount > 0 ? Color.orange : (repo.unpushedCount > 0 ? Color.blue : Color(nsColor: .separatorColor)))
                .frame(width: 6, height: 6)
        case .committing:
            CommittingIndicator()
        case .pushing:
            PushingIndicator()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 6) {
            // File list
            VStack(spacing: 0) {
                ForEach(repo.changedFiles.prefix(8)) { file in
                    HStack(spacing: 5) {
                        Text(file.status)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(statusColor(file.status))
                            .frame(width: 16, alignment: .center)

                        Text(file.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()
                    }
                    .padding(.vertical, 1.5)
                }
                if repo.changedFiles.count > 8 {
                    Text("and \(repo.changedFiles.count - 8) more")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .padding(.top, 2)
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(5)

            // Commit message
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Message")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        generateMessage()
                    } label: {
                        HStack(spacing: 2) {
                            if isGeneratingMessage {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: appState.hasAPIKey ? "sparkles" : "text.badge.star")
                                    .font(.system(size: 9))
                            }
                            Text(appState.hasAPIKey ? "Generate" : "Auto")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appState.hasAPIKey ? Color.purple : Color.secondary)
                    .disabled(isGeneratingMessage)
                }

                if let index = appState.repositories.firstIndex(where: { $0.id == repo.id }) {
                    ScrollView {
                        TextEditor(text: $appState.repositories[index].commitMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollDisabled(true)
                    }
                    .frame(minHeight: 50, maxHeight: 120)
                    .padding(2)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            }

            // Action buttons
            HStack {
                Spacer()
                if repo.changedFileCount > 0 {
                    Button {
                        Task { await manualCommit() }
                    } label: {
                        Text("Commit")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .controlSize(.small)
                    .disabled(repo.operation.isInProgress)

                    Button {
                        Task { await manualCommitAndPush() }
                    } label: {
                        Text("Commit & Push")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .controlSize(.small)
                    .disabled(repo.operation.isInProgress)
                } else if repo.unpushedCount > 0 {
                    Button {
                        Task { await pushOnly() }
                    } label: {
                        Text("Push")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .controlSize(.small)
                    .disabled(repo.operation.isInProgress)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text(message)
                .font(.caption2)
                .lineLimit(2)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .transition(.opacity)
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

    /// Green checkmark: auto-generate message, commit only
    private func quickCommit() async {
        await appState.commitOnly(repo: repo, autoGenerate: true)
    }

    /// Blue arrow: auto-generate message, commit, push
    private func quickCommitAndPush() async {
        await appState.commitAndPush(repo: repo, autoGenerate: true)
    }

    /// Push only (no commit) — for repos with unpushed commits
    private func pushOnly() async {
        await appState.pushOnly(repo: repo)
    }

    /// Expanded "Commit" button: use whatever message is in the field
    private func manualCommit() async {
        if let index = appState.repositories.firstIndex(where: { $0.id == repo.id }),
           appState.repositories[index].commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await appState.generateCommitMessage(for: repo)
        }
        await appState.commitOnly(repo: repo)
    }

    /// Expanded "Commit & Push" button: use whatever message is in the field
    private func manualCommitAndPush() async {
        if let index = appState.repositories.firstIndex(where: { $0.id == repo.id }),
           appState.repositories[index].commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await appState.generateCommitMessage(for: repo)
        }
        await appState.commitAndPush(repo: repo)
    }
}

// MARK: - Status Animations

struct CommittingIndicator: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.65)
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 12, height: 12)
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
    @State private var opacity: Double = 0.4

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.blue)
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    offset = -3
                    opacity = 1.0
                }
            }
    }
}
