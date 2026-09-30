// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_sqlite/src/crux_db_recovery.dart';
import 'package:crux_sqlite/src/guards/crux_guard_report.dart';
import 'package:crux_sqlite/src/guards/crux_guard_sources.dart';
import 'package:meta/meta.dart';

/// One file permitted to delete a database file, and the store that makes it
/// legitimate.
///
/// **The entry carries the store's own recovery declaration, not a copy of
/// it.** Write `recovery: SqliteLintRunCacheService.dataValue`, never
/// `recovery: CruxDbRecovery.recreate`. That is the single thing that keeps
/// this allowlist from being a hole: the guard rejects any entry whose
/// [recovery] is not [CruxDbRecovery.recreate], so the moment a store's own
/// declaration changes to a PRECIOUS one, its entry stops being honoured —
/// without anybody having to remember to come back here and edit the test.
/// A copied literal would keep saying `recreate` long after the store stopped
/// meaning it, which is exactly how the original defect survived review: the
/// rule lived in a docstring that had gone stale.
@immutable
final class CruxDeleteAllowlistEntry {
  /// Creates a [CruxDeleteAllowlistEntry].
  const CruxDeleteAllowlistEntry({
    required this.file,
    required this.storeName,
    required this.recovery,
    required this.reason,
  });

  /// The path (or path suffix) of the file permitted to delete. Matched by
  /// suffix so an entry survives the repo being checked out anywhere.
  final String file;

  /// The store whose data value makes the delete legitimate.
  final String storeName;

  /// **The store's own `CruxDbRecovery` declaration, referenced.** Honoured
  /// only when it is [CruxDbRecovery.recreate].
  final CruxDbRecovery recovery;

  /// Why this store's contents are reproducible, in terms a reader can check
  /// against the inventory in the migration guide.
  final String reason;
}

/// **Guard G4 — delete-database allowlist.**
///
/// No `deleteDatabase()`, and no `File.delete()` on a `.db` path, may exist in
/// code that owns a database — unless the delete is attributable to a store
/// whose declared data value is [CruxDbRecovery.recreate].
///
/// This is the guard against the original defect: a store that met an open
/// failure and solved it by deleting the user's file. It was defensible for a
/// genuinely corrupt file and catastrophic for the two other things that
/// arrive as the same exception — our own migration bug, and a merely *locked*
/// file — and the deleted history was a year of it.
///
/// There are exactly two ways for a delete site to be legitimate:
///
///  1. **Structurally** — the call sits inside a
///     `case CruxDbRecovery.recreate:` arm, so the code path is reachable only
///     for a store that declared its contents reproducible. This is how
///     `crux_sqlite`'s own open policy
///     performs the one sanctioned delete in the suite, and it is *stronger*
///     than an allowlist: the switch is exhaustive over the enum, so adding a
///     fourth data-value policy is a compile error at that site rather than a
///     silently unhandled case. No allowlist entry is needed or accepted for
///     it.
///  2. **By allowlist** — a [CruxDeleteAllowlistEntry] naming the file, the
///     store, and the store's own recovery declaration. Rejected unless that
///     declaration is [CruxDbRecovery.recreate].
///
/// An entry that matches nothing is also red. A stale allowlist entry is an
/// allowlist nobody is reading, and it is how the next one gets added without
/// an argument.
CruxGuardReport cruxAuditDatabaseDeletes({
  required Iterable<CruxSourceFile> sources,
  required Iterable<CruxDeleteAllowlistEntry> allowlist,
  required String subject,
}) {
  final findings = <CruxGuardFinding>[];
  final observations = <CruxGuardFinding>[];
  final entries = allowlist.toList();
  final used = <int>{};

  for (final entry in entries) {
    if (entry.recovery != CruxDbRecovery.recreate) {
      findings.add(
        CruxGuardFinding(
          location: 'allowlist entry for ${entry.file}',
          detail:
              'the ${entry.storeName} declares '
              'CruxDbRecovery.${entry.recovery.name}, which is PRECIOUS. An '
              'allowlist entry cannot make a precious store deletable — that '
              'is the whole point of the list. Either the store stopped being '
              'derivable (remove this entry and the delete) or the '
              'declaration is wrong.',
        ),
      );
    }
  }

  for (final file in sources) {
    for (final site in _findDeleteSites(file)) {
      if (_isRecreateArm(file.source, site.offset)) {
        observations.add(
          CruxGuardFinding(
            location: file.locate(site.offset),
            detail:
                '${site.description} — inside a `case '
                'CruxDbRecovery.recreate:` arm, so it is reachable only for a '
                'store that declared its contents reproducible.',
          ),
        );
        continue;
      }
      final index = entries.indexWhere(
        (w) => file.path.endsWith(w.file) || w.file.endsWith(file.path),
      );
      if (index < 0) {
        findings.add(
          CruxGuardFinding(
            location: file.locate(site.offset),
            detail:
                '${site.description}\n'
                '        No allowlist entry names this file, and it is not '
                'inside a `case CruxDbRecovery.recreate:` arm.',
          ),
        );
        continue;
      }
      used.add(index);
      final entry = entries[index];
      if (entry.recovery == CruxDbRecovery.recreate) {
        observations.add(
          CruxGuardFinding(
            location: file.locate(site.offset),
            detail:
                '${site.description} — allowlisted for the '
                '${entry.storeName}: ${entry.reason}',
          ),
        );
      }
    }
  }

  for (var i = 0; i < entries.length; i++) {
    if (used.contains(i)) continue;
    findings.add(
      CruxGuardFinding(
        location: 'allowlist entry for ${entries[i].file}',
        detail:
            'matches no delete site. The entry permits something that is no '
            'longer there. Remove it — a standing permission nobody is '
            'reading is how the next delete gets added without an argument.',
      ),
    );
  }

  findings.sort((a, b) => a.location.compareTo(b.location));
  observations.sort((a, b) => a.location.compareTo(b.location));

  return CruxGuardReport(
    guard: 'G4 — delete-database allowlist',
    subject: subject,
    findings: findings,
    observations: observations,
    guideSection: 'rule 5; "Corruption, migration failure and version skew"',
    whatBroke:
        'Code that owns a database deletes a database file, and nothing '
        'establishes that the file is reproducible.',
    whyTheRuleExists:
        'The app cannot tell "this file is garbage" from "this file is fine '
        'and I have a bug". Both arrive at an open call as the same '
        'exception — and so does a file that is merely LOCKED by another '
        'process. A handler that deletes on any of them destroys history that '
        'no support call can get back, in the case where the user did nothing '
        'wrong. That is not hypothetical: it is the defect this whole '
        'mechanism exists to remove, and it cost a paying user a year of '
        'violation history on an ordinary lock contention. Renaming aside '
        'costs one file the user can ignore; deleting costs everything.',
    theWayToGreen:
        'Rename the file aside instead — open through '
        'CruxSqliteOpenPolicy with CruxDbRecovery.renameAside, which '
        'quarantines the bytes as <db>.corrupt-<timestamp>, opens fresh '
        'alongside, and tells the diagnostics seam so the user learns why '
        'their chart is empty. Adding an allowlist entry is legitimate ONLY '
        "when the store's contents are genuinely reproducible from something "
        'else on disk, the inventory in the migration guide says so, and the '
        "entry references the store's own CruxDbRecovery constant rather than "
        'repeating its value.',
  );
}

final class _DeleteSite {
  const _DeleteSite(this.offset, this.description);
  final int offset;
  final String description;
}

/// `deleteDatabase(...)` in any form — the sqflite API and the factory method.
final RegExp _deleteDatabase = RegExp(r'\bdeleteDatabase\s*\(');

/// A `dart:io` delete whose target reads like a database file.
///
/// Two conditions, both necessary, and each one is there because of a shape
/// that would otherwise be misread:
///
///  * **The argument list is empty or only `recursive:`.** That is
///    `FileSystemEntity.delete`'s signature. `Database.delete(table, {where})`
///    — sqflite's ROW delete — takes a positional table name, and both
///    products use it constantly for exactly the bounded deletes the rules
///    permit (retention pruning, clearing acknowledgements). Firing on those
///    would flag correct code at the two sites most likely to be read as
///    proof the guard is noise.
///  * **The surrounding line names a database.** Both products also delete
///    ordinary files legitimately and often — JSON baselines, waveform
///    archives, scratch directories — and a guard that fired on all of them
///    would be switched off within a week.
final RegExp _fileDelete = RegExp(
  r'\b(\w+|File\s*\([^)]*\))\s*(?:\.\w+\s*)*'
  r'\.delete(?:Sync)?\s*\(\s*(?:recursive\s*:\s*\w+\s*,?\s*)?\)',
);

final RegExp _dbTarget = RegExp(
  r'''\.db['"]|\b\w*(?:[Dd]b|[Dd]atabase)(?:Path|File|Name)?\b''',
);

Iterable<_DeleteSite> _findDeleteSites(CruxSourceFile file) sync* {
  for (final match in _deleteDatabase.allMatches(file.source)) {
    yield _DeleteSite(
      match.start,
      'deleteDatabase(...) — deletes the file outright',
    );
  }
  for (final match in _fileDelete.allMatches(file.source)) {
    // `File(...)` on its own is not enough; the statement has to name a
    // database. This keeps waveform, baseline and temp-dir deletes out.
    final lineStart = file.source.lastIndexOf('\n', match.start) + 1;
    var lineEnd = file.source.indexOf('\n', match.start);
    if (lineEnd < 0) lineEnd = file.source.length;
    final line = file.source.substring(lineStart, lineEnd);
    if (!_dbTarget.hasMatch(line)) continue;
    yield _DeleteSite(
      match.start,
      'a dart:io delete of what the surrounding line names as a database '
      'file: ${line.trim()}',
    );
  }
}

/// Whether [offset] sits inside a `case CruxDbRecovery.recreate:` arm.
///
/// Scans backwards for the nearest `case CruxDbRecovery.<name>:` label. If it
/// is the `recreate` arm, the delete is reachable only for a store that
/// declared its contents reproducible — the same condition the runtime
/// enforces, checked in source.
bool _isRecreateArm(String source, int offset) {
  final label = RegExp(r'case\s+CruxDbRecovery\.(\w+)\s*:');
  String? nearest;
  for (final match in label.allMatches(source)) {
    if (match.start > offset) break;
    nearest = match.group(1);
  }
  return nearest == 'recreate';
}
