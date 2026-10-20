// GitHub Greenlight: GitHub Actions minutes, budget and runs in the macOS menubar.
//
//   Greenlight                    normal menubar app
//   Greenlight --demo             menubar app with made-up data (no GitHub calls)
//   Greenlight --screenshots DIR  render the README images with demo data, then quit
//   Greenlight --iconset DIR      render AppIcon.iconset PNGs, then quit
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    let demo: Bool
    var item: NSStatusItem!
    let popover = NSPopover()

    init(demo: Bool) { self.demo = demo }

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)

        let host = NSHostingController(rootView: PopoverView().environmentObject(model))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient

        model.onUpdate = { [weak self] in self?.refreshIcon() }
        if demo {
            Settings.persist = false
            model.loadDemo()
        } else {
            model.start()
        }
        refreshIcon()
    }

    func refreshIcon() {
        guard let button = item.button else { return }
        guard model.hasData else {
            button.image = GitHubMark.image
            button.contentTintColor = model.error != nil ? .systemRed : nil
            return
        }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        button.contentTintColor = nil
        button.image = MenubarIcon.image(model, ink: model.online ? (dark ? .white : .black) : .systemOrange)
    }

    @objc func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
}

let args = CommandLine.arguments
func argument(after flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if let dir = argument(after: "--screenshots") {
    MainActor.assumeIsolated { Screenshots.render(to: dir) }
    exit(0)
} else if let dir = argument(after: "--iconset") {
    MainActor.assumeIsolated { Screenshots.iconset(to: dir) }
    exit(0)
}

let delegate = AppDelegate(demo: args.contains("--demo"))
app.delegate = delegate
app.run()
