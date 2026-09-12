import Foundation

struct GitHubRepository: Codable, Identifiable, Hashable, Sendable {
    let id: Int64
    let fullName: String
    let defaultBranch: String
    let isPrivate: Bool
    let htmlURL: URL
    let owner: GitHubRepositoryOwner
    let updatedAt: Date

    init(
        id: Int64,
        fullName: String,
        defaultBranch: String,
        isPrivate: Bool,
        htmlURL: URL,
        owner: GitHubRepositoryOwner? = nil,
        updatedAt: Date = .distantPast
    ) {
        self.id = id
        self.fullName = fullName
        self.defaultBranch = defaultBranch
        self.isPrivate = isPrivate
        self.htmlURL = htmlURL
        self.owner = owner ?? GitHubRepositoryOwner(
            login: fullName.split(separator: "/").first.map(String.init) ?? fullName,
            kind: "User"
        )
        self.updatedAt = updatedAt
    }

    var shortName: String {
        fullName.split(separator: "/").last.map(String.init) ?? fullName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case defaultBranch = "default_branch"
        case isPrivate = "private"
        case htmlURL = "html_url"
        case owner
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        fullName = try container.decode(String.self, forKey: .fullName)
        defaultBranch = try container.decode(String.self, forKey: .defaultBranch)
        isPrivate = try container.decode(Bool.self, forKey: .isPrivate)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        owner = try container.decodeIfPresent(GitHubRepositoryOwner.self, forKey: .owner)
            ?? GitHubRepositoryOwner(
                login: fullName.split(separator: "/").first.map(String.init) ?? fullName,
                kind: "User"
            )
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

struct GitHubRepositoryOwner: Codable, Identifiable, Hashable, Sendable {
    let login: String
    let kind: String

    var id: String { login.lowercased() }
    var isOrganization: Bool { kind == "Organization" }

    enum CodingKeys: String, CodingKey {
        case login
        case kind = "type"
    }
}

struct GitHubUser: Codable, Sendable {
    let login: String
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
    }
}

struct CheckRunsResponse: Decodable, Sendable {
    let checkRuns: [GitHubCheckRun]

    enum CodingKeys: String, CodingKey {
        case checkRuns = "check_runs"
    }
}

struct GitHubCheckRun: Decodable, Sendable {
    let id: Int64
    let name: String
    let status: String
    let conclusion: String?
    let htmlURL: URL?
    let detailsURL: URL?
    let startedAt: Date?
    let completedAt: Date?
    let headSHA: String?
    let app: GitHubCheckApp?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, app
        case htmlURL = "html_url"
        case detailsURL = "details_url"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case headSHA = "head_sha"
    }
}

struct GitHubCheckApp: Decodable, Sendable {
    let name: String
}

struct GitHubCommitStatusesResponse: Decodable, Sendable {
    let statuses: [GitHubCommitStatus]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case statuses
        case totalCount = "total_count"
    }
}

struct GitHubCommitStatus: Decodable, Sendable {
    let id: Int64
    let state: String
    let description: String?
    let targetURL: URL?
    let context: String
    let createdAt: Date
    let updatedAt: Date
    let creator: GitHubStatusCreator?

    enum CodingKeys: String, CodingKey {
        case id, state, description, context, creator
        case targetURL = "target_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct GitHubStatusCreator: Decodable, Sendable {
    let login: String
}

struct GitHubCommit: Decodable, Sendable {
    let sha: String
    let commit: Details

    struct Details: Decodable, Sendable {
        let message: String
    }

    var subject: String {
        commit.message.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? commit.message
    }
}

enum CheckPhase: String, Codable, Sendable {
    case queued
    case running
    case success
    case failure
    case neutral
    case skipped
    case cancelled
    case unknown

    var isCompleted: Bool {
        ![.queued, .running, .unknown].contains(self)
    }

    var notificationVerb: String {
        switch self {
        case .queued: "Queued"
        case .running: "Started"
        case .success: "Passed"
        case .failure: "Failed"
        case .neutral: "Completed"
        case .skipped: "Skipped"
        case .cancelled: "Cancelled"
        case .unknown: "Updated"
        }
    }
}

struct MonitoredCheck: Codable, Identifiable, Hashable, Sendable {
    let runID: Int64
    let sourceKey: String?
    let repositoryID: Int64
    let repositoryName: String
    let name: String
    let phase: CheckPhase
    let url: URL
    let headSHA: String?
    let commitMessage: String?
    let providerName: String?
    let updatedAt: Date

    var id: String { "\(repositoryID):\(sourceKey ?? String(runID))" }

    var sourceKind: String { sourceKey == nil ? "check" : "status" }

    init(
        run: GitHubCheckRun,
        repository: GitHubRepository,
        commitMessage: String? = nil,
        previous: MonitoredCheck? = nil,
        now: Date = .now
    ) {
        runID = run.id
        sourceKey = nil
        repositoryID = repository.id
        repositoryName = repository.fullName
        name = run.name
        phase = Self.phase(status: run.status, conclusion: run.conclusion)
        url = run.htmlURL ?? run.detailsURL ?? repository.htmlURL
        headSHA = run.headSHA
        self.commitMessage = commitMessage
            ?? (previous?.headSHA == run.headSHA ? previous?.commitMessage : nil)
        providerName = run.app?.name
        let apiUpdatedAt: Date? = switch phase {
        case .queued, .running: run.startedAt
        case .success, .failure, .neutral, .skipped, .cancelled: run.completedAt
        case .unknown: run.completedAt ?? run.startedAt
        }
        updatedAt = apiUpdatedAt
            ?? (previous?.phase == phase ? previous?.updatedAt : nil)
            ?? now
    }

    init(
        status: GitHubCommitStatus,
        repository: GitHubRepository,
        headSHA: String,
        commitMessage: String? = nil,
        previous: MonitoredCheck? = nil
    ) {
        runID = status.id
        sourceKey = Self.commitStatusSourceKey(headSHA: headSHA, context: status.context)
        repositoryID = repository.id
        repositoryName = repository.fullName
        name = status.context
        phase = Self.phase(statusState: status.state)
        url = status.targetURL ?? repository.htmlURL
        self.headSHA = headSHA
        self.commitMessage = commitMessage
            ?? (previous?.headSHA == headSHA ? previous?.commitMessage : nil)
        providerName = status.creator?.login
        updatedAt = status.updatedAt
    }

    static func commitStatusSourceKey(headSHA: String, context: String) -> String {
        "status:\(headSHA.lowercased()):\(context.lowercased())"
    }

    static func phase(status: String, conclusion: String?) -> CheckPhase {
        switch status {
        case "queued", "waiting", "pending", "requested": return .queued
        case "in_progress": return .running
        case "completed":
            switch conclusion {
            case "success": return .success
            case "failure", "timed_out", "action_required", "startup_failure": return .failure
            case "cancelled", "stale": return .cancelled
            case "skipped": return .skipped
            case "neutral": return .neutral
            default: return .unknown
            }
        default: return .unknown
        }
    }

    static func phase(statusState: String) -> CheckPhase {
        switch statusState {
        case "pending": .running
        case "success": .success
        case "error", "failure": .failure
        default: .unknown
        }
    }
}

struct CheckSnapshot: Codable, Equatable, Sendable {
    let phase: CheckPhase
}

struct CheckEvent: Equatable, Sendable {
    let check: MonitoredCheck
    let previousPhase: CheckPhase?
}

enum StatusChangeDetector {
    static func events(
        previous: [String: CheckSnapshot],
        current: [MonitoredCheck],
        suppressNotifications: Bool
    ) -> [CheckEvent] {
        guard !suppressNotifications else { return [] }

        return current.compactMap { check in
            let oldPhase = previous[check.id]?.phase
            guard oldPhase != check.phase else { return nil }
            return CheckEvent(check: check, previousPhase: oldPhase)
        }
    }
}

enum VisibleCheckSelector {
    /// Keeps the current effective check for each repository + check name.
    /// `commitSHAsNewestFirst` is newest-first default-branch order for that repository.
    static func currentChecks(
        from checks: [MonitoredCheck],
        commitSHAsNewestFirst: [String]
    ) -> [MonitoredCheck] {
        let shaRank = Dictionary(
            uniqueKeysWithValues: commitSHAsNewestFirst.enumerated().map { ($1.lowercased(), $0) }
        )
        var bestByKey: [String: MonitoredCheck] = [:]

        for check in checks {
            let key = "\(check.repositoryID)\u{0}\(check.sourceKind)\u{0}\(check.name.lowercased())"
            guard let existing = bestByKey[key] else {
                bestByKey[key] = check
                continue
            }

            let checkRank = check.headSHA.map { shaRank[$0.lowercased()] ?? Int.max } ?? Int.max
            let existingRank = existing.headSHA.map { shaRank[$0.lowercased()] ?? Int.max } ?? Int.max

            if checkRank < existingRank {
                bestByKey[key] = check
            } else if checkRank == existingRank {
                if check.updatedAt > existing.updatedAt
                    || (check.updatedAt == existing.updatedAt && check.runID > existing.runID) {
                    bestByKey[key] = check
                }
            }
        }

        return Array(bestByKey.values)
    }

    static func visibleChecks(
        from checks: [MonitoredCheck],
        commitSHAsNewestFirstByRepository: [Int64: [String]],
        limit: Int
    ) -> [MonitoredCheck] {
        let grouped = Dictionary(grouping: checks, by: \.repositoryID)
        let current = grouped.flatMap { repositoryID, repositoryChecks in
            currentChecks(
                from: repositoryChecks,
                commitSHAsNewestFirst: commitSHAsNewestFirstByRepository[repositoryID] ?? []
            )
        }

        return Array(
            current
                .sorted {
                    if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                    if $0.repositoryName != $1.repositoryName {
                        return $0.repositoryName.localizedCaseInsensitiveCompare($1.repositoryName)
                            == .orderedAscending
                    }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                .prefix(limit)
        )
    }
}

struct RepositorySyncIssue: Identifiable, Equatable {
    let repositoryID: Int64
    let repositoryName: String
    let message: String
    var id: Int64 { repositoryID }
}

enum CheckPresentation {
    static func menuBarSymbol(checks: [MonitoredCheck], hasSyncIssues: Bool) -> String {
        if hasSyncIssues { return "exclamationmark.triangle" }
        if checks.contains(where: { $0.phase == .failure }) { return "exclamationmark.circle.fill" }
        if checks.contains(where: { $0.phase == .running || $0.phase == .queued }) { return "circle.dotted.circle" }
        if !checks.isEmpty && checks.allSatisfy({ $0.phase == .success || $0.phase == .skipped }) {
            return "checkmark.circle"
        }
        return checks.isEmpty ? "circle.dotted" : "minus.circle"
    }

    static func repositoryName(for check: MonitoredCheck, among checks: [MonitoredCheck]) -> String {
        let shortName = check.repositoryName.split(separator: "/").last.map(String.init) ?? check.repositoryName
        let names = Set(checks.filter {
            $0.repositoryName.split(separator: "/").last?.lowercased() == shortName.lowercased()
        }.map { $0.repositoryName.lowercased() })
        return names.count > 1 ? check.repositoryName : shortName
    }
}
