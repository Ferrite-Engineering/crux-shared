// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/src/audit_recorder.dart';
import 'package:crux_license/src/license_controller.dart';
import 'package:crux_license/src/license_panel_providers.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:meta/meta.dart';

/// The policy file in force, loaded once per process.
///
/// A plain [Provider] doing synchronous I/O at first read, deliberately. The
/// three day-one keys are needed **before the first frame** — the telemetry
/// disclosure decides whether to appear, and the licence decides what tier the
/// window opens at — and an asynchronous seam would have to pick a behaviour
/// for the window in between, which is a policy state nobody asked for.
///
/// Reading two small local files at startup is not the cost worth avoiding.
///
/// ### The organization's public key is not bound here, on purpose
///
/// `PolicyLoader` reads it from `crux-policy.pub` beside the well-known policy
/// path — the one directory an unprivileged user cannot write — so this
/// default construction **is** the production configuration for every
/// product, and a signed file verifies on a clean machine with nothing
/// compiled in. An earlier revision documented an
/// `overrideWithValue(PolicyLoader(trustedPublicKey: …).load())` seam as the
/// way a host supplied its key; no product ever used it, so every signed
/// policy file in the field was refused. The override still works and is what
/// a test uses to hand the panel a fixed result; it is not how a key arrives.
final cruxPolicyProvider = Provider<PolicyLoadResult>(
  (ref) => cruxPolicyLoader.load(),
  name: 'cruxPolicyProvider',
);

/// The loader [cruxPolicyProvider] runs, in every product.
///
/// Named so a test can pin what it is: the **default construction**, which
/// reads the organization's key from `crux-policy.pub` beside the well-known
/// policy path, binds no key in code, and redirects nothing. A constructor
/// argument here is the only way a build could ship without that key source —
/// or with a key Ferrite chose, which must never happen — so this is the one
/// line to watch, and `policy_binding_test.dart` watches it.
const cruxPolicyLoader = PolicyLoader();

/// The three keys that resolve **before a licence exists**.
///
/// Nothing reached from here may consult a tier: the first-launch telemetry
/// disclosure fires before any key has been entered, so the tier is unknown at
/// that instant by construction.
final dayOnePolicyProvider = Provider<DayOnePolicy>(
  (ref) => DayOnePolicy.of(ref.watch(cruxPolicyProvider).document),
  name: 'dayOnePolicyProvider',
);

/// The overrides a Pro overlay adds to be governed by the policy file.
///
/// One spread per product instead of the same wiring written four times and
/// drifting:
///
/// ```dart
/// ...cruxPolicyOverrides(),
/// ```
///
/// It binds [licenseManagedByOrganizationProvider], which renders the licence
/// panel read-only — **locked, not hidden**, so support can still ask an
/// engineer to read their own tier and expiry back.
///
/// It deliberately does **not** bind telemetry. That override needs
/// `crux_telemetry`'s vocabulary, and giving this package a dependency on it
/// would pull analytics into every licence consumer in the suite. The product
/// does that one, and it is one line.
List<Override> cruxPolicyOverrides() => <Override>[
  licenseManagedByOrganizationProvider.overrideWith(
    (ref) => ref.watch(dayOnePolicyProvider).license != null,
  ),
];

/// Activate from a licence the organization supplied in its policy file.
///
/// Call once at startup, after `controller.start()`. Does nothing when the
/// policy carries no `license` key, and **does nothing when a credential is
/// already stored** — re-activating on every launch would hit the issuer for a
/// machine that is already licensed and, on an airgapped seat, would be a
/// network call the whole design promises never happens.
///
/// ### It goes through the same path a paste does
///
/// [CruxLicenseController.activate] and nothing else. The credential the
/// organization deployed is a credential; it gets no private route into the
/// store, no separate validation, and no exemption from the checks a typed key
/// faces. An Enterprise policy licence therefore resolves with **no network
/// call at any point**, because `activate` writes the credential before it
/// tries the issuer and the resolve falls back to the stored value.
///
/// Returns whether a policy licence was applied.
Future<bool> applyPolicyLicense({
  required CruxLicenseController controller,
  required DayOnePolicy policy,
  required Future<String?> Function(String path) readFile,
}) async {
  final license = policy.license;
  if (license == null) return false;
  // Already licensed — by an earlier launch of this same policy, or by a user
  // whose key predates the deployment. The key already in use wins over the
  // policy's, and that is decided here rather than left to load order.
  if (controller.status.hasCredential) return false;

  final credential = switch (license.kind) {
    PolicyLicenseKind.inline => license.value,
    PolicyLicenseKind.file => await readFile(license.value),
  };
  if (credential == null || credential.trim().isEmpty) return false;

  final result = await controller.activate(credential);
  return result.isOk;
}

/// The audit sink this installation writes to, configured from the policy file.
///
/// [NoopAuditSink] unless the organization set `suite.audit.path`, which is the
/// honest default: auditing is off until an administrator turns it on, and a
/// product that invented a path would be writing a file nobody asked for into a
/// location nobody chose.
///
/// Lives here rather than in `crux_audit` because that package is pure Dart and
/// must stay that way — both products' headless CLIs write audit events — and a
/// Riverpod dependency would be the first Flutter-adjacent import. It lives in
/// one place rather than four because the wiring is identical in every product;
/// only the event *kinds* differ, and those are the product's.
final cruxAuditSinkProvider = Provider<AuditSink>((ref) {
  final audit = ref.watch(cruxPolicyProvider).document.suite['audit'];
  final config = audit is Map<String, Object?> && audit.containsKey('value')
      ? audit['value']
      : audit;
  if (config is! Map<String, Object?>) return const NoopAuditSink();

  final path = config['path'];
  if (path is! String || path.trim().isEmpty) return const NoopAuditSink();

  final sink = JsonlAuditSink(
    path: path.trim(),
    verbosity: switch (config['verbosity']) {
      'off' => AuditVerbosity.off,
      'verbose' => AuditVerbosity.verbose,
      // Anything unrecognised is `normal`, not an error. An administrator's
      // typo in a verbosity level must not turn auditing off silently — that
      // is the one direction this must never fail in.
      _ => AuditVerbosity.normal,
    },
  );
  ref.onDispose(sink.close);
  return sink;
}, name: 'cruxAuditSinkProvider');

/// Where a policy-load report can actually be recorded.
///
/// A refusal has to be observable
/// (<https://edacrux.app/policy-reference#failures>), and the obvious
/// implementation — record `policy.rejected` through [CruxAuditRecorder] —
/// is **impossible by construction**. Written down so nobody spends an
/// afternoon rediscovering it:
///
/// > The sink's path comes from `suite.audit.path`, which comes from the
/// > policy document. A refused file yields [PolicyDocument.absent], so
/// > `suite['audit']` is empty, so the sink is [NoopAuditSink]. **The one file
/// > that would say where to record the refusal is the one just refused.**
///
/// Reading `suite.audit.path` out of the rejected document anyway is not a way
/// around that; it inverts the threat model the signature exists for. An
/// attacker who can write the share supplies a policy whose signature fails and
/// whose audit path we honour, and the application dutifully creates a file
/// wherever they said. **A refused file gets nothing honoured from it, this
/// included.**
///
/// So the two events go to different destinations, because they are answerable
/// in different places:
///
/// - **`policy.loaded` → the audit sink.** That file configured that sink, so
///   recording into it is coherent.
/// - **`policy.rejected` → the process log.** The only channel that needs
///   nothing from the file being refused.
///
/// The process log is not a consolation prize: it is what a support bundle
/// carries, it is where [JsonlAuditSink] already reports its own failures, and
/// nothing an attacker influenced can redirect it. What it is *not* is
/// something an administrator sees at a glance — so `CruxLicensePanel`, the
/// licence settings panel each product's Pro build mounts, renders the same
/// fact from [cruxPolicyProvider] as a refused-policy notice above the licence
/// status, with the reason and this report's [PolicyLoadReport.line]. A fact
/// nothing renders was the original defect.
enum PolicyReportDestination {
  /// Recorded to the configured audit sink.
  auditSink,

  /// Reported to the process log, because no configured sink can be trusted to
  /// exist.
  processLog,
}

/// A policy load, reduced to the facts a report carries.
///
/// Pure: deciding *what to say* is testable with no sink, no container and no
/// file. [PolicyLoadResult] in, this out, and `null` when there is nothing to
/// report.
///
/// **The payload names the discovery source, never the path.** `CRUX_POLICY`
/// can point anywhere, including a home directory, and the suite's rule is that
/// no audit payload carries a filesystem path. There are only two places a
/// policy file can come from, so naming which one won answers *"which file
/// won"* completely without naming the file.
@immutable
class PolicyLoadReport {
  /// Creates a report.
  const PolicyLoadReport({
    required this.kind,
    required this.destination,
    required this.severity,
    required this.payload,
  });

  /// The report for [result], or `null` when no file was found.
  ///
  /// **Absent is not an event.** Every unmanaged installation takes that path,
  /// and a line saying *"no policy file"* on every launch of every free copy is
  /// noise that trains an administrator to ignore the one line that matters.
  static PolicyLoadReport? of(PolicyLoadResult result) {
    if (result.wasRejected) {
      return PolicyLoadReport(
        kind: CruxSharedAuditKinds.policyRejected,
        destination: PolicyReportDestination.processLog,
        // The spec says warning at minimum. Warning rather than error: the
        // application is running correctly and an administrator's intent is not
        // in force, which is what warning means.
        severity: AuditSeverity.warning,
        payload: <String, Object?>{
          'discovery': result.discovery.name,
          'signed': result.signed,
          // What the loader found when it looked for the organization's key.
          // `reason=noPublicKey key=malformed` and `reason=noPublicKey
          // key=none` are different tickets.
          'key': result.keyStatus.name,
          'reason': result.rejection!.name,
          if (result.detail case final String detail) 'detail': detail,
        },
      );
    }
    if (!result.wasLoaded) return null;
    return PolicyLoadReport(
      kind: CruxSharedAuditKinds.policyLoaded,
      destination: PolicyReportDestination.auditSink,
      severity: AuditSeverity.info,
      payload: <String, Object?>{
        'discovery': result.discovery.name,
        'signed': result.signed,
        'key': result.keyStatus.name,
      },
    );
  }

  /// The registered audit kind this report is.
  final String kind;

  /// Where it can actually be recorded.
  final PolicyReportDestination destination;

  /// How much it matters.
  final AuditSeverity severity;

  /// Structured detail. **Never a filesystem path.**
  final Map<String, Object?> payload;

  /// The one-line form, for the process log.
  String get line {
    final fields = payload.entries.map((e) => '${e.key}=${e.value}').join(' ');
    return 'crux_policy: $kind $fields';
  }
}

/// Report the policy load once, at startup.
///
/// Call after `controller.start()`, beside [applyPolicyLicense]. Returns what
/// it reported, or `null` when there was no file — useful to a test, ignored in
/// production.
///
/// Before the load report it names any key the administrator set that this
/// build **registers but does not act on** — every suite key registered with
/// `honoured: false` in `kSuiteKeys`, always, and, when [productId] is given,
/// that product's unhonoured keys from `kProductKeys`. Pass [productId];
/// omitting it is silently reporting less.
///
/// [onDiagnostic] defaults to stderr, matching [JsonlAuditSink].
PolicyLoadReport? reportPolicyLoad({
  required PolicyLoadResult result,
  required CruxAuditRecorder recorder,
  String? productId,
  void Function(String message)? onDiagnostic,
}) {
  final diagnose = onDiagnostic ?? _defaultPolicyDiagnostic;

  // Keys this build knows and ignores.
  //
  // Reported BEFORE the load report and independently of it, because the two
  // are unrelated: a file can be perfectly valid, perfectly signed, honoured
  // in full — and still set six keys that do nothing. The administrator has no
  // other way to find that out. `crux-policy lint` says the same thing, but a
  // lint only helps someone who runs one, and the person who most needs this
  // is the one who wrote the file, restarted the app, and believes the
  // restriction is now in force.
  //
  // Only keys registered with `honoured: false` are named. An *unrecognised*
  // key is deliberately NOT reported here: a newer file read by an older build
  // is expected to carry keys this release has never heard of, and the schema
  // says clients ignore those by design. Naming them would make every
  // forward-compatible file noisy at every launch.
  //
  // Suite keys first, and independent of productId: they mean the same thing
  // to every product, so there is no product to ask about.
  final ignoredSuite =
      result.document.suite.keys.where((k) => kSuiteKeys[k] == false).toList()
        ..sort();
  if (ignoredSuite.isNotEmpty) {
    diagnose(
      'crux_policy: policy.keysNotHonoured scope=suite '
      'keys=${ignoredSuite.join(",")} '
      '(set in the policy file; this build does not act on them)',
    );
  }
  if (productId != null) {
    final present = result.document.products[productId];
    final known = kProductKeys[productId];
    if (present != null && known != null) {
      final ignored = present.keys.where((k) => known[k] == false).toList()
        ..sort();
      if (ignored.isNotEmpty) {
        diagnose(
          'crux_policy: policy.keysNotHonoured product=$productId '
          'keys=${ignored.join(",")} '
          '(set in the policy file; this build does not act on them)',
        );
      }
    }
  }

  final report = PolicyLoadReport.of(result);
  if (report == null) return null;
  switch (report.destination) {
    case PolicyReportDestination.auditSink:
      recorder.record(
        report.kind,
        severity: report.severity,
        payload: report.payload,
      );
    case PolicyReportDestination.processLog:
      diagnose(report.line);
  }
  return report;
}

void _defaultPolicyDiagnostic(String message) {
  stderr.writeln(message);
}
