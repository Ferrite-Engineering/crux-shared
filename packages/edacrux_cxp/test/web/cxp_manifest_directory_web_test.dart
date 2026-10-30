// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:edacrux_cxp/edacrux_cxp.dart';
import 'package:test/test.dart';

/// The shared manifest directory in a browser, where there is no process
/// environment, no operating system to ask, and no filesystem to publish into.
///
/// CXP discovery is a same-machine filesystem mechanism, so a browser cannot
/// take part, but it must learn that through the documented [StateError]
/// ("discovery unavailable", the same signal as a missing `$HOME`), never
/// through an `UnsupportedError` escaping from `dart:io`. A web build of a
/// program that links this package then still starts, and finds out why it
/// has no peers.
///
/// Runs only under `dart test -p chrome test/web`; the VM suite never loads
/// the stub, so this is the one place the web path is actually executed.
void main() {
  test('the manifest directory is unavailable, as a StateError', () {
    expect(sharedCxpManifestDirectory, throwsStateError);
  });

  test('with both inputs injected it resolves as on that platform', () {
    expect(
      sharedCxpManifestDirectory(
        environment: const {'HOME': '/Users/alice'},
        operatingSystem: 'macos',
      ),
      '/Users/alice/Library/Application Support/crux/cxp/peers',
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

  test('a probe cannot start in a browser, and says so as a StateError', () {
    expect(() => CxpProbe.start(name: 'web-tool'), throwsStateError);
  });
}
