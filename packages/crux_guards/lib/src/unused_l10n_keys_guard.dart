// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crux_guards/src/guard_types.dart';
import 'package:meta/meta.dart';

/// A localisation key kept on purpose with no current reader, and why.
@immutable
final class CruxL10nRetention {
  /// Creates a retention entry.
  const CruxL10nRetention({required this.key, required this.reason});

  /// The ARB message key.
  final String key;

  /// Why it stays: for example, a generic message whose last user was just
  /// removed and that the product expects to need again within a release,
  /// where re-adding it would mean translating it again in every locale.
  final String reason;
}

/// The message keys of an ARB document: every top-level key that is not
/// `@`-prefixed metadata (`@@locale`, `@key` descriptions).
Set<String> cruxArbMessageKeys(String arbJson) {
  final decoded = jsonDecode(arbJson);
  if (decoded is! Map) {
    throw const FormatException('An ARB document is a JSON object');
  }
  return <String>{
    for (final key in decoded.keys)
      if (key is String && !key.startsWith('@')) key,
  };
}

/// Every localisation key some code reads.
///
/// [keys] are the template locale's message keys (see [cruxArbMessageKeys]);
/// [sources] are the product's hand-written `lib/` files, **without** the
/// generated localisations, which declare every key and would make each one
/// look used.
///
/// A key counts as read when an identifier of that name appears in code: the
/// generated accessor `l10n.someKey`, `AppLocalizations.of(context)!.someKey`,
/// or a getter that forwards to it all name it. Identifiers are read from the
/// parsed syntax tree, so a key mentioned in a comment or a string does not
/// count. The tree is not resolved, so an unrelated member that happens to
/// share a key's name also counts as a read: the guard can miss an unused key
/// that way, but never reports a used one.
///
/// A key in [retained] is allowed to go unread, with its reason. An entry
/// that names a key some code does read, or a key the ARB no longer has, is
/// a finding as well: the list stays exactly as long as it needs to be.
CruxGuardResult cruxAuditUnusedL10nKeys({
  required Set<String> keys,
  required Iterable<CruxGuardSource> sources,
  Iterable<CruxL10nRetention> retained = const <CruxL10nRetention>[],
  String arbPath = 'the template ARB',
}) {
  final names = <String>{};
  var files = 0;
  for (final file in sources) {
    files++;
    parseString(
      content: file.source,
      throwIfDiagnostics: false,
    ).unit.accept(_IdentifierCollector(names));
  }
  final read = keys.intersection(names);
  final kept = {for (final r in retained) r.key: r};
  final findings = <CruxGuardFinding>[
    for (final key in keys.difference(read).toList()..sort())
      if (!kept.containsKey(key))
        CruxGuardFinding(
          path: arbPath,
          line: 0,
          detail:
              'key "$key" is read by no code. Delete it from every locale, or '
              'retain it with a reason if it is kept on purpose.',
        ),
    for (final entry in kept.entries)
      if (!keys.contains(entry.key))
        CruxGuardFinding(
          path: arbPath,
          line: 0,
          detail:
              'retained key "${entry.key}" is not in the ARB any more; '
              'remove the retention entry.',
        )
      else if (read.contains(entry.key))
        CruxGuardFinding(
          path: arbPath,
          line: 0,
          detail:
              'retained key "${entry.key}" is read by code again; remove the '
              'retention entry.',
        ),
  ];
  return CruxGuardResult(
    findings: findings,
    filesScanned: files,
    matchesSeen: read.length,
  );
}

class _IdentifierCollector extends RecursiveAstVisitor<void> {
  _IdentifierCollector(this.names);

  final Set<String> names;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}
