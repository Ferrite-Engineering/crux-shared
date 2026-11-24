// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_mcp/src/json_writer.dart';
import 'package:meta/meta.dart';

/// The WaveCrux link prefix: scheme and action.
const String kWaveCruxLinkPrefix = 'wavecrux://open?';

/// The NetCrux link prefix: scheme and action.
const String kNetCruxLinkPrefix = 'netcrux://open?';

/// The longest link a receiving app accepts, in UTF-16 code units.
const int kMcpMaxLinkLength = 8192;

/// The longest decoded `file` value a link may carry, in UTF-16 code units.
const int kMcpMaxLinkFileLength = 4096;

/// The longest decoded name (`signal`, `cell`, `net`) a link may carry, in
/// UTF-16 code units.
const int kMcpMaxLinkNameLength = 1024;

/// The longest decoded `t` value a link may carry, in UTF-16 code units.
const int kMcpMaxLinkTimeLength = 48;

/// Why a location or link could not be built or read.
class McpLocationException implements Exception {
  /// An exception saying [message].
  const McpLocationException(this.message);

  /// One sentence for a person.
  final String message;

  @override
  String toString() => 'McpLocationException: $message';
}

/// A unit of simulated time.
enum McpTimeUnit {
  /// Femtoseconds.
  fs,

  /// Picoseconds.
  ps,

  /// Nanoseconds.
  ns,

  /// Microseconds.
  us,

  /// Milliseconds.
  ms,

  /// Seconds.
  s,

  /// A raw tick of the file's own timescale.
  tick;

  /// The unit as a document names it.
  String get wireName => name;

  /// The unit named [name] in a document, or null.
  static McpTimeUnit? fromWireName(String name) {
    for (final unit in values) {
      if (unit.name == name) return unit;
    }
    return null;
  }
}

/// A point in simulated time: a whole count of a unit.
@immutable
class McpTime implements McpJsonValue {
  /// [at] units. Throws an [ArgumentError] when [at] is negative.
  McpTime(this.at, this.unit) {
    if (at < 0) throw ArgumentError.value(at, 'at', 'a time is not negative');
  }

  /// A raw tick count.
  factory McpTime.ticks(int at) => McpTime(at, McpTimeUnit.tick);

  /// The count.
  final int at;

  /// The unit.
  final McpTimeUnit unit;

  /// The link's `t` value: the count and the unit (`1500ns`), or the count
  /// alone for a raw tick.
  String get linkValue => unit == McpTimeUnit.tick ? '$at' : '$at${unit.name}';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'at': at,
    'unit': unit.wireName,
  };

  @override
  bool operator ==(Object other) =>
      other is McpTime && other.at == at && other.unit == unit;

  @override
  int get hashCode => Object.hash(at, unit);

  @override
  String toString() => linkValue;
}

/// What a design location names: a cell or a net.
enum McpElementKind {
  /// A cell (an instance).
  cell,

  /// A net.
  net,
}

/// A place a result points at, one of five forms told apart by their
/// members.
///
/// - [McpSourceLocation]: `file`, `line`, `column` (a line of a file);
/// - [McpSignalLocation]: `file`, `signal`, `time`, `link` (a signal at a
///   time, with the WaveCrux link that opens it);
/// - [McpPlaceLocation]: `file`, `time` (a time in a file, no signal, no
///   link member);
/// - [McpElementLocation]: `file`, `cell` or `net`, `module`, `src`, `link`
///   (a cell or net of an elaborated design; `link` null until NetCrux opens
///   links);
/// - [McpTestLocation]: `test`, `run`, `file`, `line` (a test of a run, with
///   the line of its log).
///
/// Every member a form has is always written, null when empty, and no other
/// member appears.
@immutable
sealed class McpLocation implements McpJsonValue {
  const McpLocation();

  /// Reads a location back from its JSON form, refusing unknown members and
  /// a link that is not exactly the one the other members give.
  ///
  /// The form is told by its members: `signal` makes a signal location,
  /// `cell` or `net` an element location, `test` a test location, `time`
  /// without those a place, and none of them a source location.
  factory McpLocation.fromJson(Object? json) => _readLocation(json);

  /// The file the location is in, when it names one.
  String? get file;

  @override
  Map<String, Object?> toJson();

  @override
  bool operator ==(Object other) =>
      other is McpLocation &&
      other.runtimeType == runtimeType &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => mcpRenderJsonLine(this);
}

/// A line of a file, and optionally a column, counting from 1.
final class McpSourceLocation extends McpLocation {
  /// Throws an [McpLocationException] when [file] is empty or [line] or
  /// [column] is below 1.
  McpSourceLocation({required this.file, required this.line, this.column}) {
    if (file.isEmpty) throw const McpLocationException('the file is empty');
    if (line < 1) {
      throw const McpLocationException('a line counts from 1');
    }
    if (column != null && column! < 1) {
      throw const McpLocationException('a column counts from 1');
    }
  }

  @override
  final String file;

  /// The line, from 1.
  final int line;

  /// The column, from 1, when known.
  final int? column;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'file': file,
    'line': line,
    'column': column,
  };
}

/// A signal at a time in a file, with the WaveCrux link that opens it.
final class McpSignalLocation extends McpLocation {
  /// The location of [signal] at [time] in [file], an absolute path. The
  /// link is built by [waveCruxLink]; whatever it refuses, this refuses.
  factory McpSignalLocation({
    required String file,
    required String signal,
    required McpTime time,
  }) => McpSignalLocation._(
    file,
    signal,
    time,
    waveCruxLink(file, signal: signal, time: time),
  );

  const McpSignalLocation._(this.file, this.signal, this.time, this.link);

  @override
  final String file;

  /// The hierarchical name, its scopes separated by `.`.
  final String signal;

  /// The time.
  final McpTime time;

  /// `wavecrux://open?file=<file>&signal=<signal>&t=<t>`.
  final String link;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'file': file,
    'signal': signal,
    'time': time.toJson(),
    'link': link,
  };
}

/// A time in a file, without a signal and so without a link member.
///
/// What a result points at when the signal it is about is not in the file;
/// the result says which name and why. A person opens it with
/// [waveCruxLink] given the file and the time.
final class McpPlaceLocation extends McpLocation {
  /// Throws an [McpLocationException] when [file] is not absolute.
  McpPlaceLocation({required this.file, required this.time}) {
    _requireAbsolute(file, 'file');
  }

  @override
  final String file;

  /// The time.
  final McpTime time;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'file': file,
    'time': time.toJson(),
  };
}

/// A cell or a net of an elaborated design.
final class McpElementLocation extends McpLocation {
  /// The [kind] named [name] in [module] of the design read from [file].
  ///
  /// [src] is where the source declares it, when known. With [linked] the
  /// location carries the NetCrux link [netCruxLink] builds (and refuses
  /// what it refuses); without, `link` is null, as it must be until the
  /// receiving app opens such links.
  factory McpElementLocation({
    required String file,
    required McpElementKind kind,
    required String name,
    required String module,
    McpSourceLocation? src,
    bool linked = false,
  }) {
    if (file.isEmpty) throw const McpLocationException('the file is empty');
    if (name.isEmpty) {
      throw McpLocationException('the ${kind.name} name is empty');
    }
    return McpElementLocation._(
      file,
      kind,
      name,
      module,
      src,
      linked ? netCruxLink(file, kind: kind, name: name) : null,
    );
  }

  const McpElementLocation._(
    this.file,
    this.kind,
    this.name,
    this.module,
    this.src,
    this.link,
  );

  @override
  final String file;

  /// Whether [name] is a cell or a net.
  final McpElementKind kind;

  /// The cell or net name.
  final String name;

  /// The module that holds it.
  final String module;

  /// Where the source declares it, when known.
  final McpSourceLocation? src;

  /// `netcrux://open?file=<file>&cell=<name>` (or `&net=`), or null.
  final String? link;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'file': file,
    kind.name: name,
    'module': module,
    'src': src?.toJson(),
    'link': link,
  };
}

/// A test of a run, with the line of its log when known.
final class McpTestLocation extends McpLocation {
  /// Throws an [McpLocationException] when [test] or [run] is empty, or
  /// [line] is given without [file] or below 1.
  McpTestLocation({
    required this.test,
    required this.run,
    this.file,
    this.line,
  }) {
    if (test.isEmpty) throw const McpLocationException('the test is empty');
    if (run.isEmpty) throw const McpLocationException('the run is empty');
    if (file != null && file!.isEmpty) {
      throw const McpLocationException('the file is empty');
    }
    if (line != null && (file == null || line! < 1)) {
      throw const McpLocationException(
        'a line counts from 1 and needs its file',
      );
    }
  }

  /// The test's name.
  final String test;

  /// The run it belongs to.
  final String run;

  /// The test's log, when there is one.
  @override
  final String? file;

  /// The line of [file], from 1, when known.
  final int? line;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'test': test,
    'run': run,
    'file': file,
    'line': line,
  };
}

/// [value] percent-encoded for a link: every byte of its UTF-8 except
/// `A-Z a-z 0-9 - . _ ~` written `%XX` in upper-case hex.
String mcpPercentEncode(String value) {
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final unreserved =
        (byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x30 && byte <= 0x39) ||
        byte == 0x2D ||
        byte == 0x2E ||
        byte == 0x5F ||
        byte == 0x7E;
    if (unreserved) {
      out.writeCharCode(byte);
    } else {
      out
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return out.toString();
}

/// Whether [path] is absolute as text on any host: `/...`, `\\...`,
/// `C:\...` or `C:/...`. A document made on one host must read on another,
/// so this never asks the reading host.
bool mcpIsAbsoluteText(String path) {
  if (path.startsWith('/') || path.startsWith(r'\\')) return true;
  if (path.length < 3) return false;
  final c = path.codeUnitAt(0) | 0x20;
  final letter = c >= 0x61 && c <= 0x7A;
  final sep = path.codeUnitAt(2);
  return letter && path.codeUnitAt(1) == 0x3A && (sep == 0x5C || sep == 0x2F);
}

/// The WaveCrux link that opens [file], and in it [signal] at [time] when
/// given: `wavecrux://open?file=<file>&signal=<signal>&t=<t>`, each value
/// encoded by [mcpPercentEncode].
///
/// Refuses (with an [McpLocationException]) any value WaveCrux's link reader
/// would refuse, so no document carries a link that does not open: a file
/// that is not absolute, white space or a control character in a name (a
/// plain space only in a file), a name with an empty scope, and any value or
/// the whole link past its length bound.
String waveCruxLink(String file, {String? signal, McpTime? time}) {
  _checkFile(file);
  final query = StringBuffer('file=${mcpPercentEncode(file)}');
  if (signal != null) {
    _checkName(signal, 'signal');
    if (signal.split('.').any((s) => s.isEmpty)) {
      throw McpLocationException(
        '"$signal" is not a dot-separated hierarchical name',
      );
    }
    query.write('&signal=${mcpPercentEncode(signal)}');
  }
  if (time != null) {
    final t = time.linkValue;
    if (t.length > kMcpMaxLinkTimeLength) {
      throw const McpLocationException('the time is too long for a link');
    }
    query.write('&t=${mcpPercentEncode(t)}');
  }
  return _bounded('$kWaveCruxLinkPrefix$query');
}

/// The NetCrux link that opens [file] at the cell or net [name]:
/// `netcrux://open?file=<file>&cell=<name>` (or `&net=<name>`), each value
/// encoded by [mcpPercentEncode], under the same refusals as [waveCruxLink].
String netCruxLink(
  String file, {
  required McpElementKind kind,
  required String name,
}) {
  _checkFile(file);
  _checkName(name, kind.name);
  return _bounded(
    '${kNetCruxLinkPrefix}file=${mcpPercentEncode(file)}'
    '&${kind.name}=${mcpPercentEncode(name)}',
  );
}

String _bounded(String link) {
  if (link.length > kMcpMaxLinkLength) {
    throw const McpLocationException('the link is too long');
  }
  return link;
}

void _requireAbsolute(String file, String what) {
  if (file.isEmpty) throw McpLocationException('the $what is empty');
  if (!mcpIsAbsoluteText(file)) {
    throw McpLocationException('the $what "$file" is not an absolute path');
  }
}

void _checkFile(String file) {
  _requireAbsolute(file, 'file');
  if (file.length > kMcpMaxLinkFileLength) {
    throw const McpLocationException('the file path is too long for a link');
  }
  if (_hasForbiddenCharacter(file, allowSpace: true)) {
    throw const McpLocationException(
      'the file path holds a control character a link cannot carry',
    );
  }
}

void _checkName(String name, String what) {
  if (name.isEmpty) throw McpLocationException('the $what name is empty');
  if (name.length > kMcpMaxLinkNameLength) {
    throw McpLocationException('the $what name is too long for a link');
  }
  if (_hasForbiddenCharacter(name, allowSpace: false)) {
    throw McpLocationException(
      'the $what name holds white space or a control character a link '
      'cannot carry',
    );
  }
}

/// The characters WaveCrux's link reader refuses in a decoded value: C0 and
/// C1 controls, DEL, bidirectional-text controls, line and paragraph
/// separators, and white space other than a plain space, which only a file
/// path may hold.
bool _hasForbiddenCharacter(String value, {required bool allowSpace}) {
  for (final u in value.runes) {
    if (u == 0x20) {
      if (!allowSpace) return true;
      continue;
    }
    if (u < 0x20 ||
        (u >= 0x7F && u <= 0x9F) ||
        u == 0x200E ||
        u == 0x200F ||
        (u >= 0x202A && u <= 0x202E) ||
        (u >= 0x2066 && u <= 0x2069) ||
        u == 0x061C ||
        u == 0x2028 ||
        u == 0x2029 ||
        u == 0x00A0 ||
        u == 0x1680 ||
        u == 0x3000 ||
        (u >= 0x2000 && u <= 0x200B) ||
        u == 0x202F ||
        u == 0x205F ||
        u == 0xFEFF) {
      return true;
    }
  }
  return false;
}

McpLocation _readLocation(Object? json) {
  if (json is! Map<String, Object?>) {
    throw const McpLocationException('a location is an object');
  }
  final keys = json.keys.toList()..sort();
  void exactly(List<String> want, String form) {
    final sorted = [...want]..sort();
    if (keys.join(',') != sorted.join(',')) {
      throw McpLocationException(
        'a $form location has exactly ${want.join(', ')}; found '
        '${keys.join(', ')}',
      );
    }
  }

  String text(String key) {
    final v = json[key];
    if (v is! String) throw McpLocationException('`$key` is not a string');
    return v;
  }

  String? optionalText(String key) {
    final v = json[key];
    if (v == null) return null;
    if (v is! String) throw McpLocationException('`$key` is not a string');
    return v;
  }

  int count(Object? v, String key) {
    if (v is! int) throw McpLocationException('`$key` is not a whole number');
    return v;
  }

  McpTime time() {
    final t = json['time'];
    if (t is! Map<String, Object?>) {
      throw const McpLocationException('`time` is not an object');
    }
    final tk = t.keys.toList()..sort();
    if (tk.join(',') != 'at,unit') {
      throw const McpLocationException('`time` has exactly at and unit');
    }
    final unitName = t['unit'];
    final unit = unitName is String ? McpTimeUnit.fromWireName(unitName) : null;
    if (unit == null) {
      throw const McpLocationException('`time.unit` is not a known unit');
    }
    final at = count(t['at'], 'time.at');
    if (at < 0) throw const McpLocationException('`time.at` is negative');
    return McpTime(at, unit);
  }

  void sameLink(String? found, String? expected) {
    if (found != expected) {
      throw McpLocationException(
        'the link "$found" does not match its other members '
        '(expected "$expected")',
      );
    }
  }

  if (json.containsKey('signal')) {
    exactly(const ['file', 'signal', 'time', 'link'], 'signal');
    final built = McpSignalLocation(
      file: text('file'),
      signal: text('signal'),
      time: time(),
    );
    sameLink(optionalText('link'), built.link);
    return built;
  }
  if (json.containsKey('cell') || json.containsKey('net')) {
    final kind = json.containsKey('cell')
        ? McpElementKind.cell
        : McpElementKind.net;
    exactly(<String>['file', kind.name, 'module', 'src', 'link'], 'design');
    final srcJson = json['src'];
    final src = srcJson == null ? null : _readLocation(srcJson);
    if (src != null && src is! McpSourceLocation) {
      throw const McpLocationException('`src` is not a source location');
    }
    final link = optionalText('link');
    final built = McpElementLocation(
      file: text('file'),
      kind: kind,
      name: text(kind.name),
      module: text('module'),
      src: src as McpSourceLocation?,
      linked: link != null,
    );
    sameLink(link, built.link);
    return built;
  }
  if (json.containsKey('test')) {
    exactly(const ['test', 'run', 'file', 'line'], 'test');
    final line = json['line'];
    return McpTestLocation(
      test: text('test'),
      run: text('run'),
      file: optionalText('file'),
      line: line == null ? null : count(line, 'line'),
    );
  }
  if (json.containsKey('time')) {
    exactly(const ['file', 'time'], 'place');
    return McpPlaceLocation(file: text('file'), time: time());
  }
  exactly(const ['file', 'line', 'column'], 'source');
  final column = json['column'];
  return McpSourceLocation(
    file: text('file'),
    line: count(json['line'], 'line'),
    column: column == null ? null : count(column, 'column'),
  );
}
