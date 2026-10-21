// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:path/path.dart' as p;

/// FNV-1a 64-bit of [input]'s UTF-16 code units, as 16 lowercase hex digits.
///
/// Each code unit (0 to 0xFFFF) is XORed into the hash whole, as the suite's
/// first implementation did, so a string outside ASCII hashes differently
/// from FNV-1a over its UTF-8 bytes. That is deliberate and permanent:
/// signatures are stored in baselines and histories, and changing how they
/// are computed would make every stored one match nothing.
///
/// Computed as two unsigned 32-bit halves with 16-bit limbs rather than with
/// `BigInt` (about 34 times faster in a per-finding hot path) and exact under
/// dart2js, where an `int` is a 53-bit double: every partial product stays
/// below 2^32 and every running sum below 2^53.
String cruxFnv1a64(String input) {
  var hi = _offsetHi;
  var lo = _offsetLo;
  for (final unit in input.codeUnits) {
    // XOR the code unit into the low 16 bits, arithmetically, so dart2js
    // never runs a bitwise operation wider than 16 bits.
    final loLow = lo % 0x10000;
    lo = (lo - loLow) + (loLow ^ unit);

    // Multiply the 64-bit hash (hi:lo) by the prime, mod 2^64, in 16-bit
    // limbs.
    final a0 = lo % 0x10000;
    final a1 = lo ~/ 0x10000;
    final a2 = hi % 0x10000;
    final a3 = hi ~/ 0x10000;
    final p0 = a0 * _primeLimb0;
    final p1 = a0 * _primeLimb1 + a1 * _primeLimb0;
    final p2 = a0 * _primeLimb2 + a1 * _primeLimb1 + a2 * _primeLimb0;
    final p3 =
        a0 * _primeLimb3 +
        a1 * _primeLimb2 +
        a2 * _primeLimb1 +
        a3 * _primeLimb0;
    final r0 = p0 % 0x10000;
    final c1 = p1 + p0 ~/ 0x10000;
    final r1 = c1 % 0x10000;
    final c2 = p2 + c1 ~/ 0x10000;
    final r2 = c2 % 0x10000;
    final c3 = p3 + c2 ~/ 0x10000;
    // The carry out of bit 63 is dropped: arithmetic mod 2^64.
    final r3 = c3 % 0x10000;
    lo = r0 + r1 * 0x10000;
    hi = r2 + r3 * 0x10000;
  }
  return hi.toRadixString(16).padLeft(8, '0') +
      lo.toRadixString(16).padLeft(8, '0');
}

// The offset basis 0xcbf29ce484222325 as high and low 32-bit halves.
const int _offsetHi = 0xcbf29ce4;
const int _offsetLo = 0x84222325;

// The prime 0x100000001b3 as four 16-bit little-endian limbs; two are zero
// and kept so the multiply reads as the general schoolbook form.
const int _primeLimb0 = 0x01b3;
const int _primeLimb1 = 0x0000;
const int _primeLimb2 = 0x0100;
const int _primeLimb3 = 0x0000;

/// The suite's one identity for a finding across runs: the `crux-fnv1a64/1`
/// signature.
///
/// A signature is [cruxFnv1a64] over the finding's fields joined by `|`,
/// with the last field (the free text: a message, a property's source) put
/// through [normalizeText] so that reflowing it or trimming a trailing
/// newline does not change the signature. Line numbers are never a field: an
/// unrelated edit above a finding must not make it a new one.
///
/// The lint product's baselines are this scheme over
/// `<ruleId>|<project-relative file>|<message>`; formal property histories
/// use it over `<task>|<kind>|<file>|<property source>`. Two producers that
/// pass the same fields get the same signature, which is the point.
abstract final class CruxSignature {
  /// The scheme's name, written beside a stored signature so that a later
  /// scheme can be told apart from this one.
  static const String scheme = 'crux-fnv1a64/1';

  /// The signature of a finding identified by [fields] and described by
  /// [text]: [cruxFnv1a64] of `fields.join('|')`, a `|`, and [text]
  /// normalized.
  ///
  /// The fields are hashed as given, so a field that holds a path should be
  /// made checkout-independent first ([projectRelativePath]).
  static String compute(List<String> fields, String text) =>
      cruxFnv1a64('${fields.map((f) => '$f|').join()}${normalizeText(text)}');

  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// [text] with every run of white space (Unicode `\s`) collapsed to one
  /// space and the ends trimmed.
  static String normalizeText(String text) =>
      text.replaceAll(_whitespaceRun, ' ').trim();

  /// [filePath] relative to [projectRoot], `/`-separated, when the file lies
  /// inside the root; otherwise [filePath] unchanged (a source outside the
  /// project, or a synthetic location such as `<module:top>`).
  ///
  /// The path style follows [projectRoot] rather than the host, so a
  /// signature computed on Windows is computed identically on Linux. Pure
  /// text: nothing is resolved on disk.
  static String projectRelativePath(String filePath, String projectRoot) {
    if (projectRoot.isEmpty) return filePath;
    final context = _contextFor(projectRoot);
    if (!context.isWithin(projectRoot, filePath)) return filePath;
    return p.posix.joinAll(
      context.split(context.relative(filePath, from: projectRoot)),
    );
  }

  /// [text] with every `<projectRoot><separator>` prefix removed, so text
  /// that quotes a path in the project hashes the same in any checkout.
  static String projectRelativeMessage(String text, String projectRoot) {
    if (projectRoot.isEmpty) return text;
    final context = _contextFor(projectRoot);
    final root = context.normalize(projectRoot);
    var out = text.replaceAll('$root${context.separator}', '');
    if (context.style == p.Style.windows) {
      out = out.replaceAll('${root.replaceAll(r'\', '/')}/', '');
    }
    return out;
  }

  static final RegExp _windowsRoot = RegExp(r'^([A-Za-z]:[\\/]|\\\\)');

  static p.Context _contextFor(String projectRoot) {
    if (_windowsRoot.hasMatch(projectRoot)) return p.windows;
    if (projectRoot.startsWith('/')) return p.posix;
    return p.context;
  }
}
