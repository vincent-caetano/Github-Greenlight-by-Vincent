// Everything Greenlight asks GitHub, through the `gh` CLI you are already logged in to.
import Foundation

/// The `gh` binary, found in the usual Homebrew and system locations.
let GH = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

// MARK: - Response types

struct UsageResponse: Decodable { let usageItems: [UsageItem] }
struct UsageItem: Decodable {
    let product: String
    let sku: String
    let quantity: Double
    let unitType: String
    let netAmount: Double
    let pricePerUnit: Double
    let repositoryName: String?
}

struct BudgetsResponse: Decodable { let budgets: [Budget] }
struct Budget: Decodable {
    let budgetProductSku: String?
    let budgetAmount: Double
    let preventFurtherUsage: Bool
}

struct RepoInfo: Decodable { let name: String; let archived: Bool; let pushedAt: Date? }

struct RunsResponse: Decodable { let workflowRuns: [Run] }
struct Run: Decodable, Identifiable {
    let id: Int
    let name: String?
    let status: String
    let conclusion: String?
    let headBranch: String?
    let htmlUrl: String
    let runStartedAt: Date?
    let updatedAt: Date
    var repo: String = ""

    enum CodingKeys: String, CodingKey { case id, name, status, conclusion, headBranch, htmlUrl, runStartedAt, updatedAt }

    var workflow: String { name ?? "workflow" }
    var branch: String { headBranch ?? "" }
    var started: Date { runStartedAt ?? updatedAt }
    var isActive: Bool { status == "in_progress" }
    var isQueued: Bool { ["queued", "waiting", "pending", "requested"].contains(status) }
    var isFailure: Bool { status == "completed" && ["failure", "timed_out", "startup_failure"].contains(conclusion ?? "") }
    var seconds: Double { updatedAt.timeIntervalSince(started) }
}

struct UserInfo: Decodable {
    let login: String
    let type: String?
    let plan: Plan?
    struct Plan: Decodable { let name: String }
}
struct OrgInfo: Decodable { let login: String }

/// Included Actions minutes per month for a GitHub plan.
func includedMinutes(plan: String?) -> Double {
    switch plan?.lowercased() ?? "" {
    case "pro", "team": return 3000
    case "business", "enterprise", "business_plus": return 50000
    default: return 2000
    }
}

/// How many included minutes one minute on a runner costs.
func multiplier(_ sku: String) -> Double { sku.contains("macOS") ? 10 : sku.contains("Windows") ? 2 : 1 }

let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    d.dateDecodingStrategy = .iso8601
    return d
}()

// MARK: - Account

/// A GitHub organization or user whose Actions usage is watched.
struct Account: Equatable {
    let login: String
    let isOrg: Bool
    let isSelf: Bool

    private var billing: String { isOrg ? "/organizations/\(login)/settings/billing" : "/users/\(login)/settings/billing" }

    func usagePath(year: Int, month: Int) -> String { "\(billing)/usage?year=\(year)&month=\(month)" }
    var budgetsPath: String { "\(billing)/budgets" }
    var reposPath: String {
        isOrg ? "orgs/\(login)/repos?per_page=100&sort=pushed"
            : isSelf ? "user/repos?affiliation=owner&per_page=100&sort=pushed"
            : "users/\(login)/repos?per_page=100&sort=pushed"
    }
    func runsPath(_ repo: String) -> String { "repos/\(login)/\(repo)/actions/runs?per_page=30" }
    var billingURL: String {
        isOrg ? "https://github.com/organizations/\(login)/settings/billing/usage" : "https://github.com/settings/billing/usage"
    }
}

// MARK: - gh

func gh(_ path: String) -> Data? { ghRun(["api", path]) }

func ghRun(_ args: [String]) -> Data? {
    guard let GH else { return nil }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: GH)
    p.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    env["GH_PROMPT_DISABLED"] = "1"
    p.environment = env
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? data : nil
}

func ghDecode<T: Decodable>(_ type: T.Type, _ path: String) -> T? {
    gh(path).flatMap { try? decoder.decode(T.self, from: $0) }
}
