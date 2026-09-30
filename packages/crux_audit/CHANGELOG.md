# Changelog

## 0.1.0

- Initial release. `AuditEvent` + `AuditSeverity` — the shared envelope, with
  per-product plain-string kinds and the timestamp first on every JSON line.
- `AuditSink` seam, `AuditSinkHealth`, `AuditVerbosity`, and `NoopAuditSink`
  as the default.
- `JsonlAuditSink` — append-only JSON lines, opening and closing the file per
  event so external rotation (`mv` or copy-truncate) needs no detection logic.
  `maxBytes` refuses to grow the file and reports unhealthy; it never deletes.
  Write failures degrade the sink and are logged once, never thrown.
- `CruxSharedAuditKinds` — `policy.loaded`, `policy.rejected` and
  `plugin.load.refused`, the kinds that describe shared machinery rather than a
  product's own events.
- Pure Dart, guarded by `no_flutter_dependency_test.dart`.
