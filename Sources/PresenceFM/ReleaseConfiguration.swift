import Foundation

enum ReleaseConfiguration {
    static let version = "0.1.0"
    static let build = "1"

    /// Release builds inject these values through the environment before compilation.
    /// Empty values keep local and pull-request builds credential-free.
    static let discordApplicationID = bundledValue(named: "PRESENCEFM_DISCORD_APPLICATION_ID")

    static var hasDiscordConfiguration: Bool { !discordApplicationID.isEmpty }

    private static func bundledValue(named name: String) -> String {
        ProcessInfo.processInfo.environment[name] ?? Bundle.main.object(forInfoDictionaryKey: name) as? String ?? ""
    }
}
