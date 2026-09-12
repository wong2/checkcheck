import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GeometryReader { geometry in
            Form {
                Section("GitHub Account") {
                    AccountSettingsView()
                }
                if store.isConnected {
                    Section("Repositories") {
                        RepositorySettingsView()
                            .frame(height: max(200, geometry.size.height - 350))
                    }
                }
                Section("General") {
                    LaunchAtLoginSettingsView()
                    if store.isConnected {
                        NotificationSettingsView()
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 620, idealWidth: 640, maxWidth: 800)
        .frame(minHeight: store.isConnected ? 580 : 360, idealHeight: store.isConnected ? 660 : 390)
        .navigationTitle("CheckCheck Settings")
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

private struct AccountSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var token = ""

    var body: some View {
        if store.isConnected {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connected as @\(store.user?.login ?? "GitHub")")
                    Text("Token stored in Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Disconnect", role: .destructive) { store.disconnect() }
            }
            .accessibilityElement(children: .contain)
        } else {
            Text("Connect GitHub, then choose the repositories to monitor.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                SecureField("Personal Access Token", text: $token, prompt: Text("ghp_…"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
                Button {
                    connect()
                } label: {
                    HStack(spacing: 6) {
                        if store.isConnecting { ProgressView().controlSize(.small) }
                        Text(store.isConnecting ? "Connecting…" : "Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isConnecting)
            }
            Text("Use a classic token. Private repositories require the repo scope.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("Create Token on GitHub…", destination: URL(
                string: "https://github.com/settings/tokens/new?scopes=repo&description=CheckCheck%20for%20macOS"
            )!)
        }
        if let error = store.accountError {
            SettingsError(message: error)
        }
    }

    private func connect() {
        Task {
            if await store.connect(token: token) { token = "" }
        }
    }
}

private struct LaunchAtLoginSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { store.launchAtLoginStatus == .enabled },
            set: { store.setLaunchAtLogin($0) }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear { store.refreshLaunchAtLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshLaunchAtLoginStatus()
        }

        if store.launchAtLoginStatus == .requiresApproval {
            LabeledContent {
                Button("Open Login Items…") { store.openLoginItemsSettings() }
            } label: {
                Text("Allow CheckCheck in Login Items to enable automatic launch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        if let error = store.launchAtLoginError {
            SettingsError(message: error)
        }
    }
}

private struct NotificationSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        LabeledContent {
            if store.notificationPermission == .unknown {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Checking notification permission")
            } else {
                Button("Open Notification Settings…") { store.openNotificationSettings() }
            }
        } label: {
            Text("Notifications")
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await store.refreshNotificationPermission() }
    }

    private var statusText: String {
        switch store.notificationPermission {
        case .unknown: "Checking permission…"
        case .enabled: "Enabled"
        case .disabled: "Disabled in System Settings"
        }
    }
}

private struct RepositorySettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Choose repositories to monitor.")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.selectedRepositoryCount) monitored")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await store.reloadRepositories() }
                } label: {
                    Group {
                        if store.isLoadingRepositories { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(store.isLoadingRepositories)
                .help("Reload repositories")
                .accessibilityLabel("Reload repositories")
            }

            HStack(spacing: 10) {
                if let user = store.user {
                    Picker("Repository Owner", selection: $store.selectedRepositoryOwner) {
                        Text("All Owners").tag("")
                        Text(user.login).tag(user.login)
                        ForEach(store.repositoryOwners.filter {
                            $0.login.caseInsensitiveCompare(user.login) != .orderedSame
                        }) { owner in
                            Text(owner.login).tag(owner.login)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 160, alignment: .leading)
                }
                TextField("Filter Repositories", text: $store.repositorySearch, prompt: Text("Filter repositories"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                if !store.repositorySearch.isEmpty {
                    Button {
                        store.repositorySearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear repository filter")
                    .accessibilityLabel("Clear repository filter")
                }
            }

            if let error = store.repositoryError {
                SettingsError(message: error)
            }
            Divider()
            repositoryContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var repositoryContent: some View {
        if store.repositories.isEmpty && store.isLoadingRepositories {
            ProgressView("Loading repositories…").controlSize(.small)
        } else if store.repositories.isEmpty && store.repositoryError != nil {
            VStack(spacing: 8) {
                Text("Couldn’t Load Repositories")
                Button("Retry") { Task { await store.reloadRepositories() } }
                    .disabled(store.isLoadingRepositories)
            }
        } else if store.filteredRepositories.isEmpty {
            VStack(spacing: 8) {
                Text(store.repositorySearch.isEmpty ? "No Repositories Available" : "No Matching Repositories")
                Text("Try another owner or clear the filter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.filteredRepositories) { repository in
                        Toggle(isOn: Binding(
                            get: { store.selectedRepositoryIDs.contains(repository.id) },
                            set: { store.setRepository(repository, selected: $0) }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: repository.isPrivate ? "lock" : "shippingbox")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(repository.isPrivate ? "Private repository" : "Public repository")
                                Text(store.selectedRepositoryOwner.isEmpty ? repository.fullName : repository.shortName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .layoutPriority(1)
                                    .help(repository.fullName)
                                Spacer()
                                Text(repository.defaultBranch)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 140, alignment: .trailing)
                                    .help(repository.defaultBranch)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .frame(minHeight: 38)
                        .padding(.horizontal, 4)
                        .accessibilityLabel("Monitor \(repository.fullName)")
                        if repository.id != store.filteredRepositories.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

private struct SettingsError: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}
