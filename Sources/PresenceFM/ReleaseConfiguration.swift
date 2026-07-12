import Foundation

enum ReleaseConfiguration {
    static let version = "0.3.0"
    static let build = "3"

    static let discordApplicationID = bundledValue(
        named: "PRESENCEFM_DISCORD_APPLICATION_ID",
        fallback: "1525555974390153346"
    )

    static var hasDiscordConfiguration: Bool { !discordApplicationID.isEmpty }

    private static func bundledValue(named name: String, fallback: String) -> String {
        if let environmentValue = ProcessInfo.processInfo.environment[name], !environmentValue.isEmpty { return environmentValue }
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: name) as? String, !bundleValue.isEmpty { return bundleValue }
        return fallback
    }
}
