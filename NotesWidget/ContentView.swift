import SwiftUI
import AppKit

struct ContentView: View {
    @AppStorage("noteText") private var text: String = ""
    @AppStorage("fontSize") private var fontSize: Double = 14
    @AppStorage("isPinned") private var isPinned: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private static let minFontSize: Double = 9
    private static let maxFontSize: Double = 48
    private static let fontStep: Double = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            EditableTextView(
                text: $text,
                fontSize: fontSize,
                colorScheme: colorScheme,
                onIncreaseFontSize: increaseFontSize,
                onDecreaseFontSize: decreaseFontSize
            )
            .background(backgroundColor)

            PinButton(isPinned: $isPinned)
                .padding(.top, 4)
                .padding(.trailing, 8)
        }
        .ignoresSafeArea()
        .background(WindowLevelController(isPinned: isPinned))
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98)
    }

    private func increaseFontSize() {
        fontSize = min(Self.maxFontSize, fontSize + Self.fontStep)
    }

    private func decreaseFontSize() {
        fontSize = max(Self.minFontSize, fontSize - Self.fontStep)
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

private struct WindowLevelController: NSViewRepresentable {
    let isPinned: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let pinned = isPinned
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            window.level = pinned ? .floating : .normal
        }
    }
}
