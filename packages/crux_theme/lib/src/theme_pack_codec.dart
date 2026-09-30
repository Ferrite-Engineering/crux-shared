// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_theme/src/theme_pack.dart';
import 'package:flutter/material.dart' show Brightness, Color;

/// JSON-document codec for `.crux-theme.json` theme packs.
///
/// The codec is strict on input and lenient on output. Encoding always
/// emits the `#RRGGBBAA` form when alpha < 255 and the `#RRGGBB` form
/// when alpha is opaque, with category and token ids preserved in their
/// original order. Decoding rejects malformed structure (missing
/// required fields, unknown `schemaVersion`, invalid color strings,
/// invalid brightness) with [FormatException].
///
/// ## Version-gating policy (deliberate)
///
/// The `schemaVersion` field is the package's evolution lever: today it
/// must be `1`. This codec's policy is **strict refusal**: a document
/// whose `schemaVersion` is missing or not exactly
/// [currentSchemaVersion] throws [FormatException], the same class the
/// codec throws for every other schema violation.
///
/// The policy is chosen for this format specifically, and the reason
/// is that a theme pack is a *user-authored, shared artifact* rather
/// than app-managed state. Loading a `schemaVersion: 2` pack on a
/// `schemaVersion: 1` client by ignoring the fields it doesn't know
/// would render the author's theme wrongly and silently, and the user
/// has no way to tell. Refusing lets the UI say "this pack needs a
/// newer version", which is actionable. Loudness is affordable here
/// because every call path already funnels through
/// `ThemePackService.validate`, which converts the throw into an
/// inline error list rather than a crash.
///
/// Other crux-shared codecs make different choices for state they own
/// (`ProjectWorkspace` returns `null` and rebuilds; `Workspace` throws
/// a typed exception). Those are app-managed documents where silently
/// starting fresh is recoverable and a shared artifact's is not — but
/// the divergence should be reconciled deliberately rather than left
/// as four accidents.
class ThemePackCodec {
  /// Creates a codec instance. The codec carries no per-instance state
  /// today; the singleton-flavored API is kept for forward
  /// compatibility (e.g. when a future revision needs configurable
  /// behavior).
  const ThemePackCodec();

  /// Current schema version this codec writes and accepts on decode.
  static const int currentSchemaVersion = 1;

  /// Encodes [pack] to a pretty-printed JSON string.
  String encode(ThemePack pack) {
    return const JsonEncoder.withIndent('  ').convert(toJson(pack));
  }

  /// Decodes a `.crux-theme.json` document to a [ThemePack].
  ///
  /// Throws [FormatException] if the source is not valid JSON or does
  /// not conform to the schema. The optional [sourceUri] is attached to
  /// the returned pack for traceability; it does not affect decoding.
  ThemePack decode(String source, {Uri? sourceUri}) {
    final Object? raw;
    try {
      raw = json.decode(source);
    } on FormatException catch (e) {
      throw FormatException('Theme pack is not valid JSON: ${e.message}');
    }
    if (raw is! Map<String, Object?>) {
      throw const FormatException(
        'Theme pack must be a JSON object at the top level.',
      );
    }
    return fromJson(raw, sourceUri: sourceUri);
  }

  /// Serializes [pack] to the JSON-friendly map representation. Useful
  /// when callers want to embed the pack in a larger document rather
  /// than write a standalone file.
  Map<String, Object?> toJson(ThemePack pack) {
    final tokensMap = <String, Map<String, String>>{};
    for (final entry in pack.tokens.entries) {
      tokensMap[entry.key] = {
        for (final tokenEntry in entry.value.entries)
          tokenEntry.key: encodeColor(tokenEntry.value),
      };
    }
    return <String, Object?>{
      'schemaVersion': currentSchemaVersion,
      'id': pack.id,
      'displayName': pack.displayName,
      'brightness': pack.brightness == Brightness.light ? 'light' : 'dark',
      'tokens': tokensMap,
    };
  }

  /// Deserializes a pre-parsed JSON map to a [ThemePack].
  ///
  /// Throws [FormatException] for any schema violation. The optional
  /// [sourceUri] is attached to the returned pack.
  ///
  /// ### Version policy
  ///
  /// Strict refusal, and this is now the suite-wide rule for its half of the
  /// line: a theme pack is a **user-authored, shareable artifact**, so
  /// tolerating an unrecognized `schemaVersion` would render someone else's
  /// theme wrongly with no signal to either party. `KeymapCodec` was
  /// reconciled onto the same policy — it wrote `version` and never read it,
  /// which is the silent-misparse failure this refusal exists to prevent.
  ///
  /// The other half of the policy is the app-managed side: `Workspace` and
  /// `ProjectWorkspace` are files the app wrote for itself and the user cannot
  /// hand-repair, so those degrade to an empty document (after quarantining
  /// the bytes) rather than refusing, because a hard failure there bricks
  /// launch. Refusal is correct precisely when a human can act on it.
  ThemePack fromJson(Map<String, Object?> json, {Uri? sourceUri}) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int) {
      throw const FormatException(
        'Theme pack is missing required field "schemaVersion".',
      );
    }
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Theme pack uses unsupported schemaVersion '
        '($schemaVersion; expected $currentSchemaVersion).',
      );
    }

    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException(
        'Theme pack is missing required non-empty string field "id".',
      );
    }
    if (!isValidPackId(id)) {
      throw FormatException(
        'Theme pack id "$id" is not a valid pack id. The id becomes a '
        'filename inside the user themes directory, so it may not contain '
        'a path separator, a ".." segment, a drive prefix, a leading "." '
        'or "~", or any control character.',
      );
    }

    final displayName = json['displayName'];
    if (displayName is! String || displayName.isEmpty) {
      throw const FormatException(
        'Theme pack is missing required non-empty string '
        'field "displayName".',
      );
    }

    final brightnessStr = json['brightness'];
    final Brightness brightness;
    switch (brightnessStr) {
      case 'light':
        brightness = Brightness.light;
      case 'dark':
        brightness = Brightness.dark;
      default:
        throw FormatException(
          'Theme pack has invalid brightness '
          '(${brightnessStr ?? 'null'}; expected "light" or "dark").',
        );
    }

    final tokensRaw = json['tokens'];
    if (tokensRaw is! Map<String, Object?>) {
      throw const FormatException(
        'Theme pack is missing required field "tokens" '
        '(must be a JSON object).',
      );
    }

    final tokens = <String, Map<String, Color>>{};
    tokensRaw.forEach((categoryId, value) {
      if (value is! Map<String, Object?>) {
        throw FormatException(
          'Theme pack category "$categoryId" must be a JSON object.',
        );
      }
      final bucket = <String, Color>{};
      value.forEach((tokenId, colorRaw) {
        if (colorRaw is! String) {
          throw FormatException(
            'Theme pack token "$categoryId.$tokenId" must be a hex '
            'color string.',
          );
        }
        final color = tryParseColor(colorRaw);
        if (color == null) {
          throw FormatException(
            'Theme pack token "$categoryId.$tokenId" has invalid color '
            '"$colorRaw" (expected "#RRGGBB" or "#RRGGBBAA").',
          );
        }
        bucket[tokenId] = color;
      });
      tokens[categoryId] = bucket;
    });

    return ThemePack(
      id: id,
      displayName: displayName,
      brightness: brightness,
      tokens: tokens,
      sourceUri: sourceUri,
    );
  }

  /// Returns true when [id] is safe to use as a theme pack id.
  ///
  /// A pack id is not free-form text: `ThemePackService` interpolates
  /// it directly into a filename inside the user's themes directory
  /// (`<id>.crux-theme.json`) and joins that against the directory
  /// path. Theme packs are a **shareable, user-installed format** — a
  /// `.crux-theme.json` arrives by download, chat attachment or repo
  /// checkout — so an id is attacker-controlled input on a path.
  /// Without this check, `"id": "../../../../Library/LaunchAgents/com.evil"`
  /// makes `install()` write a file outside the themes directory.
  ///
  /// Validation is a conservative allow-shaped deny-list applied at
  /// **decode** time, which is the single choke point every read path
  /// (`decode`, `load`, `list`, `install`, `validate`) already funnels
  /// through — so no caller can forget it:
  ///
  /// * no POSIX (`/`) or Windows (`\`) path separator;
  /// * no `..` anywhere (covers `..`, `a..b`, and the `....//` style
  ///   normalization bypasses);
  /// * no drive prefix (`C:`) or alternate data stream (`:`);
  /// * no leading `.` (hidden files, and `.` / `..` themselves) or
  ///   leading `~` (shell home expansion in paths the UI displays);
  /// * no NUL or other control characters (C-string truncation);
  /// * no leading/trailing whitespace, which round-trips invisibly and
  ///   is stripped by some filesystems.
  static bool isValidPackId(String id) {
    if (id.isEmpty) return false;
    if (id.trim() != id) return false;
    if (id.contains('/') || id.contains(r'\')) return false;
    if (id.contains('..')) return false;
    if (id.contains(':')) return false;
    if (id.startsWith('.') || id.startsWith('~')) return false;
    for (var i = 0; i < id.length; i++) {
      final unit = id.codeUnitAt(i);
      if (unit < 0x20 || unit == 0x7F) return false;
    }
    return true;
  }

  /// Decodes only the identity fields of a pack document, skipping the
  /// token table entirely.
  ///
  /// This is what a pack *list* needs: `ThemePackService.list` renders
  /// id / display name / brightness rows and has always documented
  /// itself as reading headers "without loading the full token table",
  /// while in fact decoding and allocating every color. Applies the
  /// same schema-version and id validation as [fromJson].
  ThemePackHeader decodeHeader(String source, {Uri? sourceUri}) {
    final Object? raw;
    try {
      raw = json.decode(source);
    } on FormatException catch (e) {
      throw FormatException('Theme pack is not valid JSON: ${e.message}');
    }
    if (raw is! Map<String, Object?>) {
      throw const FormatException(
        'Theme pack must be a JSON object at the top level.',
      );
    }

    final schemaVersion = raw['schemaVersion'];
    if (schemaVersion is! int) {
      throw const FormatException(
        'Theme pack is missing required field "schemaVersion".',
      );
    }
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Theme pack uses unsupported schemaVersion '
        '($schemaVersion; expected $currentSchemaVersion).',
      );
    }

    final id = raw['id'];
    if (id is! String || id.isEmpty || !isValidPackId(id)) {
      throw const FormatException(
        'Theme pack is missing a valid non-empty string field "id".',
      );
    }
    final displayName = raw['displayName'];
    if (displayName is! String || displayName.isEmpty) {
      throw const FormatException(
        'Theme pack is missing required non-empty string '
        'field "displayName".',
      );
    }
    final brightnessStr = raw['brightness'];
    final Brightness brightness;
    switch (brightnessStr) {
      case 'light':
        brightness = Brightness.light;
      case 'dark':
        brightness = Brightness.dark;
      default:
        throw FormatException(
          'Theme pack has invalid brightness '
          '(${brightnessStr ?? 'null'}; expected "light" or "dark").',
        );
    }
    if (raw['tokens'] is! Map<String, Object?>) {
      throw const FormatException(
        'Theme pack is missing required field "tokens" '
        '(must be a JSON object).',
      );
    }

    return ThemePackHeader(
      id: id,
      displayName: displayName,
      brightness: brightness,
      sourceUri: sourceUri,
    );
  }

  /// Encodes a [Color] as a `#RRGGBB` (alpha = 255) or `#RRGGBBAA`
  /// hex string. The output is always uppercase. Public so the
  /// Settings UI can render the same form it would write.
  static String encodeColor(Color color) {
    final argb = color.toARGB32();
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final rs = r.toRadixString(16).padLeft(2, '0').toUpperCase();
    final gs = g.toRadixString(16).padLeft(2, '0').toUpperCase();
    final bs = b.toRadixString(16).padLeft(2, '0').toUpperCase();
    if (a == 0xFF) return '#$rs$gs$bs';
    final as_ = a.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#$rs$gs$bs$as_';
  }

  /// Parses a `#RRGGBB` or `#RRGGBBAA` hex color string. Accepts both
  /// upper-case and lower-case digits. Returns `null` on malformed
  /// input rather than throwing — callers report the offending key
  /// with a contextual message.
  static Color? tryParseColor(String input) {
    if (input.isEmpty) return null;
    final hex = input.startsWith('#') ? input.substring(1) : input;
    if (hex.length != 6 && hex.length != 8) return null;
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      if (v == null) return null;
      return Color(0xFF000000 | v);
    }
    // Length 8: RRGGBBAA per the spec.
    final rr = hex.substring(0, 2);
    final gg = hex.substring(2, 4);
    final bb = hex.substring(4, 6);
    final aa = hex.substring(6, 8);
    final argbHex = '$aa$rr$gg$bb';
    final v = int.tryParse(argbHex, radix: 16);
    if (v == null) return null;
    return Color(v);
  }
}
