# PresenceFM Backup Format v1

`.presencefmbackup` is a UTF-8, versioned JSON document. Version 1 contains its creation time, PresenceFM version, activity records, non-submitted queue records, and non-secret preferences.

The format intentionally excludes Last.fm API keys, shared secrets, authorization/session tokens, YTMDesktop tokens, artwork bytes, diagnostics, health history, and machine-specific paths. Last.fm is disabled after restore and must be reconnected normally.

Restore validates the complete document before mutation, rejects unknown future versions, creates an automatic local backup, replaces activity and queue data in one SwiftData save, and rolls back the context if saving fails. PresenceFM retains the two newest automatic backup documents under Application Support. The UI requires destructive confirmation before restore.
