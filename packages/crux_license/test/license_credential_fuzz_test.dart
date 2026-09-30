// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/license_fixtures.dart';

/// [parseLicenseCredential] promises totality in its own doc comment:
///
/// > Callers paste arbitrary text into this — a truncated key, a whole email,
/// > a PDF's worth of bytes — and the UI needs a sentence back, not a crash.
///
/// It is a promise the call sites rely on and none of them re-checks:
/// `CruxLicenseValidator.validate`, and `_issuerKeyFor` in
/// `license_controller.dart`. So this file makes the promise a property rather
/// than a comment.
///
/// ## The defect that motivated it
///
/// `-----BEGIN LICENSE FILE-----END LICENSE FILE-----` — 49 characters, the
/// shape you get by pasting a licence file whose body did not survive the
/// clipboard — threw `RangeError (end): Not in inclusive range 28..49: 23`.
/// Both markers end in five dashes, so `indexOf(_fileEnd)` searching from 0
/// matched five characters INSIDE the BEGIN marker and handed `substring` an
/// end before its start.
///
/// What made that expensive rather than merely wrong is the *class*:
/// `RangeError` is an `Error`, not an `Exception`, so it walked straight
/// through every `on Exception` between the parser and the activation UI and
/// surfaced as an unhandled async error. A crash-proof function that throws an
/// `Error` is worse than one that throws an `Exception`, because the ordinary
/// defences do not see it.
///
/// ## Why this shape of test
///
/// The bug was not in a branch anyone forgot to write; it was in the
/// *arithmetic between* two branches that were both present and both correct
/// in isolation. Example-based tests pick inputs a human imagined. The input
/// that broke this is one nobody would think to type — which is exactly the
/// argument for enumerating prefixes and generating marker-heavy soup instead.
/// The generator below draws from a token pool made of the markers' own
/// fragments, because self-overlapping delimiters are where this class lives.
void main() {
  late String validKey;
  late String validFile;
  late String validMachineFile;
  late String encryptedFile;

  setUpAll(() async {
    final keys = await TestIssuerKeys.fromSeed(7);
    validKey = await keys.mintKey(keyPayload());
    validFile = await keys.mintFile(filePayload());
    validMachineFile = await keys.mintMachineFile(machineFilePayload());
    encryptedFile = await keys.mintEncryptedFile(filePayload());
  });

  group('the regression', () {
    test('a licence file with its body deleted is answered, not thrown', () {
      // The exact 49-character paste. Kept as a literal, with its length
      // asserted, so a future edit to the markers cannot silently retire it.
      const paste = '-----BEGIN LICENSE FILE-----END LICENSE FILE-----';
      expect(paste.length, 49);

      final parse = _mustNotThrow('the 49-character paste', paste);
      expect(
        parse.envelope,
        isNull,
        reason: 'a body-less file is not a credential',
      );
      expect(parse.rejection, LicenseRejection.malformed);
    });

    test('the same paste through the validator resolves to a rejection', () {
      // The parser is where the fix lives, but the call site is where the bug
      // was felt: `validate` has no try at all, because the parser is total.
      const paste = '-----BEGIN LICENSE FILE-----END LICENSE FILE-----';
      expect(
        () => CruxLicenseValidator(
          product: CruxProduct.waveCrux,
          issuers: const <LicenseIssuer>[],
        ).validate(paste),
        returnsNormally,
      );
    });

    test(
      'a phantom END inside BEGIN does not hide the real END after it',
      () {
        // This is the case that separates the fix that shipped from the
        // obvious one. Bounds-checking the result of `indexOf(_fileEnd)` —
        // "if the match landed before the body, call it malformed" — also
        // stops the crash, but it MISREPORTS this input: the phantom match at
        // index 23 is before the body, so the whole file is declared to have
        // no END marker even though it plainly has one. Searching from the
        // body start instead finds the marker that is really there, and the
        // input fails later, on its contents, which is the truthful answer.
        //
        // A body opening with `END LICENSE FILE-----` fuses the two markers at
        // index 23 and is still base64-shaped (whitespace is stripped and `-`
        // maps to `+`), so it reaches the decoder rather than being refused
        // for its alphabet.
        final body = validFile
            .replaceAll(_begin, '')
            .replaceAll(_end, '')
            .trim();
        final parse = _mustNotThrow(
          'phantom-END file',
          '${_begin}END LICENSE FILE-----$body\n$_end',
        );
        expect(
          parse.rejection,
          isNot(LicenseRejection.malformed),
          reason:
              'the real END marker was found, so the failure must come from '
              'the body, not from a missing marker',
        );
      },
    );

    test('a licence file with a real body still parses', () {
      // The counterweight to the test above: proof that reading the body from
      // the end of the BEGIN marker did not move the window off the payload.
      final body = validFile.replaceAll(_begin, '').replaceAll(_end, '').trim();
      final parse = _mustNotThrow('rebuilt file', '$_begin\n$body\n$_end');
      expect(parse.envelope?.kind, LicenseCredentialKind.licenseFile);
    });
  });

  group('totality', () {
    test('every hand-picked degenerate input is answered', () {
      for (final entry in _handPicked.entries) {
        _mustNotThrow(entry.key, entry.value);
      }
    });

    test('every prefix of a valid licence key is answered', () {
      _everyPrefix('licence key', validKey);
    });

    test('every prefix of a valid licence file is answered', () {
      _everyPrefix('licence file', validFile);
    });

    test('every prefix of a valid machine file is answered', () {
      _everyPrefix('machine file', validMachineFile);
    });

    test('every prefix of an encrypted licence file is answered', () {
      _everyPrefix('encrypted licence file', encryptedFile);
    });

    test('every suffix of a valid licence file is answered', () {
      // Prefixes model a truncated paste; suffixes model one that lost its
      // head — a scroll-and-copy that started below the BEGIN marker.
      for (var i = 0; i <= validFile.length; i++) {
        _mustNotThrow('licence file suffix $i', validFile.substring(i));
      }
    });

    test('every single-character deletion from a credential is answered', () {
      for (final source in <String>[validKey, validFile, validMachineFile]) {
        for (var i = 0; i < source.length; i++) {
          _mustNotThrow(
            'deletion at $i',
            source.substring(0, i) + source.substring(i + 1),
          );
        }
      }
    });

    test('marker-heavy generated soup is answered', () {
      final random = Random(20260920);
      for (var i = 0; i < 4000; i++) {
        _mustNotThrow('soup #$i (seed 20260920)', _soup(random));
      }
    });

    test('binary and non-text bytes are answered', () {
      for (final entry in _binary().entries) {
        _mustNotThrow(entry.key, entry.value);
      }
    });

    test('a megabyte of text is answered', () {
      for (final entry in _huge().entries) {
        _mustNotThrow(entry.key, entry.value);
      }
    });
  });

  group('the fuzz is not vacuous', () {
    test('a valid credential of each kind still parses', () {
      expect(
        parseLicenseCredential(validKey).envelope?.kind,
        LicenseCredentialKind.licenseKey,
      );
      expect(
        parseLicenseCredential(validFile).envelope?.kind,
        LicenseCredentialKind.licenseFile,
      );
      expect(
        parseLicenseCredential(validMachineFile).envelope?.kind,
        LicenseCredentialKind.machineFile,
      );
      expect(
        parseLicenseCredential(encryptedFile).rejection,
        LicenseRejection.unsupportedAlgorithm,
        reason: 'an encrypted file is refused by alg, not by a parse failure',
      );
    });

    test('the generator can produce both markers and a plausible body', () {
      // If the token pool ever stopped emitting the markers, the soup test
      // above would pass on 4000 strings that never enter the file parser at
      // all — green, and blind to the exact code path the bug lived on.
      final random = Random(20260920);
      var sawBegin = 0;
      var sawBoth = 0;
      for (var i = 0; i < 4000; i++) {
        final text = _soup(random).trim();
        if (!text.startsWith('-----BEGIN LICENSE FILE-----')) continue;
        sawBegin++;
        if (text.contains('-----END LICENSE FILE-----')) sawBoth++;
      }
      expect(
        sawBegin,
        greaterThan(50),
        reason: 'the soup rarely reaches the licence-file parser',
      );
      expect(
        sawBoth,
        greaterThan(10),
        reason: 'the soup rarely reaches the substring that threw',
      );
    });

    test('the prefix walk covers the interesting lengths', () {
      expect(
        validFile.length,
        greaterThan(200),
        reason: 'the file fixture shrank; the prefix walk is now trivial',
      );
    });
  });
}

/// Call the parser, fail loudly on ANY throw — `Error` as well as `Exception`,
/// which is the whole point — and assert the result's own invariant.
LicenseEnvelopeParse _mustNotThrow(String label, String input) {
  final LicenseEnvelopeParse parse;
  try {
    parse = parseLicenseCredential(input);
  } on Object catch (error, stack) {
    fail(
      'parseLicenseCredential threw ${error.runtimeType} on $label '
      '(${input.length} chars): $error\n'
      'input preview: ${_preview(input)}\n$stack',
    );
  }
  expect(
    (parse.envelope == null) != (parse.rejection == null),
    isTrue,
    reason:
        'on $label the parse reported neither an envelope nor a rejection, '
        'or both — callers switch on exactly one being present',
  );
  return parse;
}

void _everyPrefix(String label, String source) {
  for (var i = 0; i <= source.length; i++) {
    _mustNotThrow('$label prefix of length $i', source.substring(0, i));
  }
}

String _preview(String input) {
  final flat = input.replaceAll('\n', r'\n');
  return flat.length <= 120 ? flat : '${flat.substring(0, 120)}…';
}

/// The markers as the wire format spells them, copied rather than imported:
/// `_fileBegin` and `_fileEnd` are library-private, and a test that reuses the
/// implementation's own constants cannot notice the implementation changing
/// them. Assembling the inputs by interpolation keeps them one edit wide
/// without gluing two adjacent literals together, which reads as a typo.
const String _begin = '-----BEGIN LICENSE FILE-----';
const String _end = '-----END LICENSE FILE-----';

/// Inputs a person could actually produce, and the shapes that break
/// delimiter arithmetic. Named, because a failure here should say which one.
const Map<String, String> _handPicked = <String, String>{
  'empty': '',
  'whitespace only': '   \n\t  \r\n ',
  'BEGIN marker alone': _begin,
  'BEGIN marker minus its last dash': '-----BEGIN LICENSE FILE----',
  'END marker alone': _end,
  'both markers, nothing between': '$_begin$_end',
  'body deleted, markers fused': '${_begin}END LICENSE FILE-----',
  'markers reversed': '$_end$_begin',
  'END before BEGIN with a body': '$_end\nQUJD\n$_begin',
  'nested BEGIN markers': '$_begin${_begin}QUJD$_end',
  'nested END markers': '${_begin}QUJD$_end$_end',
  'empty body, newline separated': '$_begin\n\n$_end',
  'body is the END marker text': '${_begin}END LICENSE FILE-----\n$_end',
  'dashes only': '----------------------------------------',
  'one dash short of BEGIN then END': '----BEGIN LICENSE FILE-----$_end',
  'BEGIN marker with trailing whitespace only': '$_begin   \n\t\n   ',
  'key prefix alone': 'key/',
  'key prefix then a dot': 'key/.',
  'key prefix then a dot and nothing': 'key/abc.',
  'key with a leading dot': 'key/.abc',
  'key with only dots': 'key/....',
  'key prefix, no dot': 'key/QUJDREVG',
  'key prefix, dot at the very end': 'key/QUJDREVG.',
  'bare dot': '.',
  'a whole email':
      'Hi Martin,\n\nHere is the licence you asked for:\n\n'
      'key/QUJD.REVG\n\nThanks,\nAccounts\n',
  'an unrelated PEM block':
      '-----BEGIN CERTIFICATE-----\nQUJD\n-----END CERTIFICATE-----',
  'json': '{"key": "key/QUJD.REVG"}',
  'a single null byte': '\u0000',
  'unpaired high surrogate': '\uD800',
  'unpaired low surrogate': '\uDC00',
  'BEGIN marker then an unpaired surrogate': '$_begin\uD800$_end',
  'base64 that is one character past a group':
      'key/QUJDR.QUJDREVGQUJDREVGQUJDREVGQUJDREVGQUJDREVGQUJDREVGQUJDREVG',
};

Map<String, String> _binary() {
  final latin1Soup = String.fromCharCodes(List<int>.generate(256, (i) => i));
  final surrogates = String.fromCharCodes(
    List<int>.generate(64, (i) => 0xD800 + i),
  );
  return <String, String>{
    'every byte 0..255': latin1Soup,
    'every byte, inside a licence file': '$_begin$latin1Soup$_end',
    'lone surrogates': surrogates,
    'lone surrogates inside a licence file': '$_begin$surrogates$_end',
    'lone surrogates after a key prefix': 'key/$surrogates.$surrogates',
    'invalid UTF-8 as base64':
        'key/gICAgIA.'
        'QUJDREVGQUJDREVGQUJDREVGQUJDREVGQUJDREVGQUJDREVGQUJDREVGQUJDREVG',
  };
}

Map<String, String> _huge() {
  const megabyte = 1024 * 1024;
  final dashes = '-' * megabyte;
  return <String, String>{
    'a megabyte of dashes': dashes,
    'a megabyte of dashes in a licence file': '$_begin$dashes$_end',
    'a megabyte of base64 after a key prefix': 'key/${'Q' * megabyte}.QUJD',
    'a megabyte of repeated BEGIN markers': _begin * 32768,
    'a megabyte of repeated END markers': '$_begin${_end * 32768}',
    'a megabyte of newlines in a licence file':
        '$_begin${'\n' * megabyte}$_end',
  };
}

/// Tokens chosen so that the markers, and near-misses of the markers, assemble
/// by chance. A uniform random string would essentially never contain
/// `-----BEGIN LICENSE FILE-----`, so it would never exercise the file parser
/// — the fuzz would be 4000 rejections at the prefix check.
const List<String> _tokens = <String>[
  _begin,
  _end,
  'BEGIN LICENSE FILE',
  'END LICENSE FILE',
  '-----',
  '----',
  '-',
  'key/',
  '.',
  '\n',
  ' ',
  '\t',
  'QUJDREVG',
  'Q',
  '=',
  '_',
  '+',
  '/',
  '{"alg":"base64+ed25519"}',
  '\u0000',
];

String _soup(Random random) {
  // Weighted so a run often OPENS with the BEGIN marker: the parser dispatches
  // on `startsWith`, so a marker buried mid-string never reaches the file
  // branch at all.
  final buffer = StringBuffer();
  if (random.nextInt(3) != 0) buffer.write(_tokens[random.nextInt(2)]);
  final length = random.nextInt(24);
  for (var i = 0; i < length; i++) {
    buffer.write(_tokens[random.nextInt(_tokens.length)]);
  }
  return buffer.toString();
}
