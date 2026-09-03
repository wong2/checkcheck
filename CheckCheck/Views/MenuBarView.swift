import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                if !store.isConnected {
                    setupState
                } else if store.selectedRepositoryCount == 0 {
                    noRepositoriesState
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

            Button {
                showSettings()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var checkList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.checks) { check in
                    AccessibleCheckButton(
                        label: checkAccessibilityLabel(check),
                        action: { store.open(check) }
                    ) {
                        CheckRow(check: check)
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
            title: "Choose repositories",
            systemImage: "folder.badge.plus",
            description: "Select which repositories to monitor.",
            showsSettingsButton: true
        )
    }

    private var emptyChecksState: some View {
        emptyState(
            title: "Waiting for Checks",
            systemImage: "circle.dotted",
            description: store.isRefreshing
                ? "Checking GitHub now…"
                : "No status checks on the latest commits yet."
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
                    .lineLimit(1)
            }

            if showsSettingsButton {
                Button("Open Settings") {
                    showSettings()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 36)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(error)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                Group {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .disabled(store.isRefreshing || store.selectedRepositoryCount == 0)
            .help(store.isRefreshing ? "Refreshing checks" : "Refresh checks")
            .accessibilityLabel(store.isRefreshing ? "Refreshing checks" : "Refresh checks")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Quit CheckCheck")
            .accessibilityLabel("Quit CheckCheck")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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
        let shortName = check.repositoryName.split(separator: "/").last.map(String.init) ?? check.repositoryName
        var components = [shortName, check.phase.notificationVerb, check.name]
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(shortRepositoryName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(check.phase.notificationVerb)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(color)
                        .fixedSize()
                }

                HStack(spacing: 8) {
                    Text(check.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(CheckRelativeTimeFormatter.string(
                            since: check.updatedAt,
                            relativeTo: context.date
                        ))
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .help(check.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if let commitMessage = check.commitMessage, !commitMessage.isEmpty {
                    Text(commitMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var shortRepositoryName: String {
        check.repositoryName.split(separator: "/").last.map(String.init) ?? check.repositoryName
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

private struct AccessibleCheckButton<Content: View>: NSViewRepresentable {
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> AccessibleCheckNSButton {
        let button = AccessibleCheckNSButton(frame: .zero)
        button.axLabel = label
        button.onActivate = action
        button.hosts(content())
        return button
    }

    func updateNSView(_ nsView: AccessibleCheckNSButton, context: Context) {
        nsView.axLabel = label
        nsView.onActivate = action
        nsView.hosts(content())
        nsView.invalidateIntrinsicContentSize()
    }
}

private final class AccessibleCheckNSButton: NSButton {
    var axLabel = "" {
        didSet { needsDisplay = true }
    }
    var onActivate: (() -> Void)?

    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var tracking = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryChange)
        title = ""
        image = nil
        focusRingType = .none
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
        if tracking {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            dirtyRect.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        tracking = true
        needsDisplay = true
        super.mouseDown(with: event)
        tracking = false
        needsDisplay = true
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
