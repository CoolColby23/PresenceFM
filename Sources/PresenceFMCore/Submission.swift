import CryptoKit
import Foundation

public struct SubmissionLease: Codable, Hashable, Sendable {
    public let listenID: String
    public let ownerDeviceID: UUID
    public let acquiredAt: Date
    public let expiresAt: Date
    public let accountUsername: String
    public init(listenID: String, ownerDeviceID: UUID, acquiredAt: Date = .now, expiresAt: Date, accountUsername: String) {
        self.listenID = listenID; self.ownerDeviceID = ownerDeviceID
        self.acquiredAt = acquiredAt; self.expiresAt = expiresAt; self.accountUsername = accountUsername
    }
}

public enum SubmissionResult: Codable, Hashable, Sendable { case accepted(Date), rejected(String), deferred(String) }
public protocol SubmissionCoordinator: Sendable {
    func acquireLease(for listenID: String) async throws -> SubmissionLease
    func complete(_ lease: SubmissionLease, result: SubmissionResult) async throws
}

public enum LastFMRequestBuilder {
    public static func signature(parameters: [String: String], secret: String) -> String {
        let material =
            parameters.filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }.map { $0.key + $0.value }.joined() + secret
        return Insecure.MD5.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func values(method: String, parameters: [String: String], apiKey: String, secret: String, sessionKey: String? = nil) -> [String: String] {
        var values = parameters; values["method"] = method; values["api_key"] = apiKey
        if let sessionKey { values["sk"] = sessionKey }
        values["api_sig"] = signature(parameters: values, secret: secret); values["format"] = "json"
        return values
    }

    public static func body(_ values: [String: String]) -> Data {
        values.sorted { $0.key < $1.key }.map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }
            .joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

private extension String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
