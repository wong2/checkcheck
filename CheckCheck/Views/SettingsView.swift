import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 14) {
            AccountSettingsView()
                .environmentObject(store)

            if store.isConnected {
                NotificationSettingsView()
                    .environmentObject(store)

                RepositorySettingsView()
                    .environmentObject(store)
                    .frame(maxHeight: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(20)
        .frame(width: 620)
        .frame(minHeight: minimumWindowHeight, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: store.isConnected)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var minimumWindowHeight: CGFloat {
        if store.isConnected { return 460 }
        return store.errorMessage == nil ? 180 : 240
    }
}

private struct AccountSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var token = ""

    private let tokenCreationURL = URL(
        string: "https://github.com/settings/tokens/new?scopes=repo&description=CheckCheck%20for%20macOS"
    )!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub account")
                        .font(.headline)

                    Text(accountSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if store.isConnected {
                    Button("Disconnect", role: .destructive) {
                        store.disconnect()
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, store.isConnected ? 8 : 13)

            if store.isConnected {
                Label("Token stored in Keychain", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 58)
                .padding(.trailing, 16)
                .padding(.bottom, 13)
            }

            if !store.isConnected {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        SecureField("Personal access token", text: $token, prompt: Text("ghp_…"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(connect)

                        Button {
                            connect()
                        } label: {
                            HStack(spacing: 6) {
                                if store.isConnecting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(store.isConnecting ? "Verifying…" : "Connect")
                            }
                            .frame(minWidth: 72)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isConnecting)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Classic tokens need the repo scope for private repositories.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Link("Create token on GitHub", destination: tokenCreationURL)
                            .font(.caption)
                    }
                }
                .padding(14)
            }

            if let error = store.errorMessage {
                Divider()

                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(14)
            }
        }
        .settingsCard()
    }

    private var accountSubtitle: String {
        if let user = store.user, store.isConnected {
            return "Connected as @\(user.login)"
        }
        return "Connect once, then choose the repositories to monitor."
    }

    private func connect() {
        Task {
            if await store.connect(token: token) {
                token = ""
            }
        }
    }
}

private struct NotificationSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notificationSystemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications")
                    .font(.headline)

                Text(notificationStatusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.notificationPermission == .unknown {
                ProgressView()
                    .controlSize(.small)
                    .help("Checking notification permission")
            } else {
                Button("Open Settings") {
                    store.openNotificationSettings()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .settingsCard()
        .task {
            await store.refreshNotificationPermission()
        }
    }

    private var notificationSystemImage: String {
        switch store.notificationPermission {
        case .unknown, .enabled:
            return "bell.fill"
        case .disabled:
            return "bell.slash.fill"
        }
    }

    private var notificationStatusText: String {
        switch store.notificationPermission {
        case .unknown:
            return "Checking permission…"
        case .enabled:
            return "Enabled"
        case .disabled:
            return "Disabled"
        }
    }
}

private struct RepositorySettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Repositories")
                        .font(.headline)
                    Text("Choose which repositories appear in the menu bar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(store.selectedRepositoryCount) monitored")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await store.reloadRepositories() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isLoadingRepositories)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .help("Reload repositories")
                .accessibilityLabel("Reload repositories")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 8) {
                if let user = store.user {
                    Picker("Repository owner", selection: $store.selectedRepositoryOwner) {
                        Label("Personal", systemImage: "person")
                            .tag(user.login)

                        ForEach(store.repositoryOwners.filter {
                            $0.login.caseInsensitiveCompare(user.login) != .orderedSame
                        }) { owner in
                            Label(
                                owner.login,
                                systemImage: owner.isOrganization ? "building.2" : "person.2"
                            )
                            .tag(owner.login)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150, alignment: .leading)
                }

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)

                    TextField("Filter repositories", text: $store.repositorySearch)
                        .textFieldStyle(.plain)

                    if !store.repositorySearch.isEmpty {
                        Button {
                            store.repositorySearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                        .help("Clear repository filter")
                        .accessibilityLabel("Clear repository filter")
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.55))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 42)

            Divider()

            repositoryContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .settingsCard()
    }

    @ViewBuilder
    private var repositoryContent: some View {
        if store.repositories.isEmpty && store.isLoadingRepositories {
            ProgressView("Loading repositories…")
                .controlSize(.small)
        } else if store.filteredRepositories.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: store.repositorySearch.isEmpty ? "shippingbox" : "magnifyingglass")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(store.repositorySearch.isEmpty ? "No repositories available" : "No matching repositories")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.filteredRepositories) { repository in
                        repositoryRow(repository)

                        if repository.id != store.filteredRepositories.last?.id {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func repositoryRow(_ repository: GitHubRepository) -> some View {
        let isMonitored = store.selectedRepositoryIDs.contains(repository.id)

        return Button {
            store.setRepository(repository, selected: !isMonitored)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isMonitored ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isMonitored ? Color.accentColor : Color.secondary.opacity(0.45))
                    .frame(width: 18)

                Image(systemName: repository.isPrivate ? "lock.fill" : "shippingbox")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(repository.shortName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                Spacer()

                Text(repository.defaultBranch)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isMonitored ? "Stop monitoring \(repository.shortName)" : "Monitor \(repository.shortName)"
        )
        .accessibilityValue(isMonitored ? "Monitored" : "Not monitored")
    }
}

private extension View {
    func settingsCard() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
