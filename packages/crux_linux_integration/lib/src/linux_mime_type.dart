// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// MIME types a desktop environment already maps, which an application names
/// but must never declare.
///
/// A distro's `shared-mime-info` already gives each of these a glob and a
/// "Kind" text. Installing our own declaration for one would replace that text
/// for **every** file of that type on the user's machine, including files no
/// Crux application has ever opened. Naming one in a desktop entry is enough:
/// the system's own mapping resolves it.
///
/// These are the generic types any desktop maps — the ones a structured
/// project or configuration file is otherwise typed as. **A product names
/// more**: the source and report types of its own trade, which belong in that
/// product rather than in shared code. Pass those to
/// `checkLinuxMimeCoverage` as `additionalSystemTypes` and its guard holds
/// declarations against them too.
///
/// A type missing here that a distro does map is still a type to name with
/// [LinuxMimeType.registered], not to declare.
const Set<String> kLinuxSystemMimeTypes = <String>{
  'application/json',
  'application/sarif+json',
  'application/x-yaml',
  'application/xml',
  'text/csv',
  'text/markdown',
  'text/plain',
  'text/x-csrc',
  'text/x-fortran',
  'text/x-tcl',
  'text/xml',
  'text/yaml',
  // What a stock database already globs `.vcd` to. A waveform is recognised
  // by its content instead; see [LinuxMimeMagic].
  'application/x-cdlink',
};

/// The weight `shared-mime-info` gives a glob that does not ask for one.
///
/// A glob below it loses to a type the system already maps for the same
/// extension, and a glob above it takes that extension from every
/// application on the machine.
const int kLinuxDefaultGlobWeight = 50;

/// One byte sequence that identifies a file by its content.
///
/// A [LinuxMimeMagic] holds several as alternatives: a match is enough, not
/// required, so a format whose header may begin with either of two tokens
/// lists both.
@immutable
class LinuxMimeMagicMatch {
  /// Matches [value] at [offset], or anywhere from [offset] to [offsetEnd]
  /// when that is given — the form for a token that follows a variable
  /// preamble such as a comment header.
  const LinuxMimeMagicMatch({
    required this.value,
    this.offset = 0,
    this.offsetEnd,
  });

  /// The byte string to find.
  final String value;

  /// Where to start looking, in bytes from the beginning of the file.
  final int offset;

  /// The last offset to look at, or `null` to look only at [offset].
  final int? offsetEnd;

  /// The `offset` attribute, as `shared-mime-info` spells a range.
  String get offsetAttribute =>
      offsetEnd == null ? '$offset' : '$offset:$offsetEnd';
}

/// A content match: how a file of this type is recognised when its extension
/// is not enough, or not ours to take.
///
/// This is what makes it honest to claim an extension a desktop already maps
/// to something else. `.vcd` is globbed to a Video CD playlist on a stock
/// database; outranking that with a heavier glob would retype every `.vcd` on
/// the machine, so a waveform type takes a glob *below* the default weight and
/// a magic match on the format's own header tokens. A real Video CD keeps its
/// type, and a waveform is still recognised — by what is in it.
@immutable
class LinuxMimeMagic {
  /// Creates a content match from [matches], any one of which identifies the
  /// file, at [priority] (0–100; the database's own rules mostly sit at 50).
  factory LinuxMimeMagic({
    required List<LinuxMimeMagicMatch> matches,
    int priority = kLinuxDefaultGlobWeight,
  }) {
    if (matches.isEmpty) {
      throw ArgumentError.value(
        matches,
        'matches',
        'a content match needs at least one byte string to look for',
      );
    }
    if (priority < 0 || priority > 100) {
      throw ArgumentError.value(priority, 'priority', 'must be 0–100');
    }
    return LinuxMimeMagic._(
      matches: List<LinuxMimeMagicMatch>.unmodifiable(matches),
      priority: priority,
    );
  }

  const LinuxMimeMagic._({required this.matches, required this.priority});

  /// The alternatives; any one identifies the file.
  final List<LinuxMimeMagicMatch> matches;

  /// How strongly this match speaks for the type, 0–100.
  final int priority;
}

/// One file kind an application opens, in the three forms a Linux desktop
/// needs to be told about.
///
/// A desktop entry's `MimeType=` can only match a type the system can derive
/// from the file, so naming `application/x-netcrux-project` there does nothing
/// on its own: nothing maps the extension, the file is typed as JSON or text,
/// and the application is never offered. A type of our own therefore needs
/// **both** halves — [LinuxMimeType.declared] puts it in the
/// `shared-mime-info` package the integrator installs (extensions, the "Kind"
/// text a file manager shows, and optionally a parent type) and in the entry.
///
/// The other two forms are what keeps the Linux list honest against the
/// document types a macOS bundle registers:
///
/// - [LinuxMimeType.registered] names a type the system already maps. It goes
///   in the entry and **not** in the XML, so the distro's own glob and
///   description keep deciding for every file of that type.
/// - [LinuxMimeType.unmapped] records an extension deliberately left alone —
///   `.f` belongs to Fortran on a Linux desktop, and claiming it would take it
///   from Fortran editors. It goes in neither, and carries the reason so a
///   coverage check can report it rather than call it a hole.
@immutable
class LinuxMimeType {
  /// A type this application defines: declared in the installed XML with its
  /// [extensions], [comment] and optional [subClassOf], and named in the
  /// desktop entry.
  ///
  /// [name] is the MIME name, by convention `application/x-<product>-<kind>`
  /// for a vendor type. [extensions] are the file extensions that match it,
  /// without the dot (`netcrux-project`). [comment] is the human-readable
  /// description a file manager shows in its "Kind" column.
  ///
  /// [globWeight] sets the weight of this type's globs, and [magic] a match
  /// on the file's own content. Together they are how an extension another
  /// type already claims is shared honestly rather than taken: see
  /// [LinuxMimeMagic].
  ///
  /// [subClassOf] names a parent type (`application/json`, `application/x-yaml`,
  /// `text/plain`). A desktop that knows nothing of our type still treats the
  /// file as its parent — it opens in a text editor, is searched as text, and
  /// shows a sensible icon — which is what makes declaring a type for a
  /// JSON- or YAML-shaped project file safe.
  ///
  /// Throws an [ArgumentError] when [extensions] is empty, or when [name] is
  /// a type the system already maps ([kLinuxSystemMimeTypes]) — declaring one
  /// of those would replace its "Kind" text for every such file on the
  /// machine. Name it with [LinuxMimeType.registered] instead. A *parent* may
  /// of course be a system type; that is the point of it.
  factory LinuxMimeType.declared({
    required String name,
    required String comment,
    required List<String> extensions,
    String? subClassOf,
    int? globWeight,
    LinuxMimeMagic? magic,
  }) {
    if (extensions.isEmpty) {
      throw ArgumentError.value(
        extensions,
        'extensions',
        'a declared type needs at least one extension, or nothing matches it '
            'and the application is still never offered. To record an '
            'extension left unmapped on purpose, use LinuxMimeType.unmapped',
      );
    }
    if (kLinuxSystemMimeTypes.contains(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'is a type the system already maps: declaring it would replace the '
            'description every file of that type shows. Name it with '
            'LinuxMimeType.registered instead, which puts it in the desktop '
            'entry without declaring it',
      );
    }
    if (globWeight != null && (globWeight < 1 || globWeight > 100)) {
      throw ArgumentError.value(
        globWeight,
        'globWeight',
        'must be 1–100. Below $kLinuxDefaultGlobWeight the glob loses to a '
            'type the system already maps for that extension, which is the '
            'point of setting one; above it, this application takes the '
            'extension from every other',
      );
    }
    return LinuxMimeType._(
      name: name,
      comment: comment,
      extensions: List<String>.unmodifiable(extensions),
      subClassOf: subClassOf,
      globWeight: globWeight,
      magic: magic,
    );
  }

  /// A type the system already maps: named in the desktop entry, never
  /// declared, so the distro's own glob and description keep deciding.
  const LinuxMimeType.registered(this.name)
    : comment = null,
      extensions = const <String>[],
      subClassOf = null,
      reason = null,
      globWeight = null,
      magic = null;

  /// [extensions] this application opens elsewhere but deliberately does not
  /// claim on Linux, with the [reason] a coverage check prints.
  ///
  /// It appears in neither the entry nor the XML. The record exists so that an
  /// extension missing from the Linux side is a decision somebody wrote down,
  /// not an oversight nobody noticed.
  factory LinuxMimeType.unmapped({
    required List<String> extensions,
    required String reason,
  }) {
    if (extensions.isEmpty) {
      throw ArgumentError.value(
        extensions,
        'extensions',
        'an unmapped record needs the extensions it accounts for',
      );
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'an extension left unmapped needs the reason it was left, or the next '
            'reader cannot tell a decision from an omission',
      );
    }
    return LinuxMimeType._(
      name: '',
      comment: null,
      extensions: List<String>.unmodifiable(extensions),
      reason: reason,
    );
  }

  const LinuxMimeType._({
    required this.name,
    required this.comment,
    required this.extensions,
    this.subClassOf,
    this.reason,
    this.globWeight,
    this.magic,
  });

  /// The MIME name, as it appears in the entry's `MimeType=` list. Empty for
  /// an [LinuxMimeType.unmapped] record.
  final String name;

  /// The "Kind" text for a declared type; `null` otherwise.
  final String? comment;

  /// Extensions this record accounts for, without the dot. Empty for a
  /// registered type, whose extensions are the system's business.
  final List<String> extensions;

  /// The parent type of a declared type, or `null`.
  final String? subClassOf;

  /// Why an [LinuxMimeType.unmapped] extension is left alone; `null`
  /// otherwise.
  final String? reason;

  /// The weight of this type's globs, or `null` for the database's default
  /// ([kLinuxDefaultGlobWeight]).
  ///
  /// Set it **below** the default to claim an extension another type already
  /// globs without taking it: the other type keeps winning on the extension
  /// alone, and a [magic] match is what recognises ours.
  final int? globWeight;

  /// How a file of this type is recognised by its content, or `null`.
  final LinuxMimeMagic? magic;

  /// Whether this type goes in the installed `shared-mime-info` package.
  bool get isDeclared => comment != null;

  /// Whether this type is named in the entry's `MimeType=` list.
  bool get isNamed => name.isNotEmpty;

  /// The glob patterns for a declared type (`*.netcrux-project`).
  Iterable<String> get globs => extensions.map((e) => '*.$e');
}
