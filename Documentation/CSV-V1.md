# Listening History CSV v1

PresenceFM exports visible, filtered listening history as UTF-8 CSV with RFC 4180-style quoting and a trailing newline. Timestamps use ISO 8601 and durations use decimal seconds.

The frozen column order is:

```text
schema_version,id,started_at,finalized_at,title,artist,album,platform,outcome,duration_seconds,listening_seconds,persistent_id
```

`schema_version` is `1`. Optional or unavailable values are empty, except an unavailable platform is written as `Unknown platform`. PresenceFM does not import CSV files; use a PresenceFM backup for lossless restore.
