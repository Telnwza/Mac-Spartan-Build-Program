import SwiftUI
import AppKit

@MainActor
final class UILogBuffer {
    nonisolated static let defaultMaximumCharacters = 80_000

    private let maximumCharacters: Int
    private let flushDelay: TimeInterval
    private let publish: (String) -> Void
    private var displayed: String
    private var pending = ""
    private var scheduledFlush: DispatchWorkItem?

    init(
        initialText: String,
        maximumCharacters: Int = UILogBuffer.defaultMaximumCharacters,
        flushDelay: TimeInterval = 0.12,
        publish: @escaping (String) -> Void
    ) {
        self.displayed = initialText
        self.maximumCharacters = maximumCharacters
        self.flushDelay = flushDelay
        self.publish = publish
    }

    func append(_ text: String) {
        pending += text
        if pending.count > maximumCharacters {
            pending = String(pending.suffix(maximumCharacters))
        }
        guard scheduledFlush == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.flushNow()
        }
        scheduledFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + flushDelay, execute: work)
    }

    func clear() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        pending = ""
        displayed = ""
        publish("")
    }

    func flushNow() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        guard !pending.isEmpty else { return }
        displayed += pending
        pending = ""
        if displayed.count > maximumCharacters {
            displayed = "… แสดงเฉพาะ Log ล่าสุด …\n" + displayed.suffix(maximumCharacters)
        }
        publish(displayed)
    }

    var displayedCharacterCount: Int { displayed.count }
}

struct ReadOnlyLogView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        let visibleMaxY = scrollView.documentVisibleRect.maxY
        let previousHeight = textView.bounds.height
        let wasNearBottom = textView.string.isEmpty || previousHeight - visibleMaxY < 40
        textView.string = text
        if wasNearBottom {
            textView.scrollToEndOfDocument(nil)
        }
    }
}

enum LogSupportSelfTest {
    @MainActor
    static func run() -> Bool {
        var published = ""
        let buffer = UILogBuffer(
            initialText: "start\n",
            maximumCharacters: 1_000,
            flushDelay: 60
        ) { published = $0 }
        buffer.append(String(repeating: "A", count: 2_000) + "TAIL")
        buffer.flushNow()
        let bounded = buffer.displayedCharacterCount <= 1_040
            && published.hasSuffix("TAIL")
        buffer.clear()
        return bounded && published.isEmpty
    }
}
