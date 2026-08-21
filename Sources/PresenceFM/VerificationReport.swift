import Foundation

struct VerificationReport: Codable, Equatable {
    struct Polling: Codable, Equatable {
        let latestMilliseconds: Int
        let providerMilliseconds: [String: Int]
    }

    struct LocalData: Codable, Equatable {
        let activityRecords: Int
        let queuedScrobbles: Int
        let failedScrobbles: Int
        let diagnosticRecords: Int
        let healthEvents: Int
        let artworkMemoryEntries: Int
        let artworkDiskEntries: Int
    }

    let generatedAt: Date
    let appVersion: String
    let appBuild: String
    let macOSVersion: String
    let architecture: String
    let demoMode: Bool
    let privateMode: Bool
    let enabledProviders: [String]
    let providerPriority: [String]
    let serviceStatus: [String: String]
    let polling: Polling
    let localData: LocalData

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static var currentArchitecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }
}

extension ServiceStatus {
    var verificationLabel: String { presentationLabel }
}

struct ArtworkCacheMetrics: Sendable, Equatable {
    let memoryEntries: Int
    let diskEntries: Int
}
