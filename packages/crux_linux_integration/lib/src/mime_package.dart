// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_linux_integration/src/linux_desktop_app.dart';
import 'package:crux_linux_integration/src/linux_mime_type.dart';

/// Builds the `shared-mime-info` XML package declaring [app]'s own MIME
/// types, or `null` when it declares none.
///
/// This is the half that makes a desktop entry's `MimeType=` mean anything
/// for a type of ours. A file manager types a file first and looks for
/// handlers second, so with nothing mapping `*.netcrux-project` the file is
/// typed as JSON or text and the application is never offered, however
/// completely the entry lists it. The XML supplies that mapping, and the
/// description a file manager shows in its "Kind" column.
///
/// **Only the application's own types appear here.** A type the system
/// already maps ([LinuxMimeType.registered]) is named in the entry and left
/// alone: re-declaring it would replace its description for every file of
/// that type on the machine, including files this application never opens. An
/// extension left unmapped on purpose ([LinuxMimeType.unmapped]) appears in
/// neither.
///
/// Installed at `<data home>/mime/packages/<app id>.xml` and compiled into the
/// user's MIME database by `update-mime-database`, both of which
/// `DesktopIntegrator` does.
String? buildMimePackage(LinuxDesktopApp app) {
  final declared = app.fileTypes.where((t) => t.isDeclared).toList();
  if (declared.isEmpty) return null;

  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<mime-info '
      'xmlns="http://www.freedesktop.org/standards/shared-mime-info">',
    );
  for (final type in declared) {
    buffer
      ..writeln('  <mime-type type="${_attribute(type.name)}">')
      ..writeln('    <comment>${_text(type.comment!)}</comment>');
    // comment, sub-class-of, magic, glob: the order the database's own
    // rules are written in. A desktop that knows nothing of our type still
    // treats the file as its parent: it opens in a text editor and is
    // searched as text.
    final parent = type.subClassOf;
    if (parent != null) {
      buffer.writeln('    <sub-class-of type="${_attribute(parent)}"/>');
    }
    final magic = type.magic;
    if (magic != null) {
      buffer.writeln('    <magic priority="${magic.priority}">');
      for (final match in magic.matches) {
        buffer.writeln(
          '      <match type="string" value="${_attribute(match.value)}" '
          'offset="${match.offsetAttribute}"/>',
        );
      }
      buffer.writeln('    </magic>');
    }
    final weight = type.globWeight;
    for (final glob in type.globs) {
      final attributes = weight == null ? '' : ' weight="$weight"';
      buffer.writeln('    <glob pattern="${_attribute(glob)}"$attributes/>');
    }
    buffer.writeln('  </mime-type>');
  }
  buffer.writeln('</mime-info>');
  return buffer.toString();
}

/// Escapes [value] for an XML attribute. A product's own name or description
/// reaches this file verbatim, and an unescaped `&` makes the whole package
/// unparseable — which `update-mime-database` reports by ignoring it, leaving
/// the association silently missing.
String _attribute(String value) =>
    _text(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');

/// Escapes [value] for XML character data.
String _text(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
