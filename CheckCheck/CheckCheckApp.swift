import AppKit
import SwiftUI

@main
struct CheckCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #if CHECKCHECK_QA
    @StateObject private var store = AppStore(isPreview: true)
    #else
    @StateObject private var store = AppStore(
        isPreview: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    )
    #endif

    init() {
        #if CHECKCHECK_QA
        // Exercise full keyboard navigation within this app without changing system preferences.
        UserDefaults.standard.register(defaults: ["AppleKeyboardUIMode": 3])
        #endif
    }

    var body: some Scene {
        #if CHECKCHECK_QA
        WindowGroup("CheckCheck UI Validation", id: "qa") {
            QAControls().environmentObject(store)
        }
        Window("CheckCheck Popover Preview", id: "qa-preview") {
            MenuBarView().environmentObject(store)
        }
        .windowResizability(.contentSize)
        #endif
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            Image(systemName: store.menuBarSymbol)
                .accessibilityLabel(store.menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
        .defaultSize(width: 640, height: 660)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if CHECKCHECK_QA
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        #else
        NSApp.setActivationPolicy(.accessory)
        #endif
    }
}

#if CHECKCHECK_QA
private struct QAControls: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var state = "Connected"
    @State private var dark = false
    private let states = ["Disconnected", "Account Error", "No Repositories", "Loading", "First Failure",
                          "Connected", "Refreshing", "Empty", "Partial Failure", "Cached Failure", "Repository Error"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Isolated UI validation").font(.headline)
            Picker("Scenario", selection: $state) {
                ForEach(states, id: \.self) { Text($0) }
            }
            .onChange(of: state) { _, value in store.showQAState(value) }
            Toggle("Dark Appearance", isOn: $dark)
                .onChange(of: dark) { _, value in
                    NSApp.appearance = NSAppearance(named: value ? .darkAqua : .aqua)
                }
            Button("Show Popover Preview…") { openWindow(id: "qa-preview") }
            Button("Open Settings…") { openSettings(); NSApp.activate() }
            Text("Use the menu bar icon to inspect the real popover. No account, network, notifications, or login items are used.")
                .font(.caption).foregroundStyle(.secondary)
            Text(store.qaLastAction).font(.caption)
            Button("Quit QA") { NSApp.terminate(nil) }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { store.showQAState(state) }
    }
}
#endif
