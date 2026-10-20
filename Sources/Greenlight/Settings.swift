// The one thing Greenlight remembers: which account to watch.
import Foundation

final class Settings: ObservableObject {
    static let shared = Settings()
    /// False in demo and screenshot modes, so they never overwrite the real settings.
    static var persist = true

    /// Organization or user login. Empty means "pick one for me" on first launch.
    @Published var account: String {
        didSet { if Settings.persist { UserDefaults.standard.set(account, forKey: "account") } }
    }

    /// Overrides the included minutes guessed from the plan:
    /// `defaults write io.github.vincent-caetano.greenlight includedMinutes -int 3000`
    var includedOverride: Double? {
        let v = UserDefaults.standard.double(forKey: "includedMinutes")
        return v > 0 ? v : nil
    }

    private init() {
        account = UserDefaults.standard.string(forKey: "account") ?? ""
    }
}
