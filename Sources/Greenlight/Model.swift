// Live state: minutes used, budget, and workflow runs. Runs refresh every minute,
// billing every 15 minutes (GitHub itself only updates usage about once an hour).
import Foundation

let ACTIVE_DAYS = 30.0          // only watch repos pushed in the last N days
let FAIL_WINDOW = 24.0 * 3600   // failures older than this are ignored
let WARN = 90.0                 // percent at which a gauge turns red
let CAUTION = 70.0              // percent at which a gauge turns orange

final class Model: ObservableObject {
    @Published var account: Account?
    @Published var accounts: [String] = []      // your login and your orgs, for the account menu
    @Published var online = false
    @Published var error: String?
    @Published var updated: Date?

    @Published var included = 2000.0
    @Published var used = 0.0                   // included minutes consumed, with runner multipliers
    @Published var overage = 0.0                // dollars billed this month
    @Published var budget: Double?              // Actions budget, dollars per month
    @Published var stopAtBudget = false
    @Published var pricePerMinute = 0.006
    @Published var byRepo: [(name: String, minutes: Double)] = []
    @Published var byRunner: [(sku: String, minutes: Double)] = []
    @Published var runs: [Run] = []

    // MARK: Derived

    var hasData: Bool { updated != nil && account != nil }
    var pct: Double { included > 0 ? 100 * used / included : 0 }
    var overIncluded: Bool { used >= included }
    var budgetLeft: Double? { budget.map { max(0, $0 - overage) } }
    var budgetPct: Double { budget.map { $0 > 0 ? 100 * overage / $0 : 100 } ?? 0 }
    var budgetReached: Bool { stopAtBudget && (budgetLeft ?? 1) <= 0 }

    var running: [Run] { runs.filter(\.isActive).sorted { $0.started > $1.started } }
    var queued: [Run] { runs.filter(\.isQueued) }
    var recent: [Run] { Array(runs.filter { $0.status == "completed" }.sorted { $0.updatedAt > $1.updatedAt }.prefix(6)) }

    /// The latest run per repo, workflow and branch in the last 24h, when it failed.
    var failed: [Run] {
        let window = runs.filter { Date().timeIntervalSince($0.started) < FAIL_WINDOW }
        let latest = Dictionary(grouping: window) { "\($0.repo)|\($0.workflow)|\($0.branch)" }
            .values.compactMap { $0.max { $0.started < $1.started } }
        return latest.filter(\.isFailure).sorted { $0.updatedAt > $1.updatedAt }
    }

    var daysInMonth: Int { Calendar.current.range(of: .day, in: .month, for: now)?.count ?? 30 }
    var dayOfMonth: Int { Calendar.current.component(.day, from: now) }
    var projected: Double { used / Double(max(dayOfMonth, 1)) * Double(daysInMonth) }
    var resetDate: Date {
        let c = Calendar.current
        let start = c.date(from: c.dateComponents([.year, .month], from: now)) ?? now
        return c.date(byAdding: .month, value: 1, to: start) ?? now
    }

    /// The clock the model reads. Demo mode pins it so screenshots stay stable.
    var now: Date { clock ?? Date() }
    var clock: Date?

    var onUpdate: (() -> Void)?

    private let settings = Settings.shared
    private var repos: [String] = []
    private var reposFetched: Date?
    private var billingFetched: Date?
    private var busy = false
    private var timer: Timer?

    // MARK: Refresh

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// Switches to another account and starts over.
    func watch(_ login: String) {
        settings.account = login
        account = nil; runs = []; byRepo = []; byRunner = []; budget = nil
        repos = []; reposFetched = nil; billingFetched = nil; updated = nil
        onUpdate?()
        refresh()
    }

    func refresh(force: Bool = false) {
        guard !busy else { return }
        guard GH != nil else {
            error = "GitHub CLI not found. Install it with `brew install gh`."
            onUpdate?(); return
        }
        busy = true
        if force { billingFetched = nil; reposFetched = nil }
        let wanted = settings.account
        let current = account
        DispatchQueue.global(qos: .utility).async { [self] in
            let now = Date()
            let resolved = (current?.login == wanted && current != nil) ? current : resolve(wanted)
            guard let acct = resolved else {
                DispatchQueue.main.async { [self] in
                    error = "Not logged in to gh. Run `gh auth login`."
                    online = false; busy = false; onUpdate?()
                }
                return
            }

            var repoList: [String]?
            if reposFetched.map({ now.timeIntervalSince($0) > 3600 }) ?? true,
               let list = ghDecode([RepoInfo].self, acct.reposPath) {
                repoList = list.filter { !$0.archived && now.timeIntervalSince($0.pushedAt ?? .distantPast) < ACTIVE_DAYS * 86400 }
                    .map(\.name)
            }

            var usage: UsageResponse?, budgets: BudgetsResponse?
            if billingFetched.map({ now.timeIntervalSince($0) > 900 }) ?? true {
                let c = Calendar.current.dateComponents([.year, .month], from: now)
                usage = ghDecode(UsageResponse.self, acct.usagePath(year: c.year!, month: c.month!))
                if usage != nil { budgets = ghDecode(BudgetsResponse.self, acct.budgetsPath) }
            }

            var all: [Run] = [], ok = true
            for repo in repoList ?? DispatchQueue.main.sync(execute: { repos }) {
                guard let r = ghDecode(RunsResponse.self, acct.runsPath(repo)) else { ok = false; continue }
                all += r.workflowRuns.map { var x = $0; x.repo = repo; return x }
            }

            DispatchQueue.main.async { [self] in
                guard settings.account == wanted else { busy = false; return }   // switched mid-refresh
                account = acct
                if let repoList { repos = repoList; reposFetched = now }
                if let usage { apply(usage); billingFetched = now }
                if let budgets {
                    let b = budgets.budgets.first { $0.budgetProductSku == "actions" }
                    budget = b?.budgetAmount; stopAtBudget = b?.preventFurtherUsage ?? false
                }
                runs = all
                online = ok && billingFetched != nil
                error = billingFetched == nil ? "Could not read billing for \(acct.login). You need to be an owner or billing manager."
                    : ok ? nil : "Some repositories did not load."
                updated = now
                busy = false
                onUpdate?()
            }
        }
    }

    /// Works out whether the login is an org or a user, its plan, and your account list.
    private func resolve(_ wanted: String) -> Account? {
        guard let me = ghDecode(UserInfo.self, "user") else { return nil }
        let orgs = ghDecode([OrgInfo].self, "user/orgs")?.map(\.login) ?? []
        let login = wanted.isEmpty ? (orgs.first ?? me.login) : wanted
        let isSelf = login.caseInsensitiveCompare(me.login) == .orderedSame
        let info = isSelf ? me : ghDecode(UserInfo.self, "users/\(login)")
        let isOrg = info?.type == "Organization"
        let plan = isSelf ? me.plan?.name : isOrg ? ghDecode(UserInfo.self, "orgs/\(login)")?.plan?.name : nil
        let minutes = settings.includedOverride ?? includedMinutes(plan: plan)
        DispatchQueue.main.async { [self] in
            accounts = [me.login] + orgs
            included = minutes
            if settings.account.isEmpty { settings.account = login }
        }
        return Account(login: login, isOrg: isOrg, isSelf: isSelf)
    }

    func apply(_ u: UsageResponse) {
        let mins = u.usageItems.filter { $0.product == "actions" && $0.unitType == "Minutes" }
        used = mins.reduce(0) { $0 + $1.quantity * multiplier($1.sku) }
        overage = u.usageItems.filter { $0.product == "actions" }.reduce(0) { $0 + $1.netAmount }
        pricePerMinute = mins.first { $0.sku == "Actions Linux" }?.pricePerUnit ?? pricePerMinute
        byRepo = Dictionary(grouping: mins) { $0.repositoryName ?? "other" }
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.quantity * multiplier($1.sku) }) }
            .sorted { $0.1 > $1.1 }
        byRunner = Dictionary(grouping: mins, by: \.sku)
            .map { ($0.key.replacingOccurrences(of: "Actions ", with: ""), $0.value.reduce(0) { $0 + $1.quantity }) }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: Run actions

    func rerun(_ r: Run) { act(["run", "rerun", "\(r.id)", "--failed", "-R", "\(account?.login ?? "")/\(r.repo)"]) }
    func cancel(_ r: Run) { act(["run", "cancel", "\(r.id)", "-R", "\(account?.login ?? "")/\(r.repo)"]) }

    private func act(_ args: [String]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = ghRun(args)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.refresh() }
        }
    }
}
