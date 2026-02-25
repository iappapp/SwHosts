import SwiftUI
import AppKit

struct HostsSyntaxEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.applyHighlighting(to: text)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable

        if textView.string != text {
            context.coordinator.applyHighlighting(to: text)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        private var isUpdatingText = false

        private let ipRegex = try? NSRegularExpression(pattern: #"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#)
        private let domainRegex = try? NSRegularExpression(pattern: #"\b(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}\b"#)

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isUpdatingText else { return }
            text = textView.string
            applyHighlighting(to: textView.string)
        }

        func applyHighlighting(to value: String) {
            guard let textView else { return }
            let selectedRange = textView.selectedRange()
            isUpdatingText = true

            let attributed = NSMutableAttributedString(string: value)
            let fullRange = NSRange(location: 0, length: attributed.length)
            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.textColor
            ], range: fullRange)

            if let ipRegex {
                ipRegex.matches(in: value, range: fullRange).forEach { match in
                    attributed.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
                }
            }

            if let domainRegex {
                domainRegex.matches(in: value, range: fullRange).forEach { match in
                    attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: match.range)
                }
            }

            textView.textStorage?.setAttributedString(attributed)
            textView.setSelectedRange(selectedRange)
            isUpdatingText = false
        }
    }
}
