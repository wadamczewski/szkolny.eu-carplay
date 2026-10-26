import Foundation

public enum LibrusError: LocalizedError, Equatable {
    case network(String)
    case invalidResponse(String)
    case invalidLogin
    case captchaRequired
    case portalAccessDenied
    case portalAccountDisconnected
    case portalAccountNotActivated
    case portalAPIDisabled
    case tokenExpired
    case maintenance
    case accessDenied(String)
    case timetableNotPublic
    case featureNotActive(String)
    case api(code: String, message: String?)
    case synergiaSession(String)
    case messageSendFailed(String)
    case messageSendUnconfirmed
    case parse(String)
    case notLoggedIn

    public var errorDescription: String? {
        switch self {
        case .network(let m): return "Błąd połączenia: \(m)"
        case .invalidResponse(let m): return "Nieprawidłowa odpowiedź serwera: \(m)"
        case .invalidLogin: return "Nieprawidłowy login lub hasło."
        case .captchaRequired: return "Librus wymaga rozwiązania CAPTCHA. Zaloguj się ponownie przez Konto Librus."
        case .portalAccessDenied: return "Sesja Konta Librus wygasła. Zaloguj się ponownie."
        case .portalAccountDisconnected: return "Konto Synergia wymaga akcji na portal.librus.pl (np. ponownego połączenia)."
        case .portalAccountNotActivated: return "Konto Librus nie zostało aktywowane."
        case .portalAPIDisabled: return "Librus wyłączył dostęp API dla tego konta."
        case .tokenExpired: return "Token wygasł. Odśwież dane."
        case .maintenance: return "Librus ma przerwę techniczną. Spróbuj później."
        case .accessDenied(let m): return "Brak dostępu: \(m)"
        case .timetableNotPublic: return "Plan lekcji ucznia nie jest publiczny."
        case .featureNotActive(let f): return "Funkcja nieaktywna w szkole: \(f)"
        case .api(let code, let message): return "Błąd API Librus (\(code))" + (message.map { ": \($0)" } ?? "")
        case .synergiaSession(let m): return "Nie udało się zalogować do Synergii: \(m)"
        case .messageSendFailed(let m): return "Nie wysłano wiadomości: \(m)"
        case .messageSendUnconfirmed: return "Nie udało się potwierdzić wysłania. Sprawdź folder Wysłane przed ponowną próbą."
        case .parse(let m): return "Nie udało się odczytać danych: \(m)"
        case .notLoggedIn: return "Nie jesteś zalogowany."
        }
    }
}
