// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The static guard that keeps integration tests from booting behind the
/// licence agreement.
///
/// A separate entry point from `crux_eula.dart`, on the precedent of
/// `crux_sqlite_guards.dart`: test-only tooling never enters the runtime
/// barrel, and nothing here is imported by a product's `lib/`. The scanner
/// is shared; each product keeps a thin test under `test/static/` that hands
/// it that repository's `integration_test/` sources and names its own boot
/// and seed helpers:
///
/// ```dart
/// final findings = cruxAuditEulaSeededBoots(
///   sources: [
///     for (final f in integrationTestFiles)
///       CruxEulaGuardSource(path: f.path, source: f.readAsStringSync()),
///   ],
///   seedCalls: {'seedEulaAcceptance', 'seedFirstLaunchAnswers'},
/// );
/// expect(findings, isEmpty, reason: findings.join('\n'));
/// ```
library;

export 'src/guards/eula_seed_guard.dart';
