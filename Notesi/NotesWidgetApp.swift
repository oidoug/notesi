import SwiftUI
import AppKit
import ServiceManagement

@main
struct NotesWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        clearSavedSceneState()
        Migration.performIfNeeded()
        registerLoginItemIfNeeded()
        AppLifecycle.observeTermination()
    }

    private func clearSavedSceneState() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let url = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Saved Application State")
            .appendingPathComponent("\(bundleID).savedState")
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    var body: some Scene {
        WindowGroup(for: UUID.self) { $id in
            ContentView(noteID: id)
                .frame(minWidth: 200, minHeight: 150)
        } defaultValue: {
            OpenNotesRegistry.shared.ids.first ?? Migration.primaryNoteID()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            NewNoteCommands()
            PinCommands()
        }
    }

    private func registerLoginItemIfNeeded() {
        let didRegisterKey = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: didRegisterKey) else { return }

        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: didRegisterKey)
        } catch {
            print("Login item registration failed: \(error)")
        }
    }
}

private struct NewNoteCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note Window") {
                openWindow(value: UUID())
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

private struct PinCommands: Commands {
    @FocusedBinding(\.pinned) private var pinned: Bool?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button((pinned ?? false) ? "Unpin from Top" : "Pin to Top") {
                pinned?.toggle()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(pinned == nil)
        }
    }
}

struct PinnedFocusKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var pinned: Binding<Bool>? {
        get { self[PinnedFocusKey.self] }
        set { self[PinnedFocusKey.self] = newValue }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}

enum AppLifecycle {
    static var isTerminating = false

    static func observeTermination() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            isTerminating = true
        }
    }
}

enum WindowFrameStore {
    private static let defaults = UserDefaults.standard
    private static func key(for id: UUID) -> String { "noteFrame.\(id.uuidString)" }

    static func frame(for id: UUID) -> NSRect? {
        guard let str = defaults.string(forKey: key(for: id)) else { return nil }
        let rect = NSRectFromString(str)
        return rect.size.width > 0 && rect.size.height > 0 ? rect : nil
    }

    static func save(_ frame: NSRect, for id: UUID) {
        defaults.set(NSStringFromRect(frame), forKey: key(for: id))
    }
}

final class OpenNotesRegistry {
    static let shared = OpenNotesRegistry()
    private let key = "openNoteIDs"
    private let defaults = UserDefaults.standard

    var ids: [UUID] {
        let strs = defaults.stringArray(forKey: key) ?? []
        return strs.compactMap { UUID(uuidString: $0) }
    }

    func add(_ id: UUID) {
        var current = defaults.stringArray(forKey: key) ?? []
        guard !current.contains(id.uuidString) else { return }
        current.append(id.uuidString)
        defaults.set(current, forKey: key)
    }

    func remove(_ id: UUID) {
        var current = defaults.stringArray(forKey: key) ?? []
        let before = current.count
        current.removeAll { $0 == id.uuidString }
        guard current.count != before else { return }
        defaults.set(current, forKey: key)
    }
}

enum Migration {
    private static let didMigrateKey = "didMigrateToMultiNote_v1"
    private static let primaryKey = "primaryNoteID"

    static func primaryNoteID() -> UUID {
        let defaults = UserDefaults.standard
        if let str = defaults.string(forKey: primaryKey),
           let id = UUID(uuidString: str) {
            return id
        }
        let cloud = NSUbiquitousKeyValueStore.default
        if let str = cloud.string(forKey: primaryKey),
           let id = UUID(uuidString: str) {
            defaults.set(str, forKey: primaryKey)
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: primaryKey)
        cloud.set(id.uuidString, forKey: primaryKey)
        return id
    }

    static func performIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didMigrateKey) else { return }

        let cloud = NSUbiquitousKeyValueStore.default
        cloud.synchronize()

        let primaryID: String
        if let cloudID = cloud.string(forKey: primaryKey) {
            primaryID = cloudID
        } else if let localID = defaults.string(forKey: primaryKey) {
            primaryID = localID
            cloud.set(localID, forKey: primaryKey)
        } else {
            primaryID = UUID().uuidString
            cloud.set(primaryID, forKey: primaryKey)
        }
        defaults.set(primaryID, forKey: primaryKey)

        let textKey = "note.\(primaryID).text"
        let fontKey = "note.\(primaryID).fontSize"

        if cloud.string(forKey: textKey) == nil {
            let oldText = cloud.string(forKey: "noteText")
                ?? defaults.string(forKey: "noteText")
            if let oldText {
                cloud.set(oldText, forKey: textKey)
                defaults.set(oldText, forKey: textKey)
            }
        }

        if cloud.object(forKey: fontKey) == nil {
            let cloudFont = (cloud.object(forKey: "fontSize") as? NSNumber)?.doubleValue
            let localFont = defaults.object(forKey: "fontSize") as? Double
            if let oldFont = cloudFont ?? localFont {
                cloud.set(oldFont, forKey: fontKey)
                defaults.set(oldFont, forKey: fontKey)
            }
        }

        cloud.synchronize()
        defaults.set(true, forKey: didMigrateKey)
    }
}
