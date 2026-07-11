import AppKit
import SwiftUI

enum PanelMode: String, CaseIterable, Identifiable {
    case desktop
    case floating
    case normal

    var id: Self { self }
    var title: String {
        switch self {
        case .desktop: "Auf dem Desktop"
        case .floating: "Immer im Vordergrund"
        case .normal: "Normales Fenster"
        }
    }

    var symbol: String {
        switch self {
        case .desktop: "macbook"
        case .floating: "rectangle.on.rectangle"
        case .normal: "macwindow"
        }
    }
}

struct WindowModeController: NSViewRepresentable {
    let mode: PanelMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.collectionBehavior.insert(.canJoinAllSpaces)

        switch mode {
        case .desktop:
            let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow)) + 1
            window.level = NSWindow.Level(rawValue: desktopLevel)
            window.collectionBehavior.insert(.stationary)
            window.collectionBehavior.insert(.ignoresCycle)
        case .floating:
            window.level = .floating
            window.collectionBehavior.remove(.stationary)
            window.collectionBehavior.remove(.ignoresCycle)
        case .normal:
            window.level = .normal
            window.collectionBehavior.remove(.stationary)
            window.collectionBehavior.remove(.ignoresCycle)
        }
    }
}
