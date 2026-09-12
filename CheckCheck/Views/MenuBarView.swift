import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var store: AppStore
    @State private var showsSyncDetails = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !store.syncIssues.isEmpty && !store.checks.isEmpty {
                syncWarning
                Divider()
            }

            Group {
                if !store.isConnected {
                    setupState
                } else if store.selectedRepositoryCount == 0 {
                    noRepositoriesState
                } else if store.checks.isEmpty && !store.syncIssues.isEmpty {
                    syncErrorState
                } else if store.checks.isEmpty {
                    emptyChecksState
                } else {
                    checkList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 380, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: applicationIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Text("CheckCheck")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Menu {
                Button("Settings…") { showSettings() }
                    .keyboardShortcut(",")
                Divider()
                Button("Quit CheckCheck") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("CheckCheck menu")
            .accessibilityLabel("CheckCheck menu")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var checkList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.checks) { check in
                    FocusableCheckButton(
                        label: checkAccessibilityLabel(check),
                        action: { store.open(check) }
                    ) {
                        CheckRow(check: check, repositoryName: store.repositoryDisplayName(for: check),
                                 isStale: store.syncIssues.contains { $0.repositoryID == check.repositoryID })
                    }

                    if check.id != store.checks.last?.id {
                        Divider()
                            .opacity(0.45)
                            .padding(.leading, 44)
                    }
                }
            }
        }
    }

    private var setupState: some View {
        emptyState(
            title: "Connect GitHub",
            systemImage: "key.horizontal",
            description: "Connect GitHub to start watching Checks.",
            showsSettingsButton: true
        )
    }

    private var noRepositoriesState: some View {
        emptyState(
            title: "Choose Repositories",
            systemImage: "folder.badge.plus",
            description: "Select which repositories to monitor.",
            showsSettingsButton: true
        )
    }

    private var emptyChecksState: some View {
        emptyState(
            title: store.isRefreshing ? "Checking GitHub" : (store.lastRefresh == nil ? "Waiting to Sync" : "No Checks Yet"),
            systemImage: "circle.dotted",
            description: store.isRefreshing
                ? "Checking GitHub now…"
                : (store.lastRefresh == nil
                    ? "The first sync hasn’t finished. Refresh to try again."
                    : "No status checks on the latest commits yet.")
        )
    }

    private func emptyState(
        title: String,
        systemImage: String,
        description: String,
        showsSettingsButton: Bool = false
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsSettingsButton {
                Button("Open Settings…") {
                    showSettings()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 36)
    }

    private var syncWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sync Incomplete")
                    .font(.system(size: 12, weight: .semibold))
                Text("Some results may be out of date.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Details…") { showsSyncDetails = true }
                .popover(isPresented: $showsSyncDetails) { syncDetails }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var syncErrorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Couldn’t Fetch Checks")
                .font(.system(size: 17, weight: .semibold))
            Text("The monitored repositories couldn’t be synced. No results are available yet.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Details…") { showsSyncDetails = true }
                .popover(isPresented: $showsSyncDetails) { syncDetails }
                Button(store.isRefreshing ? "Retrying…" : "Retry") {
                    Task { await store.refresh() }
                }
                .disabled(!store.canRefresh)
            }
            .controlSize(.small)
        }
        .padding(28)
    }

    private var syncDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Issues")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.syncIssues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.repositoryName).fontWeight(.semibold)
                            Text(issue.message).foregroundStyle(.secondary)
                            if let date = store.repositorySyncDates[issue.repositoryID] {
                                Text("Last synced: \(date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                            } else {
                                Text("No successful sync yet").font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    }
                }
            }
            .frame(maxHeight: 240)
            HStack {
                Button("Retry") { Task { await store.refresh() } }
                    .disabled(!store.canRefresh)
                Spacer()
                Button("Done") { showsSyncDetails = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(syncDescription(at: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(store.lastRefresh.map {
                        "All monitored repositories synced by " + $0.formatted(date: .abbreviated, time: .shortened)
                    } ?? "A complete sync of the monitored repositories has not finished.")
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.refresh() }
            } label: {
                Group {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!store.canRefresh)
            .keyboardShortcut("r")
            .help(store.isRefreshing ? "Refreshing checks" : "Refresh checks")
            .accessibilityLabel(store.isRefreshing ? "Refreshing checks" : "Refresh checks")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func syncDescription(at now: Date) -> String {
        guard store.isConnected else { return "GitHub isn’t connected" }
        guard store.selectedRepositoryCount > 0 else { return "No repositories selected" }
        if let date = store.lastRefresh {
            let prefix = store.syncIssues.isEmpty ? "Synced" : "Last complete sync"
            return "\(prefix) \(CheckRelativeTimeFormatter.string(since: date, relativeTo: now))"
        }
        if store.isRefreshing { return "Syncing repositories…" }
        return "Waiting for a complete sync"
    }

    private func showSettings() {
        dismiss()
        openSettings()
        NSApp.activate()
    }

    private var applicationIcon: NSImage {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            return NSApplication.shared.applicationIconImage
        }
        return image
    }

    private func checkAccessibilityLabel(_ check: MonitoredCheck) -> String {
        var components = [check.repositoryName, check.phase.notificationVerb, check.name]
        if store.syncIssues.contains(where: { $0.repositoryID == check.repositoryID }) {
            components.append("Sync incomplete; result may be out of date")
        }
        if let commitMessage = check.commitMessage {
            components.append(commitMessage)
        }
        components.append("Updated \(check.updatedAt.formatted(date: .abbreviated, time: .shortened))")
        return components.joined(separator: ", ")
    }
}

enum CheckRelativeTimeFormatter {
    static func string(since updatedAt: Date, relativeTo now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(updatedAt))
        return switch seconds {
        case ..<60: "now"
        case ..<3_600: "\(Int(seconds / 60))m ago"
        case ..<86_400: "\(Int(seconds / 3_600))h ago"
        case ..<604_800: "\(Int(seconds / 86_400))d ago"
        case ..<2_592_000: "\(Int(seconds / 604_800))w ago"
        default: updatedAt.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

private struct CheckRow: View {
    let check: MonitoredCheck
    let repositoryName: String
    let isStale: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if isStale {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .help("Sync incomplete; this result may be out of date")
                    }
                    Text(repositoryName)
                        .help(check.repositoryName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(check.phase.notificationVerb)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(color)
                        .fixedSize()
                }

                HStack(spacing: 8) {
                    Text(check.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .help(check.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(CheckRelativeTimeFormatter.string(
                            since: check.updatedAt,
                            relativeTo: context.date
                        ))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .help(check.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if let commitMessage = check.commitMessage, !commitMessage.isEmpty {
                    Text(commitMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help(commitMessage)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var symbol: String {
        switch check.phase {
        case .queued: "clock"
        case .running: "circle.dotted.circle"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .neutral: "minus.circle.fill"
        case .skipped: "forward.circle.fill"
        case .cancelled: "slash.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var color: Color {
        switch check.phase {
        case .running: .blue
        case .success: .green
        case .failure: .red
        case .queued, .neutral, .skipped, .cancelled, .unknown: .secondary
        }
    }
}

private struct FocusableCheckButton<Content: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        AccessibleCheckButton(label: label, action: action, onPressChanged: { isPressed = $0 }) {
            content()
                .background(Color.primary.opacity(isPressed ? 0.12 : (isHovered ? 0.06 : 0)))
                .clipped()
                .onHover { isHovered = $0 }
        }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                        .padding(3)
                        .allowsHitTesting(false)
                }
            }
            .onKeyPress(keys: [.space, .return]) { _ in
                action()
                return .handled
            }
    }
}

private struct AccessibleCheckButton<Content: View>: NSViewRepresentable {
    let label: String
    let action: () -> Void
    let onPressChanged: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> AccessibleCheckNSButton {
        let button = AccessibleCheckNSButton(frame: .zero)
        button.axLabel = label
        button.onActivate = action
        button.onPressChanged = onPressChanged
        button.hosts(content())
        return button
    }

    func updateNSView(_ nsView: AccessibleCheckNSButton, context: Context) {
        nsView.axLabel = label
        nsView.onActivate = action
        nsView.onPressChanged = onPressChanged
        nsView.hosts(content())
        nsView.invalidateIntrinsicContentSize()
    }
}

private final class AccessibleCheckNSButton: NSButton {
    var axLabel = "" {
        didSet { needsDisplay = true }
    }
    var onActivate: (() -> Void)?
    var onPressChanged: ((Bool) -> Void)?

    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryChange)
        title = ""
        image = nil
        focusRingType = .none // The SwiftUI focus owner draws the row focus indicator.
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func hosts<Content: View>(_ view: Content) {
        host.rootView = AnyView(view)
    }

    override var intrinsicContentSize: NSSize {
        host.fittingSize
    }

    override func draw(_ dirtyRect: NSRect) {
        // SwiftUI owns the row background. AppKit's dirtyRect can extend beyond
        // this view, so painting it here can tint neighboring rows as well.
    }

    // Keep one focus stop per row; SwiftUI owns keyboard navigation and activation.
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onPressChanged?(true)
        defer { onPressChanged?(false) }
        super.mouseDown(with: event)
    }

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        onActivate?()
        return true
    }

    override func accessibilityLabel() -> String? { axLabel }
    override func accessibilityTitle() -> String? { axLabel }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityHelp() -> String? { "Opens this check on GitHub" }
}
