# crux_audit

The shared audit-event envelope, the sink seam, and an append-only JSON-lines
sink. Pure Dart, permanently: the products' headless Pro CLIs write audit
events too.

```dart
import 'package:crux_audit/crux_audit.dart';

final sink = JsonlAuditSink(path: '/var/log/edacrux/audit.jsonl');
await sink.record(AuditEvent(
  timestamp: DateTime.now().toUtc(),
  product: 'lintcrux',
  kind: 'waiver.created',
  payload: {'rule': 'W123'},
));
```

In a Flutter product you rarely construct either directly: `crux_license`'s
`cruxAuditSinkProvider` builds the sink from the organization's policy file,
and `CruxAuditRecorder` stamps `product` and the CXP peer id so a call site
names only its kind and payload.

## Surface

| Symbol | Purpose |
|---|---|
| `AuditEvent`, `AuditSeverity` | The envelope: timestamp, product, kind, severity, optional peer id, payload. `toJsonLine()` puts the timestamp first. |
| `AuditSink`, `AuditSinkHealth` | The seam, and what a settings panel shows when writing fails. |
| `AuditVerbosity` | `off` / `normal` / `verbose` — which severities a sink records. |
| `JsonlAuditSink` | Append-only JSON lines at a path, with an optional `maxBytes` safety valve. |
| `NoopAuditSink` | The default: auditing is off until an administrator turns it on. |
| `CruxSharedAuditKinds` | The three kinds that describe shared machinery: `policy.loaded`, `policy.rejected`, `plugin.load.refused`. |

## The envelope is shared; the event kinds are not

A kind is a plain string the product registers, because what is worth
recording is the product's own business — a shared enum would need editing here
every time any one of four products learned a new event. Only the envelope is
fixed, so one file holding four products' events is still one parseable stream.

`CruxSharedAuditKinds` is the one exception, and a narrow one: four spellings of
"the policy file was rejected" would make a shared file unfilterable for
exactly the events an administrator most wants to find.

## Rotation is the organization's

**This sink does not rotate.** An organization that turns on audit logging
already runs logrotate or an agent that does the same, and a second rotation
policy fighting theirs is worse than none.

So it opens the file, appends one line and closes — per event. No handle is
held between writes, which makes every rotation scheme work with no detection
logic: after `mv` the next event creates a fresh file at the path; after
copy-truncate it appends at zero. Audit events are human-paced, so the extra
syscalls are irrelevant next to correctness under somebody else's logrotate.

`maxBytes`, when set, is a safety valve against filling a disk, not a rotation
policy: the sink stops growing the file and reports itself unhealthy. It never
renames or deletes anything.

## Failure: degrade loudly, never throw

Every write path is guarded. A failure degrades the sink — `AuditSinkHealth`
reports it, with the time it started — and is logged once, so a full disk
cannot produce a second log that fills what is left. A product that crashed
because it could not audit is worse than one that was never audited, and a log
that quietly stopped is worse than both.

## Not in this package

- **No syslog transport, no webhook, no SIEM connector.** An organization that
  wants forwarding points its existing log shipper at the file.
- **No Flutter and no Riverpod.** The provider wiring lives in `crux_license`.
  `no_flutter_dependency_test.dart` walks the resolved dependency closure on
  every run.
