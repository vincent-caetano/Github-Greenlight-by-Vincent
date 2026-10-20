// Renders the README images and the app icon from the real views, using demo data.
import AppKit
import SwiftUI

@MainActor
enum Screenshots {
    static func render(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Settings.persist = false
        Format.locale = Locale(identifier: "en_US")
        let model = Model()
        model.loadDemo(.healthy)

        func panel(_ tab: Tab, dark: Bool) -> some View {
            PopoverView(fixedTab: tab).environmentObject(model).modifier(PanelChrome(dark: dark))
        }

        // Banner: icon, name and tagline next to the Usage tab
        capture(Banner(panel: AnyView(panel(.usage, dark: true))), dark: true, to: "\(dir)/banner.png")

        // Hero: wallpaper, menubar, and the Runs tab dropping from the menubar item
        capture(Hero(menubar: MenubarIcon.image(model, ink: .white), panel: AnyView(panel(.runs, dark: true))),
                dark: true, to: "\(dir)/hero.png")

        // Both tabs side by side, in both appearances
        for dark in [true, false] {
            capture(HStack(alignment: .top, spacing: 8) {
                ForEach(Tab.allCases, id: \.rawValue) { panel($0, dark: dark) }
            }.padding(24), dark: dark, to: "\(dir)/tabs-\(dark ? "dark" : "light").png")
        }

        // Menubar close-ups: within the included minutes, then billing against the budget
        for dark in [true, false] {
            let ink: NSColor = dark ? .white : .black
            model.loadDemo(.healthy)
            let healthy = MenubarIcon.image(model, ink: ink)
            model.loadDemo(.onBudget)
            model.runs = []
            let budget = MenubarIcon.image(model, ink: ink)
            capture(VStack(alignment: .leading, spacing: 0) {
                MenubarStrip(image: healthy, dark: dark)
                MenubarStrip(image: budget, dark: dark)
            }, dark: dark, to: "\(dir)/menubar-\(dark ? "dark" : "light").png")
        }

        // Budget view, once the included minutes are gone
        model.loadDemo(.onBudget)
        for dark in [true, false] {
            capture(panel(.usage, dark: dark), dark: dark, to: "\(dir)/budget-\(dark ? "dark" : "light").png")
        }
    }

    /// AppIcon.iconset, ready for `iconutil -c icns`.
    static func iconset(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = CGFloat(base * scale)
                let view = AppIcon().padding(px * 0.098).frame(width: px, height: px)
                let r = ImageRenderer(content: view)
                r.scale = 1
                guard let cg = r.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
            }
        }
    }

    /// Draws a view in an offscreen window so AppKit-backed controls render too.
    static func capture<V: View>(_ view: V, dark: Bool, to path: String) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        hosting.appearance = appearance
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
    }
}

/// Popover look for screenshots: rounded panel, hairline border, soft shadow.
struct PanelChrome: ViewModifier {
    var dark: Bool
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(dark ? Color(white: 0.14) : Color(white: 0.975)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(dark ? 0.14 : 0.1)))
            .shadow(color: .black.opacity(dark ? 0.45 : 0.18), radius: 18, y: 8)
            .padding(28)
    }
}

/// Deep green wallpaper shared by the banner and the hero.
struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.09, blue: 0.08),
                                    Color(red: 0.05, green: 0.24, blue: 0.17),
                                    Color(red: 0.16, green: 0.55, blue: 0.33)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.5, green: 1, blue: 0.6).opacity(0.22), .clear],
                           center: .init(x: 0.18, y: 0.8), startRadius: 10, endRadius: 460)
        }
    }
}

struct Banner: View {
    var panel: AnyView
    var body: some View {
        ZStack {
            Wallpaper()
            HStack(alignment: .center, spacing: 36) {
                VStack(alignment: .leading, spacing: 18) {
                    AppIcon().frame(width: 132, height: 132).shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GitHub Greenlight").font(.system(size: 46, weight: .bold))
                        Text("by Vincent").font(.system(size: 20, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                    }
                    Text("GitHub Actions minutes, budget\nand runs, live in your Mac menubar.")
                        .font(.system(size: 21, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(3)
                    HStack(spacing: 8) {
                        chip("Native Swift"); chip("No tokens stored"); chip("Free and open source")
                    }
                }
                .foregroundStyle(.white)
                panel.scaleEffect(0.92)
            }
            .padding(.horizontal, 60)
        }
        .frame(width: 1280, height: 760)
    }

    func chip(_ s: String) -> some View {
        Text(s).font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2)))
    }
}

struct Hero: View {
    var menubar: NSImage
    var panel: AnyView

    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper()
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Image(systemName: "apple.logo").font(.system(size: 15))
                    Text("Finder").fontWeight(.bold)
                    Text("File")
                    Text("Edit")
                    Spacer()
                    Image(nsImage: menubar)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.2)))
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75percent")
                    Text("Thu Oct 22  9:41")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 30)
                .background(Color.black.opacity(0.22))
                HStack {
                    Spacer()
                    panel.padding(.trailing, 120).padding(.top, -20)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 860, height: 800)
    }
}

struct MenubarStrip: View {
    var image: NSImage
    var dark: Bool
    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: image)
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("9:41")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(dark ? Color.white : Color.black)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(dark ? Color(white: 0.12) : Color(white: 0.94)))
        .padding(8)
    }
}
