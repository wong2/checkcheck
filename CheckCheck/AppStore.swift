import AppKit
import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var user: GitHubUser?
    @Published private(set) var repositories: [GitHubRepository] = []
    @Published private(set) var checks: [MonitoredCheck] = []
    @Published private(set) var isConnecting = false
    @Published private(set) var isLoadingRepositories = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var notificationPermission = NotificationPermission.unknown
    @Published var repositorySearch = ""
    @Published var selectedRepositoryOwner = ""
    @Published var selectedRepositoryIDs: Set<Int64> = [] {
        didSet {
            guard selectedRepositoryIDs != oldValue else { return }
            save(selectedRepositoryIDs, key: Keys.selectedRepositories)
            checks.removeAll { !selectedRepositoryIDs.contains($0.repositoryID) }
            Task { await refresh() }
        }
    }

    private enum Keys {
        static let repositories = "repositories"
        static let selectedRepositories = "selectedRepositories"
        static let checks = "checks"
        static let snapshots = "snapshots"
        static let baselineRepositories = "baselineRepositories"
        static let user = "user"
    }

    private let client = GitHubClient()
    private let notifications = NotificationService()
    private let defaults = UserDefaults.standard
    private var snapshots: [String: CheckSnapshot] = [:]
    private var baselineRepositoryIDs: Set<Int64> = []
    private var checkRunsByCommit: [String: [MonitoredCheck]] = [:]
    private var pollingTask: Task<Void, Never>?
    private let activePollingInterval: Duration = .seconds(10)
    private let idlePollingInterval: Duration = .seconds(60)
    private let commitsPerRepository = 5
    private let maximumVisibleChecks = 10

    var isConnected: Bool { KeychainStore.loadToken() != nil }
    var selectedRepositoryCount: Int { selectedRepositoryIDs.count }
    var hasRunningChecks: Bool { checks.contains { $0.phase == .running || $0.phase == .queued } }

    var hasFailures: Bool {
        checks.contains { $0.phase == .failure }
    }

    var allChecksPassed: Bool {
        !checks.isEmpty && checks.allSatisfy { $0.phase == .success || $0.phase == .skipped }
    }

    var menuBarSymbol: String {
        if isRefreshing { return "arrow.triangle.2.circlepath" }
        if hasFailures { return "exclamationmark.circle.fill" }
        if hasRunningChecks { return "circle.dotted.circle" }
        if allChecksPassed { return "checkmark.circle" }
        if !checks.isEmpty { return "minus.circle" }
        return "circle.dotted"
    }

    var menuBarAccessibilityLabel: String {
        if hasFailures { return "CheckCheck, checks failed" }
        if hasRunningChecks { return "CheckCheck, checks running" }
        if allChecksPassed { return "CheckCheck, checks passed" }
        if !checks.isEmpty { return "CheckCheck, checks completed" }
        return "CheckCheck, idle"
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

    init() {
        repositories = load([GitHubRepository].self, key: Keys.repositories) ?? []
        selectedRepositoryIDs = load(Set<Int64>.self, key: Keys.selectedRepositories) ?? []
        checks = load([MonitoredCheck].self, key: Keys.checks) ?? []
        for check in checks {
            guard let headSHA = check.headSHA else { continue }
            checkRunsByCommit["\(check.repositoryID):\(headSHA)", default: []].append(check)
        }
        snapshots = load([String: CheckSnapshot].self, key: Keys.snapshots) ?? [:]
        baselineRepositoryIDs = load(Set<Int64>.self, key: Keys.baselineRepositories) ?? []
        user = load(GitHubUser.self, key: Keys.user)
        selectedRepositoryOwner = user?.login ?? ""

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
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Enter a GitHub token."
            return false
        }

        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let newUser = try await client.user(token: token)
            try KeychainStore.save(token: token)
            user = newUser
            selectedRepositoryOwner = newUser.login
            save(newUser, key: Keys.user)
            notificationPermission = await notifications.prepareAuthorization()
            Task { await reloadRepositories() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func disconnect() {
        do {
            try KeychainStore.deleteToken()
            user = nil
            repositories = []
            selectedRepositoryOwner = ""
            selectedRepositoryIDs = []
            checks = []
            snapshots = [:]
            baselineRepositoryIDs = []
            [Keys.user, Keys.repositories, Keys.checks, Keys.snapshots, Keys.baselineRepositories]
                .forEach(defaults.removeObject(forKey:))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadRepositories() async {
        guard !isLoadingRepositories,
              let token = KeychainStore.loadToken() else { return }
        isLoadingRepositories = true
        errorMessage = nil
        defer { isLoadingRepositories = false }

        do {
            repositories = try await client.repositories(token: token)
            if selectedRepositoryOwner.isEmpty
                || !repositories.contains(where: {
                    $0.owner.login.caseInsensitiveCompare(selectedRepositoryOwner) == .orderedSame
                }) {
                selectedRepositoryOwner = user?.login ?? repositoryOwners.first?.login ?? ""
            }
            save(repositories, key: Keys.repositories)
        } catch {
            errorMessage = error.localizedDescription
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
        guard !isRefreshing,
              let token = KeychainStore.loadToken(),
              !selectedRepositoryIDs.isEmpty else { return }

        let selected = repositories.filter { selectedRepositoryIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        var refreshedChecks: [MonitoredCheck] = []
        var commitSHAsNewestFirstByRepository: [Int64: [String]] = [:]
        var failures: [String] = []
        var successfulRefreshes = 0

        for repository in selected {
            do {
                let commits = try await client.commits(
                    repository: repository,
                    limit: commitsPerRepository,
                    token: token
                )
                commitSHAsNewestFirstByRepository[repository.id] = commits.map(\.sha)
                let validKeys = Set(commits.map { "\(repository.id):\($0.sha)" })
                checkRunsByCommit = checkRunsByCommit.filter {
                    !$0.key.hasPrefix("\(repository.id):") || validKeys.contains($0.key)
                }

                let headSHA = commits.first?.sha
                let shasToRefresh = commits.compactMap { commit -> String? in
                    let cachedRuns = checkRunsByCommit["\(repository.id):\(commit.sha)"]
                    guard commit.sha == headSHA
                            || cachedRuns == nil
                            || cachedRuns?.contains(where: { !$0.phase.isCompleted }) == true else {
                        return nil
                    }
                    return commit.sha
                }
                let refreshedRunsBySHA = await client.checkRuns(
                    repository: repository,
                    shas: shasToRefresh,
                    token: token
                )

                for commit in commits {
                    let key = "\(repository.id):\(commit.sha)"
                    guard let runs = refreshedRunsBySHA[commit.sha] else { continue }
                    let previousChecks = Dictionary(
                        uniqueKeysWithValues: (checkRunsByCommit[key] ?? []).map { ($0.runID, $0) }
                    )
                    checkRunsByCommit[key] = runs.map {
                        MonitoredCheck(
                            run: $0,
                            repository: repository,
                            commitMessage: commit.subject,
                            previous: previousChecks[$0.id]
                        )
                    }
                }

                let repositoryChecks = commits.flatMap {
                    checkRunsByCommit["\(repository.id):\($0.sha)"] ?? []
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
                for event in events {
                    notificationPermission = await notifications.send(event: event)
                }

                snapshots = snapshots.filter { !$0.key.hasPrefix("\(repository.id):") }
                repositoryChecks.forEach { snapshots[$0.id] = CheckSnapshot(phase: $0.phase) }
                baselineRepositoryIDs.insert(repository.id)
                refreshedChecks.append(contentsOf: repositoryChecks)
                successfulRefreshes += 1
            } catch {
                refreshedChecks.append(contentsOf: checks.filter { $0.repositoryID == repository.id })
                if commitSHAsNewestFirstByRepository[repository.id] == nil {
                    commitSHAsNewestFirstByRepository[repository.id] = checks
                        .filter { $0.repositoryID == repository.id }
                        .compactMap(\.headSHA)
                }
                failures.append("\(repository.shortName): \(error.localizedDescription)")
            }
        }

        checks = VisibleCheckSelector.visibleChecks(
            from: refreshedChecks,
            commitSHAsNewestFirstByRepository: commitSHAsNewestFirstByRepository,
            limit: maximumVisibleChecks
        )
        if successfulRefreshes > 0 {
            lastRefresh = .now
        }
        errorMessage = failures.first
        save(checks, key: Keys.checks)
        save(snapshots, key: Keys.snapshots)
        save(baselineRepositoryIDs, key: Keys.baselineRepositories)
    }

    func open(_ check: MonitoredCheck) {
        NSWorkspace.shared.open(check.url)
    }

    func refreshNotificationPermission() async {
        notificationPermission = await notifications.prepareAuthorization()
    }

    func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
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
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
