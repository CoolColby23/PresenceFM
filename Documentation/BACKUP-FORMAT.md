# PresenceFM Backup Format v1

`.presencefmbackup` is a UTF-8, versioned JSON document. Version 1 contains its creation time, PresenceFM version, activity records, non-submitted queue records, and non-secret preferences.

The format intentionally excludes Last.fm API keys, shared secrets, authorization/session tokens, YTMDesktop tokens, artwork bytes, diagnostics, health history, and machine-specific paths. Last.fm is disabled after restore and must be reconnected normally.

Restore validates the complete document before mutation, rejects unknown future versions, creates an automatic local backup, replaces activity and queue data in one SwiftData save, and rolls back the context if saving fails. PresenceFM retains the two newest automatic backup documents under Application Support. The UI requires destructive confirmation before restore.

## Encrypted iCloud envelope

Entitled builds can wrap the same v1 JSON payload in an authenticated encrypted envelope. PresenceFM derives a 256-bit key from a user-supplied passphrase using PBKDF2-HMAC-SHA256 with a random 16-byte salt and 120,000 iterations, then seals the payload with AES-256-GCM. The envelope records only its version, salt, iteration count, and combined ciphertext/authentication tag. The passphrase and derived key are never persisted.

The latest encrypted document is written atomically to the app's iCloud Drive container. If the running signature has no iCloud container entitlement, the UI reports the capability as unavailable and does not fall back to an unencrypted or misleadingly local “cloud” file.
