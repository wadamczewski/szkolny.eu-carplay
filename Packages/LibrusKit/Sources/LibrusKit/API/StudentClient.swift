import Foundation

/// Everything the app does for one student: API sync, timetable weeks and the Synergia website
/// (messages). Mirrors the feature list in `LibrusFeatures.kt`.
public final class StudentClient: @unchecked Sendable {
    public let profile: StudentProfile
    public let session: AccountSession
    public let api: LibrusAPI
    public let synergia: SynergiaWeb
    private var dict = LibrusParsers.Dictionaries()
    private let dictLock = NSLock()

    public init(profile: StudentProfile, session: AccountSession) {
        self.profile = profile
        self.session = session
        let login = profile.login
        if let credentialSession = session.credentialSession {
            api = LibrusAPI.gateway(session: credentialSession)
            synergia = SynergiaWeb(provider: credentialSession)
        } else {
            let api = LibrusAPI.bearer(http: HTTPClient()) { force in
                try await session.apiToken(for: login, forceRefresh: force)
            }
            self.api = api
            synergia = SynergiaWeb(provider: AutoLoginSynergiaSession(api: api))
        }
    }

    /// Full refresh. Individual sections may fail (e.g. lucky number disabled in a school);
    /// those are reported in `warnings` instead of failing the whole sync.
    public func sync(weekStart: Day = Day.defaultTimetableWeek) async throws -> StudentData {
        var warnings: [String] = []

        // Fail fast on auth problems before firing ~20 requests.
        let me = try await api.get("Me")["Me"]

        async let subjects = optional("Przedmioty") { LibrusParsers.subjects(try await self.api.get("Subjects")) }
        async let teachers = optional("Nauczyciele") { LibrusParsers.teachers(try await self.api.get("Users")) }
        async let classrooms = optional("Sale") { LibrusParsers.classrooms(try await self.api.get("Classrooms")) }
        async let gradeCategories = optional("Kategorie ocen") { LibrusParsers.gradeCategories(try await self.api.get("Grades/Categories")) }
        async let gradeComments = optional("Komentarze ocen") { LibrusParsers.gradeComments(try await self.api.get("Grades/Comments")) }
        async let eventCategories = optional("Kategorie wydarzeń") { LibrusParsers.eventCategories(try await self.api.get("HomeWorks/Categories")) }
        async let attendanceTypes = optional("Typy frekwencji") { LibrusParsers.attendanceTypes(try await self.api.get("Attendances/Types")) }
        async let noticeCategories = optional("Kategorie uwag") { LibrusParsers.noticeCategories(try await self.api.get("Notes/Categories")) }
        async let lessons = optional("Lekcje") { LibrusParsers.lessons(try await self.api.get("Lessons")) }

        async let gradesJSON = optional("Oceny") { try await self.api.get("Grades") }
        async let eventsJSON = optional("Terminarz") { try await self.api.get("HomeWorks") }
        async let attendanceJSON = optional("Frekwencja") { try await self.api.get("Attendances") }
        async let notesJSON = optional("Uwagi") { try await self.api.get("Notes") }
        async let noticesJSON = optional("Ogłoszenia") { try await self.api.get("SchoolNotices") }
        async let luckyJSON = optional("Szczęśliwy numerek") { try await self.api.get("LuckyNumbers") }
        async let timetableJSON = optional("Plan lekcji") { try await self.api.get("Timetables?weekStart=\(weekStart)") }

        var d = LibrusParsers.Dictionaries()
        d.subjects = collect(await subjects, into: &warnings) ?? [:]
        d.teachers = collect(await teachers, into: &warnings) ?? [:]
        d.classrooms = collect(await classrooms, into: &warnings) ?? [:]
        d.gradeCategories = collect(await gradeCategories, into: &warnings) ?? [:]
        d.gradeComments = collect(await gradeComments, into: &warnings) ?? [:]
        d.eventCategories = collect(await eventCategories, into: &warnings) ?? [:]
        d.attendanceTypes = collect(await attendanceTypes, into: &warnings) ?? [:]
        d.noticeCategories = collect(await noticeCategories, into: &warnings) ?? [:]
        d.lessons = collect(await lessons, into: &warnings) ?? [:]
        dictLock.withLock { dict = d }

        var data = StudentData()
        let account = me["Account"]
        let user = me["User"]
        data.studentName = [user["FirstName"].string, user["LastName"].string].compactMap { $0 }.joined(separator: " ").fixedName.nilIfEmpty
        if account["GroupId"].int == 5 {
            data.accountName = [account["FirstName"].string, account["LastName"].string].compactMap { $0 }.joined(separator: " ").fixedName.nilIfEmpty
        }
        data.subjects = d.subjects.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        if let json = collect(await gradesJSON, into: &warnings) { data.grades = LibrusParsers.grades(json, dict: d) }
        if let json = collect(await eventsJSON, into: &warnings) { data.events = LibrusParsers.events(json, dict: d) }
        if let json = collect(await attendanceJSON, into: &warnings) { data.attendance = LibrusParsers.attendance(json, dict: d) }
        if let json = collect(await notesJSON, into: &warnings) { data.notices = LibrusParsers.notices(json, dict: d) }
        if let json = collect(await noticesJSON, into: &warnings) { data.announcements = LibrusParsers.announcements(json, dict: d) }
        if let json = collect(await luckyJSON, into: &warnings) { data.luckyNumber = LibrusParsers.luckyNumber(json) }
        if let json = collect(await timetableJSON, into: &warnings) {
            data.timetable[weekStart.string] = LibrusParsers.timetable(json, dict: d)
        }
        data.warnings = warnings
        data.fetchedAt = Date()
        return data
    }

    /// One timetable week, using dictionaries from the last sync.
    public func timetable(weekStart: Day) async throws -> [TimetableDay] {
        let json = try await api.get("Timetables?weekStart=\(weekStart)")
        let d = dictLock.withLock { dict }
        return LibrusParsers.timetable(json, dict: d)
    }

    public func markAnnouncementRead(_ id: String) async {
        _ = try? await api.get("SchoolNotices/MarkAsRead/\(id)")
    }

    // MARK: helpers

    private func optional<T>(_ label: String, _ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(LabeledError(label: label, error: error)) }
    }

    private func collect<T>(_ result: Result<T, Error>, into warnings: inout [String]) -> T? {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            if let labeled = error as? LabeledError {
                // Disabled features are expected in some schools; don't nag about them.
                if case LibrusError.featureNotActive = labeled.error { return nil }
                warnings.append("\(labeled.label): \(labeled.error.localizedDescription)")
            }
            return nil
        }
    }
}

private struct LabeledError: Error {
    let label: String
    let error: Error
}
