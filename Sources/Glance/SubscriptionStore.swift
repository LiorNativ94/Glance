import Combine
import Foundation
import GlanceCore
import Security
import LocalAuthentication

struct SubscriptionCredentials {
    let accessToken: String
    let accountID: String?
    let plan: String?

    static func parse(_ data: Data, provider: SubscriptionProvider, now: Date = .now) throws -> Self {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubscriptionError.signIn(provider)
        }
        let values = root[provider == .claude ? "claudeAiOauth" : "tokens"] as? [String: Any]
        let tokenKey = provider == .claude ? "accessToken" : "access_token"
        guard let token = values?[tokenKey] as? String, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SubscriptionError.signIn(provider)
        }
        if provider == .claude {
            if let expiry = values?["expiresAt"] as? Double, expiry / 1000 <= now.timeIntervalSince1970 {
                throw SubscriptionError.signIn(provider)
            }
            if let scopes = values?["scopes"] as? [String], !scopes.contains("user:profile") {
                throw SubscriptionError.signIn(provider)
            }
        }
        return Self(accessToken: token, accountID: values?["account_id"] as? String,
                    plan: values?["subscriptionType"] as? String)
    }

    static func load(_ provider: SubscriptionProvider, allowInteraction: Bool) throws -> Self {
        let environment = ProcessInfo.processInfo.environment
        let key = provider == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
        let customHome = environment[key].flatMap { $0.isEmpty ? nil : $0 }
        let home = customHome.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(provider == .claude ? ".claude" : ".codex")
        let file = home.appendingPathComponent(provider == .claude ? ".credentials.json" : "auth.json")
        if FileManager.default.fileExists(atPath: file.path) {
            if let data = try? Data(contentsOf: file), let credentials = try? parse(data, provider: provider) {
                return credentials
            }
        }
        guard provider == .claude, customHome == nil else { throw SubscriptionError.signIn(provider) }
        // Interactive reads only follow a connect/refresh click. Background polling never prompts.
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw SubscriptionError.signIn(provider) }
        guard status == errSecSuccess, let data = result as? Data else { throw SubscriptionError.keychain }
        return try parse(data, provider: provider)
    }
}

/// Credentials go only to the provider's fixed HTTPS endpoint, never to redirects or a disk cache.
final class SubscriptionClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = SubscriptionClient()
    private var session: URLSession!
    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    static func request(_ provider: SubscriptionProvider, credentials: SubscriptionCredentials) -> URLRequest {
        let endpoint = provider == .claude ? "https://api.anthropic.com/api/oauth/usage" : "https://chatgpt.com/backend-api/wham/usage"
        var request = URLRequest(url: URL(string: endpoint)!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Glance", forHTTPHeaderField: "User-Agent")
        if provider == .claude {
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        } else if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    func fetch(_ provider: SubscriptionProvider, allowInteraction: Bool) async throws -> SubscriptionUsage {
        let credentials = try await Task.detached(priority: .utility) {
            try SubscriptionCredentials.load(provider, allowInteraction: allowInteraction)
        }.value
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: Self.request(provider, credentials: credentials))
        guard let response = response as? HTTPURLResponse else { throw SubscriptionError.invalidResponse }
        try Self.validate(response, provider: provider)
        // Parse quota before optional identity enrichment; profile failures cannot erase valid meters.
        let usage = try SubscriptionUsage.parse(data, provider: provider, plan: credentials.plan,
            accountID: provider == .codex ? credentials.accountID.flatMap { $0.isEmpty ? nil : SubscriptionIdentity.codexAccount($0) } : nil)
        guard provider == .claude else { return usage }
        var identity: (accountID: String?, email: String?) = (nil, nil)
        do {
            let (profile, profileResponse) = try await session.data(for: Self.profileRequest(credentials: credentials))
            guard let response = profileResponse as? HTTPURLResponse else { throw SubscriptionError.invalidResponse }
            try Self.validate(response, provider: .claude)
            identity = try SubscriptionIdentity.parseClaudeProfile(profile)
        } catch {
            try Task.checkCancellation()
        }
        return SubscriptionUsage(plan: usage.plan, windows: usage.windows, updatedAt: usage.updatedAt,
                                 accountID: identity.accountID, email: identity.email)
    }

    static func profileRequest(credentials: SubscriptionCredentials) -> URLRequest {
        var request = Self.request(.claude, credentials: credentials)
        request.url = URL(string: "https://api.anthropic.com/api/oauth/profile")!
        request.setValue(nil, forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 4
        return request
    }

    static func resetRequest(credentials: SubscriptionCredentials) -> URLRequest {
        var request = Self.request(.codex, credentials: credentials)
        request.url = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.timeoutInterval = 4
        return request
    }

    func fetchResetInventory(expectedAccountID: String) async throws -> ResetCreditInventory {
        let credentials = try await Task.detached(priority: .utility) {
            try SubscriptionCredentials.load(.codex, allowInteraction: false)
        }.value
        try Task.checkCancellation()
        guard let rawID = credentials.accountID, !rawID.isEmpty,
              SubscriptionIdentity.codexAccount(rawID) == expectedAccountID else { throw SubscriptionError.signIn(.codex) }
        let (data, response) = try await session.data(for: Self.resetRequest(credentials: credentials))
        guard let response = response as? HTTPURLResponse else { throw SubscriptionError.invalidResponse }
        try Self.validate(response, provider: .codex)
        return try ResetCreditInventory.parse(data)
    }

    static func validate(_ response: HTTPURLResponse, provider: SubscriptionProvider, now: Date = .now) throws {
        switch response.statusCode {
        case 200: return
        case 401, 403: throw SubscriptionError.signIn(provider)
        case 429:
            let raw = response.value(forHTTPHeaderField: "Retry-After") ?? ""
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let seconds = TimeInterval(raw).flatMap { $0.isFinite ? $0 : nil }
            let retry = seconds.map { now.addingTimeInterval(max(300, $0)) }
                ?? formatter.date(from: raw) ?? now.addingTimeInterval(300)
            throw SubscriptionError.rateLimited(max(now.addingTimeInterval(300), retry))
        default: throw SubscriptionError.server(response.statusCode)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class SubscriptionStore: ObservableObject {
    struct State {
        var usage: SubscriptionUsage?
        var error: String?
        var refreshing = false
        var resetInventory: ResetCreditInventory?
        var resetError: String?
        var resetUpdatedAt: Date?
        var resetRefreshing = false
    }
    typealias ResetFetch = (String) async throws -> ResetCreditInventory
    typealias Fetch = (SubscriptionProvider, Bool) async throws -> SubscriptionUsage
    @Published private(set) var enabled: Set<SubscriptionProvider>
    @Published private(set) var states: [SubscriptionProvider: State] = [:]
    private let defaults: UserDefaults
    private let fetch: Fetch
    private let resetFetch: ResetFetch?
    var onUsage: ((SubscriptionProvider, SubscriptionUsage) -> Void)?
    var detailTabs: [SubscriptionProvider: String] = [:]
    private var timer: Timer?
    private var tasks: [SubscriptionProvider: Task<Void, Never>] = [:]
    private var generations: [SubscriptionProvider: UUID] = [:]
    private var retryAfter: [SubscriptionProvider: Date] = [:]
    private var resetRetryAfter: Date?

    init(defaults: UserDefaults = .standard, startPolling: Bool = true,
         resetFetch: ResetFetch? = nil, fetch: Fetch? = nil) {
        self.defaults = defaults
        self.fetch = fetch ?? { try await SubscriptionClient.shared.fetch($0, allowInteraction: $1) }
        self.resetFetch = resetFetch ?? (fetch == nil ? { try await SubscriptionClient.shared.fetchResetInventory(expectedAccountID: $0) } : nil)
        enabled = Set((defaults.stringArray(forKey: "subscriptionProviders") ?? []).compactMap(SubscriptionProvider.init(rawValue:)))
        if startPolling {
            refreshAll()
            timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refreshAll() }
            timer?.tolerance = 30
        }
    }
    deinit { timer?.invalidate(); tasks.values.forEach { $0.cancel() } }

    func setEnabled(_ provider: SubscriptionProvider, _ value: Bool) {
        if value {
            enabled.insert(provider)
            refresh(provider, allowInteraction: true)
        } else {
            enabled.remove(provider)
            tasks.removeValue(forKey: provider)?.cancel()
            generations.removeValue(forKey: provider)
            states.removeValue(forKey: provider)
        }
        defaults.set(enabled.map(\.rawValue).sorted(), forKey: "subscriptionProviders")
    }

    func refreshAll() {
        for provider in enabled { refresh(provider) }
    }

    func refresh(_ provider: SubscriptionProvider, allowInteraction: Bool = false) {
        guard enabled.contains(provider), tasks[provider] == nil,
              (retryAfter[provider] ?? .distantPast) <= Date() else { return }
        let generation = UUID()
        generations[provider] = generation
        states[provider, default: State()].refreshing = true
        let fetch = self.fetch
        tasks[provider] = Task { @MainActor [weak self] in
            let result: Result<SubscriptionUsage, Error>
            do { result = .success(try await fetch(provider, allowInteraction)) }
            catch { result = .failure(error) }
            guard let self, self.generations[provider] == generation, self.enabled.contains(provider) else { return }
            defer { if self.generations[provider] == generation { self.tasks.removeValue(forKey: provider) } }
            switch result {
            case .success(let usage):
                self.states[provider] = State(usage: usage)
                self.retryAfter.removeValue(forKey: provider)
                self.onUsage?(provider, usage)
                guard self.generations[provider] == generation, self.enabled.contains(provider),
                      provider == .codex, let accountID = usage.accountID, let resetFetch = self.resetFetch else { return }
                guard (self.resetRetryAfter ?? .distantPast) <= Date() else {
                    self.states[provider]?.resetError = "Reset inventory is cooling down. It will refresh automatically."
                    return
                }
                self.states[provider]?.resetRefreshing = true
                let inventory: Result<ResetCreditInventory, Error>
                do { inventory = .success(try await resetFetch(accountID)) }
                catch { inventory = .failure(error) }
                guard self.generations[provider] == generation, self.enabled.contains(provider),
                      self.states[provider]?.usage?.accountID == accountID else { return }
                self.states[provider]?.resetRefreshing = false
                switch inventory {
                case .success(let value):
                    self.states[provider]?.resetInventory = value
                    self.states[provider]?.resetUpdatedAt = value.updatedAt
                    self.resetRetryAfter = nil
                case .failure(let error):
                    self.states[provider]?.resetError = "Reset inventory is unavailable. Your allowance reading is up to date."
                    if case SubscriptionError.rateLimited(let date) = error { self.resetRetryAfter = date }
                }
            case .failure(let error):
                // Clear old readings on failure so a changed account cannot inherit another account's meters.
                self.states[provider] = State(error: (error as? SubscriptionError)?.errorDescription
                    ?? "Couldn’t reach \(provider.name). Check your connection and refresh.")
                if case SubscriptionError.rateLimited(let date) = error { self.retryAfter[provider] = date }
            }
        }
    }

    func remaining(_ provider: SubscriptionProvider) -> Double? {
        states[provider]?.usage?.limitingWindow()?.remainingFraction
    }
}
