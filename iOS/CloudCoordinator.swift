import CloudKit
import Foundation
import PresenceFMCore

enum CloudCoordinationError: LocalizedError {
    case unavailable, privateMode, accountMismatch, leaseHeld
    var errorDescription: String? {
        switch self {
        case .unavailable: "Cloud coordination is unavailable. The scrobble remains queued."
        case .privateMode: "Private Mode prevents submission."
        case .accountMismatch: "Mac and iPhone must use the same Last.fm account."
        case .leaseHeld: "Another device is submitting this listen."
        }
    }
}

actor CloudSubmissionCoordinator: SubmissionCoordinator {
    static let zoneID = CKRecordZone.ID(zoneName: "PresenceFM", ownerName: CKCurrentUserDefaultName)
    private let database: CKDatabase?
    private let deviceID: UUID
    private let username: @Sendable () async -> String?
    private let localOnly: Bool

    init(containerIdentifier: String?, deviceID: UUID, localOnly: Bool = false, username: @escaping @Sendable () async -> String?) {
        database = containerIdentifier.map { CKContainer(identifier: $0).privateCloudDatabase }
        self.deviceID = deviceID; self.localOnly = localOnly; self.username = username
    }

    func prepare() async throws {
        guard let database else { if localOnly { return }; throw CloudCoordinationError.unavailable }
        _ = try? await database.save(CKRecordZone(zoneID: Self.zoneID))
        let gateID = CKRecord.ID(recordName: "global", zoneID: Self.zoneID)
        if (try? await database.record(for: gateID)) == nil {
            let gate = CKRecord(recordType: "SubmissionGate", recordID: gateID)
            gate["generation"] = 1 as CKRecordValue; gate["privateMode"] = false as CKRecordValue
            _ = try? await database.save(gate)
        }
    }

    func sync(evidence: PlaybackEvidence, listen: CanonicalListen) async throws {
        guard let database else { if localOnly { return }; throw CloudCoordinationError.unavailable }
        let recordID = CKRecord.ID(recordName: listen.id, zoneID: Self.zoneID)
        let record = (try? await database.record(for: recordID)) ?? CKRecord(recordType: "Listen", recordID: recordID)
        record["title"] = listen.canonicalMetadata.title as CKRecordValue
        record["artist"] = listen.canonicalMetadata.artist as CKRecordValue
        record["album"] = listen.canonicalMetadata.album as CKRecordValue?
        record["startedAt"] = listen.canonicalMetadata.startedAt as CKRecordValue?
        record["state"] = listen.state.rawValue as CKRecordValue
        record["confidence"] = evidence.confidence.rawValue as CKRecordValue
        _ = try await database.save(record)

        let evidenceRecord = CKRecord(recordType: "Evidence", recordID: .init(recordName: evidence.id.uuidString, zoneID: Self.zoneID))
        evidenceRecord["listen"] = CKRecord.Reference(recordID: recordID, action: .none)
        evidenceRecord["deviceID"] = evidence.deviceID.uuidString as CKRecordValue
        evidenceRecord["origin"] = evidence.origin.rawValue as CKRecordValue
        evidenceRecord["capturedAt"] = evidence.capturedAt as CKRecordValue
        evidenceRecord["playTime"] = evidence.observedPlayTime as CKRecordValue?
        _ = try? await database.save(evidenceRecord)
    }

    func acquireLease(for listenID: String) async throws -> SubmissionLease {
        guard let account = await username(), !account.isEmpty else { throw CompanionLastFMError.unauthorized }
        guard let database else {
            if localOnly {
                return SubmissionLease(listenID: listenID, ownerDeviceID: deviceID, expiresAt: .now.addingTimeInterval(120), accountUsername: account)
            }
            throw CloudCoordinationError.unavailable
        }
        let gate = try await database.record(for: .init(recordName: "global", zoneID: Self.zoneID))
        if (gate["privateMode"] as? NSNumber)?.boolValue == true { throw CloudCoordinationError.privateMode }
        if let selected = gate["username"] as? String, !selected.isEmpty, selected != account { throw CloudCoordinationError.accountMismatch }
        gate["username"] = account as CKRecordValue

        let listenID = CKRecord.ID(recordName: listenID, zoneID: Self.zoneID)
        let listen = (try? await database.record(for: listenID)) ?? CKRecord(recordType: "Listen", recordID: listenID)
        if let owner = listen["leaseOwner"] as? String, owner != deviceID.uuidString,
            let expiry = listen["leaseExpiresAt"] as? Date, expiry > .now
        {
            throw CloudCoordinationError.leaseHeld
        }
        let expires = Date().addingTimeInterval(120)
        listen["leaseOwner"] = deviceID.uuidString as CKRecordValue; listen["leaseExpiresAt"] = expires as CKRecordValue
        listen["state"] = ListenState.submitting.rawValue as CKRecordValue
        let result = try await database.modifyRecords(saving: [gate, listen], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        for value in result.saveResults.values { _ = try value.get() }
        return SubmissionLease(listenID: listen.recordID.recordName, ownerDeviceID: deviceID, expiresAt: expires, accountUsername: account)
    }

    func complete(_ lease: SubmissionLease, result: SubmissionResult) async throws {
        guard let database else { return }
        let record = try await database.record(for: .init(recordName: lease.listenID, zoneID: Self.zoneID))
        guard record["leaseOwner"] as? String == deviceID.uuidString else { throw CloudCoordinationError.leaseHeld }
        switch result {
        case .accepted(let date): record["state"] = ListenState.submitted.rawValue as CKRecordValue; record["submittedAt"] = date as CKRecordValue
        case .rejected(let message): record["state"] = ListenState.failed.rawValue as CKRecordValue; record["lastError"] = message as CKRecordValue
        case .deferred(let message): record["state"] = ListenState.queued.rawValue as CKRecordValue; record["lastError"] = message as CKRecordValue
        }
        record["leaseOwner"] = nil; record["leaseExpiresAt"] = nil; _ = try await database.save(record)
    }

    func setPrivateMode(_ enabled: Bool, effectiveAt: Date) async throws {
        guard let database else { if localOnly { return }; throw CloudCoordinationError.unavailable }
        let gate = try await database.record(for: .init(recordName: "global", zoneID: Self.zoneID))
        gate["privateMode"] = enabled as CKRecordValue; gate["privateModeEffectiveAt"] = effectiveAt as CKRecordValue
        gate["generation"] = ((gate["generation"] as? NSNumber)?.intValue ?? 0) + 1 as CKRecordValue
        _ = try await database.save(gate)
    }
}
