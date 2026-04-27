import AppKit
import SwiftUI

struct EditableTextView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let colorScheme: ColorScheme
    let onIncreaseFontSize: () -> Void
    let onDecreaseFontSize: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let contentSize = scrollView.contentSize
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = NotesTextView(
            frame: NSRect(origin: .zero, size: contentSize),
            textContainer: textContainer
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        applyAppearance(to: textView)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NotesTextView else { return }

        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }
        applyAppearance(to: textView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let textView = scrollView.documentView as? NotesTextView {
            textView.coordinator = nil
            textView.delegate = nil
        }
    }

    private func applyAppearance(to textView: NotesTextView) {
        let isDark = colorScheme == .dark
        textView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        textView.textColor = isDark ? .white : .black
        textView.insertionPointColor = isDark ? .white : .black
        textView.font = NSFont.systemFont(ofSize: CGFloat(fontSize))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditableTextView

        init(_ parent: EditableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func increaseFontSize() {
            parent.onIncreaseFontSize()
        }

        func decreaseFontSize() {
            parent.onDecreaseFontSize()
        }
    }
}

final class NotesTextView: NSTextView {
    weak var coordinator: EditableTextView.Coordinator?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let onlyCommand = flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)
        let onlyOption = flags.contains(.option) && !flags.contains(.command) && !flags.contains(.control)

        if onlyCommand, let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "+", "=":
                coordinator?.increaseFontSize()
                return true
            case "-", "_":
                coordinator?.decreaseFontSize()
                return true
            default:
                break
            }
        }

        if onlyOption {
            switch event.keyCode {
            case 126: // up arrow
                moveSelectedLines(up: true)
                return true
            case 125: // down arrow
                moveSelectedLines(up: false)
                return true
            default:
                break
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    private func moveSelectedLines(up: Bool) {
        guard let textStorage = self.textStorage else { return }

        let nsString = textStorage.string as NSString
        let selection = self.selectedRange()
        let selectedLineRange = nsString.lineRange(for: selection)

        if up {
            // No previous line — nothing to move.
            guard selectedLineRange.location > 0 else { return }

            let previousLineRange = nsString.lineRange(
                for: NSRange(location: selectedLineRange.location - 1, length: 0)
            )

            let combinedRange = NSRange(
                location: previousLineRange.location,
                length: previousLineRange.length + selectedLineRange.length
            )
            let previousLine = nsString.substring(with: previousLineRange)
            let selectedLines = nsString.substring(with: selectedLineRange)

            let previousEndsWithNewline = previousLine.hasSuffix("\n")
            let selectedEndsWithNewline = selectedLines.hasSuffix("\n")

            // If selected block was the last line (no trailing newline) we need to
            // move the newline boundary so neither block ends up missing/extra.
            let newSelectedLines: String
            let newPreviousLine: String
            if !selectedEndsWithNewline && previousEndsWithNewline {
                newSelectedLines = String(selectedLines) + "\n"
                newPreviousLine = String(previousLine.dropLast())
            } else {
                newSelectedLines = String(selectedLines)
                newPreviousLine = String(previousLine)
            }

            let replacement = newSelectedLines + newPreviousLine

            guard shouldChangeText(in: combinedRange, replacementString: replacement) else { return }
            textStorage.replaceCharacters(in: combinedRange, with: replacement)
            didChangeText()

            let offsetWithinLines = selection.location - selectedLineRange.location
            let newSelectionLocation = previousLineRange.location + offsetWithinLines
            self.setSelectedRange(NSRange(location: newSelectionLocation, length: selection.length))
        } else {
            let endOfSelected = selectedLineRange.location + selectedLineRange.length
            // No next line — nothing to move.
            guard endOfSelected < nsString.length else { return }

            let nextLineRange = nsString.lineRange(for: NSRange(location: endOfSelected, length: 0))

            let combinedRange = NSRange(
                location: selectedLineRange.location,
                length: selectedLineRange.length + nextLineRange.length
            )
            let selectedLines = nsString.substring(with: selectedLineRange)
            let nextLine = nsString.substring(with: nextLineRange)

            let selectedEndsWithNewline = selectedLines.hasSuffix("\n")
            let nextEndsWithNewline = nextLine.hasSuffix("\n")

            let newSelectedLines: String
            let newNextLine: String
            if !nextEndsWithNewline && selectedEndsWithNewline {
                newNextLine = String(nextLine) + "\n"
                newSelectedLines = String(selectedLines.dropLast())
            } else {
                newNextLine = String(nextLine)
                newSelectedLines = String(selectedLines)
            }

            let replacement = newNextLine + newSelectedLines

            guard shouldChangeText(in: combinedRange, replacementString: replacement) else { return }
            textStorage.replaceCharacters(in: combinedRange, with: replacement)
            didChangeText()

            let offsetWithinLines = selection.location - selectedLineRange.location
            let newSelectionLocation = selectedLineRange.location + newNextLine.utf16.count + offsetWithinLines
            self.setSelectedRange(NSRange(location: newSelectionLocation, length: selection.length))
        }
    }
}
