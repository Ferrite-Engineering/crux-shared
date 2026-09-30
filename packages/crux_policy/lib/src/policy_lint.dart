// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_policy/src/policy_document.dart';
import 'package:crux_policy/src/policy_value.dart';
import 'package:crux_policy/src/product_keys.dart';

/// A validator for every suite-wide key the schema knows.
///
/// <https://edacrux.app/policy-reference#suite-keys>. The key *names*, and
/// whether each is honoured, are [kSuiteKeys]; this map says only what a valid
/// value looks like, and a test holds its key set equal to that one. Together
/// with [kSuiteAuditKeys] these are the CLI's only sources of truth about what
/// is valid. A key whose value is an object needs a companion map like that
/// one — a bare `is Map` validator leaves the whole subtree unchecked.
final Map<String, bool Function(Object? value)> kSuiteKeyValidators = {
  'telemetry': (v) => v == 'allow' || v == 'deny',
  'license': (v) =>
      v is Map<String, Object?> &&
      (v.containsKey('key') ^ v.containsKey('file')) &&
      (v['key'] ?? v['file']) is String,
  'updateChannel': (v) => v == 'stable' || v == 'beta' || v == 'pinned',
  'pinnedVersion': (v) => v is String,
  'manifestUrl': (v) => v is String && Uri.tryParse(v) != null,
  'theme': (v) => v is String,
  'filePathRestrictions': (v) => v is Map<String, Object?>,
  'audit': (v) => v is Map<String, Object?>,
  'plugins': (v) => v is Map<String, Object?>,
  'remoteApis': (v) => v is Map<String, Object?>,
};

/// Every key inside `suite.audit`, with a validator.
///
/// Separate from [kSuiteKeyValidators] because `audit` is an object rather
/// than a scalar, and a validator that only asserted "is a map" left the whole
/// subtree unchecked — a file whose every audit key was misspelled linted
/// clean.
///
/// **`path` is the key that turns auditing on.** `policy_binding.dart` falls
/// back to `NoopAuditSink` when it is missing or not a string, so a typo there
/// silently disables an Enterprise compliance feature. The runtime is
/// deliberately fail-soft about `verbosity` — an unrecognised level resolves to
/// `normal`, never `off` — and that fail-soft choice is only safe because this
/// lint is supposed to catch the typo first.
final Map<String, bool Function(Object? value)> kSuiteAuditKeys = {
  'path': (v) => v is String && v.trim().isNotEmpty,
  'verbosity': (v) => v == 'off' || v == 'normal' || v == 'verbose',
};

/// Everything wrong with [source], reported at once.
///
/// **At once** is the point: an administrator fixing a policy file one error
/// per run is an administrator who stops using the tool.
List<PolicyDiagnostic> lintPolicySource(String source) {
  final out = <PolicyDiagnostic>[];

  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    return [PolicyDiagnostic(key: '<file>', reason: 'not valid JSON: $error')];
  }
  if (decoded is! Map<String, Object?>) {
    return const [
      PolicyDiagnostic(key: '<file>', reason: 'top level must be an object'),
    ];
  }

  out.addAll(PolicyDocument.parse(source).diagnostics);

  final suite = decoded['suite'];
  if (suite != null && suite is! Map<String, Object?>) {
    out.add(
      const PolicyDiagnostic(key: 'suite', reason: 'must be an object'),
    );
  } else if (suite is Map<String, Object?>) {
    for (final entry in suite.entries) {
      final honoured = kSuiteKeys[entry.key];
      final validator = kSuiteKeyValidators[entry.key];
      if (honoured == null || validator == null) {
        // NOT an error. Unknown keys are ignored by clients, and a
        // lint that failed on them would make every forward-compatible file
        // unlintable by an older CLI.
        out.add(
          PolicyDiagnostic(
            key: 'suite.${entry.key}',
            reason:
                'unknown to this version of the CLI — clients will ignore it, '
                'which is by design; check the spelling',
          ),
        );
        continue;
      }
      final unwrapped = _unwrap(entry.value, 'suite.${entry.key}', out);
      if (unwrapped != _invalid && !validator(unwrapped)) {
        out.add(
          PolicyDiagnostic(
            key: 'suite.${entry.key}',
            reason: 'value ${jsonEncode(unwrapped)} is not valid for this key',
          ),
        );
      }
      // Spelled correctly, and nothing reads it. Reported whatever the value's
      // shape, in the same words as an unhonoured product key: the two are the
      // same mistake, and an administrator should not have to learn which
      // block a key lives in to be told it does nothing.
      if (!honoured) out.add(_notHonoured('suite.${entry.key}'));
    }

    // Descend into `audit`. Unknown child keys get the same forward-compatible
    // wording as unknown suite keys: a client ignores them, so this is a
    // spelling prompt rather than a hard error.
    final auditRaw = _unwrap(suite['audit'], 'suite.audit', out);
    if (auditRaw is Map<String, Object?>) {
      for (final entry in auditRaw.entries) {
        final key = 'suite.audit.${entry.key}';
        final validator = kSuiteAuditKeys[entry.key];
        if (validator == null) {
          out.add(
            PolicyDiagnostic(
              key: key,
              reason:
                  'unknown to this version of the CLI — clients will ignore '
                  'it, which is by design; check the spelling',
            ),
          );
          continue;
        }
        final unwrapped = _unwrap(entry.value, key, out);
        if (unwrapped == _invalid) continue;
        if (!validator(unwrapped)) {
          out.add(
            PolicyDiagnostic(
              key: key,
              reason:
                  'value ${jsonEncode(unwrapped)} is not valid for this key',
            ),
          );
        }
      }
      if (!auditRaw.containsKey('path')) {
        out.add(
          const PolicyDiagnostic(
            key: 'suite.audit.path',
            reason:
                'required — without it the audit sink is a no-op and nothing '
                'is recorded',
          ),
        );
      }
    }

    if (suite['updateChannel'] case final Object channel) {
      final value = channel is Map<String, Object?>
          ? channel['value']
          : channel;
      if (value == 'pinned' && !suite.containsKey('pinnedVersion')) {
        out.add(
          const PolicyDiagnostic(
            key: 'suite.pinnedVersion',
            reason: 'required when updateChannel is "pinned"',
          ),
        );
      }
    }
  }

  final products = decoded['products'];
  if (products != null && products is! Map<String, Object?>) {
    out.add(
      const PolicyDiagnostic(key: 'products', reason: 'must be an object'),
    );
  } else if (products is Map<String, Object?>) {
    for (final entry in products.entries) {
      if (!kKnownProducts.contains(entry.key)) {
        out.add(
          PolicyDiagnostic(
            key: 'products.${entry.key}',
            reason:
                'not a product in this suite — clients ignore it silently, so '
                'this is almost certainly a typo',
          ),
        );
      }
      if (entry.value is! Map<String, Object?>) {
        out.add(
          PolicyDiagnostic(
            key: 'products.${entry.key}',
            reason: 'must be an object',
          ),
        );
        continue;
      }

      // Descend into the product's own keys. Without this, EVERY key under a
      // correctly-spelled product linted clean — a misspelled key and a key
      // this build does not honour were both answered with silence, which is
      // the one answer an administrator cannot act on.
      final known = kProductKeys[entry.key];
      if (known == null) continue; // unknown product, already reported above
      final block = entry.value! as Map<String, Object?>;
      for (final key in block.keys) {
        final honoured = known[key];
        if (honoured == null) {
          out.add(
            PolicyDiagnostic(
              key: 'products.${entry.key}.$key',
              reason:
                  'unknown to this version of the CLI — clients will ignore '
                  'it, which is by design; check the spelling',
            ),
          );
        } else if (!honoured) {
          out.add(_notHonoured('products.${entry.key}.$key'));
        }
      }
    }
  }

  return out;
}

/// The finding for a key that is registered, spelled correctly, and read by
/// nothing — worded identically for a suite key and a product key.
PolicyDiagnostic _notHonoured(String key) => PolicyDiagnostic(
  key: key,
  reason:
      'registered but NOT honoured by this release — it is spelled '
      'correctly and will still have no effect. If it configures a '
      'restriction, the restriction is not in force',
);

const Object _invalid = Object();

Object? _unwrap(Object? raw, String key, List<PolicyDiagnostic> out) {
  if (raw is! Map<String, Object?>) return raw;
  if (!raw.containsKey('value')) {
    // Could legitimately be a nested object key like `audit` — only complain
    // when the shape looks like a botched lock.
    if (raw.containsKey('locked')) {
      out.add(
        PolicyDiagnostic(key: key, reason: 'has "locked" but no "value"'),
      );
      return _invalid;
    }
    return raw;
  }
  final locked = raw['locked'];
  if (locked != null && locked is! bool) {
    out.add(PolicyDiagnostic(key: key, reason: '"locked" must be a boolean'));
    return _invalid;
  }
  return raw['value'];
}
