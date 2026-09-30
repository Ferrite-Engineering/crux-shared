// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates a deterministic, human-readable snapshot of the public API surface
// of every crux-shared package.
//
// Each package exposes exactly one barrel (`lib/<package>.dart`). The snapshot
// is that barrel's *export namespace* — precisely the set of symbols a consumer
// can reach — rendered as sorted, signature-bearing lines. Committing the
// snapshots and diffing them in CI turns "somebody changed the substrate under
// eight repos" from an invisible event into a reviewable diff.
//
// Usage (always via tool/api-snapshot.sh):
//   dart run bin/api_snapshot.dart --write    # regenerate goldens
//   dart run bin/api_snapshot.dart --check    # fail if goldens are stale
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;

/// Directory (relative to the repo root) holding the committed goldens.
const goldenDir = 'api';

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

/// Returns the process exit code. Kept separate from `main` because Dart
/// ignores a value returned from `main` — a guard that reports a violation and
/// still exits 0 is worse than no guard at all.
Future<int> _run(List<String> args) async {
  final write = args.contains('--write');
  final check = args.contains('--check');
  if (write == check) {
    stderr.writeln('usage: api_snapshot.dart (--write | --check)');
    return 64;
  }

  // bin/ -> api_snapshot/ -> tool/ -> repo root.
  final repoRoot = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..', '..', '..'),
  );
  final packagesDir = Directory(p.join(repoRoot, 'packages'));
  if (!packagesDir.existsSync()) {
    stderr.writeln('no packages/ directory under $repoRoot');
    return 66;
  }

  final packages =
      packagesDir
          .listSync()
          .whereType<Directory>()
          .map((d) => p.basename(d.path))
          .where((n) => !n.startsWith('.'))
          .toList()
        ..sort();

  // A package's MAIN barrel is `lib/<name>.dart` and is mandatory.
  //
  // A package may also expose SECONDARY barrels — further top-level
  // `lib/*.dart` entry points that let a constrained host import a subset
  // without the dependency the main barrel drags in
  // (`crux_license/lib/crux_license_core.dart` keeps `dart:ui` out of a
  // headless AOT kernel; `crux_sqlite`'s test-support barrels keep tooling out
  // of the runtime surface). A consumer can import those, so they are public API
  // by exactly the same definition and get their own golden. Snapshotting only
  // `lib/<name>.dart` left them untracked.
  final barrels = <_Barrel>[];
  final missingBarrels = <String>[];
  for (final name in packages) {
    final libDir = Directory(p.join(packagesDir.path, name, 'lib'));
    final barrel = p.join(libDir.path, '$name.dart');
    if (!File(barrel).existsSync()) {
      // A package with no barrel would silently escape API tracking, which is
      // exactly the blind spot this tool exists to close.
      if (libDir.existsSync()) missingBarrels.add(name);
      continue;
    }
    barrels.add(_Barrel(name, '$name.dart', barrel));
    final secondary =
        libDir
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where((b) => b.endsWith('.dart') && b != '$name.dart')
            .toList()
          ..sort();
    for (final base in secondary) {
      barrels.add(_Barrel(name, base, p.join(libDir.path, base)));
    }
  }
  if (missingBarrels.isNotEmpty) {
    stderr.writeln(
      'ERROR: package(s) with a lib/ but no lib/<name>.dart barrel, so their '
      'public API cannot be snapshotted: ${missingBarrels.join(', ')}. '
      'Every crux-shared package exposes a main barrel.',
    );
    return 65;
  }

  final collection = AnalysisContextCollection(
    includedPaths: [for (final b in barrels) b.path],
  );

  var stale = 0;
  for (final barrel in barrels) {
    final session = collection.contextFor(barrel.path).currentSession;
    final result = await session.getResolvedLibrary(barrel.path);
    if (result is! ResolvedLibraryResult) {
      stderr.writeln('ERROR: could not resolve ${barrel.path}: $result');
      return 65;
    }
    final rendered = _renderLibrary(barrel.importUri, result.element);
    final goldenPath = p.join(repoRoot, goldenDir, barrel.goldenName);
    final golden = File(goldenPath);

    if (write) {
      golden.parent.createSync(recursive: true);
      golden.writeAsStringSync(rendered);
      stdout.writeln('wrote $goldenDir/${barrel.goldenName}');
    } else {
      final existing = golden.existsSync() ? golden.readAsStringSync() : null;
      if (existing != rendered) {
        stale++;
        stdout.writeln(
          existing == null
              ? 'MISSING golden: $goldenDir/${barrel.goldenName}'
              : 'CHANGED public API: ${barrel.importUri}',
        );
      }
    }
  }

  if (check && stale > 0) {
    stdout
      ..writeln('')
      ..writeln(
        '$stale package(s) have a public API differing from the '
        'committed golden.',
      )
      ..writeln('If the change is intentional, run:')
      ..writeln('    tool/api-snapshot.sh --write')
      ..writeln(
        'and commit the updated api/*.api.txt files. Review the diff: '
        'a removed or re-signatured line is a breaking change for all four '
        'products.',
      );
    return 1;
  }
  return 0;
}

/// One snapshotted entry point: the package it belongs to, the library file,
/// and the golden that records it.
class _Barrel {
  _Barrel(this.package, this.basename, this.path);

  final String package;

  /// The barrel's file name, e.g. `crux_license.dart` or
  /// `crux_license_core.dart`.
  final String basename;
  final String path;

  /// What a consumer writes to reach this entry point.
  String get importUri => 'package:$package/$basename';

  /// `<barrel basename without .dart>.api.txt`. Barrel basenames are
  /// package-prefixed by convention, so this is unique across the repo.
  String get goldenName =>
      '${basename.substring(0, basename.length - '.dart'.length)}.api.txt';
}

String _renderLibrary(String importUri, LibraryElement library) {
  final lines = <String>[];
  final namespace = library.exportNamespace.definedNames2;
  final names = namespace.keys.toList()..sort();

  for (final name in names) {
    if (name.startsWith('_')) continue;
    final element = namespace[name]!;
    lines.addAll(_renderTopLevel(name, element));
  }

  final buffer = StringBuffer()
    ..writeln('# Public API surface of $importUri')
    ..writeln('#')
    ..writeln('# GENERATED — do not edit by hand.')
    ..writeln('# Regenerate with: tool/api-snapshot.sh --write')
    ..writeln('#')
    ..writeln(
      '# Every line is a symbol a consuming product can reach. A line '
      'that',
    )
    ..writeln('# disappears or changes shape is a breaking change for all four')
    ..writeln(
      '# products; a line that appears is new public surface to '
      'justify.',
    )
    ..writeln('');
  for (final line in lines) {
    buffer.writeln(line);
  }
  return buffer.toString();
}

List<String> _renderTopLevel(String name, Element element) {
  switch (element) {
    case ClassElement():
      return _renderInterface(
        _classKeyword(element),
        element,
        supertypes: _supertypes(element),
      );
    case EnumElement():
      return _renderInterface(
        'enum',
        element,
        supertypes: _supertypes(element),
      );
    case MixinElement():
      return _renderInterface(
        'mixin',
        element,
        supertypes: _supertypes(element),
      );
    case ExtensionTypeElement():
      return _renderInterface(
        'extension type',
        element,
        supertypes: _supertypes(element),
      );
    case ExtensionElement():
      final header =
          'extension $name${_typeParams(element.typeParameters)} '
          'on ${_type(element.extendedType)}';
      return [header, ..._members(header, element)];
    case TypeAliasElement():
      return [
        'typedef $name${_typeParams(element.typeParameters)} = '
            '${_type(element.aliasedType)}',
      ];
    case TopLevelFunctionElement():
      return [
        '$name${_typeParams(element.typeParameters)}'
            '${_params(element.formalParameters)} -> '
            '${_type(element.returnType)}',
      ];
    case GetterElement():
      return ['get $name -> ${_type(element.returnType)}'];
    case SetterElement():
      return ['set $name${_params(element.formalParameters)}'];
    case TopLevelVariableElement():
      return [
        '${element.isConst ? 'const' : 'var'} $name: '
            '${_type(element.type)}',
      ];
    default:
      return ['$name: ${element.runtimeType}'];
  }
}

String _classKeyword(ClassElement e) {
  final parts = <String>[
    if (e.isSealed) 'sealed',
    if (e.isFinal) 'final',
    if (e.isInterface) 'interface',
    if (e.isBase) 'base',
    if (e.isMixinClass) 'mixin',
    if (e.isAbstract && !e.isSealed) 'abstract',
    'class',
  ];
  return parts.join(' ');
}

String _supertypes(InterfaceElement e) {
  final parts = <String>[];
  if (e is ClassElement) {
    final sup = e.supertype;
    if (sup != null && !sup.isDartCoreObject) {
      parts.add('extends ${_type(sup)}');
    }
    final mixins = e.mixins.map(_type).toList()..sort();
    if (mixins.isNotEmpty) parts.add('with ${mixins.join(', ')}');
  }
  final interfaces = e.interfaces.map(_type).toList()..sort();
  if (interfaces.isNotEmpty) parts.add('implements ${interfaces.join(', ')}');
  return parts.isEmpty ? '' : ' ${parts.join(' ')}';
}

List<String> _renderInterface(
  String keyword,
  InstanceElement element, {
  String supertypes = '',
}) {
  final header =
      '$keyword ${element.name}'
      '${_typeParams(element.typeParameters)}$supertypes';
  return [header, ..._members(header, element)];
}

List<String> _members(String header, InstanceElement element) {
  final out = <String>[];
  final prefix = '  ';

  if (element is InterfaceElement) {
    final ctors = <String>[];
    for (final c in element.constructors) {
      if (c.isPrivate || c.isSynthetic) continue;
      final label = c.name == 'new' || (c.name ?? '').isEmpty
          ? element.name
          : '${element.name}.${c.name}';
      ctors.add(
        '$prefix${c.isConst ? 'const ' : ''}'
        '${c.isFactory ? 'factory ' : ''}$label${_params(c.formalParameters)}',
      );
    }
    ctors.sort();
    out.addAll(ctors);
  }

  final members = <String>[];
  for (final f in element.fields) {
    if (f.isPrivate || f.isSynthetic) continue;
    members.add(
      '$prefix${f.isStatic ? 'static ' : ''}'
      '${f.isConst ? 'const ' : (f.isFinal ? 'final ' : 'var ')}'
      '${f.name}: ${_type(f.type)}',
    );
  }
  for (final g in element.getters) {
    if (g.isPrivate || g.isSynthetic) continue;
    members.add(
      '$prefix${g.isStatic ? 'static ' : ''}get ${g.name} -> '
      '${_type(g.returnType)}',
    );
  }
  for (final s in element.setters) {
    if (s.isPrivate || s.isSynthetic) continue;
    members.add(
      '$prefix${s.isStatic ? 'static ' : ''}set ${s.name}'
      '${_params(s.formalParameters)}',
    );
  }
  for (final m in element.methods) {
    if (m.isPrivate || m.isSynthetic) continue;
    members.add(
      '$prefix${m.isStatic ? 'static ' : ''}${m.name}'
      '${_typeParams(m.typeParameters)}${_params(m.formalParameters)} -> '
      '${_type(m.returnType)}',
    );
  }
  members.sort();
  out.addAll(members);
  return out;
}

String _typeParams(List<TypeParameterElement> params) {
  if (params.isEmpty) return '';
  final rendered = params.map((p) {
    final bound = p.bound;
    return bound == null ? p.name : '${p.name} extends ${_type(bound)}';
  });
  return '<${rendered.join(', ')}>';
}

String _params(List<FormalParameterElement> params) {
  final required = <String>[];
  final positional = <String>[];
  final named = <String>[];
  for (final param in params) {
    final base = '${_type(param.type)} ${param.name ?? ''}'.trim();
    if (param.isNamed) {
      named.add('${param.isRequired ? 'required ' : ''}$base');
    } else if (param.isOptionalPositional) {
      positional.add(base);
    } else {
      required.add(base);
    }
  }
  named.sort();
  final parts = <String>[
    ...required,
    if (positional.isNotEmpty) '[${positional.join(', ')}]',
    if (named.isNotEmpty) '{${named.join(', ')}}',
  ];
  return '(${parts.join(', ')})';
}

String _type(DartType type) => type.getDisplayString();
