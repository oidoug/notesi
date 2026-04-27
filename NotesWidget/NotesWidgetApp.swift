import SwiftUI

@main
struct NotesWidgetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 200, minHeight: 150)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
