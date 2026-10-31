import AppKit
import SwiftUI

/// AppKit-backed inline editor used inside the project `List`.
///
/// `List(selection:)` owns keyboard focus on macOS, so a SwiftUI `TextField`
/// inserted after a double click can lose focus before its first key event.
/// This control explicitly becomes the window's first responder. It owns the
/// text for the whole editing session so SwiftUI updates cannot interrupt
/// marked text from an input method such as the Korean IME.
@MainActor
struct ProjectNameEditor: NSViewRepresentable {
    let text: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> AutoFocusTextField {
        let textField = AutoFocusTextField(string: text)
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .exterior
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        return textField
    }

    func updateNSView(_ textField: AutoFocusTextField, context: Context) {
        context.coordinator.parent = self

        // Never replace stringValue while a field editor exists. Even writing
        // the same logical value can cancel an active marked-text composition.
        if textField.currentEditor() == nil, textField.stringValue != text {
            textField.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ProjectNameEditor
        private var isFinishing = false

        init(parent: ProjectNameEditor) {
            self.parent = parent
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            finishCommit(textField.stringValue)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                finishCommit(textView.string)
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                finishCancel()
                return true
            }

            return false
        }

        private func finishCommit(_ text: String) {
            guard !isFinishing else { return }
            isFinishing = true
            parent.onCommit(text)
        }

        private func finishCancel() {
            guard !isFinishing else { return }
            isFinishing = true
            parent.onCancel()
        }
    }
}

@MainActor
final class AutoFocusTextField: NSTextField {
    private var hasRequestedFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !hasRequestedFocus else { return }
        hasRequestedFocus = true

        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }

            // When the executable is launched from Xcode, Xcode can remain the
            // active application even though this field is first responder in
            // its own window. Activate the app and key the window before focus.
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(self)
            self.currentEditor()?.selectAll(nil)
        }
    }
}
