import Foundation

enum ReleaseConfiguration {
    static var version: String {
        bundledValue(named: "CFBundleShortVersionString", fallback: "1.0.0")
    }
    static var build: String {
        bundledValue(named: "CFBundleVersion", fallback: "1")
    }

    static let discordApplicationID = bundledValue(
        named: "PRESENCEFM_DISCORD_APPLICATION_ID",
        fallback: "1525555974390153346"
    )

    // The Discord application currently has no uploaded Rich Presence assets.
    // Use its public application icon directly so the fallback and small badge
    // keep working even when an asset key is unavailable.
    static let discordApplicationIconURL =
        "https://cdn.discordapp.com/app-icons/1525555974390153346/409fc4cf26402a15fc6b0d4d5a6a3c36.png?size=1024"

    static var hasDiscordConfiguration: Bool { !discordApplicationID.isEmpty }

    private static func bundledValue(named name: String, fallback: String) -> String {
        if let environmentValue = ProcessInfo.processInfo.environment[name], !environmentValue.isEmpty { return environmentValue }
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: name) as? String, !bundleValue.isEmpty { return bundleValue }
        return fallback
    }
}
