import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @StateObject private var store = NoteStore()
    @AppStorage("isPinned") private var isPinned: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private static let minFontSize: Double = 9
    private static let maxFontSize: Double = 48
    private static let fontStep: Double = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VisualEffectBackground()

            // gets a touch of color to feel less washed-out.
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

            PinButton(isPinned: $isPinned)
                .padding(.top, 4)
                .padding(.trailing, 8)
        }
        .ignoresSafeArea()
        .background(WindowChromeController(isPinned: isPinned))
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
            persist(text, forKey: Keys.text)
        }
    }

    @Published var fontSize: Double {
        didSet {
            guard !isApplyingExternalChange else { return }
            persist(fontSize, forKey: Keys.fontSize)
        }
    }

    private enum Keys {
        static let text = "noteText"
        static let fontSize = "fontSize"
        static let defaultFontSize: Double = 14
    }

    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?
    private var isApplyingExternalChange = false

    init() {
        let cloudText = cloud.string(forKey: Keys.text)
        let localText = defaults.string(forKey: Keys.text)
        self.text = cloudText ?? localText ?? ""

        let cloudFontSize = (cloud.object(forKey: Keys.fontSize) as? NSNumber)?.doubleValue
        let localFontSize = defaults.object(forKey: Keys.fontSize) as? Double
        self.fontSize = cloudFontSize ?? localFontSize ?? Keys.defaultFontSize

        // First-run on a new device: push existing local values up to iCloud.
        if cloudText == nil, let local = localText {
            cloud.set(local, forKey: Keys.text)
        }
        if cloudFontSize == nil, let local = localFontSize {
            cloud.set(local, forKey: Keys.fontSize)
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

    private func applyExternalChange(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else { return }

        isApplyingExternalChange = true
        defer { isApplyingExternalChange = false }

        for key in changedKeys {
            switch key {
            case Keys.text:
                if let newValue = cloud.string(forKey: key), newValue != text {
                    text = newValue
                    defaults.set(newValue, forKey: key)
                }
            case Keys.fontSize:
                if let newValue = (cloud.object(forKey: key) as? NSNumber)?.doubleValue,
                   newValue != fontSize {
                    fontSize = newValue
                    defaults.set(newValue, forKey: key)
                }
            default:
                break
            }
        }
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

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let pinned = isPinned
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            window.level = pinned ? .floating : .normal

            if !coordinator.didConfigure {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                coordinator.didConfigure = true
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var didConfigure = false
    }
}
