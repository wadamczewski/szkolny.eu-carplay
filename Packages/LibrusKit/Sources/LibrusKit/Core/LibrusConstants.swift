import Foundation

/// Endpoints and client identifiers, ported from szkolny-android `data/api/Constants.kt` (GPL-3.0).
/// These are public identifiers of the Librus mobile app taken from that open-source repository —
/// not personal credentials.
public enum LibrusConstants {
    public static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 LibrusMobileApp"
    public static let webUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    // Konto Librus (portal) OAuth
    public static let portalClientID = "VaItV6oRutdo8fnjJwysnTjVlvaswf52ZqmXsJGP"
    public static let portalRedirectURL = "app://librus"
    public static let portalAuthorizeURL = URL(string: "https://portal.librus.pl/konto-librus/redirect/dru")!
    public static let portalTokenURL = URL(string: "https://portal.librus.pl/oauth2/access_token")!
    public static let portalHeader = "pl.librus.synergiaDru2"
    public static let portalAPIURL = "https://portal.librus.pl/api"
    public static let portalAccountsPath = "/v3/SynergiaAccounts"
    public static let portalFreshAccountPath = "/v3/SynergiaAccounts/fresh/"

    // Synergia API
    public static let apiURL = "https://api.librus.pl/2.0"
    public static let apiTokenURL = URL(string: "https://api.librus.pl/OAuth/Token")!
    public static let apiAuthorization = "Mjg6ODRmZGQzYTg3YjAzZDNlYTZmZmU3NzdiNThiMzMyYjE="

    // Synergia website (messages, attachments)
    public static let synergiaURL = "https://synergia.librus.pl"
    public static let synergiaTokenLoginURL = "https://synergia.librus.pl/loguj/token/TOKEN/przenies"
    public static let sandboxURL = "https://sandbox.librus.pl/index.php?action="
}
