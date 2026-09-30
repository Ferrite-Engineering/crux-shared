// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_linux_integration/src/desktop_entry.dart';
import 'package:crux_linux_integration/src/linux_desktop_app.dart';
import 'package:crux_linux_integration/src/linux_mime_type.dart';
import 'package:crux_linux_integration/src/mime_package.dart';

/// Checks that [app]'s Linux file associations account for every extension
/// the application registers elsewhere, and that the two halves agree.
///
/// Returns one line per problem, empty when there is none — so a product's
/// test is `expect(checkLinuxMimeCoverage(app, registeredExtensions: …),
/// isEmpty)`, and the failure prints what is missing. The guard lives here so
/// all four products inherit the same rules rather than each deciding what
/// "covered" means.
///
/// [registeredExtensions] is what the application registers on the platform
/// that already has associations — the extensions in its macOS bundle's
/// document types — without the dot.
///
/// What it holds [app] to:
///
/// - No declaration names a type the system already maps. The generic ones
///   are [kLinuxSystemMimeTypes]; a product passes the types of its own trade
///   as [additionalSystemTypes], since those names belong in the product.
/// - Every registered extension is accounted for: matched by a declared type,
///   or written off with a reason. A type the system maps carries no
///   extensions of its own, so its extensions are accounted for by being
///   named in the desktop entry; list them with the type as
///   `registeredExtensionsOf` if a product wants them checked too.
/// - An extension is claimed once. Two types matching `*.crux-project` make
///   the winner a matter of which package the database read last.
/// - Every declared type reaches the entry's `MimeType=`, and every type in
///   the entry is either declared here or already mapped by the system. A
///   declared type the entry omits is a mapping nothing uses; a named type
///   neither declared nor registered is a claim nothing resolves.
///
/// An extension left unmapped on purpose is reported in the returned report's
/// [LinuxMimeCoverage.deliberatelyUnmapped], not as a problem: the record is
/// the decision, and a reader sees "deliberately unmapped: …" rather than a
/// hole.
LinuxMimeCoverage checkLinuxMimeCoverage(
  LinuxDesktopApp app, {
  required Set<String> registeredExtensions,
  Map<String, List<String>> registeredExtensionsOf =
      const <String, List<String>>{},
  Set<String> additionalSystemTypes = const <String>{},
}) {
  final problems = <String>[];
  if (app.mimeTypes.isNotEmpty) {
    problems.add(
      'mimeTypes carries bare names (${app.mimeTypes.join(', ')}), which '
      'install no mapping: a file manager types the file before it looks for '
      'handlers, so a name there matches nothing unless the system already '
      'maps it. Move them to fileTypes',
    );
  }
  final systemTypes = <String>{
    ...kLinuxSystemMimeTypes,
    ...additionalSystemTypes,
  };
  final unmapped = <String, String>{};
  final claimedBy = <String, String>{};

  for (final type in app.fileTypes) {
    if (type.isDeclared && systemTypes.contains(type.name)) {
      problems.add(
        '${type.name} is a type the system already maps, so declaring it '
        'would replace the description every file of that type shows on the '
        'machine. Name it with LinuxMimeType.registered instead',
      );
    }
    if (type.reason != null) {
      for (final extension in type.extensions) {
        unmapped[extension] = type.reason!;
      }
      continue;
    }
    for (final extension in <String>[
      ...type.extensions,
      ...?registeredExtensionsOf[type.name],
    ]) {
      final owner = claimedBy[extension];
      if (owner != null) {
        problems.add(
          '.$extension is claimed by both $owner and ${type.name}; which one '
          'wins is whichever package the MIME database read last',
        );
        continue;
      }
      claimedBy[extension] = type.name;
    }
  }

  for (final extension in registeredExtensions) {
    if (claimedBy.containsKey(extension) || unmapped.containsKey(extension)) {
      continue;
    }
    problems.add(
      '.$extension is registered on another platform but nothing on Linux '
      'maps it: declare a type for it, name the type the system already maps, '
      'or record it as deliberately unmapped with the reason',
    );
  }

  final entry = buildDesktopEntry(app, appImagePath: '/x.AppImage');
  final named = <String>{
    for (final line in entry.split('\n'))
      if (line.startsWith('MimeType='))
        ...line
            .substring('MimeType='.length)
            .split(';')
            .where((s) => s.isNotEmpty),
  };
  final xml = buildMimePackage(app) ?? '';
  for (final type in app.fileTypes) {
    if (type.reason != null) continue;
    if (!named.contains(type.name)) {
      problems.add(
        "${type.name} is not in the entry's MimeType= list, so nothing is "
        'offered for the files it maps',
      );
    }
    if (type.isDeclared && !xml.contains('type="${type.name}"')) {
      problems.add(
        '${type.name} is declared but missing from the installed package, so '
        'the entry names a type nothing resolves',
      );
    }
  }

  return LinuxMimeCoverage(
    problems: List<String>.unmodifiable(problems),
    deliberatelyUnmapped: Map<String, String>.unmodifiable(unmapped),
  );
}

/// What [checkLinuxMimeCoverage] found.
class LinuxMimeCoverage {
  /// Creates a coverage report.
  const LinuxMimeCoverage({
    required this.problems,
    required this.deliberatelyUnmapped,
  });

  /// One line per problem; empty when the associations are complete and
  /// consistent.
  final List<String> problems;

  /// Extension → the reason it is deliberately left to other applications.
  final Map<String, String> deliberatelyUnmapped;

  /// Whether nothing is wrong.
  bool get isComplete => problems.isEmpty;

  /// The report as a human-readable block, deliberate gaps included, for a
  /// test failure message.
  @override
  String toString() {
    final lines = <String>[
      ...problems.map((p) => 'problem: $p'),
      ...deliberatelyUnmapped.entries.map(
        (e) => 'deliberately unmapped: .${e.key} — ${e.value}',
      ),
    ];
    return lines.isEmpty ? 'every extension is mapped' : lines.join('\n');
  }
}
