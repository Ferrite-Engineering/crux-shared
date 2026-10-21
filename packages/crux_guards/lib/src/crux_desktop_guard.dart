// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crux_guards/src/dialog_sites.dart' show isTypeName;
import 'package:crux_guards/src/guard_types.dart';
import 'package:meta/meta.dart';

/// The raw Material patterns the Crux Desktop layer replaces.
enum CruxDesktopPattern {
  /// A `showDialog(...)` call without a target.
  showDialog('showDialog', 'showCruxDialog'),

  /// An `AlertDialog` (or `AlertDialog.adaptive`) construction.
  alertDialog('AlertDialog', 'CruxDialog'),

  /// A `SimpleDialog` construction.
  simpleDialog('SimpleDialog', 'CruxDialog'),

  /// A `SnackBar` construction.
  snackBar('SnackBar', 'showCruxInfoSnack / showCruxErrorSnack'),

  /// A `showSnackBar(...)` call on any target, cascades included.
  showSnackBar('showSnackBar', 'showCruxInfoSnack / showCruxErrorSnack'),

  /// `Icons.more_vert` and its outlined, rounded and sharp variants.
  moreVert('Icons.more_vert', 'CruxOverflowMenu (Icons.more_horiz)'),

  /// A Material `Switch` construction.
  materialSwitch('Switch', 'CruxSwitch'),

  /// A `SwitchListTile` (or `SwitchListTile.adaptive`) construction.
  switchListTile('SwitchListTile', 'CruxFormRow.toggle'),

  /// A `Switch.adaptive` construction.
  switchAdaptive('Switch.adaptive', 'CruxSwitch'),

  /// A `CheckboxListTile` (or `CheckboxListTile.adaptive`) construction.
  checkboxListTile('CheckboxListTile', 'CruxFormRow.checkbox'),

  /// A Material `SegmentedButton` construction.
  segmentedButton('SegmentedButton', 'CruxSegmentedControl'),

  /// A Material `DropdownButton` construction.
  dropdownButton('DropdownButton', 'CruxPopUpButton'),

  /// A Material `DropdownButtonFormField` construction.
  dropdownButtonFormField(
    'DropdownButtonFormField',
    'CruxPopUpButton (CruxPopUpFormField where a Form validates or saves it)',
  );

  const CruxDesktopPattern(this.id, this.replacement);

  /// The pattern as written in an allow-list file: `showDialog`,
  /// `Icons.more_vert`, `Switch.adaptive`.
  final String id;

  /// What replaces it, as named in findings.
  final String replacement;

  /// The pattern whose [id] is [id], or `null` when there is none.
  static CruxDesktopPattern? fromId(String id) {
    for (final pattern in values) {
      if (pattern.id == id) return pattern;
    }
    return null;
  }
}

/// The comment that marks a call site as rendering only in the phone layout,
/// where the raw Material pattern stays. A reason follows it on the same
/// line: `// crux-desktop: phone-only, the phone layout keeps Material 3`.
const String kCruxDesktopPhoneOnlyMarker = 'crux-desktop: phone-only';

/// One use of a [CruxDesktopPattern], as [cruxFindDesktopSites] reports it.
@immutable
final class CruxDesktopSite {
  /// Creates a site.
  const CruxDesktopSite({
    required this.path,
    required this.line,
    required this.pattern,
    required this.phoneOnly,
  });

  /// The file, as the sources name it.
  final String path;

  /// The 1-based line of the pattern's name.
  final int line;

  /// Which pattern it is.
  final CruxDesktopPattern pattern;

  /// Whether a [kCruxDesktopPhoneOnlyMarker] comment with a reason covers
  /// the site: above the site itself, or above an enclosing statement or
  /// expression, up to and including the enclosing class member or
  /// top-level declaration.
  final bool phoneOnly;

  @override
  String toString() =>
      '$path:$line (${pattern.id}${phoneOnly ? ', phone-only' : ''})';
}

/// Every use of a [CruxDesktopPattern] in [sources], phone-only sites
/// included.
///
/// Reads the syntax tree of each source (no resolution), so a mention in a
/// comment, a doc reference or a string is not a site. Both forms an
/// unresolved parse gives a construction count: `AlertDialog(...)` (a method
/// invocation) and `const AlertDialog(...)` (an instance creation), with or
/// without an import prefix.
List<CruxDesktopSite> cruxFindDesktopSites(
  Iterable<CruxGuardSource> sources,
) => _scan(sources).sites;

/// One file and pattern whose sites are known and not yet migrated, with how
/// many there are and why they have not moved.
@immutable
final class CruxDesktopAllowance {
  /// Creates an allowance.
  const CruxDesktopAllowance({
    required this.file,
    required this.pattern,
    required this.count,
    required this.reason,
  }) : assert(count >= 1, 'an allowance covers at least one site'),
       assert(reason != '', 'an allowance needs a reason');

  /// The file, as the sources name it.
  final String file;

  /// The pattern it allows.
  final CruxDesktopPattern pattern;

  /// Exactly how many unannotated sites of [pattern] the file holds.
  final int count;

  /// Why these sites have not moved onto the Crux Desktop layer yet.
  final String reason;

  @override
  String toString() => '$file | ${pattern.id} | $count | $reason';
}

/// Parses the allow-list file text.
///
/// Format, one entry per line, `|`-separated, `#` starts a comment line,
/// blank lines ignored:
///
/// ```text
/// lib/features/foo/foo_dialog.dart | showDialog | 2 | moves onto showCruxDialog with the rest of the foo dialogs
/// ```
///
/// Everything after the third `|` is the reason. Throws a [FormatException]
/// naming the line for a malformed line, an unknown pattern id, a count
/// below 1, an empty reason, or a second entry for the same file and
/// pattern.
List<CruxDesktopAllowance> cruxParseDesktopAllowList(String text) {
  final out = <CruxDesktopAllowance>[];
  final firstLine = <(String, CruxDesktopPattern), int>{};
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final number = i + 1;
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    FormatException fail(String why) =>
        FormatException('Crux Desktop allow-list line $number: $why', line);
    final parts = line.split('|');
    if (parts.length < 4) {
      throw fail('expected `file | pattern | count | reason`');
    }
    final file = parts[0].trim();
    if (file.isEmpty) throw fail('the file is empty');
    final id = parts[1].trim();
    final pattern = CruxDesktopPattern.fromId(id);
    if (pattern == null) {
      final known = CruxDesktopPattern.values.map((p) => p.id).join(', ');
      throw fail('unknown pattern `$id`; expected one of $known');
    }
    final count = int.tryParse(parts[2].trim());
    if (count == null || count < 1) {
      throw fail('the count must be a whole number of at least 1');
    }
    final reason = parts.sublist(3).join('|').trim();
    if (reason.isEmpty) throw fail('the reason is empty');
    final key = (file, pattern);
    final earlier = firstLine[key];
    if (earlier != null) {
      throw fail('a second entry for $file | $id (the first is line $earlier)');
    }
    firstLine[key] = number;
    out.add(
      CruxDesktopAllowance(
        file: file,
        pattern: pattern,
        count: count,
        reason: reason,
      ),
    );
  }
  return out;
}

/// Renders [sites] as allow-list text: one line per file and pattern with its
/// count, sorted by file then pattern id, each with [reason], so a product
/// can seed its file. Phone-only sites are left out; they need no entry.
///
/// Throws an [ArgumentError] when [reason] is empty or spans lines.
String cruxFormatDesktopAllowList(
  Iterable<CruxDesktopSite> sites, {
  required String reason,
}) {
  final why = reason.trim();
  if (why.isEmpty || why.contains('\n')) {
    throw ArgumentError.value(reason, 'reason', 'must be one non-empty line');
  }
  final counts = <(String, CruxDesktopPattern), int>{};
  for (final site in sites) {
    if (site.phoneOnly) continue;
    final key = (site.path, site.pattern);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byFile = a.$1.compareTo(b.$1);
      return byFile != 0 ? byFile : a.$2.id.compareTo(b.$2.id);
    });
  final buffer = StringBuffer();
  for (final key in keys) {
    buffer.writeln('${key.$1} | ${key.$2.id} | ${counts[key]} | $why');
  }
  return buffer.toString();
}

/// No raw Material pattern the Crux Desktop layer replaces, outside a
/// phone-only call site or a shrinking allow-list.
///
/// The desktop layout uses the Crux Desktop widgets (`showCruxDialog`,
/// `CruxDialog`, the Crux snack helpers, `CruxOverflowMenu`, `CruxSwitch`,
/// `CruxFormRow`, `CruxSegmentedControl`, `CruxPopUpButton`); every
/// [CruxDesktopPattern] site in [sources] is a finding
/// that names its replacement, unless:
///
/// - **it is phone-only**: a `//` or `///` comment holding
///   [kCruxDesktopPhoneOnlyMarker] and a reason sits directly above the site,
///   or above an enclosing statement or expression, up to and including its
///   class member or top-level declaration. A marker covers a call site, never
///   a whole file or class; or
/// - **an allowance absorbs it**: [allowances] names its file and pattern with
///   the exact number of unannotated sites the file holds.
///
/// **Exact accounting.** A site over an allowance's count is a finding; a
/// count above the sites found is a finding that says what to lower it to; an
/// allowance with no site is a finding; a marker without a reason is a
/// finding (and covers nothing); a marker that covers no site is a finding.
/// [CruxGuardResult.matchesSeen] is every site found, exempted or not.
///
/// **What it cannot see.** The scan is unresolved, so a pattern reached
/// through a typedef, a re-export under another name or a helper declared
/// outside [sources] is invisible, and a same-named product declaration
/// counts as the pattern.
CruxGuardResult cruxAuditCruxDesktop({
  required Iterable<CruxGuardSource> sources,
  Iterable<CruxDesktopAllowance> allowances = const <CruxDesktopAllowance>[],
}) {
  final files = sources.toList();
  final scan = _scan(files);
  final findings = <CruxGuardFinding>[];

  final allowed = <(String, CruxDesktopPattern), CruxDesktopAllowance>{};
  for (final a in allowances) {
    final key = (a.file, a.pattern);
    if (allowed.containsKey(key)) {
      findings.add(
        CruxGuardFinding(
          path: a.file,
          line: 0,
          detail:
              'a second allowance for ${a.pattern.id}: keep one entry per '
              'file and pattern.',
        ),
      );
      continue;
    }
    allowed[key] = a;
  }

  final groups = <(String, CruxDesktopPattern), List<CruxDesktopSite>>{};
  for (final site in scan.sites) {
    if (site.phoneOnly) continue;
    groups
        .putIfAbsent((site.path, site.pattern), () => <CruxDesktopSite>[])
        .add(site);
  }

  for (final MapEntry(:key, value: group) in groups.entries) {
    final allowance = allowed.remove(key);
    final pattern = key.$2;
    if (allowance == null) {
      for (final site in group) {
        findings.add(
          CruxGuardFinding(
            path: site.path,
            line: site.line,
            detail:
                '${pattern.id} is a raw Material pattern the Crux Desktop '
                'layer replaces: use ${pattern.replacement}. If this call '
                'site renders only in the phone layout, put '
                '`// $kCruxDesktopPhoneOnlyMarker, <why>` on the line above '
                'its statement or member.',
          ),
        );
      }
      continue;
    }
    final n = allowance.count;
    if (group.length > n) {
      for (final site in group.skip(n)) {
        findings.add(
          CruxGuardFinding(
            path: site.path,
            line: site.line,
            detail:
                '${pattern.id} is over the allow-list count: the entry '
                'allows $n and the file has ${group.length}. Use '
                '${pattern.replacement} for the new site, or, if it renders '
                'only in the phone layout, put '
                '`// $kCruxDesktopPhoneOnlyMarker, <why>` on the line above '
                'its statement or member.',
          ),
        );
      }
    } else if (group.length < n) {
      findings.add(
        CruxGuardFinding(
          path: allowance.file,
          line: 0,
          detail:
              'allow-list entry for ${pattern.id} allows $n but the file has '
              '${group.length}: lower the count to ${group.length}.',
        ),
      );
    }
  }

  for (final allowance in allowed.values) {
    findings.add(
      CruxGuardFinding(
        path: allowance.file,
        line: 0,
        detail:
            'allow-list entry for ${allowance.pattern.id} matches no site: '
            'the count is now 0, so remove the entry.',
      ),
    );
  }

  findings.addAll(scan.markerFindings);
  return CruxGuardResult(
    findings: findings,
    filesScanned: files.length,
    matchesSeen: scan.sites.length,
  );
}

/// The construction patterns, by the type name an unresolved parse sees.
const Map<String, CruxDesktopPattern> _constructorPatterns =
    <String, CruxDesktopPattern>{
      'AlertDialog': CruxDesktopPattern.alertDialog,
      'SimpleDialog': CruxDesktopPattern.simpleDialog,
      'SnackBar': CruxDesktopPattern.snackBar,
      'Switch': CruxDesktopPattern.materialSwitch,
      'SwitchListTile': CruxDesktopPattern.switchListTile,
      'CheckboxListTile': CruxDesktopPattern.checkboxListTile,
      'SegmentedButton': CruxDesktopPattern.segmentedButton,
      'DropdownButton': CruxDesktopPattern.dropdownButton,
      'DropdownButtonFormField': CruxDesktopPattern.dropdownButtonFormField,
    };

/// The `Icons` members [CruxDesktopPattern.moreVert] matches.
const Set<String> _moreVertIcons = <String>{
  'more_vert',
  'more_vert_outlined',
  'more_vert_rounded',
  'more_vert_sharp',
};

/// The pattern a construction of [type] through constructor [constructor]
/// (`null` for the unnamed one) is, if any.
CruxDesktopPattern? _constructionPattern(String type, String? constructor) {
  final pattern = _constructorPatterns[type];
  if (pattern == null) return null;
  if (constructor == null) return pattern;
  if (constructor != 'adaptive') return null;
  return pattern == CruxDesktopPattern.materialSwitch
      ? CruxDesktopPattern.switchAdaptive
      : pattern;
}

({List<CruxDesktopSite> sites, List<CruxGuardFinding> markerFindings}) _scan(
  Iterable<CruxGuardSource> sources,
) {
  final sites = <CruxDesktopSite>[];
  final markerFindings = <CruxGuardFinding>[];
  for (final file in sources) {
    final unit = parseString(
      content: file.source,
      throwIfDiagnostics: false,
    ).unit;
    final markers = _markersIn(unit);
    final used = <int>{};
    final visitor = _DesktopVisitor();
    unit.accept(visitor);
    for (final (node, nameOffset, pattern) in visitor.found) {
      final marker = _coveringMarker(node, markers);
      if (marker != null) used.add(marker.offset);
      sites.add(
        CruxDesktopSite(
          path: file.path,
          line: lineOf(file.source, nameOffset),
          pattern: pattern,
          phoneOnly: marker != null && marker.hasReason,
        ),
      );
    }
    for (final marker in markers.values) {
      if (!marker.hasReason) {
        markerFindings.add(
          CruxGuardFinding(
            path: file.path,
            line: lineOf(file.source, marker.offset),
            detail:
                'the $kCruxDesktopPhoneOnlyMarker marker has no reason, so '
                'it covers nothing: write why the site renders only in the '
                'phone layout after it, '
                '`// $kCruxDesktopPhoneOnlyMarker, <why>`.',
          ),
        );
      } else if (!used.contains(marker.offset)) {
        markerFindings.add(
          CruxGuardFinding(
            path: file.path,
            line: lineOf(file.source, marker.offset),
            detail:
                'the $kCruxDesktopPhoneOnlyMarker marker covers no Crux '
                'Desktop site: the site moved, was migrated, or another '
                'marker nearer to it covers it. Remove the marker.',
          ),
        );
      }
    }
  }
  return (sites: sites, markerFindings: markerFindings);
}

@immutable
final class _Marker {
  const _Marker(this.offset, {required this.hasReason});

  final int offset;
  final bool hasReason;
}

/// Every `//` or `///` comment in [unit] holding the marker, by offset.
Map<int, _Marker> _markersIn(CompilationUnit unit) {
  final out = <int, _Marker>{};
  Token? token = unit.beginToken;
  while (token != null) {
    Token? comment = token.precedingComments;
    while (comment is CommentToken) {
      final text = comment.lexeme;
      final at = text.indexOf(kCruxDesktopPhoneOnlyMarker);
      if (text.startsWith('//') && at >= 0) {
        final rest = text
            .substring(at + kCruxDesktopPhoneOnlyMarker.length)
            .replaceFirst(RegExp(r'^[\s,;:.\-]+'), '')
            .trim();
        out[comment.offset] = _Marker(
          comment.offset,
          hasReason: rest.isNotEmpty,
        );
      }
      comment = comment.next;
    }
    if (token.type == TokenType.EOF) break;
    token = token.next;
  }
  return out;
}

/// The nearest marker above [node] or one of its ancestors, up to and
/// including the enclosing class member or top-level declaration.
_Marker? _coveringMarker(AstNode node, Map<int, _Marker> markers) {
  if (markers.isEmpty) return null;
  for (AstNode? n = node; n != null; n = n.parent) {
    for (final token in _leadingTokens(n)) {
      Token? comment = token.precedingComments;
      while (comment is CommentToken) {
        final marker = markers[comment.offset];
        if (marker != null) return marker;
        comment = comment.next;
      }
    }
    if (n is ClassMember ||
        (n is CompilationUnitMember && n.parent is CompilationUnit)) {
      return null;
    }
  }
  return null;
}

/// The tokens whose preceding comments sit above [node]: its first token,
/// or for a declaration each annotation and the first token after them
/// (where the doc comment and any line comments are attached).
Iterable<Token> _leadingTokens(AstNode node) sync* {
  if (node is AnnotatedNode) {
    for (final annotation in node.metadata) {
      yield annotation.beginToken;
    }
    yield node.firstTokenAfterCommentAndMetadata;
  } else {
    yield node.beginToken;
  }
}

class _DesktopVisitor extends RecursiveAstVisitor<void> {
  /// Each site's node, the offset of its name, and its pattern.
  final List<(AstNode, int, CruxDesktopPattern)> found =
      <(AstNode, int, CruxDesktopPattern)>[];

  @override
  void visitComment(Comment node) {
    // A doc comment's `[Icons.more_vert]` reference is prose, not a use.
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final pattern = _invocationPattern(node);
    if (pattern != null) found.add((node, node.methodName.offset, pattern));
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final named = node.constructorName;
    final prefix = named.type.importPrefix?.name.lexeme;
    final name = named.type.name.lexeme;
    final constructor = named.name?.name;
    // Unresolved, `const Switch.adaptive()` reads as type `adaptive` with
    // import prefix `Switch`; a capitalised prefix is the type.
    final pattern = prefix != null && constructor == null && isTypeName(prefix)
        ? _constructionPattern(prefix, name)
        : _constructionPattern(name, constructor);
    if (pattern != null) found.add((node, named.offset, pattern));
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'Icons' &&
        _moreVertIcons.contains(node.identifier.name)) {
      found.add((node, node.offset, CruxDesktopPattern.moreVert));
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    final onIcons = switch (target) {
      SimpleIdentifier(:final name) => name == 'Icons',
      PrefixedIdentifier(:final identifier) => identifier.name == 'Icons',
      _ => false,
    };
    if (onIcons && _moreVertIcons.contains(node.propertyName.name)) {
      found.add((node, node.offset, CruxDesktopPattern.moreVert));
    }
    super.visitPropertyAccess(node);
  }

  CruxDesktopPattern? _invocationPattern(MethodInvocation node) {
    final name = node.methodName.name;
    final target = node.target;
    if (name == 'showSnackBar') return CruxDesktopPattern.showSnackBar;
    if (target == null && !node.isCascaded) {
      if (name == 'showDialog') return CruxDesktopPattern.showDialog;
      return _constructionPattern(name, null);
    }
    switch (target) {
      // `Switch.adaptive(...)`, or `m.AlertDialog(...)` through a prefix.
      case SimpleIdentifier(name: final t):
        return isTypeName(t)
            ? _constructionPattern(t, name)
            : _constructionPattern(name, null);
      // `m.Switch.adaptive(...)`.
      case PrefixedIdentifier(:final prefix, :final identifier)
          when !isTypeName(prefix.name):
        return _constructionPattern(identifier.name, name);
      default:
        return null;
    }
  }
}
