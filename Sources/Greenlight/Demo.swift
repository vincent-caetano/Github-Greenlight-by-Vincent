// Made-up data for `--demo` and the README images. No real account, repo or bill.
import Foundation

enum Scenario {
    case healthy    // 64% of included minutes, two runs going
    case onBudget   // included minutes used up, billing against a $10 budget
}

extension Model {
    func loadDemo(_ scenario: Scenario = .healthy) {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9, minute: 41)) ?? Date()
        clock = now
        account = Account(login: "acme-labs", isOrg: true, isSelf: false)
        accounts = ["octo-dev", "acme-labs"]
        included = 3000
        budget = 10
        stopAtBudget = true
        pricePerMinute = 0.006

        let repos: [(String, Double)] = scenario == .healthy
            ? [("web-app", 1124), ("api", 512), ("ios-app", 218), ("docs-site", 66)]
            : [("web-app", 1806), ("api", 804), ("ios-app", 322), ("docs-site", 85)]
        byRepo = repos.map { (name: $0.0, minutes: $0.1) }
        used = repos.reduce(0) { $0 + $1.1 }
        byRunner = scenario == .healthy
            ? [(sku: "Linux", minutes: 1702), (sku: "macOS", minutes: 21.8)]
            : [(sku: "Linux", minutes: 2695), (sku: "macOS", minutes: 32.2)]
        overage = scenario == .healthy ? 0 : 2.58

        func run(_ id: Int, _ repo: String, _ name: String, _ branch: String, _ status: String,
                 _ conclusion: String?, startedMinutesAgo: Double, took: Double) -> Run {
            let started = now.addingTimeInterval(-startedMinutesAgo * 60)
            let json = """
            {"id":\(id),"name":"\(name)","status":"\(status)","conclusion":\(conclusion.map { "\"\($0)\"" } ?? "null"),
             "head_branch":"\(branch)","html_url":"https://github.com/acme-labs/\(repo)/actions/runs/\(id)",
             "run_started_at":"\(ISO8601DateFormatter().string(from: started))",
             "updated_at":"\(ISO8601DateFormatter().string(from: started.addingTimeInterval(took * 60)))"}
            """
            var r = try! decoder.decode(Run.self, from: Data(json.utf8))
            r.repo = repo
            return r
        }
        runs = [
            run(9001, "web-app", "CI", "feat/checkout", "in_progress", nil, startedMinutesAgo: 3, took: 3),
            run(9002, "api", "Deploy", "main", "in_progress", nil, startedMinutesAgo: 1, took: 1),
            run(9003, "ios-app", "TestFlight", "release/2.4", "queued", nil, startedMinutesAgo: 0.5, took: 0),
            run(9004, "web-app", "E2E", "fix/cart-total", "completed", "failure", startedMinutesAgo: 52, took: 9),
            run(9005, "api", "CI", "main", "completed", "success", startedMinutesAgo: 20, took: 4),
            run(9006, "web-app", "CI", "main", "completed", "success", startedMinutesAgo: 35, took: 6),
            run(9007, "docs-site", "Pages", "main", "completed", "success", startedMinutesAgo: 70, took: 2),
            run(9008, "ios-app", "Unit tests", "main", "completed", "success", startedMinutesAgo: 110, took: 11),
            run(9009, "api", "Nightly backup", "main", "completed", "success", startedMinutesAgo: 400, took: 1),
        ]
        online = true
        error = nil
        updated = now.addingTimeInterval(-20)
    }
}
