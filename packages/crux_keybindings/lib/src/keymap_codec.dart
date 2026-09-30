// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_keybindings/src/key_binding.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';

/// Default schema identifier embedded in a serialized keymap. Products may pass
/// their own (e.g. `'wavecrux.keymap'`) for friendlier share files; decode does
/// not validate it, so files stay forward/backward compatible.
const String defaultKeymapSchema = 'crux.keymap';

/// Current keymap schema version. Bump on an incompatible shape change.
///
/// [KeymapCodec.decode] accepts this version and any *older* one (the payload
/// is tolerated field-by-field), and refuses anything newer with a
/// [KeymapSchemaVersionException].
const int kKeymapVersion = 1;

/// Thrown by [KeymapCodec.decode] / [KeymapCodec.decodeString] when a keymap
/// declares a schema version this build does not understand.
///
/// ### Why this refuses instead of degrading
///
/// A `.crux-keymap` is a **user-authored, shareable artifact** — the same
/// category as a theme pack. It arrives from another human, often from a newer
/// build. Parsing a version-2 envelope under version-1 assumptions does not
/// produce "most of" their keymap; it produces a silently *different* one, and
/// the user's only signal is that their shortcuts do the wrong thing. Refusing
/// loudly lets the host say "this keymap was made with a newer version of
/// the product" and leave the existing bindings untouched.
///
/// Contrast the app-managed side of the same policy: `Workspace` and
/// `ProjectWorkspace` are files the app wrote for itself, the user cannot
/// hand-repair them, and a hard failure would brick launch — so those degrade
/// to an empty document (after quarantining the bytes) rather than refusing.
class KeymapSchemaVersionException extends FormatException {
  /// Creates an exception reporting an unsupported [version].
  KeymapSchemaVersionException(this.version)
    : super(
        'Keymap declares schema version $version, but this build supports at '
        'most $kKeymapVersion. It was probably saved by a newer release.',
      );

  /// The unsupported version found in the envelope.
  final int version;
}

/// Serializes a product's keyboard-shortcut customization set to and from a
/// versioned JSON envelope, generic over the product's [CruxAction] enum.
///
/// The payload stores **diffs from default**, keyed by [CruxAction.id]:
///
/// - an entry mapping to a [KeyBinding] JSON object = a rebind,
/// - an entry mapping to `null` = an explicit *unbind*,
/// - an absent action = inherits the product default (so actions added in a
///   later release are picked up rather than orphaned).
///
/// Unknown action ids (e.g. from a keymap shared by a newer build) and
/// malformed bindings are skipped on decode rather than failing the whole map.
class KeymapCodec<A extends CruxAction> {
  /// Creates a codec for the given [actions] (typically `MyAction.values`).
  /// [schema] is the cosmetic schema string written into the envelope.
  KeymapCodec({required Iterable<A> actions, this.schema = defaultKeymapSchema})
    : _byId = {for (final a in actions) a.id: a};

  /// Schema string written into the envelope.
  final String schema;

  final Map<String, A> _byId;

  /// Encodes [diffs] to the versioned envelope. A `null` value is preserved as
  /// an explicit unbind. Entries are emitted in a deterministic id order so the
  /// same customization set always serializes identically.
  Map<String, Object?> encode(Map<A, KeyBinding?> diffs) {
    final entries = diffs.entries.toList()
      ..sort((a, b) => a.key.id.compareTo(b.key.id));
    return {
      'schema': schema,
      'version': kKeymapVersion,
      'bindings': {
        for (final e in entries) e.key.id: e.value?.toJson(),
      },
    };
  }

  /// Decodes a versioned envelope to a diff map. Returns an empty map for any
  /// structurally invalid payload. A `null` binding value round-trips as an
  /// explicit unbind.
  ///
  /// Throws [KeymapSchemaVersionException] when the envelope declares a schema
  /// version newer than [kKeymapVersion]. Until this check existed, `version`
  /// was **written but never read**: a keymap from a future release was parsed
  /// under today's assumptions and silently produced the wrong bindings.
  ///
  /// A missing or non-integer `version` is treated as legacy-compatible rather
  /// than fatal — every field below is validated individually, so a
  /// hand-edited file without the envelope key still decodes safely.
  Map<A, KeyBinding?> decode(Object? json) {
    if (json is! Map) return {};
    final version = json['version'];
    if (version is int && version > kKeymapVersion) {
      throw KeymapSchemaVersionException(version);
    }
    final bindings = json['bindings'];
    if (bindings is! Map) return {};
    final out = <A, KeyBinding?>{};
    bindings.forEach((key, value) {
      if (key is! String) return;
      final action = _byId[key];
      if (action == null) return; // unknown / removed action
      if (value == null) {
        out[action] = null; // explicit unbind
        return;
      }
      final binding = KeyBinding.fromJson(value);
      if (binding != null) out[action] = binding;
      // A malformed binding is skipped so the action inherits its default.
    });
    return out;
  }

  /// Encodes [diffs] to a pretty-printed JSON string (share file / persisted
  /// preference value).
  String encodeToString(Map<A, KeyBinding?> diffs) =>
      const JsonEncoder.withIndent('  ').convert(encode(diffs));

  /// Decodes a JSON string to a diff map. Returns an empty map for invalid JSON
  /// or an unrecognized shape.
  ///
  /// Propagates [KeymapSchemaVersionException] — the JSON parse is caught, the
  /// version refusal deliberately is not. Swallowing it here would restore the
  /// exact silent-misparse bug the version check exists to fix (an unsupported
  /// keymap would come back as "no customizations" and quietly wipe the
  /// user's bindings on the next save).
  Map<A, KeyBinding?> decodeString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return {};
    }
    return decode(decoded);
  }
}
