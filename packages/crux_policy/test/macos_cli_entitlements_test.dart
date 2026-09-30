// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Guards the entitlements the macOS `crux-policy` executable is signed with.
///
/// The binary is Dart AOT, and the Hardened Runtime that notarization
/// requires KILLS a Dart AOT executable at launch (SIGKILL, exit 137) unless
/// it carries `com.apple.security.cs.allow-unsigned-executable-memory`: the
/// runtime maps its AOT snapshot into executable memory no code signature
/// covers. `allow-jit` does not substitute for it. Nothing about the failure
/// is visible before launch — the signature verifies and notarization
/// accepts it — so the key looks removable to anyone tidying the file. This
/// pins the complete set, and pins the release workflow to signing with the
/// file and running the binary after signing.
void main() {
  final packageRoot = Directory.current.path;
  final entitlements = File(
    p.join(packageRoot, 'tool', 'macos_cli.entitlements'),
  );
  final workflow = File(
    p.join(
      packageRoot,
      '..',
      '..',
      '.github',
      'workflows',
      'release-crux-policy.yml',
    ),
  );

  test('the CLI entitlements are exactly the pinned set', () {
    final plist = entitlements.readAsStringSync();
    final keys = RegExp(r'<key>([^<]+)</key>\s*(<[^>]+>)')
        .allMatches(plist)
        .map((m) => '${m.group(1)}=${m.group(2)!.replaceAll(' ', '')}')
        .toList();
    expect(
      keys,
      ['com.apple.security.cs.allow-unsigned-executable-memory=<true/>'],
      reason:
          'The Hardened Runtime SIGKILLs a Dart AOT executable at launch '
          'without allow-unsigned-executable-memory, and allow-jit is no '
          'substitute. Any other key widens the runtime for no measured '
          'reason.',
    );
    expect(
      RegExp('<key>').allMatches(plist).length,
      1,
      reason: 'A key is declared twice, or a value is not a boolean.',
    );
  });

  test('the release workflow signs with the file and runs the result', () {
    final text = workflow.readAsStringSync();
    expect(
      text,
      contains(
        '--entitlements packages/crux_policy/tool/macos_cli.entitlements',
      ),
      reason:
          'The macOS signing step must pass the CLI entitlements file to '
          'codesign, or the published binary dies at launch.',
    );
    final signAt = text.indexOf('--entitlements packages/crux_policy/tool');
    final runAt = text.indexOf(r'"$bin" --version', signAt);
    expect(
      runAt,
      greaterThan(signAt),
      reason:
          'The signed binary must be run after codesign. The smoke test '
          'before signing cannot see a launch-time kill.',
    );
  });
}
