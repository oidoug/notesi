import SwiftUI
import ServiceManagement

@main
struct NotesWidgetApp: App {
    @AppStorage("isPinned") private var isPinned: Bool = false

    init() {
        registerLoginItemIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 200, minHeight: 150)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button(isPinned ? "Unpin from Top" : "Pin to Top") {
                    isPinned.toggle()
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
    }

    /// Adds the app to the user's Login Items the first time it launches.
    /// Only attempts registration once so that if the user later removes us
    /// from System Settings → General → Login Items, we don't keep re-adding.
    private func registerLoginItemIfNeeded() {
        let didRegisterKey = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: didRegisterKey) else { return }

        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: didRegisterKey)
        } catch {
            // Leave the flag unset so we retry on the next launch.
            print("Login item registration failed: \(error)")
        }
    }
}
