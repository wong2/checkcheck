import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppStore: ObservableObject {
    #if CHECKCHECK_QA
    @Published private(set) var qaLastAction = "No check opened"
    #endif
    @Published private(set) var user: GitHubUser?
    @Published private(set) var repositories: [GitHubRepository] = []
    @Published private(set) var checks: [MonitoredCheck] = []
    @Published private(set) var isConnecting = false
    @Published private(set) var isLoadingRepositories = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var repositorySyncDates: [Int64: Date] = [:]
    @Published private(set) var syncIssues: [RepositorySyncIssue] = []
    @Published private(set) var accountError: String?
    @Published private(set) var repositoryError: String?
    @Published private(set) var notificationPermission = NotificationPermission.unknown
    @Published private(set) var launchAtLoginStatus = SMAppService.mainApp.status
    @Published private(set) var launchAtLoginError: String?
    @Published var repositorySearch = ""
    @Published var selectedRepositoryOwner = ""
    @Published var selectedRepositoryIDs: Set<Int64> = [] {
        didSet {
            guard selectedRepositoryIDs != oldValue else { return }
            refreshGeneration += 1
            syncIssues.removeAll { !selectedRepositoryIDs.contains($0.repositoryID) }
            repositorySyncDates = repositorySyncDates.filter { selectedRepositoryIDs.contains($0.key) }
            save(repositorySyncDates, key: Keys.repositorySyncDates)
            save(selectedRepositoryIDs, key: Keys.selectedRepositories)
            checks.removeAll { !selectedRepositoryIDs.contains($0.repositoryID) }
            if automaticallyStart && !isPreview { Task { await refresh() } }
        }
    }

    private enum Keys {
        static let repositories = "repositories"
        static let selectedRepositories = "selectedRepositories"
        static let checks = "checks"
        static let repositorySyncDates = "repositorySyncDates"
        static let snapshots = "snapshots"
        static let baselineRepositories = "baselineRepositories"
        static let user = "user"
        static let launchAtLoginInitialized = "launchAtLoginInitialized"
    }

    private let client: GitHubClient
    private let notifications = NotificationService()
    private let defaults: UserDefaults
    let isPreview: Bool
    private let automaticallyStart: Bool
    private let tokenProvider: () -> String?
    private var refreshGeneration = 0
    private var accountGeneration = 0
    private var snapshots: [String: CheckSnapshot] = [:]
    private var baselineRepositoryIDs: Set<Int64> = []
    private var checksByCommit: [String: [MonitoredCheck]] = [:]
    private var fullyFetchedCommitKeys: Set<String> = []
    private var pollingTask: Task<Void, Never>?
    private let activePollingInterval: Duration = .seconds(10)
    private let idlePollingInterval: Duration = .seconds(60)
    private let commitsPerRepository = 5
    private let maximumVisibleChecks = 10

    var isConnected: Bool { isPreview ? user != nil : tokenProvider() != nil }

    var lastRefresh: Date? {
        guard !selectedRepositoryIDs.isEmpty,
              selectedRepositoryIDs.allSatisfy({ repositorySyncDates[$0] != nil }) else { return nil }
        return selectedRepositoryIDs.compactMap { repositorySyncDates[$0] }.min()
    }

    var canRefresh: Bool { isConnected && selectedRepositoryCount > 0 && !isRefreshing }

    func repositoryDisplayName(for check: MonitoredCheck) -> String {
        CheckPresentation.repositoryName(for: check, among: checks)
    }

    var selectedRepositoryCount: Int { selectedRepositoryIDs.count }
    var hasRunningChecks: Bool { checks.contains { $0.phase == .running || $0.phase == .queued } }

    var hasFailures: Bool {
        checks.contains { $0.phase == .failure }
    }

    var allChecksPassed: Bool {
        !checks.isEmpty && checks.allSatisfy { $0.phase == .success || $0.phase == .skipped }
    }

    var menuBarSymbol: String {
        CheckPresentation.menuBarSymbol(checks: checks, hasSyncIssues: !syncIssues.isEmpty)
    }

    var menuBarAccessibilityLabel: String {
        var description = "CheckCheck, "
        if hasFailures { description += "checks failed" }
        else if hasRunningChecks { description += "checks running" }
        else if allChecksPassed { description += "checks passed" }
        else if !checks.isEmpty { description += "checks completed" }
        else { description += "idle" }
        if !syncIssues.isEmpty { description += ", sync incomplete, results may be out of date" }
        return description
    }

    var filteredRepositories: [GitHubRepository] {
        repositories
            .filter { repository in
                (selectedRepositoryOwner.isEmpty
                    || repository.owner.login.caseInsensitiveCompare(selectedRepositoryOwner) == .orderedSame)
                    && (repositorySearch.isEmpty
                        || repository.fullName.localizedCaseInsensitiveContains(repositorySearch))
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
    }

    var repositoryOwners: [GitHubRepositoryOwner] {
        let owners = Dictionary(
            repositories.map { ($0.owner.id, $0.owner) },
            uniquingKeysWith: { first, _ in first }
        ).values
        let personalLogin = user?.login

        return owners.sorted { lhs, rhs in
            let lhsRank = lhs.login.caseInsensitiveCompare(personalLogin ?? "") == .orderedSame
                ? 0 : (lhs.isOrganization ? 1 : 2)
            let rhsRank = rhs.login.caseInsensitiveCompare(personalLogin ?? "") == .orderedSame
                ? 0 : (rhs.isOrganization ? 1 : 2)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.login.localizedCaseInsensitiveCompare(rhs.login) == .orderedAscending
        }
    }

    init(
        isPreview: Bool = false,
        defaults: UserDefaults = .standard,
        client: GitHubClient = GitHubClient(),
        automaticallyStart: Bool = true,
        tokenProvider: @escaping () -> String? = KeychainStore.loadToken
    ) {
        self.isPreview = isPreview
        self.defaults = defaults
        self.client = client
        self.automaticallyStart = automaticallyStart
        self.tokenProvider = tokenProvider
        guard !isPreview else { return }
        repositorySyncDates = load([Int64: Date].self, key: Keys.repositorySyncDates) ?? [:]
        repositories = load([GitHubRepository].self, key: Keys.repositories) ?? []
        selectedRepositoryIDs = load(Set<Int64>.self, key: Keys.selectedRepositories) ?? []
        checks = load([MonitoredCheck].self, key: Keys.checks) ?? []
        for check in checks {
            guard let headSHA = check.headSHA else { continue }
            checksByCommit["\(check.repositoryID):\(headSHA)", default: []].append(check)
        }
        snapshots = load([String: CheckSnapshot].self, key: Keys.snapshots) ?? [:]
        baselineRepositoryIDs = load(Set<Int64>.self, key: Keys.baselineRepositories) ?? []
        user = load(GitHubUser.self, key: Keys.user)
        selectedRepositoryOwner = user?.login ?? ""

        guard automaticallyStart else { return }

        // Register only once so a later change in System Settings is respected.
        if !defaults.bool(forKey: Keys.launchAtLoginInitialized) {
            defaults.set(true, forKey: Keys.launchAtLoginInitialized)
            if launchAtLoginStatus == .notRegistered {
                setLaunchAtLogin(true)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            self.notificationPermission = await self.notifications.prepareAuthorization()
        }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.reloadRepositories()
            await self.startPolling()
        }
    }

    deinit {
        pollingTask?.cancel()
    }

    func connect(token rawToken: String) async -> Bool {
        guard !isPreview, !isConnecting else { return false }
        let generation = accountGeneration
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            accountError = "Enter a GitHub token."
            return false
        }

        isConnecting = true
        accountError = nil
        defer { isConnecting = false }

        do {
            let newUser = try await client.user(token: token)
            guard generation == accountGeneration else { return false }
            try KeychainStore.save(token: token)
            user = newUser
            selectedRepositoryOwner = newUser.login
            save(newUser, key: Keys.user)
            notificationPermission = await notifications.prepareAuthorization()
            Task { await reloadRepositories() }
            return true
        } catch {
            guard generation == accountGeneration else { return false }
            accountError = error.localizedDescription
            return false
        }
    }

    func disconnect() {
        guard !isPreview else { return }
        do {
            try KeychainStore.deleteToken()
            accountGeneration += 1
            refreshGeneration += 1
            syncIssues = []
            repositoryError = nil
            repositorySyncDates = [:]
            checksByCommit = [:]
            fullyFetchedCommitKeys = []
            user = nil
            repositories = []
            selectedRepositoryOwner = ""
            selectedRepositoryIDs = []
            checks = []
            snapshots = [:]
            baselineRepositoryIDs = []
            [Keys.user, Keys.repositories, Keys.checks, Keys.snapshots, Keys.baselineRepositories, Keys.repositorySyncDates]
                .forEach(defaults.removeObject(forKey:))
            accountError = nil
        } catch {
            accountError = error.localizedDescription
        }
    }

    func reloadRepositories() async {
        guard !isPreview, !isLoadingRepositories,
              let token = tokenProvider() else { return }
        let generation = accountGeneration
        isLoadingRepositories = true
        repositoryError = nil
        defer { isLoadingRepositories = false }

        do {
            let loaded = try await client.repositories(token: token)
            guard generation == accountGeneration else { return }
            repositories = loaded
            if !selectedRepositoryOwner.isEmpty && !repositories.contains(where: {
                    $0.owner.login.caseInsensitiveCompare(selectedRepositoryOwner) == .orderedSame
                }) {
                selectedRepositoryOwner = user?.login ?? repositoryOwners.first?.login ?? ""
            }
            save(repositories, key: Keys.repositories)
        } catch {
            guard generation == accountGeneration else { return }
            repositoryError = error.localizedDescription
        }
    }

    func setRepository(_ repository: GitHubRepository, selected: Bool) {
        if selected {
            selectedRepositoryIDs.insert(repository.id)
        } else {
            selectedRepositoryIDs.remove(repository.id)
        }
    }

    func refresh() async {
        guard !isPreview, !isRefreshing,
              let token = tokenProvider(),
              !selectedRepositoryIDs.isEmpty else { return }

        let selected = repositories.filter { selectedRepositoryIDs.contains($0.id) }
        let generation = refreshGeneration
        isRefreshing = true
        // Keep the last error visible until a retry actually succeeds.
        defer {
            isRefreshing = false
            if generation != refreshGeneration, isConnected {
                Task { await refresh() }
            }
        }

        let unavailableIDs = selectedRepositoryIDs.subtracting(Set(selected.map(\.id)))
        var refreshedChecks = checks.filter { unavailableIDs.contains($0.repositoryID) }
        var commitSHAsNewestFirstByRepository: [Int64: [String]] = [:]
        var failures = unavailableIDs.map { id in
            RepositorySyncIssue(repositoryID: id, repositoryName: checks.first { $0.repositoryID == id }?.repositoryName ?? "Repository \(id)",
                                message: "Repository unavailable. Reload repositories in Settings.")
        }

        for repository in selected {
            do {
                let commits = try await client.commits(
                    repository: repository,
                    limit: commitsPerRepository,
                    token: token
                )
                guard generation == refreshGeneration else { return }
                commitSHAsNewestFirstByRepository[repository.id] = commits.map(\.sha)
                let validKeys = Set(commits.map { "\(repository.id):\($0.sha)" })
                checksByCommit = checksByCommit.filter {
                    !$0.key.hasPrefix("\(repository.id):") || validKeys.contains($0.key)
                }

                fullyFetchedCommitKeys = fullyFetchedCommitKeys.filter {
                    !$0.hasPrefix("\(repository.id):") || validKeys.contains($0)
                }
                let headSHA = commits.first?.sha
                let shasToRefresh = commits.compactMap { commit -> String? in
                    let cachedChecks = checksByCommit["\(repository.id):\(commit.sha)"]
                    guard commit.sha == headSHA
                            || !fullyFetchedCommitKeys.contains("\(repository.id):\(commit.sha)")
                            || cachedChecks == nil
                            || cachedChecks?.contains(where: { !$0.phase.isCompleted }) == true else {
                        return nil
                    }
                    return commit.sha
                }
                async let refreshedRunsBySHA = client.checkRuns(
                    repository: repository,
                    shas: shasToRefresh,
                    token: token
                )
                async let refreshedStatusesBySHA = client.commitStatuses(
                    repository: repository,
                    shas: shasToRefresh,
                    token: token
                )
                let (runsBySHA, statusesBySHA) = await (
                    refreshedRunsBySHA,
                    refreshedStatusesBySHA
                )

                guard generation == refreshGeneration else { return }
                let incomplete = shasToRefresh.contains { runsBySHA[$0] == nil || statusesBySHA[$0] == nil }
                if incomplete {
                    failures.append(RepositorySyncIssue(
                        repositoryID: repository.id,
                        repositoryName: repository.fullName,
                        message: "Some checks could not be fetched. Previous results are retained; try again."
                    ))
                }

                for commit in commits {
                    let key = "\(repository.id):\(commit.sha)"
                    let previousChecks = checksByCommit[key] ?? []
                    guard runsBySHA[commit.sha] != nil || statusesBySHA[commit.sha] != nil else {
                        continue
                    }

                    var refreshedCommitChecks: [MonitoredCheck] = []
                    if let runs = runsBySHA[commit.sha] {
                        let previousRuns = Dictionary(
                            uniqueKeysWithValues: previousChecks
                                .filter { $0.sourceKey == nil }
                                .map { ($0.runID, $0) }
                        )
                        refreshedCommitChecks.append(contentsOf: runs.map {
                            MonitoredCheck(
                                run: $0,
                                repository: repository,
                                commitMessage: commit.subject,
                                previous: previousRuns[$0.id]
                            )
                        })
                    } else {
                        refreshedCommitChecks.append(contentsOf: previousChecks.filter { $0.sourceKey == nil })
                    }

                    if let statuses = statusesBySHA[commit.sha] {
                        let previousStatuses = Dictionary(
                            uniqueKeysWithValues: previousChecks.compactMap { check in
                                check.sourceKey.map { ($0, check) }
                            }
                        )
                        refreshedCommitChecks.append(contentsOf: statuses.map { status in
                            let sourceKey = MonitoredCheck.commitStatusSourceKey(
                                headSHA: commit.sha,
                                context: status.context
                            )
                            return MonitoredCheck(
                                status: status,
                                repository: repository,
                                headSHA: commit.sha,
                                commitMessage: commit.subject,
                                previous: previousStatuses[sourceKey]
                            )
                        })
                    } else {
                        refreshedCommitChecks.append(contentsOf: previousChecks.filter { $0.sourceKey != nil })
                    }

                    checksByCommit[key] = refreshedCommitChecks
                    if runsBySHA[commit.sha] != nil && statusesBySHA[commit.sha] != nil {
                        fullyFetchedCommitKeys.insert(key)
                    } else {
                        fullyFetchedCommitKeys.remove(key)
                    }
                }

                let repositoryChecks = commits.flatMap {
                    checksByCommit["\(repository.id):\($0.sha)"] ?? []
                }
                let suppress = !baselineRepositoryIDs.contains(repository.id)
                let recentThreshold = Date.now.addingTimeInterval(-300)
                let notificationChecks = repositoryChecks.filter {
                    snapshots[$0.id] != nil || $0.updatedAt > recentThreshold
                }
                let events = StatusChangeDetector.events(
                    previous: snapshots,
                    current: notificationChecks,
                    suppressNotifications: suppress
                )
                for event in events where automaticallyStart {
                    notificationPermission = await notifications.send(event: event)
                    guard generation == refreshGeneration else { return }
                }

                snapshots = snapshots.filter { !$0.key.hasPrefix("\(repository.id):") }
                repositoryChecks.forEach { snapshots[$0.id] = CheckSnapshot(phase: $0.phase) }
                baselineRepositoryIDs.insert(repository.id)
                refreshedChecks.append(contentsOf: repositoryChecks)
                if !incomplete { repositorySyncDates[repository.id] = .now }
            } catch {
                guard generation == refreshGeneration else { return }
                refreshedChecks.append(contentsOf: checks.filter { $0.repositoryID == repository.id })
                if commitSHAsNewestFirstByRepository[repository.id] == nil {
                    commitSHAsNewestFirstByRepository[repository.id] = checks
                        .filter { $0.repositoryID == repository.id }
                        .compactMap(\.headSHA)
                }
                failures.append(RepositorySyncIssue(repositoryID: repository.id, repositoryName: repository.fullName,
                                                    message: error.localizedDescription))
            }
        }

        checks = VisibleCheckSelector.visibleChecks(
            from: refreshedChecks,
            commitSHAsNewestFirstByRepository: commitSHAsNewestFirstByRepository,
            limit: maximumVisibleChecks
        )
        syncIssues = failures.sorted { $0.repositoryName < $1.repositoryName }
        save(repositorySyncDates, key: Keys.repositorySyncDates)
        save(checks, key: Keys.checks)
        save(snapshots, key: Keys.snapshots)
        save(baselineRepositoryIDs, key: Keys.baselineRepositories)
    }

    func open(_ check: MonitoredCheck) {
        #if CHECKCHECK_QA
        if isPreview { qaLastAction = "Opened " + check.repositoryName + ": " + check.name; return }
        #endif
        NSWorkspace.shared.open(check.url)
    }

    func refreshNotificationPermission() async {
        guard !isPreview else { return }
        notificationPermission = await notifications.prepareAuthorization()
    }

    func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshLaunchAtLoginStatus() {
        guard !isPreview else { return }
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isPreview else { return }
        launchAtLoginError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = "Could not update launch at login: \(error.localizedDescription)"
        }
        refreshLaunchAtLoginStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func startPolling() async {
        await refresh()
        while !Task.isCancelled {
            let interval = hasRunningChecks ? activePollingInterval : idlePollingInterval
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard !isPreview, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

#if CHECKCHECK_QA
extension AppStore {
    func showQAState(_ state: String) {
        user = state == "Disconnected" || state == "Account Error" ? nil : GitHubUser(login: "octocat", avatarURL: nil)
        repositories = [
            GitHubRepository(id: 1, fullName: "octocat/checkcheck", defaultBranch: "main", isPrivate: false,
                             htmlURL: URL(string: "https://github.com/octocat/checkcheck")!),
            GitHubRepository(id: 2, fullName: "team/checkcheck", defaultBranch: "release/very-long-branch-name", isPrivate: true,
                             htmlURL: URL(string: "https://github.com/team/checkcheck")!),
            GitHubRepository(id: 3, fullName: "octocat/a-repository-with-a-very-long-name-for-accessibility-validation", defaultBranch: "main", isPrivate: false,
                             htmlURL: URL(string: "https://github.com/octocat/example")!)
        ]
        selectedRepositoryOwner = ""
        selectedRepositoryIDs = state == "No Repositories" || user == nil ? [] : [1, 2, 3]
        checks = []
        repositorySyncDates = [:]
        syncIssues = []
        accountError = state == "Account Error" ? "The token is invalid or expired. Create a new token on GitHub and connect again." : nil
        repositoryError = state == "Repository Error" ? "Repositories couldn’t be loaded. Check your connection and retry." : nil
        notificationPermission = .enabled
        isRefreshing = state == "Loading" || state == "Refreshing"
        if ["Connected", "Refreshing", "Partial Failure", "Cached Failure"].contains(state) {
            checks = repositories.enumerated().map { index, repository in
                MonitoredCheck(run: GitHubCheckRun(
                    id: Int64(index + 1), name: index == 0 ? "Build and Test / macOS (arm64, Release)" : "Deploy Production",
                    status: index == 1 ? "in_progress" : "completed", conclusion: index == 0 ? "failure" : "success",
                    htmlURL: repository.htmlURL, detailsURL: nil, startedAt: .now.addingTimeInterval(-120),
                    completedAt: .now.addingTimeInterval(-60), headSHA: "abc123", app: nil
                ), repository: repository, commitMessage: "Improve sync feedback and keyboard navigation for every check")
            }
        }
        if ["Connected", "Refreshing", "Empty", "Partial Failure", "Cached Failure"].contains(state) {
            repositorySyncDates = [1: .now.addingTimeInterval(-30), 2: .now.addingTimeInterval(-30), 3: .now.addingTimeInterval(-30)]
        }
        if ["First Failure", "Partial Failure", "Cached Failure"].contains(state) {
            syncIssues = [RepositorySyncIssue(repositoryID: 2, repositoryName: "team/checkcheck",
                message: "GitHub API rate limit exceeded. Try again after the rate limit resets, or check the token’s access to this repository.")]
            repositorySyncDates[2] = state == "First Failure" ? nil : .now.addingTimeInterval(-3600)
        }
    }
}
#endif
