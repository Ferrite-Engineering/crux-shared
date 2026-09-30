// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/src/policy_document.dart';
import 'package:crux_policy/src/policy_value.dart';
import 'package:meta/meta.dart';

/// Which level supplied the value a caller is looking at.
enum PolicySource {
  /// The organization set it and forbade changing it.
  policyLocked,

  /// The user's own setting, which outranks an unlocked policy default.
  userSetting,

  /// The organization's suggested starting point, for a user who has not
  /// chosen. Outranked by any choice the user has actually made.
  policyDefault,

  /// The product's compiled-in default.
  builtIn,
}

/// A resolved setting and where it came from.
@immutable
class ResolvedSetting<T extends Object> {
  /// Creates a resolution.
  const ResolvedSetting({required this.value, required this.source});

  /// The value in force.
  final T value;

  /// Which level supplied it.
  final PolicySource source;

  /// Whether the user may change it.
  ///
  /// The Settings UI must render a locked control **with this source named**.
  /// A greyed control with no explanation is a support ticket; "locked by your
  /// organization's policy file" is not.
  bool get locked => source == PolicySource.policyLocked;
}

/// Resolves one key against a [PolicyDocument], the user's setting and the
/// product's built-in default.
///
/// Order, highest first:
///
/// ```text
/// 1. policy-LOCKED value      the organization decided, and forbade changing
/// 2. the user's own setting   what this user actually chose
/// 3. policy DEFAULT value     the organization's suggested starting point
/// 4. the product's built-in default
/// ```
///
/// ### Why 2 and 3 are this way round
///
/// The first draft of the specification wrote
/// `locked > default > user > built-in`. **That ordering is incoherent**, and
/// the specification was corrected to match this implementation rather than
/// the other way round.
///
/// The reason: if a policy *default* outranks the user's own setting, then the
/// user cannot change it — because "changing it" means writing a user setting,
/// which would immediately be outranked again. A default that cannot be
/// departed from is not a default; it is a lock whose control forgot to grey
/// itself out, which is strictly worse than a lock because the UI invites an
/// edit that silently does nothing.
///
/// Two behaviours are genuinely wanted and `locked` already distinguishes them:
///
/// - **locked** — the organization decided. The user sees the value, greyed,
///   with its source named.
/// - **default** — the organization supplies a starting point for anyone who
///   has not chosen. Whoever has chosen keeps their choice.
///
/// Getting this wrong is not cosmetic: an administrator who sets an unlocked
/// default expecting a suggestion would silently override every engineer's
/// preferences on the next deployment.
class PolicyResolver {
  /// Creates a resolver over [document] for the product identified by
  /// [productId].
  PolicyResolver({
    required this.document,
    required this.productId,
    List<PolicyDiagnostic>? diagnostics,
  }) : _diagnostics = diagnostics ?? <PolicyDiagnostic>[] {
    _diagnostics.addAll(document.diagnostics);
  }

  /// The policy in force.
  final PolicyDocument document;

  /// Which product this build is. A key naming a **different** product
  /// is ignored silently — not warned about, not an error. One file serves a
  /// mixed fleet, so a WaveCrux install meeting SimCrux keys is the normal
  /// case rather than a misconfiguration.
  final String productId;

  final List<PolicyDiagnostic> _diagnostics;

  /// Keys that were present but not applied.
  List<PolicyDiagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Resolve the suite-wide key [key].
  ///
  /// [parse] converts the raw JSON value to `T` and returns null when it is not
  /// valid — an unknown enum member, the wrong type, a malformed shape. An
  /// invalid value is **skipped and reported**, and resolution continues at the
  /// next level down.
  ResolvedSetting<T> suiteValue<T extends Object>(
    String key, {
    required T? Function(Object? raw) parse,
    required T builtIn,
    T? userSetting,
  }) => _resolve(
    dottedKey: 'suite.$key',
    raw: document.suite[key],
    parse: parse,
    builtIn: builtIn,
    userSetting: userSetting,
  );

  /// Resolve [key] from this product's namespace.
  ResolvedSetting<T> productValue<T extends Object>(
    String key, {
    required T? Function(Object? raw) parse,
    required T builtIn,
    T? userSetting,
  }) => _resolve(
    dottedKey: 'products.$productId.$key',
    raw: document.products[productId]?[key],
    parse: parse,
    builtIn: builtIn,
    userSetting: userSetting,
  );

  ResolvedSetting<T> _resolve<T extends Object>({
    required String dottedKey,
    required Object? raw,
    required T? Function(Object? raw) parse,
    required T builtIn,
    required T? userSetting,
  }) {
    final policy = _policyValue(dottedKey, raw, parse);

    // A lock outranks everything, including a choice the user already made.
    if (policy != null && policy.locked) {
      return ResolvedSetting<T>(
        value: policy.value,
        source: PolicySource.policyLocked,
      );
    }
    // The user's own choice outranks an unlocked policy default — see the
    // class doc for why a policy default does not outrank the user.
    if (userSetting != null) {
      return ResolvedSetting<T>(
        value: userSetting,
        source: PolicySource.userSetting,
      );
    }
    if (policy != null) {
      return ResolvedSetting<T>(
        value: policy.value,
        source: PolicySource.policyDefault,
      );
    }
    return ResolvedSetting<T>(value: builtIn, source: PolicySource.builtIn);
  }

  /// The policy's own value for a key, or null when it is absent or invalid.
  ///
  /// **A locked-but-invalid key does not fall back to a lock.** It falls back
  /// to the user's setting, because the alternative is inventing a value nobody
  /// wrote and presenting it as the organization's decision.
  PolicyValue<T>? _policyValue<T extends Object>(
    String dottedKey,
    Object? raw,
    T? Function(Object? raw) parse,
  ) {
    if (raw == null) return null;

    if (raw is Map<String, Object?>) {
      if (!raw.containsKey('value')) {
        _report(dottedKey, 'object form is missing its "value" member');
        return null;
      }
      final lockedRaw = raw['locked'];
      if (lockedRaw != null && lockedRaw is! bool) {
        _report(dottedKey, '"locked" must be a boolean');
        return null;
      }
      final parsed = parse(raw['value']);
      if (parsed == null) {
        _report(dottedKey, 'value ${_show(raw['value'])} is not valid here');
        return null;
      }
      return PolicyValue<T>(parsed, locked: lockedRaw as bool? ?? false);
    }

    final parsed = parse(raw);
    if (parsed == null) {
      _report(dottedKey, 'value ${_show(raw)} is not valid here');
      return null;
    }
    return PolicyValue<T>(parsed);
  }

  void _report(String key, String reason) =>
      _diagnostics.add(PolicyDiagnostic(key: key, reason: reason));

  static String _show(Object? raw) => raw is String ? '"$raw"' : '$raw';
}
