# Persistence and Migration Policy

PresenceFM stores listening activity, queued scrobbles, bounded redacted diagnostics, and bounded integration-health events in SwiftData. The original public layout is represented by `PresenceFMSchemaV0`; `PresenceFMSchemaV1` adds optional insight fields and health events. `PresenceFMMigrationPlan` is the only supported route for schema changes.

The explicit store lives at `~/Library/Application Support/PresenceFM/PresenceFM.store`. On first upgraded launch, PresenceFM copies the historical `~/Library/Application Support/default.store` and its SQLite sidecars into that location while leaving the legacy files untouched. Before opening a store whose schema marker differs, PresenceFM creates a physical backup and retains the newest two.

New stored fields must be optional or have a migration stage and fixtures covering every public schema. A migration must never overwrite the only copy of a store. If the persistent container cannot open, PresenceFM starts with an in-memory recovery session and offers retry, latest-physical-backup restore, or a fresh store. A failed store is moved into `FailedStores` rather than deleted.

The current bounds are 5,000 activity records, 1,000 diagnostic records, and 200 health events. Submitted scrobbles remain visible through one queue-drain cycle and are then removed. Pending and permanently failed queues warn before their respective 5,000 and 500 record hard limits; new work is rejected with an explicit notification rather than silently discarded.

Migration tests cover the V0→V1 SwiftData stage, older optional fields, legacy-file copying, two-backup retention, restore, and fresh-store preservation. Release QA must still include an upgrade using preserved real data from the previous public version.
