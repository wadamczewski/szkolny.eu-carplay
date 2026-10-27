import Foundation
import LibrusKit
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var accounts: [StoredAccount] = []
    private(set) var data: StudentData?
    private(set) var isRefreshing = false
    var lastError: String?

    var selectedProfileID: String? {
        didSet {
            guard !isDemo else { return }
            UserDefaults.standard.set(selectedProfileID, forKey: "selectedProfileID")
            data = selectedProfileID.flatMap(DataCache.load)
        }
    }

    @ObservationIgnored private var sessions: [UUID: AccountSession] = [:]
    @ObservationIgnored private var clients: [String: StudentClient] = [:]

    /// Fake data for screenshots (Debug builds, `-DemoData` launch argument).
    let isDemo: Bool

    init() {
        #if DEBUG
        isDemo = DemoData.isEnabled
        if isDemo {
            accounts = [DemoData.account]
            selectedProfileID = DemoData.profile.id
            data = DemoData.studentData()
            return
        }
        #else
        isDemo = false
        #endif
        accounts = KeychainStore.loadAccounts()
        let saved = UserDefaults.standard.string(forKey: "selectedProfileID")
        selectedProfileID = profiles.first { $0.id == saved }?.id ?? profiles.first?.id
        // Observers don't run during init.
        data = selectedProfileID.flatMap(DataCache.load)
    }

    var profiles: [StudentProfile] { accounts.flatMap(\.profiles) }
    var currentProfile: StudentProfile? { profiles.first { $0.id == selectedProfileID } }
    var isLoggedIn: Bool { !profiles.isEmpty }

    var currentClient: StudentClient? {
        guard let profile = currentProfile else { return nil }
        if let client = clients[profile.id] { return client }
        guard let session = session(for: profile.accountID) else { return nil }
        let client = StudentClient(profile: profile, session: session)
        clients[profile.id] = client
        return client
    }

    // MARK: Login

    func finishPortalLogin(code: String) async throws {
        let (account, tokens) = try await LibrusLogin.finishPortalLogin(code: code, email: nil)
        guard !account.profiles.isEmpty else {
            throw LibrusError.api(code: "NoAccounts", message: "Do Konta Librus nie podłączono żadnego konta Synergia.")
        }
        let session = add(account)
        await session.seed(portalTokens: tokens, apiToken: nil)
    }

    func synergiaLogin(login: String, password: String) async throws {
        let account = try await LibrusLogin.synergiaLogin(login: login, password: password)
        _ = add(account)
    }

    private func add(_ account: StoredAccount) -> AccountSession {
        // Re-login with an account that's already here replaces it instead of duplicating students.
        let logins = Set(account.profiles.map(\.login))
        for old in accounts where old.profiles.contains(where: { logins.contains($0.login) }) {
            remove(old)
        }
        accounts.append(account)
        KeychainStore.saveAccounts(accounts)
        let session = makeSession(account)
        if currentProfile == nil || selectedProfileID == nil {
            selectedProfileID = account.profiles.first?.id
        }
        Task { await refresh() }
        return session
    }

    func remove(_ account: StoredAccount) {
        for profile in account.profiles {
            DataCache.remove(profile.id)
            clients[profile.id] = nil
        }
        sessions[account.id] = nil
        accounts.removeAll { $0.id == account.id }
        KeychainStore.saveAccounts(accounts)
        if currentProfile == nil {
            selectedProfileID = profiles.first?.id
        }
    }

    private func session(for accountID: UUID) -> AccountSession? {
        if let session = sessions[accountID] { return session }
        guard let account = accounts.first(where: { $0.id == accountID }) else { return nil }
        return makeSession(account)
    }

    private func makeSession(_ account: StoredAccount) -> AccountSession {
        let session = AccountSession(account: account) { [weak self] updated in
            await self?.accountUpdated(updated)
        }
        sessions[account.id] = session
        return session
    }

    private func accountUpdated(_ account: StoredAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        KeychainStore.saveAccounts(accounts)
    }

    // MARK: Data

    func refresh() async {
        #if DEBUG
        if isDemo { data = DemoData.studentData(); return }
        #endif
        guard let client = currentClient, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var fresh = try await client.sync()
            // Keep other already-loaded timetable weeks.
            if let old = data, client.profile.id == selectedProfileID {
                fresh.timetable = old.timetable.merging(fresh.timetable) { $1 }
            }
            guard client.profile.id == selectedProfileID else { return }
            data = fresh
            DataCache.save(fresh, for: client.profile.id)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func timetable(week: Day) async throws -> [TimetableDay] {
        #if DEBUG
        if isDemo {
            let days = DemoData.timetable(week: week)
            data?.timetable[week.string] = days
            return days
        }
        #endif
        guard let client = currentClient else { throw LibrusError.notLoggedIn }
        let days = try await client.timetable(weekStart: week)
        if client.profile.id == selectedProfileID, var current = data {
            current.timetable[week.string] = days
            data = current
            DataCache.save(current, for: client.profile.id)
        }
        return days
    }

    func markAnnouncementRead(_ announcement: Announcement) {
        guard !announcement.read, let client = currentClient else { return }
        Task { await client.markAnnouncementRead(announcement.id) }
    }
}
