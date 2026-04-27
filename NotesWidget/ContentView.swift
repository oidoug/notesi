import SwiftUI

struct ContentView: View {
    @AppStorage("noteText") private var text: String = ""
    @AppStorage("fontSize") private var fontSize: Double = 14
    @Environment(\.colorScheme) private var colorScheme

    private static let minFontSize: Double = 9
    private static let maxFontSize: Double = 48
    private static let fontStep: Double = 1

    var body: some View {
        EditableTextView(
            text: $text,
            fontSize: fontSize,
            colorScheme: colorScheme,
            onIncreaseFontSize: increaseFontSize,
            onDecreaseFontSize: decreaseFontSize
        )
        .background(backgroundColor)
        .ignoresSafeArea()
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
