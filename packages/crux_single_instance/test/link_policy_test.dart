// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_single_instance/crux_single_instance.dart';
import 'package:test/test.dart';

void main() {
  final policy = SingleInstanceLinkPolicy(
    schemes: const ['viewer', 'viewer-dev'],
    maxLinkBytes: 64,
  );

  test('accepts one URL of a declared scheme', () {
    expect(policy.check('viewer://open?file=/a/b.txt&t=1'), isNull);
    expect(policy.check('viewer-dev:x'), isNull);
    expect(policy.accepts('VIEWER://open'), isTrue);
  });

  // Characters a link may not carry, written as code points so none of them
  // is invisible or reorders this file's text.
  const forbidden = <int>[
    0x20, // space
    0x0A, // line feed
    0x09, // tab
    0x00, // NUL
    0x7F, // delete
    0x85, // next line
    0xA0, // no-break space
    0x2028, // line separator
    0x202E, // right-to-left override
    0x3000, // ideographic space
    0xFEFF, // byte-order mark
  ];
  for (final code in forbidden) {
    test('refuses U+${code.toRadixString(16).padLeft(4, '0')}', () {
      final link = 'viewer://a${String.fromCharCode(code)}b';
      expect(
        policy.check(link),
        SingleInstanceLinkRejection.forbiddenCharacter,
      );
      expect(policy.accepts(link), isFalse);
    });
  }

  test('refuses two links in one', () {
    expect(
      policy.check('viewer://a viewer://b'),
      SingleInstanceLinkRejection.forbiddenCharacter,
    );
  });

  final refused = <String, SingleInstanceLinkRejection>{
    '': SingleInstanceLinkRejection.badLength,
    'viewer://${'a' * 60}': SingleInstanceLinkRejection.badLength,
    // 31 two-byte characters: under the bound in UTF-16, over it in UTF-8.
    'viewer://${'é' * 31}': SingleInstanceLinkRejection.badLength,
    'viewer': SingleInstanceLinkRejection.notAUrl,
    ':viewer': SingleInstanceLinkRejection.notAUrl,
    'viewer://[::1': SingleInstanceLinkRejection.notAUrl,
    'https://example.com/': SingleInstanceLinkRejection.schemeNotDeclared,
    'viewers://open': SingleInstanceLinkRejection.schemeNotDeclared,
    'file:///etc/passwd': SingleInstanceLinkRejection.schemeNotDeclared,
  };
  var index = 0;
  for (final MapEntry(key: link, value: why) in refused.entries) {
    test('refuses case ${index++}: ${why.name}', () {
      expect(policy.check(link), why, reason: link);
      expect(policy.accepts(link), isFalse);
    });
  }

  test('the bound is in UTF-8 bytes', () {
    final exact = SingleInstanceLinkPolicy(
      schemes: const ['viewer'],
      maxLinkBytes: 'viewer://é'.length + 1,
    );
    expect(exact.check('viewer://é'), isNull);
  });

  group('construction', () {
    test('needs a scheme', () {
      expect(
        () => SingleInstanceLinkPolicy(schemes: const []),
        throwsArgumentError,
      );
    });

    for (final bad in ['Viewer', 'view er', '1viewer', 'viewer:', '']) {
      test('refuses the scheme "$bad"', () {
        expect(
          () => SingleInstanceLinkPolicy(schemes: [bad]),
          throwsArgumentError,
        );
      });
    }

    test('needs a positive bound', () {
      expect(
        () => SingleInstanceLinkPolicy(
          schemes: const ['viewer'],
          maxLinkBytes: 0,
        ),
        throwsArgumentError,
      );
    });

    test('keeps an unmodifiable copy of the schemes', () {
      final schemes = ['viewer'];
      final copy = SingleInstanceLinkPolicy(schemes: schemes);
      schemes.add('other');
      expect(copy.schemes, {'viewer'});
      expect(() => copy.schemes.add('x'), throwsUnsupportedError);
    });
  });
}
