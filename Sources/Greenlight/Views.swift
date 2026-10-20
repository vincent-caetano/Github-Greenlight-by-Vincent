// The popover: Usage and Runs tabs, header and footer.
import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Formatting

enum Format {
    /// Screenshots pin this to English so the README reads the same everywhere.
    static var locale = Locale.current

    static func minutes(_ m: Double) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: m.rounded(.down))) ?? "\(Int(m))"
    }
    static func dollars(_ d: Double) -> String { String(format: "$%.2f", d) }
    static func ago(_ d: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(d))
        return s < 60 ? "now" : s < 3600 ? "\(s / 60)m" : s < 86400 ? "\(s / 3600)h" : "\(s / 86400)d"
    }
    static func duration(_ s: Double) -> String { s < 60 ? "\(Int(s))s" : "\(Int(s / 60))m" }
}

enum Palette {
    static let blue = Color(red: 0.25, green: 0.6, blue: 1)
    static let yellow = Color(red: 1, green: 0.8, blue: 0.2)
    static let green = Color(red: 0.3, green: 0.82, blue: 0.45)
    static let red = Color(red: 1, green: 0.35, blue: 0.4)
    static let orange = Color(red: 1, green: 0.6, blue: 0.2)

    static func level(_ pct: Double) -> Color { pct >= WARN ? red : pct >= CAUTION ? orange : blue }
}

func openURL(_ url: String) { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }

// MARK: - Building blocks

struct UsageBar: View {
    var pct: Double
    var color: Color
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color).frame(width: max(height, g.size.width * CGFloat(min(pct, 100) / 100)))
            }
        }
        .frame(height: height)
    }
}

struct Meter: View {
    var label: String
    var detail: String
    var value: String
    var color: Color
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(color)
        }
    }
}

struct KV: View {
    var key: String
    var value: String
    var color: Color = .primary
    var body: some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).monospacedDigit().foregroundStyle(color)
        }
        .font(.system(size: 12))
    }
}

struct Dot: View {
    var color: Color
    var body: some View { Circle().fill(color).frame(width: 7, height: 7) }
}

struct Live: View {
    var icon: String
    var value: String
    var label: String
    var color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 16, weight: .semibold).monospacedDigit())
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Block<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
            content
        }
    }
}

/// One workflow run: status dot, workflow, repo and branch, age. Click opens it on GitHub.
struct RunRow: View {
    @EnvironmentObject var m: Model
    var run: Run
    var color: Color
    var trailing: String

    var body: some View {
        Button { openURL(run.htmlUrl) } label: {
            HStack(spacing: 8) {
                Dot(color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(run.workflow).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text("\(run.repo) · \(run.branch)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(trailing).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open run") { openURL(run.htmlUrl) }
            if run.isFailure { Button("Re-run failed jobs") { m.rerun(run) } }
            if run.isActive || run.isQueued { Button("Cancel run") { m.cancel(run) } }
            Button("Copy run URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(run.htmlUrl, forType: .string)
            }
        }
    }
}

// MARK: - Popover

enum Tab: Int, CaseIterable {
    case usage, runs
    var title: String { ["Usage", "Runs"][rawValue] }
    var icon: String { ["gauge.with.dots.needle.67percent", "play.circle"][rawValue] }
}

struct PopoverView: View {
    @EnvironmentObject var m: Model
    @AppStorage("tab") private var storedTab = 0
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    /// Pins a tab for screenshots.
    var fixedTab: Tab?

    var current: Tab { fixedTab ?? Tab(rawValue: storedTab) ?? .usage }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            tabBar
            Text(current.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 14) {
                if let error = m.error, !m.hasData {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !m.hasData {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Asking GitHub…").font(.system(size: 12)) }
                } else {
                    switch current {
                    case .usage: usage
                    case .runs: runs
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // Header: GitHub mark, account, status, last update
    var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: GitHubMark.image).resizable().frame(width: 16, height: 16)
            Text(m.account?.login ?? "GitHub").font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text("Actions").font(.system(size: 14)).foregroundStyle(.secondary)
            Spacer()
            Dot(color: m.online ? Palette.green : m.hasData ? Palette.yellow : Palette.red)
            Text(m.updated.map { "updated \(Format.ago($0, now: m.now))" } ?? "loading")
                .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 2)
    }

    var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.rawValue) { t in
                Button { storedTab = t.rawValue } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .foregroundStyle(t == current ? Color.accentColor : .primary.opacity(0.7))
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(t == current ? Color.accentColor.opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    // MARK: Usage tab

    var usage: some View {
        Group {
            Block(title: nil) {
                Meter(label: "Minutes", detail: String(format: "%.0f%%", m.pct),
                      value: "\(Format.minutes(m.used)) / \(Format.minutes(m.included))", color: Palette.level(m.pct))
                UsageBar(pct: m.pct, color: Palette.level(m.pct))
            }
            VStack(spacing: 5) {
                KV(key: "Projected this month", value: "\(Format.minutes(m.projected)) min",
                   color: m.projected > m.included ? Palette.orange : .primary)
                KV(key: "Resets", value: m.resetDate.formatted(.dateTime.month(.abbreviated).day().locale(Format.locale))
                   + " · in \(m.daysInMonth - m.dayOfMonth + 1)d")
            }
            if let budget = m.budget {
                Divider()
                Block(title: nil) {
                    Meter(label: "Budget", detail: String(format: "%.0f%%", m.budgetPct),
                          value: "\(Format.dollars(m.overage)) / \(Format.dollars(budget))",
                          color: m.overage > 0 ? Palette.level(m.budgetPct) : .primary)
                    UsageBar(pct: m.budgetPct, color: Palette.level(m.budgetPct))
                    VStack(spacing: 5) {
                        KV(key: "Left", value: "\(Format.dollars(m.budgetLeft ?? 0)) · ~\(Format.minutes((m.budgetLeft ?? 0) / m.pricePerMinute)) min")
                        KV(key: "At the limit", value: m.stopAtBudget ? "Runs stop" : "Keeps billing")
                    }
                }
            } else if m.overage > 0 {
                KV(key: "Billed overage", value: Format.dollars(m.overage), color: Palette.red)
            }
            if m.budgetReached || m.overIncluded {
                Label(m.budgetReached ? "Budget reached. New runs are blocked until the reset."
                      : m.budget != nil ? "Free minutes used up. Runs now bill against the budget."
                      : "Free minutes used up. Runs now bill per minute.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(m.budgetReached ? Palette.red : Palette.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !m.byRepo.isEmpty {
                Divider()
                Block(title: "By repository") {
                    let top = max(m.byRepo.first?.minutes ?? 1, 1)
                    VStack(spacing: 7) {
                        ForEach(m.byRepo.prefix(6), id: \.name) { r in
                            HStack(spacing: 8) {
                                Text(r.name).font(.system(size: 12)).lineLimit(1).frame(width: 110, alignment: .leading)
                                UsageBar(pct: 100 * r.minutes / top, color: Palette.blue, height: 5)
                                Text(Format.minutes(r.minutes)).font(.system(size: 12, weight: .medium).monospacedDigit())
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            if m.byRunner.count > 1 || m.byRunner.contains(where: { multiplier($0.sku) > 1 }) {
                Block(title: "By runner") {
                    VStack(spacing: 5) {
                        ForEach(m.byRunner, id: \.sku) { r in
                            let x = multiplier(r.sku)
                            KV(key: r.sku, value: x > 1 ? "\(Format.minutes(r.minutes)) × \(Int(x))" : Format.minutes(r.minutes))
                        }
                    }
                }
            }
        }
    }

    // MARK: Runs tab

    var runs: some View {
        Group {
            HStack {
                Live(icon: "play.fill", value: "\(m.running.count)", label: "Running", color: Palette.blue)
                Live(icon: "pause.fill", value: "\(m.queued.count)", label: "Queued", color: Palette.yellow)
                Live(icon: "xmark", value: "\(m.failed.count)", label: "Failed, 24h",
                     color: m.failed.isEmpty ? Palette.green : Palette.red)
            }
            if !m.running.isEmpty || !m.queued.isEmpty {
                Divider()
                Block(title: "In progress") {
                    VStack(spacing: 8) {
                        ForEach(m.running) { RunRow(run: $0, color: Palette.blue, trailing: Format.ago($0.started, now: m.now)) }
                        ForEach(m.queued) { RunRow(run: $0, color: Palette.yellow, trailing: "queued") }
                    }
                }
            }
            if !m.failed.isEmpty {
                Divider()
                Block(title: "Failed") {
                    VStack(spacing: 8) {
                        ForEach(m.failed.prefix(5)) { RunRow(run: $0, color: Palette.red, trailing: Format.ago($0.updatedAt, now: m.now)) }
                        if m.failed.count > 5 {
                            Text("+\(m.failed.count - 5) more").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider()
            Block(title: "Recent") {
                VStack(spacing: 8) {
                    ForEach(m.recent) { r in
                        RunRow(run: r, color: r.conclusion == "success" ? Palette.green : r.isFailure ? Palette.red : .secondary,
                               trailing: "\(Format.duration(r.seconds)) · \(Format.ago(r.updatedAt, now: m.now))")
                    }
                }
            }
        }
    }

    // MARK: Footer

    var footer: some View {
        HStack(spacing: 8) {
            footerButton("Billing", "creditcard") { if let a = m.account { openURL(a.billingURL) } }
            footerButton("Actions", "play.circle") {
                guard let a = m.account else { return }
                openURL(m.failed.first.map { "https://github.com/\(a.login)/\($0.repo)/actions" } ?? "https://github.com/\(a.login)")
            }
            Menu {
                if m.accounts.count > 1 {
                    Picker("Account", selection: Binding(get: { m.account?.login ?? "" }, set: { m.watch($0) })) {
                        ForEach(m.accounts, id: \.self) { Text($0).tag($0) }
                    }
                    Divider()
                }
                Button("Refresh now") { m.refresh(force: true) }
                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {}
                    openAtLogin = SMAppService.mainApp.status == .enabled
                }))
                Divider()
                Button("Quit GitHub Greenlight") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        }
    }

    func footerButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
