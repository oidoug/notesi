import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    let noteID: UUID
    @StateObject private var store: NoteStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    private static let minFontSize: Double = 9
    private static let maxFontSize: Double = 48
    private static let fontStep: Double = 1
    private static var didBootstrap = false

    init(noteID: UUID) {
        self.noteID = noteID
        self._store = StateObject(wrappedValue: NoteStore(noteID: noteID))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VisualEffectBackground()

            Color.black
                .opacity(colorScheme == .dark ? 0.4 : 0.0)
                .allowsHitTesting(false)
            Color.white
                .opacity(colorScheme == .dark ? 0.0 : 0.15)
                .allowsHitTesting(false)

            EditableTextView(
                text: $store.text,
                fontSize: store.fontSize,
                colorScheme: colorScheme,
                onIncreaseFontSize: increaseFontSize,
                onDecreaseFontSize: decreaseFontSize
            )

            HStack(spacing: 6) {
                TitleEditor(title: $store.title)
                PinButton(isPinned: $store.isPinned)
            }
            .padding(.top, 4)
            .padding(.trailing, 8)
        }
        .ignoresSafeArea()
        .background(WindowChromeController(isPinned: store.isPinned, title: store.title, noteID: noteID))
        .focusedSceneValue(\.pinned, $store.isPinned)
        .onAppear {
            OpenNotesRegistry.shared.add(noteID)
            bootstrapAdditionalWindowsIfNeeded()
        }
    }

    private func bootstrapAdditionalWindowsIfNeeded() {
        guard !Self.didBootstrap else { return }
        Self.didBootstrap = true
        let currentID = noteID
        let open = openWindow
        DispatchQueue.main.async {
            for id in OpenNotesRegistry.shared.ids where id != currentID {
                open(value: id)
            }
        }
    }

    private func increaseFontSize() {
        store.fontSize = min(Self.maxFontSize, store.fontSize + Self.fontStep)
    }

    private func decreaseFontSize() {
        store.fontSize = max(Self.minFontSize, store.fontSize - Self.fontStep)
    }
}

private final class NoteStore: ObservableObject {
    @Published var text: String {
        didSet {
            guard !isApplyingExternalChange else { return }
            persist(text, forKey: keys.text)
        }
    }

    @Published var title: String {
        didSet {
            guard !isApplyingExternalChange else { return }
            persist(title, forKey: keys.title)
        }
    }

    @Published var fontSize: Double {
        didSet {
            guard !isApplyingExternalChange else { return }
            persist(fontSize, forKey: keys.fontSize)
        }
    }

    @Published var isPinned: Bool {
        didSet {
            guard !isApplyingExternalChange else { return }
            persist(isPinned, forKey: keys.pinned)
        }
    }

    private struct Keys {
        let text: String
        let title: String
        let fontSize: String
        let pinned: String
        static let defaultFontSize: Double = 14

        init(noteID: UUID) {
            let base = "note.\(noteID.uuidString)"
            self.text = "\(base).text"
            self.title = "\(base).title"
            self.fontSize = "\(base).fontSize"
            self.pinned = "\(base).pinned"
        }
    }

    private let keys: Keys
    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?
    private var isApplyingExternalChange = false

    init(noteID: UUID) {
        let keys = Keys(noteID: noteID)
        self.keys = keys

        let cloudText = cloud.string(forKey: keys.text)
        let localText = defaults.string(forKey: keys.text)
        self.text = cloudText ?? localText ?? ""

        let cloudTitle = cloud.string(forKey: keys.title)
        let localTitle = defaults.string(forKey: keys.title)
        self.title = cloudTitle ?? localTitle ?? ""

        let cloudFont = (cloud.object(forKey: keys.fontSize) as? NSNumber)?.doubleValue
        let localFont = defaults.object(forKey: keys.fontSize) as? Double
        self.fontSize = cloudFont ?? localFont ?? Keys.defaultFontSize

        let cloudPinned = (cloud.object(forKey: keys.pinned) as? NSNumber)?.boolValue
        let localPinned = defaults.object(forKey: keys.pinned) as? Bool
        self.isPinned = cloudPinned ?? localPinned ?? false

        // First-run on this device: push existing local values up to iCloud.
        if cloudText == nil, let local = localText {
            cloud.set(local, forKey: keys.text)
        }
        if cloudTitle == nil, let local = localTitle {
            cloud.set(local, forKey: keys.title)
        }
        if cloudFont == nil, let local = localFont {
            cloud.set(local, forKey: keys.fontSize)
        }
        if cloudPinned == nil, let local = localPinned {
            cloud.set(local, forKey: keys.pinned)
        }

        cloud.synchronize()

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] note in
            self?.applyExternalChange(note)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func persist(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
        cloud.set(value, forKey: key)
    }

    private func persist(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: key)
        cloud.set(value, forKey: key)
    }

    private func persist(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
        cloud.set(value, forKey: key)
    }

    private func applyExternalChange(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else { return }

        isApplyingExternalChange = true
        defer { isApplyingExternalChange = false }

        for key in changedKeys {
            switch key {
            case keys.text:
                if let new = cloud.string(forKey: key), new != text {
                    text = new
                    defaults.set(new, forKey: key)
                }
            case keys.title:
                if let new = cloud.string(forKey: key), new != title {
                    title = new
                    defaults.set(new, forKey: key)
                }
            case keys.fontSize:
                if let new = (cloud.object(forKey: key) as? NSNumber)?.doubleValue,
                   new != fontSize {
                    fontSize = new
                    defaults.set(new, forKey: key)
                }
            case keys.pinned:
                if let new = (cloud.object(forKey: key) as? NSNumber)?.boolValue,
                   new != isPinned {
                    isPinned = new
                    defaults.set(new, forKey: key)
                }
            default:
                break
            }
        }
    }
}

private struct TitleEditor: View {
    @Binding var title: String
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .frame(maxWidth: 140)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
            } else {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft = title
                        isEditing = true
                        DispatchQueue.main.async { focused = true }
                    }
                    .help("Click to rename")
            }
        }
    }

    private func commit() {
        title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        focused = false
    }
}

private struct PinButton: View {
    @Binding var isPinned: Bool
    @State private var isHovering = false

    var body: some View {
        Button(action: { isPinned.toggle() }) {
            Text("P")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(foregroundColor)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(isPinned ? 0 : 0.15), lineWidth: 2)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isPinned ? "Unpin from top" : "Pin to top")
    }

    private var foregroundColor: Color {
        isPinned ? .accentColor : .primary
    }

    private var backgroundFill: Color {
        if isPinned {
            return Color.accentColor.opacity(0.2)
        } else if isHovering {
            return Color.primary.opacity(0.12)
        } else {
            return Color.clear
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct WindowChromeController: NSViewRepresentable {
    let isPinned: Bool
    let title: String
    let noteID: UUID

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let pinned = isPinned
        let titleText = title.isEmpty ? "Untitled" : title
        let id = noteID
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            window.level = pinned ? .floating : .normal
            window.title = titleText

            if !coordinator.didConfigure {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.isRestorable = false
                coordinator.didConfigure = true

                if let saved = WindowFrameStore.frame(for: id) {
                    window.setFrame(saved, display: true)
                }

                coordinator.observe(window: window, noteID: id)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var didConfigure = false
        private var observers: [NSObjectProtocol] = []

        func observe(window: NSWindow, noteID: UUID) {
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                guard !AppLifecycle.isTerminating else { return }
                OpenNotesRegistry.shared.remove(noteID)
            })
            let saveFrame: (Notification) -> Void = { [weak window] _ in
                guard let window else { return }
                WindowFrameStore.save(window.frame, for: noteID)
            }
            observers.append(center.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main,
                using: saveFrame
            ))
            observers.append(center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main,
                using: saveFrame
            ))
        }

        deinit {
            let center = NotificationCenter.default
            observers.forEach { center.removeObserver($0) }
        }
    }
}
