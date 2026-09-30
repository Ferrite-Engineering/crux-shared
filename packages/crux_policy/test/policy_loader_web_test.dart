// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:crux_policy/crux_policy.dart';
import 'package:test/test.dart';

/// The loader on the web, where there is no process environment and no
/// filesystem.
///
/// Every product reads the policy file before its first frame, and the web
/// builds run the same startup path as desktop. So the web answer has to be the
/// same one a desktop machine with no policy file gets — **absent** — and never
/// an `UnsupportedError` from `dart:io` escaping into app startup.
///
/// Runs only under `dart test -p chrome`, which CI's Chrome step invokes. The
/// VM suite never loads the stub, so this is the one place the web path is
/// actually executed.
void main() {
  test('load() reports an absent policy rather than throwing', () {
    final result = const PolicyLoader().load();

    expect(result.document.isPresent, isFalse);
    expect(result.wasRejected, isFalse);
    expect(result.sourcePath, isNull);
    // The key lookup runs before discovery and reads a file too; with no
    // filesystem it must answer "none", not throw.
    expect(result.keyStatus, PolicyKeyStatus.none);
  });

  test('a CRUX_POLICY override points at a file that cannot exist here', () {
    // A host that injects an environment still has no filesystem to read.
    final result = const PolicyLoader(
      environment: <String, String>{'CRUX_POLICY': '/etc/policy.json'},
    ).load();

    expect(result.document.isPresent, isFalse);
    expect(result.wasRejected, isFalse);
  });

  test('defaultWellKnownPath does not reach for the platform', () {
    expect(PolicyLoader.defaultWellKnownPath, returnsNormally);
    expect(PolicyLoader.defaultPublicKeyPath, returnsNormally);
  });
}
