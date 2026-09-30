// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';

/// A release the manifest advertises.
///
/// Both fields are nullable rather than defaulted so that each group can spell
/// out the axis it is testing — `channel` in the channel groups, `version` in
/// the pinned one — without the analyzer calling the explicit value redundant.
/// A test that names the value it is asserting on reads better than one that
/// relies on a helper's default.
UpdateInfo _info({String? version, String? channel}) =>
    UpdateInfo(version: version ?? '2.0.0', channel: channel ?? 'stable');

void main() {
  group('fromNames', () {
    test('maps the policy file vocabulary onto the enum', () {
      expect(
        UpdatePolicy.fromNames(channel: 'stable').channel,
        UpdateChannelPolicy.stable,
      );
      expect(
        UpdatePolicy.fromNames(channel: 'beta').channel,
        UpdateChannelPolicy.beta,
      );
      expect(
        UpdatePolicy.fromNames(channel: 'pinned').channel,
        UpdateChannelPolicy.pinned,
      );
    });

    test('an unrecognised channel is unconstrained, never a throw', () {
      expect(UpdatePolicy.fromNames(channel: 'nightly').channel, isNull);
      expect(UpdatePolicy.fromNames(channel: 'STABLE').channel, isNull);
      expect(UpdatePolicy.fromNames().channel, isNull);
    });

    test('round-trips DayOnePolicy enum names', () {
      // The binding a Pro overlay writes is `policy.updateChannel?.name`, so
      // every name `crux_policy` can produce must land somewhere here. Spelled
      // out rather than looped: a value this drops would otherwise silently
      // become "unconstrained" on a fleet that configured it.
      for (final name in ['stable', 'beta', 'pinned']) {
        expect(UpdatePolicy.fromNames(channel: name).channel, isNotNull);
      }
    });

    test('blank version and URL strings resolve to absent', () {
      final policy = UpdatePolicy.fromNames(
        pinnedVersion: '   ',
        manifestUrl: '  ',
      );
      expect(policy.pinnedVersion, isNull);
      expect(policy.manifestUri, isNull);
      expect(policy.isAbsent, isTrue);
    });

    test('trims a pinned version', () {
      expect(
        UpdatePolicy.fromNames(pinnedVersion: ' 1.4.0 ').pinnedVersion,
        '1.4.0',
      );
    });
  });

  group('mirror URL', () {
    test('accepts https and http', () {
      expect(
        UpdatePolicy.fromNames(
          manifestUrl: 'https://mirror.corp.test/n.json',
        ).manifestUri,
        Uri.parse('https://mirror.corp.test/n.json'),
      );
      // Plain http is honoured: an internal mirror on a closed network
      // commonly has no certificate.
      expect(
        UpdatePolicy.fromNames(
          manifestUrl: 'http://mirror.corp.test/n.json',
        ).manifestUri,
        Uri.parse('http://mirror.corp.test/n.json'),
      );
    });

    test('rejects file:, data: and relative URLs', () {
      for (final raw in [
        'file:///tmp/manifest.json',
        'data:application/json,{}',
        '/srv/manifest.json',
        'mirror.corp.test/n.json',
      ]) {
        expect(
          UpdatePolicy.fromNames(manifestUrl: raw).manifestUri,
          isNull,
          reason: raw,
        );
      }
    });
  });

  group('allows — no channel configured', () {
    test('offers everything', () {
      const policy = UpdatePolicy.absent;
      expect(policy.allows(_info(channel: 'beta')), isTrue);
      expect(policy.allows(_info(channel: 'nightly')), isTrue);
      expect(UpdatePolicy.absent.allows(_info()), isTrue);
    });

    test('a pinned version alone does nothing', () {
      // An administrator who wrote pinnedVersion while trialling the key has
      // not thereby pinned the fleet; `updateChannel: pinned` declares that.
      const policy = UpdatePolicy(pinnedVersion: '1.0.0');
      expect(policy.allows(_info(version: '9.9.9')), isTrue);
    });
  });

  group('allows — stable', () {
    const policy = UpdatePolicy(channel: UpdateChannelPolicy.stable);

    test('offers stable', () {
      expect(policy.allows(_info(channel: 'stable')), isTrue);
    });

    test('withholds beta and anything else', () {
      expect(policy.allows(_info(channel: 'beta')), isFalse);
      expect(policy.allows(_info(channel: 'nightly')), isFalse);
      expect(policy.allows(_info(channel: '')), isFalse);
    });

    test('an unlabelled manifest release is stable, so it is offered', () {
      // UpdateInfo.fromJson defaults `channel` to 'stable', so a manifest that
      // says nothing about channels behaves for a stable fleet exactly as it
      // does for an unconstrained one.
      final parsed = UpdateInfo.fromJson({'version': '2.0.0'})!;
      expect(parsed.channel, 'stable');
      expect(policy.allows(parsed), isTrue);
    });

    test('matches case-insensitively and ignores surrounding space', () {
      expect(policy.allows(_info(channel: ' Stable ')), isTrue);
    });
  });

  group('allows — beta', () {
    const policy = UpdatePolicy(channel: UpdateChannelPolicy.beta);

    test('widens by exactly one channel', () {
      expect(policy.allows(_info(channel: 'beta')), isTrue);
      expect(policy.allows(_info(channel: 'stable')), isTrue);
    });

    test('opting into betas is not opting into every future channel', () {
      expect(policy.allows(_info(channel: 'alpha')), isFalse);
      expect(policy.allows(_info(channel: 'nightly')), isFalse);
    });
  });

  group('allows — pinned', () {
    const policy = UpdatePolicy(
      channel: UpdateChannelPolicy.pinned,
      pinnedVersion: '1.4.0',
    );

    test('withholds anything newer than the pin', () {
      expect(policy.allows(_info(version: '1.4.1')), isFalse);
      expect(policy.allows(_info(version: '2.0.0')), isFalse);
    });

    test('is a ceiling, not an equality test', () {
      // The deployment this serves: an on-prem mirror advertising 1.4.0 to a
      // fleet pinned at 1.4.0, where a seat still on 1.2.0 must be told.
      expect(policy.allows(_info(version: '1.4.0')), isTrue);
      expect(policy.allows(_info(version: '1.3.9')), isTrue);
    });

    test('ignores the release channel entirely', () {
      // The pin names a version. A fleet pinned to a beta build is a fleet
      // pinned to that build.
      expect(policy.allows(_info(version: '1.4.0', channel: 'beta')), isTrue);
    });

    test('withholds when no version was pinned', () {
      const orphan = UpdatePolicy(channel: UpdateChannelPolicy.pinned);
      expect(orphan.allows(_info(version: '0.0.1')), isFalse);
    });

    test('withholds when either version is unparseable', () {
      const badPin = UpdatePolicy(
        channel: UpdateChannelPolicy.pinned,
        pinnedVersion: 'latest',
      );
      expect(badPin.allows(_info(version: '1.0.0')), isFalse);
      expect(policy.allows(_info(version: 'nightly-build')), isFalse);
    });
  });

  group('value semantics', () {
    test('isAbsent is true only with nothing set', () {
      expect(UpdatePolicy.absent.isAbsent, isTrue);
      expect(
        const UpdatePolicy(channel: UpdateChannelPolicy.stable).isAbsent,
        isFalse,
      );
      expect(const UpdatePolicy(pinnedVersion: '1.0.0').isAbsent, isFalse);
      expect(
        UpdatePolicy(manifestUri: Uri.parse('https://a.test/m')).isAbsent,
        isFalse,
      );
    });

    test('equality and hashCode cover every field', () {
      const a = UpdatePolicy(
        channel: UpdateChannelPolicy.pinned,
        pinnedVersion: '1.4.0',
      );
      const b = UpdatePolicy(
        channel: UpdateChannelPolicy.pinned,
        pinnedVersion: '1.4.0',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          const UpdatePolicy(
            channel: UpdateChannelPolicy.pinned,
            pinnedVersion: '1.5.0',
          ),
        ),
      );
      expect(
        UpdatePolicy(manifestUri: Uri.parse('https://a.test/m')),
        isNot(UpdatePolicy(manifestUri: Uri.parse('https://b.test/m'))),
      );
    });

    test('toString names the channel and the pin', () {
      expect(
        const UpdatePolicy(
          channel: UpdateChannelPolicy.pinned,
          pinnedVersion: '1.4.0',
        ).toString(),
        contains('pinned'),
      );
    });
  });
}
