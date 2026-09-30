// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_audit/src/audit_event.dart' show AuditSeverity;

/// The audit event kinds that are **not** a product's own business.
///
/// Kinds are per-product by design — the envelope is shared, the vocabulary is
/// not — but three events describe the shared machinery itself rather than
/// anything a product does, and giving each product its own spelling of "the
/// policy file was rejected" would make a shared file unfilterable for exactly
/// the events an administrator most wants to find.
///
/// These are the shared kinds of <https://edacrux.app/audit-log#shared>, given
/// identifiers.
abstract final class CruxSharedAuditKinds {
  /// `policy.loaded` — a policy file was found and honoured.
  ///
  /// Payload names the discovery source and whether the file was signed, which
  /// together answer the question an administrator debugging a value they
  /// cannot account for is actually asking: *which* file won.
  static const String policyLoaded = 'policy.loaded';

  /// `policy.rejected` — a policy file was found and refused.
  ///
  /// [AuditSeverity.warning] at minimum. This is the loud half of the spec's
  /// two-failures rule: a missing or malformed file degrades silently to
  /// `absent` because failing closed there bricks a deployment over a typo,
  /// but a file whose signature does not verify is refused and said so, because
  /// failing open on a bad signature is self-granting.
  static const String policyRejected = 'policy.rejected';

  /// `plugin.load.refused` — a plugin outside the allowlist was not loaded.
  ///
  /// Distinct from any product's own plugin-load-attempted kind: this is the
  /// refusal, which is the security-relevant event.
  static const String pluginLoadRefused = 'plugin.load.refused';

  /// Every shared kind, for the products' conformance tests.
  static const Set<String> all = <String>{
    policyLoaded,
    policyRejected,
    pluginLoadRefused,
  };
}
