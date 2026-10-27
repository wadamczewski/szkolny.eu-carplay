import LibrusKit
import QuickLook
import SwiftUI
import WebKit

struct MessagesView: View {
    @Environment(AppModel.self) private var model
    @State private var folder: MessageFolder = .inbox
    @State private var messages: [MessageSummary] = []
    @State private var page = 0
    @State private var canLoadMore = true
    @State private var isLoading = false
    @State private var error: String?
    @State private var showCompose = false
    @State private var showWeb = false

    var body: some View {
        NavigationStack {
            List {
                Picker("Folder", selection: $folder) {
                    Text("Odebrane").tag(MessageFolder.inbox)
                    Text("Wysłane").tag(MessageFolder.sent)
                }
                .pickerStyle(.segmented)

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Button("Otwórz wiadomości w Synergii") { showWeb = true }
                    }
                }

                ForEach(messages) { message in
                    NavigationLink {
                        MessageDetailView(summary: message)
                    } label: {
                        MessageRow(message: message)
                    }
                }

                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if canLoadMore && !messages.isEmpty {
                    Button("Wczytaj starsze") { Task { await load(reset: false) } }
                } else if messages.isEmpty && error == nil {
                    ContentUnavailableView("Brak wiadomości", systemImage: "envelope.open")
                }
            }
            .navigationTitle("Wiadomości")
            .refreshable { await load(reset: true) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileMenu() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button { showWeb = true } label: { Label("Otwórz w Synergii", systemImage: "safari") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    Button { showCompose = true } label: { Image(systemName: "square.and.pencil") }
                }
            }
            .task(id: "\(folder.rawValue)-\(model.selectedProfileID ?? "")") { await load(reset: true) }
            .sheet(isPresented: $showCompose) {
                ComposeMessageView { Task { if folder == .sent { await load(reset: true) } } }
            }
            .sheet(isPresented: $showWeb) { SynergiaWebSheet(path: "wiadomosci") }
        }
    }

    private func load(reset: Bool) async {
        #if DEBUG
        if model.isDemo { messages = DemoData.messages(folder); canLoadMore = false; return }
        #endif
        guard let client = model.currentClient, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let nextPage = reset ? 0 : page + 1
        do {
            let result = try await client.synergia.messages(folder, page: nextPage)
            if reset { messages = result } else {
                let known = Set(messages.map(\.id))
                messages += result.filter { !known.contains($0.id) }
            }
            page = nextPage
            canLoadMore = !result.isEmpty
            error = nil
        } catch {
            if reset { messages = [] }
            self.error = error.localizedDescription
        }
    }
}

private struct MessageRow: View {
    let message: MessageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                if message.unread && message.folder == .inbox {
                    Circle().fill(.tint).frame(width: 8, height: 8)
                }
                Text(message.correspondent)
                    .font(.subheadline.weight(message.unread ? .bold : .regular))
                    .lineLimit(1)
                Spacer()
                if message.hasAttachments { Image(systemName: "paperclip").foregroundStyle(.secondary) }
                Text(String(message.date.prefix(10))).font(.caption).foregroundStyle(.secondary)
            }
            Text(message.subject)
                .font(.subheadline)
                .fontWeight(message.unread ? .semibold : .regular)
                .lineLimit(2)
            if message.folder == .sent && message.unread {
                Text("Nieprzeczytana przez odbiorcę").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct MessageDetailView: View {
    @Environment(AppModel.self) private var model
    let summary: MessageSummary
    @State private var detail: MessageDetail?
    @State private var error: String?
    @State private var downloading: String?
    @State private var previewURL: URL?
    @State private var showReply = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail?.subject ?? summary.subject).font(.title3.bold())
                Text(detail?.sender ?? summary.correspondent).font(.subheadline)
                Text(detail?.date ?? summary.date).font(.caption).foregroundStyle(.secondary)
                if let attachments = detail?.attachments, !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(attachments) { attachment in
                                Button { Task { await open(attachment) } } label: {
                                    HStack(spacing: 4) {
                                        if downloading == attachment.id { ProgressView().controlSize(.small) }
                                        else { Image(systemName: "paperclip") }
                                        Text(attachment.filename).lineLimit(1)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(downloading != nil)
                            }
                        }
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            if let detail {
                HTMLView(html: detail.bodyHTML)
            } else if error == nil {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if summary.folder == .inbox {
                Button { showReply = true } label: { Image(systemName: "arrowshape.turn.up.left") }
            }
        }
        .sheet(isPresented: $showReply) {
            ComposeMessageView(replySubject: "Re: " + (detail?.subject ?? summary.subject),
                               replyTo: detail?.sender ?? summary.correspondent,
                               quotedBody: detail.map { plainText($0.bodyHTML) })
        }
        .quickLookPreview($previewURL)
        .task { await load() }
    }

    private func load() async {
        #if DEBUG
        if model.isDemo { detail = DemoData.message(summary); return }
        #endif
        guard let client = model.currentClient else { return }
        do {
            detail = try await client.synergia.message(id: summary.id, folder: summary.folder)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func open(_ attachment: MessageAttachment) async {
        guard let client = model.currentClient else { return }
        downloading = attachment.id
        defer { downloading = nil }
        do {
            previewURL = try await client.synergia.download(attachment)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ComposeMessageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var replySubject: String? = nil
    /// Name shown in the original message — used to preselect a matching recipient.
    var replyTo: String? = nil
    var quotedBody: String? = nil
    var onSent: () -> Void = {}

    @State private var groups: [RecipientGroup] = []
    @State private var group: String = ""
    @State private var recipients: [Recipient] = []
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var isBusy = false
    @State private var error: String?

    init(replySubject: String? = nil, replyTo: String? = nil, quotedBody: String? = nil, onSent: @escaping () -> Void = {}) {
        self.replySubject = replySubject
        self.replyTo = replyTo
        self.quotedBody = quotedBody
        self.onSent = onSent
        _subject = State(initialValue: replySubject ?? "")
        _messageBody = State(initialValue: quotedBody.map { "\n\n----\n" + $0 } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Do") {
                    Picker("Grupa", selection: $group) {
                        ForEach(groups) { Text($0.name).tag($0.value) }
                    }
                    if !selected.isEmpty {
                        Text(recipients.filter { selected.contains($0.id) }.map(\.name).joined(separator: ", "))
                            .font(.subheadline)
                    }
                    NavigationLink("Wybierz odbiorców (\(selected.count))") {
                        List(filteredRecipients, selection: $selected) { Text($0.name) }
                            .environment(\.editMode, .constant(.active))
                            .searchable(text: $search)
                            .navigationTitle("Odbiorcy")
                    }
                    .disabled(recipients.isEmpty)
                }
                Section("Wiadomość") {
                    TextField("Temat", text: $subject)
                    TextEditor(text: $messageBody).frame(minHeight: 200)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .navigationTitle(replySubject == nil ? "Nowa wiadomość" : "Odpowiedź")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isBusy { ProgressView() } else {
                        Button("Wyślij") { Task { await send() } }
                            .disabled(selected.isEmpty || subject.trimmingCharacters(in: .whitespaces).isEmpty
                                      || messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .task { await loadGroups() }
            .onChange(of: group) { _, newValue in Task { await loadRecipients(newValue) } }
        }
    }

    private var filteredRecipients: [Recipient] {
        search.isEmpty ? recipients : recipients.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func loadGroups() async {
        #if DEBUG
        if model.isDemo { groups = DemoData.recipientGroups; group = groups.first?.value ?? ""; return }
        #endif
        guard let client = model.currentClient else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            groups = try await client.synergia.recipientGroups()
            group = groups.first { $0.value == "nauczyciel" }?.value ?? groups.first?.value ?? ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadRecipients(_ group: String) async {
        #if DEBUG
        if model.isDemo { recipients = DemoData.recipients; return }
        #endif
        guard let client = model.currentClient, !group.isEmpty else { return }
        do {
            recipients = try await client.synergia.recipients(group: group)
            selected = selected.filter { id in recipients.contains { $0.id == id } }
            if let replyTo, selected.isEmpty {
                // "Kowalski Jan (Nauczyciel)" → match on the name part.
                let name = replyTo.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? replyTo
                let words = Set(name.lowercased().split(separator: " "))
                if let match = recipients.first(where: { Set($0.name.lowercased().split(separator: " ")) == words }) {
                    selected = [match.id]
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() async {
        guard let client = model.currentClient else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.synergia.send(subject: subject, body: messageBody, recipientIDs: Array(selected))
            onSent()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Fallback: the real Synergia page, logged in with the app's session cookies. If the
/// automatic session fails too, it opens Synergia's own login page so the user can log in by hand.
struct SynergiaWebSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let path: String
    @State private var cookies: [HTTPCookie]?
    @State private var sessionFailed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if sessionFailed {
                    Text("Automatyczne logowanie nie zadziałało — zaloguj się na stronie Synergii.")
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.orange.opacity(0.2))
                }
                if let cookies {
                    CookieWebView(url: URL(string: sessionFailed
                                           ? "\(LibrusConstants.synergiaURL)/loguj/portalRodzina"
                                           : "\(LibrusConstants.synergiaURL)/\(path)")!,
                                  cookies: cookies)
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            .navigationTitle("Synergia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } } }
            .task {
                do {
                    cookies = try await model.currentClient?.synergia.sessionCookies() ?? []
                } catch {
                    sessionFailed = true
                    cookies = []
                }
            }
        }
    }
}

private struct CookieWebView: UIViewRepresentable {
    let url: URL
    let cookies: [HTTPCookie]

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = LibrusConstants.webUserAgent
        let store = config.websiteDataStore.httpCookieStore
        Task { @MainActor in
            for cookie in cookies { await store.setCookie(cookie) }
            view.load(URLRequest(url: url))
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
