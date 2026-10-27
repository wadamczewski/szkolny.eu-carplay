import LibrusKit
import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddAccount = false
    @State private var accountToRemove: StoredAccount?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AgendaView() } label: { Label("Terminarz", systemImage: "calendar.badge.clock") }
                    NavigationLink { AttendanceView() } label: { Label("Frekwencja", systemImage: "checklist") }
                    NavigationLink { NoticesView() } label: { Label("Uwagi", systemImage: "exclamationmark.bubble") }
                    NavigationLink { AnnouncementsView() } label: { Label("Ogłoszenia", systemImage: "megaphone") }
                }

                Section("Uczniowie") {
                    ForEach(model.profiles) { profile in
                        Button {
                            model.selectedProfileID = profile.id
                            Task { await model.refresh() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.studentName).foregroundStyle(.primary)
                                    Text(profile.isParent ? "konto rodzica · \(profile.login)" : profile.login)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == model.selectedProfileID {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                    Button { showAddAccount = true } label: { Label("Dodaj konto", systemImage: "plus") }
                }

                Section("Zalogowane konta") {
                    ForEach(model.accounts) { account in
                        HStack {
                            Label(account.kind == .portal ? "Konto Librus" : "Synergia: \(account.displayName)",
                                  systemImage: account.kind == .portal ? "envelope" : "person.badge.key")
                            Spacer()
                            Button("Wyloguj", role: .destructive) { accountToRemove = account }
                                .buttonStyle(.borderless)
                        }
                    }
                }

                Section("O aplikacji") {
                    Text("Nieoficjalny klient dziennika Librus Synergia. Port na iOS aplikacji Szkolny.eu (szkolny-eu/szkolny-android), rozpowszechnianej na licencji GNU GPL v3. Aplikacja nie jest powiązana z Librus Sp. z o.o.")
                        .font(.footnote)
                    Link("Kod źródłowy oryginału (GitHub)", destination: URL(string: "https://github.com/szkolny-eu/szkolny-android")!)
                    Link("Licencja GPL v3", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                }
            }
            .navigationTitle("Więcej")
            .sheet(isPresented: $showAddAccount) { LoginView(isAddingAccount: true) }
            .confirmationDialog("Wylogować to konto?", isPresented: .constant(accountToRemove != nil), titleVisibility: .visible) {
                Button("Wyloguj i usuń dane z telefonu", role: .destructive) {
                    if let account = accountToRemove { model.remove(account) }
                    accountToRemove = nil
                }
                Button("Anuluj", role: .cancel) { accountToRemove = nil }
            }
        }
    }
}

struct AttendanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = (model.data?.attendance ?? []).filter { $0.base != .present }
        let all = model.data?.attendance ?? []
        List {
            Section {
                let lessons = all.count
                let absences = all.filter { $0.base.isAbsence }.count
                let percent = lessons > 0 ? Double(lessons - absences) / Double(lessons) * 100 : 0
                HStack {
                    Text("Obecność")
                    Spacer()
                    Text(lessons > 0 ? String(format: "%.1f%%", percent).replacingOccurrences(of: ".", with: ",") : "—").font(.headline)
                }
                HStack {
                    Text("Nieobecności (w tym uspr.)")
                    Spacer()
                    Text("\(absences)")
                }
                HStack {
                    Text("Spóźnienia")
                    Spacer()
                    Text("\(all.filter { $0.base == .belated }.count)")
                }
            }
            if entries.isEmpty {
                ContentUnavailableView("Brak wpisów innych niż obecność", systemImage: "checkmark.circle")
            }
            ForEach(Dictionary(grouping: entries, by: \.day).sorted { $0.key > $1.key }, id: \.key) { day, items in
                Section(day.longLabel) {
                    ForEach(items.sorted { $0.lessonNumber < $1.lessonNumber }) { entry in
                        HStack {
                            Text(entry.typeShort)
                                .font(.caption.weight(.bold))
                                .frame(width: 36, height: 24)
                                .background((Color(hex: entry.colorHex) ?? .gray).opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading) {
                                Text(entry.subject ?? "Lekcja \(entry.lessonNumber)")
                                Text("\(entry.typeName) · lekcja \(entry.lessonNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Frekwencja")
        .refreshable { await model.refresh() }
    }
}

struct NoticesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            let notices = model.data?.notices ?? []
            if notices.isEmpty {
                ContentUnavailableView("Brak uwag", systemImage: "hand.thumbsup")
            }
            ForEach(notices) { notice in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: notice.kind == .positive ? "plus.circle.fill" : notice.kind == .negative ? "minus.circle.fill" : "circle.fill")
                            .foregroundStyle(notice.kind == .positive ? .green : notice.kind == .negative ? .red : .gray)
                        Text(notice.category.isEmpty ? "Uwaga" : notice.category).font(.headline)
                        Spacer()
                        Text(notice.day.shortLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(notice.text).textSelection(.enabled)
                    if let teacher = notice.teacher {
                        Text(teacher).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Uwagi")
        .refreshable { await model.refresh() }
    }
}

struct AnnouncementsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            let announcements = model.data?.announcements ?? []
            if announcements.isEmpty {
                ContentUnavailableView("Brak ogłoszeń", systemImage: "megaphone")
            }
            ForEach(announcements) { announcement in
                NavigationLink {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(announcement.subject).font(.title3.bold())
                            Text([announcement.author, announcement.startDay?.longLabel].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(announcement.text).textSelection(.enabled)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear { model.markAnnouncementRead(announcement) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(announcement.subject)
                            .fontWeight(announcement.read ? .regular : .bold)
                        Text(announcement.startDay?.shortLabel ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Ogłoszenia")
        .refreshable { await model.refresh() }
    }
}
