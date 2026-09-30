// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

/// The shared manifest directory in a browser, where there is no process
/// environment, no operating system to ask, and no filesystem to publish into.
///
/// All four products resolve this directory on the path that starts their CXP
/// server, and the products ship web builds. CXP discovery is a same-machine
/// filesystem mechanism, so a browser cannot take part — but it must learn that
/// through the documented [StateError] ("discovery unavailable", the same
/// signal as a missing `$HOME`), never through an `UnsupportedError` escaping
/// from `dart:io`.
///
/// Runs only under `dart test -p chrome test/web`, which CI invokes as its own
/// step. The VM suite never loads the stub, so this is the one place the web
/// path is actually executed.
void main() {
  group('with nothing injected', () {
    test('the manifest directory is unavailable, as a StateError', () {
      expect(sharedCxpManifestDirectory, throwsStateError);
    });

    test('the workspace directory, derived from it, is unavailable too', () {
      expect(sharedCxpWorkspaceDirectory, throwsStateError);
    });
  });

  group('with the environment and operating system injected', () {
    // Resolution is pure path arithmetic once both inputs are given, so a
    // caller that supplies them gets the same answer a desktop build would.
    test('the manifest directory resolves as on that platform', () {
      expect(
        sharedCxpManifestDirectory(
          environment: const {'HOME': '/Users/alice'},
          operatingSystem: 'macos',
        ),
        '/Users/alice/Library/Application Support/crux/cxp/peers',
      );
    });

    test('the workspace directory stays its sibling', () {
      expect(
        sharedCxpWorkspaceDirectory(
          environment: const {'HOME': '/home/alice'},
          operatingSystem: 'linux',
        ),
        '/home/alice/.local/share/crux/cxp/workspace',
      );
    });

    test('only one of the two is still unavailable', () {
      expect(
        () => sharedCxpManifestDirectory(
          environment: const {'HOME': '/Users/alice'},
        ),
        throwsStateError,
      );
      expect(
        () => sharedCxpManifestDirectory(operatingSystem: 'macos'),
        throwsStateError,
      );
    });
  });
}
