// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The product ids, and every key name the suite's policy schema knows —
/// suite-wide and per-product — with whether this suite honours each one.
///
/// Public, unlike the rest of the linter, because two callers need it: the
/// `crux-policy` CLI, which reports a key an administrator misspelled or one
/// this release does not honour, and each product at startup, which reports
/// the same thing to an administrator who never runs the CLI.
library;

/// The product ids the schema knows.
const Set<String> kKnownProducts = {
  'wavecrux',
  'netcrux',
  'lintcrux',
  'simcrux',
};

/// Every suite-wide key the schema knows, and whether this suite **honours**
/// it — the same column, meaning and reporting as [kProductKeys], for the keys
/// under `suite` (<https://edacrux.app/policy-reference#suite-keys>).
///
/// `true` means some production code reads the key; `false` means it is
/// registered vocabulary that nothing acts on yet. A `false` key still lints
/// for shape, and both `crux-policy lint` and the startup report name it as
/// not honoured, for the reason [kProductKeys] gives: several of these
/// describe a restriction, and silence would read as the restriction being in
/// force.
///
/// Who reads each `true` key:
///
/// - `telemetry`, `license`, `updateChannel`, `pinnedVersion` and
///   `manifestUrl` are the day-one keys. `DayOnePolicy` resolves them with no
///   licence present, and each product's Pro build binds them from there.
/// - `audit` configures the audit sink the licence package builds from the
///   policy file.
///
/// Adding a key to the schema means adding it here **and** giving it a
/// validator in the linter; a test holds the two key sets equal. Flipping a key
/// to `true` is the last line of the change that makes something read it.
const Map<String, bool> kSuiteKeys = {
  'telemetry': true,
  'license': true,
  'updateChannel': true,
  'pinnedVersion': true,
  'manifestUrl': true,
  'audit': true,
  'theme': false,
  'filePathRestrictions': false,
  'plugins': false,
  'remoteApis': false,
};

/// Every key each product registers, and whether this suite **honours** it.
///
/// `true` means some production code reads the key; `false` means it is
/// registered vocabulary that nothing acts on yet. Both are linted, and they
/// are linted *differently*, because they are different mistakes: a key not in
/// this map at all is almost certainly a typo, while a key with `false` is
/// spelled correctly and still will not do anything.
///
/// **Why the second case needs saying out loud.** Several of these configure a
/// restriction — whether a server may run, which peers may be reached, which
/// binaries may be invoked. An administrator who writes one and hears nothing
/// concludes the restriction is in force. Silence is the worst answer
/// available: worse than rejecting the key, because a rejection is visible.
///
/// Kept here rather than in the products because the linter is a standalone
/// CLI in this package and cannot import them. Each product's
/// `*_policy_keys_test.dart` asserts its registry matches its entry, so the
/// two cannot drift apart unnoticed.
const Map<String, Map<String, bool>> kProductKeys = {
  'wavecrux': {
    'signalGroups': true,
    'decoderSettings': true,
    'sessionTemplates': true,
    'themePacks': true,
    'wcpServer': true,
    'cxpServer': true,
    'approvedPlugins': true,
  },
  'netcrux': {
    'crossProbePeerAllowlist': true,
    'symbolLibraries': true,
  },
  'lintcrux': {
    'ruleSeverityOverrides': false,
    'mandatoryEngines': false,
    'ciGateThreshold': true,
    'teamDatabaseSubmitter': true,
  },
  'simcrux': {
    'defaultSimulator': false,
    'simulatorBinaryPolicy': false,
    'ciGateThreshold': false,
    'retentionPolicy': true,
    'distributedExecutionBackend': true,
    'teamDatabaseSubmitter': true,
  },
};
