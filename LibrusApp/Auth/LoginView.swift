import LibrusKit
import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Shown as a sheet when adding another account.
    var isAddingAccount = false

    @State private var showPortal = false
    @State private var login = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var error: String?
    @State private var accountsAtStart: [StoredAccount] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("Dziennik")
                            .font(.largeTitle.bold())
                        Text("Nieoficjalny klient Librus Synergia na iOS, oparty na kodzie Szkolny.eu.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    Button {
                        showPortal = true
                    } label: {
                        Label("Zaloguj przez Konto Librus", systemImage: "envelope.fill")
                    }
                } header: {
                    Text("Rodzice i uczniowie z e-mailem")
                } footer: {
                    Text("Logowanie odbywa się na stronie portal.librus.pl. Aplikacja nie widzi hasła — zapisuje tylko token w pęku kluczy.")
                }

                Section {
                    TextField("Login (np. 1234567u)", text: $login)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Hasło", text: $password)
                        .textContentType(.password)
                    Button {
                        Task { await synergiaLogin() }
                    } label: {
                        if isLoggingIn {
                            ProgressView()
                        } else {
                            Text("Zaloguj loginem Synergia")
                        }
                    }
                    .disabled(login.isEmpty || password.isEmpty || isLoggingIn)
                } header: {
                    Text("Login i hasło Synergia")
                } footer: {
                    Text("Logowanie przez stronę synergia.librus.pl. Hasło jest zapisywane w pęku kluczy tylko na tym urządzeniu, bo bez niego sesja Synergii nie może być odnowiona.")
                }
            }
            .navigationTitle(isAddingAccount ? "Dodaj konto" : "")
            .toolbar {
                if isAddingAccount {
                    ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                }
            }
            .sheet(isPresented: $showPortal, onDismiss: {
                if isAddingAccount && model.accounts != accountsAtStart { dismiss() }
            }) {
                PortalLoginView()
            }
            .onAppear { accountsAtStart = model.accounts }
            .alert("Logowanie nieudane", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func synergiaLogin() async {
        isLoggingIn = true
        defer { isLoggingIn = false }
        do {
            try await model.synergiaLogin(login: login.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
            if isAddingAccount { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
