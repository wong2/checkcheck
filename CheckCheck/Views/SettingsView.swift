import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView(selection: $store.selectedSettingsTab) {
            AccountSettingsView()
                .environmentObject(store)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(SettingsTab.account)

            RepositorySettingsView()
                .environmentObject(store)
                .tabItem { Label("Repositories", systemImage: "shippingbox") }
                .tag(SettingsTab.repositories)
        }
        .frame(width: 620, height: settingsHeight)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var settingsHeight: CGFloat {
        switch store.selectedSettingsTab {
        case .account:
            if store.errorMessage != nil { return 350 }
            return store.isConnected ? 240 : 280
        case .repositories:
            return 500
        }
    }
}

enum SettingsTab {
    case account
    case repositories
}

private struct AccountSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var token = ""

    private let tokenCreationURL = URL(
        string: "https://github.com/settings/tokens/new?scopes=repo&description=CheckCheck%20for%20macOS"
    )!

    var body: some View {
        Form {
            Section("GitHub account") {
                if let user = store.user, store.isConnected {
                    LabeledContent("Signed in as") {
                        Text("@\(user.login)")
                            .fontWeight(.medium)
                    }

                    LabeledContent("Token") {
                        Label("Stored in Keychain", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Notifications") {
                        switch store.notificationPermission {
                        case .unknown:
                            ProgressView()
                                .controlSize(.small)
                        case .enabled:
                            Label("Enabled", systemImage: "bell.fill")
                                .foregroundStyle(.secondary)
                        case .disabled:
                            Button("Open Notification Settings") {
                                store.openNotificationSettings()
                            }
                        }
                    }

                    Button("Disconnect", role: .destructive) {
                        store.disconnect()
                    }
                } else {
                    HStack {
                        Text("Personal access token")
                        Spacer()
                        SecureField("Personal access token", text: $token, prompt: Text("ghp_…"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                            .onSubmit(connect)
                    }

                    Text("Use a classic token with the repo scope to monitor private repositories. Public repositories do not require a scope.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        Link(destination: tokenCreationURL) {
                            Label("Create token on GitHub", systemImage: "arrow.up.right.square")
                        }
                        Spacer()
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
                            .frame(minWidth: 76)
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isConnecting)
                    }
                }
            }

            if let error = store.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(10)
        .task {
            await store.refreshNotificationPermission()
        }
    }

    private func connect() {
        Task {
            if await store.connect(token: token) {
                token = ""
            }
        }
    }
}

private struct RepositorySettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            if store.isConnected {
                HStack(spacing: 10) {
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
                        .fixedSize()

                        Divider()
                            .frame(height: 18)
                    }

                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
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
                        .accessibilityLabel("Clear repository filter")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            if !store.isConnected {
                ContentUnavailableView(
                    "Connect GitHub first",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Add a token in Account settings before choosing repositories.")
                )
            } else if store.repositories.isEmpty && store.isLoadingRepositories {
                ProgressView("Loading repositories…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.filteredRepositories.isEmpty && store.repositorySearch.isEmpty {
                ContentUnavailableView(
                    "No repositories",
                    systemImage: "shippingbox",
                    description: Text("No repositories are available for this owner.")
                )
            } else if store.filteredRepositories.isEmpty {
                ContentUnavailableView.search(text: store.repositorySearch)
            } else {
                List(store.filteredRepositories) { repository in
                    let isMonitored = store.selectedRepositoryIDs.contains(repository.id)

                    HStack(spacing: 8) {
                        Button {
                            store.setRepository(repository, selected: !isMonitored)
                        } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isMonitored ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isMonitored ? "Stop monitoring \(repository.shortName)" : "Monitor \(repository.shortName)")
                        .accessibilityLabel(
                            isMonitored ? "Stop monitoring \(repository.shortName)" : "Monitor \(repository.shortName)"
                        )

                        Image(systemName: repository.isPrivate ? "lock.fill" : "shippingbox")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(repository.shortName)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Text(repository.defaultBranch)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text("\(store.selectedRepositoryCount) monitored")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await store.reloadRepositories() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(!store.isConnected || store.isLoadingRepositories)
            }
            .font(.callout)
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
