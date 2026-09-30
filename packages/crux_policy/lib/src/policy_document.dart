// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_policy/src/policy_value.dart';
import 'package:meta/meta.dart';

/// A parsed `.crux-policy.json`, or the reason there is not one.
///
/// **Total by construction.** Every path returns a document; no input reaches a
/// `throw`. A policy file arrives from a network share and may be anything at
/// all, and the caller needs an answer rather than a crash.
@immutable
class PolicyDocument {
  /// Creates a document.
  const PolicyDocument({
    required this.schema,
    required this.suite,
    required this.products,
    this.org,
    this.diagnostics = const <PolicyDiagnostic>[],
  });

  /// Parse [source] into a document. **Never throws** — a malformed file
  /// yields a document with diagnostics, not an exception.
  factory PolicyDocument.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      return PolicyDocument(
        schema: 0,
        suite: const <String, Object?>{},
        products: const <String, Map<String, Object?>>{},
        diagnostics: [
          PolicyDiagnostic(key: '<file>', reason: 'not valid JSON: $error'),
        ],
      );
    }
    if (decoded is! Map<String, Object?>) {
      return const PolicyDocument(
        schema: 0,
        suite: <String, Object?>{},
        products: <String, Map<String, Object?>>{},
        diagnostics: [
          PolicyDiagnostic(key: '<file>', reason: 'top level is not an object'),
        ],
      );
    }

    final diagnostics = <PolicyDiagnostic>[];

    final schemaValue = decoded['schema'];
    final schema = schemaValue is int ? schemaValue : 0;
    if (schemaValue == null) {
      diagnostics.add(
        const PolicyDiagnostic(
          key: 'schema',
          reason: 'missing; it is the one required key',
        ),
      );
    } else if (schemaValue is! int) {
      diagnostics.add(
        PolicyDiagnostic(
          key: 'schema',
          reason: 'must be an integer, got ${schemaValue.runtimeType}',
        ),
      );
    }

    final suite = decoded['suite'];
    final products = decoded['products'];

    return PolicyDocument(
      schema: schema == 0 && schemaValue is! int ? 1 : schema,
      org: decoded['org'] is String ? decoded['org']! as String : null,
      suite: suite is Map<String, Object?> ? suite : const <String, Object?>{},
      products: <String, Map<String, Object?>>{
        if (products is Map<String, Object?>)
          for (final entry in products.entries)
            if (entry.value case final Map<String, Object?> body)
              entry.key: body,
      },
      diagnostics: diagnostics,
    );
  }

  /// The state of every installation with no policy file: **behaves exactly as
  /// if the seam did not exist.**
  ///
  /// A file that is missing, unreadable or malformed lands here
  /// (<https://edacrux.app/policy-reference#failures>).
  /// Failing closed on a missing file would brick a deployment over a typo.
  static const PolicyDocument absent = PolicyDocument(
    schema: 0,
    suite: <String, Object?>{},
    products: <String, Map<String, Object?>>{},
  );

  /// The declared schema version.
  ///
  /// **Read for diagnostics, never for gatekeeping.** A client MUST
  /// NOT refuse a file whose schema is higher than it knows. Refusing a newer
  /// file reintroduces exactly the version coupling this whole design removes.
  final int schema;

  /// Suite-wide keys, raw. Read through a resolver rather than directly.
  final Map<String, Object?> suite;

  /// Per-product namespaces, raw.
  final Map<String, Map<String, Object?>> products;

  /// The organization's own name for itself, if it set one.
  final String? org;

  /// Keys that were present but not applied. See [PolicyDiagnostic].
  final List<PolicyDiagnostic> diagnostics;

  /// Whether any policy governs this installation.
  bool get isPresent => !identical(this, absent) && schema > 0;
}
