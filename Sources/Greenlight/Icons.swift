// The menubar image, the GitHub mark, and the app icon.
import AppKit
import SwiftUI

// MARK: - GitHub mark

enum GitHubMark {
    /// Octicons `mark-github`, as a template image so it follows the menubar ink.
    static let image: NSImage = {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>"#
        let img = NSImage(data: Data(svg.utf8)) ?? NSImage()
        img.isTemplate = true
        return img
    }()

    /// The mark filled with one color, for drawing inside another image.
    static func tinted(_ color: NSColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            image.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
    }
}

// MARK: - Menubar

enum MenubarIcon {
    /// GitHub mark, a vertical gauge, then a small label over a bold value, drawn like
    /// the system's own menubar extras. Until the included minutes run out the gauge
    /// and MIN show minutes used. After that, with a budget set, they switch to the
    /// budget and LEFT shows the dollars remaining. RUN appears only while a workflow
    /// is running. Failures stay in the popover so the menubar never nags.
    static func image(_ m: Model, ink: NSColor) -> NSImage {
        let H: CGFloat = 22, barW: CGFloat = 7, barH: CGFloat = 16, gap: CGFloat = 6, logo: CGFloat = 15
        let smallFont = NSFont.systemFont(ofSize: 7, weight: .semibold)
        let valueFont = NSFont.systemFont(ofSize: 11.5, weight: .bold)
        func attrs(_ f: NSFont) -> [NSAttributedString.Key: Any] { [.font: f, .foregroundColor: ink] }

        let onBudget = m.overIncluded && m.budget != nil
        let gaugePct = onBudget ? m.budgetPct : m.pct
        let fill = gaugePct >= WARN ? NSColor.systemRed : gaugePct >= CAUTION ? NSColor.systemOrange
            : NSColor(red: 0.45, green: 0.75, blue: 1, alpha: 1)
        var blocks: [(label: String, value: String)] = [onBudget
            ? ("LEFT", Format.dollars(m.budgetLeft ?? 0))
            : ("MIN", String(format: "%.0f%%", m.pct))]
        if !m.running.isEmpty { blocks.append(("RUN", "\(m.running.count)")) }

        let widths = blocks.map { b in
            max((b.value as NSString).size(withAttributes: attrs(valueFont)).width,
                (b.label as NSString).size(withAttributes: attrs(smallFont)).width)
        }
        let lead = logo + 4 + barW
        let W = ceil(lead + gap + widths.reduce(0, +) + gap * CGFloat(blocks.count - 1) + 1)
        let mark = GitHubMark.tinted(ink, size: logo)

        let image = NSImage(size: NSSize(width: W, height: H), flipped: false) { _ in
            mark.draw(in: NSRect(x: 0, y: (H - logo) / 2, width: logo, height: logo))

            // Gauge: outlined bar filled to the percent used
            let bx = logo + 4, by = (H - barH) / 2
            let outline = NSBezierPath(roundedRect: NSRect(x: bx + 0.5, y: by + 0.5, width: barW - 1, height: barH - 1), xRadius: 2, yRadius: 2)
            ink.withAlphaComponent(0.85).setStroke()
            outline.lineWidth = 1
            outline.stroke()
            let inner = NSRect(x: bx + 1.5, y: by + 1.5, width: barW - 3, height: barH - 3)
            let h = inner.height * CGFloat(max(0, min(100, gaugePct))) / 100
            if h > 0 {
                fill.setFill()
                NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: max(h, 1)), xRadius: 1, yRadius: 1).fill()
            }

            // Blocks: small label centered over a bold value
            var x = lead + gap
            for (b, w) in zip(blocks, widths) {
                let l = b.label as NSString, v = b.value as NSString
                let lsz = l.size(withAttributes: attrs(smallFont)), vsz = v.size(withAttributes: attrs(valueFont))
                l.draw(at: NSPoint(x: x + (w - lsz.width) / 2, y: 12.5), withAttributes: attrs(smallFont))
                v.draw(at: NSPoint(x: x + (w - vsz.width) / 2, y: -1), withAttributes: attrs(valueFont))
                x += w + gap
            }
            return true
        }
        image.accessibilityDescription = onBudget
            ? "GitHub Actions: \(Format.dollars(m.budgetLeft ?? 0)) of budget left"
            : String(format: "GitHub Actions: %.0f%% of included minutes used", m.pct)
        return image
    }
}

// MARK: - App icon

/// A traffic light on the same dark tile as Hostbar's icon: two lights off, the green one on.
struct AppIcon: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.17, green: 0.21, blue: 0.24),
                                                  Color(red: 0.05, green: 0.07, blue: 0.08)],
                                         startPoint: .top, endPoint: .bottom))
                RadialGradient(colors: [Palette.green.opacity(0.35), .clear],
                               center: .init(x: 0.5, y: 0.7), startRadius: 0, endRadius: s * 0.5)
                    .clipShape(RoundedRectangle(cornerRadius: s * 0.225, style: .continuous))
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: max(1, s * 0.006))
                housing(s)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func housing(_ s: CGFloat) -> some View {
        let w = s * 0.3, h = s * 0.66, line = s * 0.028, light = w * 0.62
        return ZStack {
            RoundedRectangle(cornerRadius: w * 0.5, style: .continuous)
                .fill(Color.black.opacity(0.35))
            RoundedRectangle(cornerRadius: w * 0.5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: line)
            VStack(spacing: (h - light * 3) / 4.2) {
                Circle().fill(Color.white.opacity(0.13)).frame(width: light, height: light)
                Circle().fill(Color.white.opacity(0.13)).frame(width: light, height: light)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.62, green: 1, blue: 0.7), Palette.green],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: light * 0.6))
                    .frame(width: light, height: light)
                    .shadow(color: Palette.green.opacity(0.9), radius: s * 0.05)
            }
        }
        .frame(width: w, height: h)
    }
}
