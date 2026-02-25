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
        textView.string = text

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.applyHighlighting()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.textBinding = $text
        textView.isEditable = isEditable

        if context.coordinator.ignoreNextExternalSync {
            context.coordinator.ignoreNextExternalSync = false
            return
        }

        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlighting()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textBinding: Binding<String>
        weak var textView: NSTextView?
        private var isUpdatingText = false
        var ignoreNextExternalSync = false

        private let ipRegex = try? NSRegularExpression(pattern: #"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#)
        private let domainRegex = try? NSRegularExpression(pattern: #"\b(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}\b"#)

        init(text: Binding<String>) {
            self.textBinding = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isUpdatingText else { return }
            ignoreNextExternalSync = true
            textBinding.wrappedValue = textView.string
            applyHighlighting()
        }

        func applyHighlighting() {
            guard let textView else { return }
            let value = textView.string
            let selectedRange = textView.selectedRange()
            isUpdatingText = true

            let fullRange = NSRange(location: 0, length: (value as NSString).length)

            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.textColor
            ], range: fullRange)

            if let ipRegex {
                ipRegex.matches(in: value, range: fullRange).forEach { match in
                    textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
                }
            }

            if let domainRegex {
                domainRegex.matches(in: value, range: fullRange).forEach { match in
                    textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.labelColor, range: match.range)
                }
            }

            textView.textStorage?.endEditing()
            textView.setSelectedRange(selectedRange)
            isUpdatingText = false
        }
    }
}
