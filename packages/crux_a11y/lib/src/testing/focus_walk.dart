// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a desktop screen reader hears when keyboard focus lands somewhere.
///
/// The fields mirror what the desktop accessibility bridge
/// (`shell/platform/common/accessibility_bridge.cc`) hands to the platform:
/// the semantics label becomes the accessible name, the value stays the
/// value, the tooltip becomes the description, and the role is derived from
/// the flags in the same order the bridge checks them. The bridge drops the
/// semantics hint entirely, so a hint is never heard and is not recorded.
@immutable
class FocusStop {
  /// Creates a stop record.
  const FocusStop({
    required this.spoken,
    required this.name,
    required this.value,
    required this.description,
    required this.role,
    required this.states,
    required this.entered,
    required this.focusTarget,
  });

  /// Whether any semantics node reports focus. When false the bridge sends
  /// no focus event and the screen reader says nothing at all.
  final bool spoken;

  /// The accessible name (the semantics label), whitespace collapsed.
  final String name;

  /// The accessible value.
  final String value;

  /// The accessible description (the semantics tooltip).
  final String description;

  /// The role the bridge assigns: `button`, `edit`, `heading`, `graphic`,
  /// `link`, `radio button`, `check box`, `switch`, `slider`, `text`, or
  /// `grouping`.
  final String role;

  /// State words in the order they are spoken, for example `checked` or
  /// `collapsed`.
  final List<String> states;

  /// Named containers focus moved into on the way to this stop, outermost
  /// first, each rendered as `<name> <role>`.
  final List<String> entered;

  /// The focused widget and its focus node, for diagnosing a bad stop.
  final String focusTarget;

  /// True when the stop is announced with no name, value, or description:
  /// the screen reader says only `text` or `grouping`.
  bool get isNameless => name.isEmpty && value.isEmpty && description.isEmpty;

  /// One transcript line.
  ///
  /// A control with only a tooltip is spoken under the tooltip, because the
  /// Windows bridge folds the tooltip into the accessible name when the
  /// label is empty; a tooltip beside a label is shown after a dash.
  String get line {
    if (!spoken) return '(silent)';
    final spokenName = name.isEmpty ? description : name;
    final parts = <String>[
      ...entered.map((e) => '[$e]'),
      if (spokenName.isNotEmpty) spokenName,
      role,
      ...states,
      if (value.isNotEmpty) value,
      if (name.isNotEmpty && description.isNotEmpty && description != name)
        '— $description',
    ];
    return parts.join(' ');
  }

  @override
  String toString() => '$line  <$focusTarget>';
}

/// Properties of a walk that a screen reader user experiences as defects.
enum FocusWalkRule {
  /// Focus moved but no semantics node reports it, so nothing is announced.
  silentStop,

  /// A stop is announced as a bare role: `text`, `grouping`, `check box`.
  namelessStop,

  /// A stop carries a name and a description that are different strings,
  /// so one control is announced under two names.
  twoNames,

  /// A named container repeats the name of the control it holds.
  containerRepeatsName,

  /// A name contains a glyph desktop speech engines do not read, such as an
  /// arrow, which is spoken as a question mark or skipped.
  unspeakableGlyph,

  /// Tab never returned to the first stop, so there is a trap or the order
  /// is longer than the walk allowed.
  noCycle,

  /// Focus landed on a widget that lies outside the window.
  offscreenStop,
}

/// One rule violation found in a walk.
@immutable
class FocusWalkProblem {
  /// Creates a problem report.
  const FocusWalkProblem(this.rule, this.stopIndex, this.detail);

  /// The rule that failed.
  final FocusWalkRule rule;

  /// 1-based stop number, or 0 for a whole-walk problem.
  final int stopIndex;

  /// Human-readable explanation, including the stop.
  final String detail;

  @override
  String toString() => stopIndex == 0
      ? '${rule.name}: $detail'
      : '${rule.name} at stop '
            '$stopIndex: $detail';
}

/// The sequence of stops produced by pressing Tab (or Shift+Tab) repeatedly.
@immutable
class FocusWalk {
  /// Creates a walk record.
  const FocusWalk({
    required this.stops,
    required this.cycled,
    required this.reverse,
    required this.offscreen,
  });

  /// The stops, in the order they were reached.
  final List<FocusStop> stops;

  /// Whether the walk returned to its first stop.
  final bool cycled;

  /// Whether the walk used Shift+Tab.
  final bool reverse;

  /// 1-based indexes of stops whose widget lies outside the window.
  final Set<int> offscreen;

  /// The walk as a numbered transcript, one stop per line.
  String get transcript {
    final b = StringBuffer()
      ..writeln(
        '# ${reverse ? 'Shift+Tab' : 'Tab'} walk: ${stops.length} stops, '
        '${cycled ? 'cycles' : 'does not cycle'}',
      );
    for (var i = 0; i < stops.length; i++) {
      b.writeln('${i + 1}. ${stops[i].line}');
    }
    return b.toString();
  }

  /// Every rule violation in the walk, minus the rules in [ignore].
  List<FocusWalkProblem> problems({
    Set<FocusWalkRule> ignore = const <FocusWalkRule>{},
  }) {
    final out = <FocusWalkProblem>[];
    void add(FocusWalkRule rule, int index, String detail) {
      if (!ignore.contains(rule)) {
        out.add(FocusWalkProblem(rule, index, detail));
      }
    }

    if (!cycled) {
      add(
        FocusWalkRule.noCycle,
        0,
        'focus did not return to the first stop after ${stops.length} stops',
      );
    }
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      final n = i + 1;
      if (!s.spoken) {
        add(FocusWalkRule.silentStop, n, '$s');
        continue;
      }
      if (s.isNameless) {
        add(FocusWalkRule.namelessStop, n, '$s');
      }
      // Two names means two unrelated strings ("Stats" / "Show Statistics").
      // A description that contains the name — a shortcut suffix, a tab's
      // full path — adds to the name rather than competing with it.
      if (s.name.isNotEmpty &&
          s.description.isNotEmpty &&
          !_norm(s.description).contains(_norm(s.name)) &&
          !_norm(s.name).contains(_norm(s.description))) {
        add(FocusWalkRule.twoNames, n, '$s');
      }
      final own = <String>{
        if (s.name.isNotEmpty) _norm(s.name),
        if (s.description.isNotEmpty) _norm(s.description),
      };
      // Exact repetition only: a row-specific name that contains its
      // container's name ("Close sample.vcd" inside "sample.vcd") is good
      // practice, not a defect.
      for (final container in s.entered) {
        final label = _norm(container.substring(0, container.lastIndexOf(' ')));
        if (own.contains(label)) {
          add(FocusWalkRule.containerRepeatsName, n, '$s');
          break;
        }
      }
      if (_unspeakable.hasMatch('${s.name} ${s.value} ${s.description}')) {
        add(FocusWalkRule.unspeakableGlyph, n, '$s');
      }
      if (offscreen.contains(n)) {
        add(FocusWalkRule.offscreenStop, n, '$s');
      }
    }
    return out;
  }
}

/// Arrows, box drawing, geometric shapes and the private use area: glyphs
/// that desktop speech engines read as a question mark or skip.
final RegExp _unspeakable = RegExp(
  '[←-⇿─-◿⟰-⟿⤀-⥿-]',
);

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

Iterable<SemanticsNode> _roots(WidgetTester tester) sync* {
  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) yield root;
  }
}

List<SemanticsNode> _focusedNodes(WidgetTester tester) {
  final found = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.isMergedIntoParent) return;
    if (node.getSemanticsData().flagsCollection.isFocused ==
        ui.Tristate.isTrue) {
      found.add(node);
    }
    node
        .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
        .forEach(visit);
  }

  _roots(tester).forEach(visit);
  return found;
}

bool _hasUnmergedChildren(SemanticsNode node) {
  var any = false;
  node.visitChildren((child) {
    if (!child.isMergedIntoParent) any = true;
    return !any;
  });
  return any;
}

String _roleOf(SemanticsNode node, SemanticsData d) {
  final f = d.flagsCollection;
  if (f.isButton) return 'button';
  if (f.isTextField && !f.isReadOnly) return 'edit';
  if (f.isHeader) return 'heading';
  if (f.isImage) return 'graphic';
  if (f.isLink) return 'link';
  if (f.isInMutuallyExclusiveGroup && f.isChecked != ui.CheckedState.none) {
    return 'radio button';
  }
  if (f.isChecked != ui.CheckedState.none) return 'check box';
  if (f.isToggled != ui.Tristate.none) return 'switch';
  if (f.isSlider) return 'slider';
  return _hasUnmergedChildren(node) ? 'grouping' : 'text';
}

List<String> _statesOf(SemanticsData d) {
  final f = d.flagsCollection;
  return <String>[
    if (f.isEnabled == ui.Tristate.isFalse) 'unavailable',
    if (f.isExpanded == ui.Tristate.isTrue) 'expanded',
    if (f.isExpanded == ui.Tristate.isFalse) 'collapsed',
    if (f.isChecked == ui.CheckedState.isTrue) 'checked',
    if (f.isChecked == ui.CheckedState.isFalse) 'not checked',
    if (f.isChecked == ui.CheckedState.mixed) 'half checked',
    if (f.isToggled == ui.Tristate.isTrue) 'on',
    if (f.isToggled == ui.Tristate.isFalse) 'off',
    if (f.isSelected == ui.Tristate.isTrue) 'selected',
  ];
}

String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

List<SemanticsNode> _namedAncestors(SemanticsNode node) {
  final chain = <SemanticsNode>[];
  var cur = node.parent;
  while (cur != null) {
    if (cur.getSemanticsData().label.trim().isNotEmpty) chain.add(cur);
    cur = cur.parent;
  }
  return chain.reversed.toList();
}

/// Framework plumbing that says nothing about which control a focus node
/// belongs to.
const Set<String> _plumbing = <String>{
  'Actions',
  'AnimatedBuilder',
  'Builder',
  'CallbackShortcuts',
  'ConstrainedBox',
  'Container',
  'DefaultSelectionStyle',
  'DefaultTextStyle',
  'ExcludeFocus',
  'ExcludeSemantics',
  'Focus',
  'FocusScope',
  'FocusTraversalGroup',
  'FocusableActionDetector',
  'IconTheme',
  'KeyedSubtree',
  'ListenableBuilder',
  'Listener',
  'Material',
  'MergeSemantics',
  'MouseRegion',
  'Padding',
  'RawGestureDetector',
  'RepaintBoundary',
  'Semantics',
  'Shortcuts',
  'SizedBox',
  'Tooltip',
};

String _describeFocusTarget(FocusNode? node) {
  if (node == null) return 'no primary focus';
  final context = node.context;
  if (context == null) return 'no context';
  final chain = <String>[];
  context.visitAncestorElements((element) {
    final type = element.widget.runtimeType.toString();
    if (!_plumbing.contains(type) && !type.startsWith('_')) chain.add(type);
    return chain.length < 3;
  });
  final label = node.debugLabel == null ? '' : ' "${node.debugLabel}"';
  return '${context.widget.runtimeType}$label in ${chain.join(' < ')}';
}

/// Describes where keyboard focus is right now, as a screen reader hears it.
///
/// [previous] lists the named containers of the stop before, so only the
/// containers newly entered are reported; pass nothing for a first stop.
FocusStop describeFocus(
  WidgetTester tester, {
  List<SemanticsNode> previous = const <SemanticsNode>[],
}) {
  final focusTarget = _describeFocusTarget(FocusManager.instance.primaryFocus);
  final focused = _focusedNodes(tester);
  if (focused.isEmpty) {
    return FocusStop(
      spoken: false,
      name: '',
      value: '',
      description: '',
      role: '',
      states: const <String>[],
      entered: const <String>[],
      focusTarget: focusTarget,
    );
  }
  final node = focused.last;
  final d = node.getSemanticsData();
  final ancestors = _namedAncestors(node);
  return FocusStop(
    spoken: true,
    name: _collapse(d.label),
    value: _collapse(d.value),
    description: _collapse(d.tooltip),
    role: _roleOf(node, d),
    states: _statesOf(d),
    entered: <String>[
      for (final a in ancestors)
        if (!previous.contains(a))
          [
            _collapse(a.getSemanticsData().label),
            _roleOf(a, a.getSemanticsData()),
          ].join(' '),
    ],
    focusTarget: focusTarget,
  );
}

Future<void> _pressTab(WidgetTester tester, {required bool reverse}) async {
  if (reverse) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (reverse) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

/// Presses Tab (or Shift+Tab when [reverse]) until focus returns to the
/// first stop or [maxStops] is reached, recording each stop.
///
/// Semantics must be enabled (`tester.ensureSemantics()`) before the walk.
/// The walk starts from wherever focus is; the first Tab press produces the
/// first stop.
Future<FocusWalk> walkFocus(
  WidgetTester tester, {
  bool reverse = false,
  int maxStops = 200,
}) async {
  final stops = <FocusStop>[];
  final offscreen = <int>{};
  // The render view's size, not the test view's: `setSurfaceSize` resizes
  // the former only.
  final window = tester.binding.renderViews.fold<Rect>(
    Rect.zero,
    (area, view) => area.expandToInclude(Offset.zero & view.size),
  );
  FocusNode? first;
  // Containers around the starting focus are already "entered"; a screen
  // reader does not repeat them when focus moves within them.
  final initial = _focusedNodes(tester);
  var previous = initial.isEmpty
      ? <SemanticsNode>[]
      : _namedAncestors(initial.last);
  var cycled = false;
  for (var i = 0; i < maxStops; i++) {
    await _pressTab(tester, reverse: reverse);
    final node = FocusManager.instance.primaryFocus;
    if (node == null) break;
    if (first == null) {
      first = node;
    } else if (identical(node, first)) {
      cycled = true;
      break;
    }
    stops.add(describeFocus(tester, previous: previous));
    final focused = _focusedNodes(tester);
    previous = focused.isEmpty ? previous : _namedAncestors(focused.last);
    if (!window.overlaps(node.rect)) offscreen.add(stops.length);
  }
  return FocusWalk(
    stops: stops,
    cycled: cycled,
    reverse: reverse,
    offscreen: offscreen,
  );
}

/// Fails unless [walk] breaks none of the [FocusWalkRule]s outside [ignore].
void expectCleanFocusWalk(
  FocusWalk walk, {
  Set<FocusWalkRule> ignore = const <FocusWalkRule>{},
  String context = '',
}) {
  final problems = walk.problems(ignore: ignore);
  if (problems.isEmpty) return;
  fail(
    'Focus walk${context.isEmpty ? '' : ' ($context)'} has '
    '${problems.length} problem(s):\n'
    '${problems.map((p) => '  $p').join('\n')}\n\n${walk.transcript}',
  );
}

/// Fails unless keyboard focus is on a node a screen reader announces with a
/// name. Use it wherever focus must land: at launch, when a dialog opens,
/// and after the focused control is removed.
///
/// When [named] is given, the stop's name, value or description must
/// contain it.
void expectFocusAnnounced(
  WidgetTester tester, {
  String? named,
  String context = '',
}) {
  final stop = describeFocus(tester);
  final where = context.isEmpty ? '' : ' ($context)';
  if (!stop.spoken || stop.isNameless) {
    fail(
      'Keyboard focus$where is not announced: $stop. '
      'A screen reader reads the window class name or nothing.',
    );
  }
  if (named != null &&
      !'${stop.name} ${stop.value} ${stop.description}'.contains(named)) {
    fail('Keyboard focus$where is on "$stop", expected "$named".');
  }
}

/// Compares [walk]'s transcript with the text file at [path], relative to
/// the package root. Run `flutter test --update-goldens` to rewrite it.
void expectFocusWalkGolden(FocusWalk walk, String path) {
  final file = File(path);
  final actual = walk.transcript;
  if (autoUpdateGoldenFiles) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(actual);
    return;
  }
  if (!file.existsSync()) {
    fail(
      'No focus-walk golden at $path. Run flutter test --update-goldens and '
      'review the transcript it writes.\n\n$actual',
    );
  }
  final expected = file.readAsStringSync().replaceAll('\r\n', '\n');
  if (expected == actual) return;
  final e = expected.split('\n');
  final a = actual.split('\n');
  var line = 0;
  while (line < e.length && line < a.length && e[line] == a[line]) {
    line++;
  }
  fail(
    'Focus walk differs from $path at line ${line + 1}:\n'
    '  expected: ${line < e.length ? e[line] : '(end)'}\n'
    '  actual:   ${line < a.length ? a[line] : '(end)'}\n'
    'If the change is intended, run flutter test --update-goldens.\n\n'
    '$actual',
  );
}

/// Records the announcements a widget sends to assistive technology.
///
/// Live regions are not announced by the desktop accessibility bridges, so
/// on Windows, macOS and Linux an explicit announcement is the only way a
/// status change is spoken. A SnackBar alone never appears here.
class AnnouncementRecorder {
  /// Starts recording for the rest of the current test.
  factory AnnouncementRecorder.attach(WidgetTester tester) {
    final recorder = AnnouncementRecorder._();
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
        message,
      ) async {
        if (message is Map && message['type'] == 'announce') {
          final data = message['data'];
          if (data is Map && data['message'] is String) {
            recorder.messages.add(data['message'] as String);
          }
        }
        return null;
      });
    addTearDown(
      () => messenger.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        null,
      ),
    );
    return recorder;
  }

  AnnouncementRecorder._();

  /// Every announced message, oldest first.
  final List<String> messages = <String>[];
}
