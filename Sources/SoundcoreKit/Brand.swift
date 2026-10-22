import Foundation

/// Product identity shared by the app and the widget. The Swift modules keep their technical
/// names (SoundcoreKit speaks the Soundcore protocol); everything a person sees says Kyōmei.
public enum Brand {
    public static let name = "Kyōmei"
    public static let asciiName = "Kyomei"
    public static let kanji = "共鳴"
    public static let tagline = "Your sound. In harmony."
    public static let organization = "Kakushin"

    public static let repository = URL(string: "https://github.com/kakushindev/kyomei-core")!
    public static let releases = URL(string: "https://github.com/kakushindev/kyomei-core/releases")!
    public static let issues = URL(string: "https://github.com/kakushindev/kyomei-core/issues")!
    public static let website = URL(string: "https://kyomei.kakushin.dev")!
    public static let organizationURL = URL(string: "https://kakushin.dev")!

    public static let disclaimer =
        "Kyōmei is an independent open-source project by Kakushin. It is not affiliated with, endorsed by or sponsored by Anker Innovations or Soundcore."

    /// `kyomei://…`; the pre-rebrand scheme is still accepted so older widget instances keep working.
    public static let urlScheme = "kyomei"
    public static let acceptedURLSchemes: Set<String> = ["kyomei", "soundcore-mac"]

    /// Bundle identifier used before the rebrand, for one-time settings migration.
    public static let legacyBundleIdentifier = "dev.local.soundcore-macos"
}
