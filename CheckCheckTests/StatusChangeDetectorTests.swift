import XCTest
@testable import CheckCheck

final class StatusChangeDetectorTests: XCTestCase {
    private let repository = GitHubRepository(
        id: 42,
        fullName: "wong2/checkcheck",
        defaultBranch: "main",
        isPrivate: false,
        htmlURL: URL(string: "https://github.com/wong2/checkcheck")!
    )

    func testBaselineSuppressesNotifications() {
        let check = makeCheck(id: 1, status: "completed", conclusion: "success")
        let events = StatusChangeDetector.events(
            previous: [:],
            current: [check],
            suppressNotifications: true
        )
        XCTAssertTrue(events.isEmpty)
    }

    func testNewRunningCheckEmitsEvent() {
        let check = makeCheck(id: 2, status: "in_progress", conclusion: nil)
        let events = StatusChangeDetector.events(
            previous: [:],
            current: [check],
            suppressNotifications: false
        )
        XCTAssertEqual(events, [CheckEvent(check: check, previousPhase: nil)])
    }

    func testPhaseTransitionEmitsEvent() {
        let check = makeCheck(id: 3, status: "completed", conclusion: "failure")
        let previous = [check.id: CheckSnapshot(phase: .running)]
        let events = StatusChangeDetector.events(
            previous: previous,
            current: [check],
            suppressNotifications: false
        )
        XCTAssertEqual(events.first?.previousPhase, .running)
        XCTAssertEqual(events.first?.check.phase, .failure)
    }

    func testUnchangedPhaseDoesNotEmitEvent() {
        let check = makeCheck(id: 4, status: "completed", conclusion: "success")
        let previous = [check.id: CheckSnapshot(phase: .success)]
        let events = StatusChangeDetector.events(
            previous: previous,
            current: [check],
            suppressNotifications: false
        )
        XCTAssertTrue(events.isEmpty)
    }

    func testConclusionMapping() {
        XCTAssertEqual(MonitoredCheck.phase(status: "completed", conclusion: "timed_out"), .failure)
        XCTAssertEqual(MonitoredCheck.phase(status: "completed", conclusion: "skipped"), .skipped)
        XCTAssertEqual(MonitoredCheck.phase(status: "queued", conclusion: nil), .queued)
    }

    func testCommitStatusMapping() {
        XCTAssertEqual(MonitoredCheck.phase(statusState: "pending"), .running)
        XCTAssertEqual(MonitoredCheck.phase(statusState: "success"), .success)
        XCTAssertEqual(MonitoredCheck.phase(statusState: "error"), .failure)
        XCTAssertEqual(MonitoredCheck.phase(statusState: "failure"), .failure)
    }

    func testRelativeTimeFormattingAtDisplayBoundaries() {
        let updatedAt = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            CheckRelativeTimeFormatter.string(
                since: updatedAt,
                relativeTo: updatedAt.addingTimeInterval(59)
            ),
            "now"
        )
        XCTAssertEqual(
            CheckRelativeTimeFormatter.string(
                since: updatedAt,
                relativeTo: updatedAt.addingTimeInterval(60)
            ),
            "1m ago"
        )
        XCTAssertEqual(
            CheckRelativeTimeFormatter.string(
                since: updatedAt,
                relativeTo: updatedAt.addingTimeInterval(3_600)
            ),
            "1h ago"
        )
        XCTAssertEqual(
            CheckRelativeTimeFormatter.string(
                since: updatedAt,
                relativeTo: updatedAt.addingTimeInterval(86_400)
            ),
            "1d ago"
        )
    }

    func testRelativeTimeFormattingTreatsFutureDatesAsNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            CheckRelativeTimeFormatter.string(
                since: now.addingTimeInterval(60),
                relativeTo: now
            ),
            "now"
        )
    }

    func testCommitStatusBecomesVisibleCheck() {
        let updatedAt = Date(timeIntervalSince1970: 200)
        let status = GitHubCommitStatus(
            id: 50,
            state: "success",
            description: "Deployment succeeded",
            targetURL: URL(string: "https://railway.com/deployment/50"),
            context: "notebooklm-web-importer.com - nblm-site",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            creator: GitHubStatusCreator(login: "railway-app")
        )

        let check = MonitoredCheck(
            status: status,
            repository: repository,
            headSHA: "abc123",
            commitMessage: "Fix pnpm setup in Docker build"
        )

        XCTAssertEqual(check.name, status.context)
        XCTAssertEqual(check.phase, .success)
        XCTAssertEqual(check.url, status.targetURL)
        XCTAssertEqual(check.headSHA, "abc123")
        XCTAssertEqual(check.commitMessage, "Fix pnpm setup in Docker build")
        XCTAssertEqual(check.providerName, "railway-app")
        XCTAssertEqual(check.updatedAt, updatedAt)
    }

    func testCommitStatusIdentityIsStableAcrossTransitions() {
        let pending = makeStatus(id: 51, state: "pending")
        let success = makeStatus(id: 52, state: "success")

        let pendingCheck = MonitoredCheck(
            status: pending,
            repository: repository,
            headSHA: "abc123"
        )
        let successCheck = MonitoredCheck(
            status: success,
            repository: repository,
            headSHA: "abc123",
            previous: pendingCheck
        )

        XCTAssertEqual(pendingCheck.id, successCheck.id)
        XCTAssertNotEqual(pendingCheck.runID, successCheck.runID)
        XCTAssertEqual(successCheck.phase, .success)
    }

    func testLegacyCachedCheckDecodesWithoutSourceKey() throws {
        let check = makeCheck(id: 53, status: "completed", conclusion: "success")
        let encoded = try JSONEncoder().encode(check)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "sourceKey")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(MonitoredCheck.self, from: legacyData)

        XCTAssertNil(decoded.sourceKey)
        XCTAssertEqual(decoded.id, check.id)
    }

    func testCheckPrefersGitHubPageOverProviderDetails() {
        let githubURL = URL(string: "https://github.com/wong2/checkcheck/runs/5")!
        let providerURL = URL(string: "https://dash.cloudflare.com/builds/5")!
        let run = GitHubCheckRun(
            id: 5,
            name: "Workers Builds",
            status: "completed",
            conclusion: "success",
            htmlURL: githubURL,
            detailsURL: providerURL,
            startedAt: nil,
            completedAt: nil,
            headSHA: nil,
            app: nil
        )

        XCTAssertEqual(MonitoredCheck(run: run, repository: repository).url, githubURL)
    }

    func testCheckUsesCompletionAsStatusUpdateTime() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let completedAt = Date(timeIntervalSince1970: 200)
        let run = makeRun(
            id: 6,
            status: "completed",
            conclusion: "success",
            startedAt: startedAt,
            completedAt: completedAt
        )

        let check = MonitoredCheck(run: run, repository: repository, now: Date(timeIntervalSince1970: 300))

        XCTAssertEqual(check.updatedAt, completedAt)
    }

    func testCommitSubjectUsesOnlyTheFirstLine() {
        let commit = GitHubCommit(
            sha: "1234567890",
            commit: GitHubCommit.Details(message: "Keep the list compact\n\nMore context")
        )

        XCTAssertEqual(commit.subject, "Keep the list compact")
    }

    func testCheckPreservesObservedTimeWhenGitHubOmitsStatusTime() {
        let firstObservedAt = Date(timeIntervalSince1970: 100)
        let run = makeRun(id: 7, status: "queued", conclusion: nil)
        let previous = MonitoredCheck(run: run, repository: repository, now: firstObservedAt)

        let refreshed = MonitoredCheck(
            run: run,
            repository: repository,
            previous: previous,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(refreshed.updatedAt, firstObservedAt)
    }

    func testQueuedCheckUsesGitHubStartTime() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let run = makeRun(id: 9, status: "queued", conclusion: nil, startedAt: startedAt)

        let check = MonitoredCheck(
            run: run,
            repository: repository,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(check.updatedAt, startedAt)
    }

    func testCheckUsesObservationTimeWhenPhaseChangesWithoutCompletionTime() {
        let queuedRun = makeRun(id: 8, status: "queued", conclusion: nil)
        let previous = MonitoredCheck(
            run: queuedRun,
            repository: repository,
            now: Date(timeIntervalSince1970: 100)
        )
        let completedRun = makeRun(
            id: 8,
            status: "completed",
            conclusion: "success",
            startedAt: Date(timeIntervalSince1970: 50)
        )
        let observedAt = Date(timeIntervalSince1970: 200)

        let refreshed = MonitoredCheck(
            run: completedRun,
            repository: repository,
            previous: previous,
            now: observedAt
        )

        XCTAssertEqual(refreshed.updatedAt, observedAt)
    }

    func testCurrentChecksKeepNewestCommitPerRepositoryAndName() {
        let older = makeCheck(
            id: 10,
            status: "in_progress",
            conclusion: nil,
            headSHA: "old",
            commitMessage: "older build",
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let newer = makeCheck(
            id: 11,
            status: "completed",
            conclusion: "success",
            headSHA: "new",
            commitMessage: "newer build",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let otherName = makeCheck(
            id: 12,
            status: "completed",
            conclusion: "failure",
            headSHA: "new",
            name: "CI",
            commitMessage: "newer build",
            updatedAt: Date(timeIntervalSince1970: 250)
        )

        let selected = VisibleCheckSelector.currentChecks(
            from: [older, newer, otherName],
            commitSHAsNewestFirst: ["new", "old"]
        )

        XCTAssertEqual(Set(selected.map(\.runID)), [11, 12])
        XCTAssertFalse(selected.contains { $0.phase == .running })
    }

    func testVisibleChecksSortByUpdatedAtAndLimit() {
        let otherRepository = GitHubRepository(
            id: 99,
            fullName: "wong2/other",
            defaultBranch: "main",
            isPrivate: false,
            htmlURL: URL(string: "https://github.com/wong2/other")!
        )
        let checks = [
            makeCheck(
                id: 20,
                status: "completed",
                conclusion: "success",
                headSHA: "a",
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            makeCheck(
                id: 21,
                status: "completed",
                conclusion: "failure",
                headSHA: "b",
                name: "Lint",
                updatedAt: Date(timeIntervalSince1970: 300)
            ),
            MonitoredCheck(
                run: makeRun(
                    id: 22,
                    status: "in_progress",
                    conclusion: nil,
                    startedAt: Date(timeIntervalSince1970: 200),
                    headSHA: "c"
                ),
                repository: otherRepository,
                commitMessage: "other",
                now: Date(timeIntervalSince1970: 200)
            )
        ]

        let visible = VisibleCheckSelector.visibleChecks(
            from: checks,
            commitSHAsNewestFirstByRepository: [
                repository.id: ["b", "a"],
                otherRepository.id: ["c"]
            ],
            limit: 2
        )

        XCTAssertEqual(visible.map(\.runID), [21, 22])
    }

    private func makeCheck(
        id: Int64,
        status: String,
        conclusion: String?,
        headSHA: String = "1234567890",
        name: String = "Workers Builds",
        commitMessage: String? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 200)
    ) -> MonitoredCheck {
        MonitoredCheck(
            run: makeRun(
                id: id,
                status: status,
                conclusion: conclusion,
                startedAt: updatedAt,
                completedAt: status == "completed" ? updatedAt : nil,
                headSHA: headSHA,
                name: name
            ),
            repository: repository,
            commitMessage: commitMessage,
            now: updatedAt
        )
    }

    private func makeRun(
        id: Int64,
        status: String,
        conclusion: String?,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        headSHA: String = "1234567890",
        name: String = "Workers Builds"
    ) -> GitHubCheckRun {
        GitHubCheckRun(
            id: id,
            name: name,
            status: status,
            conclusion: conclusion,
            htmlURL: URL(string: "https://github.com/wong2/checkcheck/runs/\(id)"),
            detailsURL: nil,
            startedAt: startedAt,
            completedAt: completedAt,
            headSHA: headSHA,
            app: GitHubCheckApp(name: "Cloudflare Workers")
        )
    }

    private func makeStatus(
        id: Int64,
        state: String,
        context: String = "notebooklm-web-importer.com - nblm-site"
    ) -> GitHubCommitStatus {
        GitHubCommitStatus(
            id: id,
            state: state,
            description: nil,
            targetURL: URL(string: "https://railway.com/deployment/\(id)"),
            context: context,
            createdAt: Date(timeIntervalSince1970: Double(id)),
            updatedAt: Date(timeIntervalSince1970: Double(id)),
            creator: GitHubStatusCreator(login: "railway-app")
        )
    }
}
