// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// What a product's Linux runner is missing for the file-dialog channel, one
/// sentence per gap; empty when the runner is wired.
///
/// [myApplicationCc] is `linux/runner/my_application.cc`, [runnerCmake]
/// `linux/runner/CMakeLists.txt` and [linuxCmake] `linux/CMakeLists.txt`,
/// each as text. The runner must:
///
/// - list `crux_file_dialogs.cc` among its sources and put its directory on
///   the include path, so the header resolves;
/// - link X11, which the bell handler calls (`XSetErrorHandler`), found with
///   `pkg_check_modules(X11 ...)` in the top-level file;
/// - include `crux_file_dialogs.h` and, inside `my_application_activate`,
///   call `crux_select_renderer_for_display(...)` before `fl_view_new`, and
///   `crux_register_file_dialog_channel(view)` and
///   `crux_tolerate_refused_x_bell(...)` after `fl_register_plugins`;
/// - call `crux_prefer_x11_when_only_display_is_set()` and then
///   `crux_skip_accessibility_bridge_without_session_bus(...)` in
///   `my_application_new`, before GTK starts.
///
/// Comments are stripped first, so a call that is commented out does not
/// count.
List<String> cruxCheckLinuxRunnerFileDialogs({
  required String myApplicationCc,
  required String runnerCmake,
  required String linuxCmake,
}) {
  final findings = <String>[];
  final cc = _stripCComments(myApplicationCc);
  final runner = _stripHashComments(runnerCmake);
  final linux = _stripHashComments(linuxCmake);

  if (!RegExp(r'"[^"\n]*/crux_file_dialogs\.cc"').hasMatch(runner)) {
    findings.add(
      'linux/runner/CMakeLists.txt does not compile crux_file_dialogs.cc '
      "(crux-shared's packages/crux_file_dialogs/native/linux).",
    );
  }
  if (!RegExp(
    r'target_include_directories\([^)]*crux_file_dialogs/native/linux',
  ).hasMatch(runner)) {
    findings.add(
      'linux/runner/CMakeLists.txt does not put '
      'crux_file_dialogs/native/linux on the include path.',
    );
  }
  if (!RegExp(r'target_link_libraries\([^)]*PkgConfig::X11').hasMatch(runner)) {
    findings.add('linux/runner/CMakeLists.txt does not link PkgConfig::X11.');
  }
  if (!RegExp(r'pkg_check_modules\(\s*X11\b').hasMatch(linux)) {
    findings.add(
      'linux/CMakeLists.txt does not find X11 (pkg_check_modules(X11 ...)).',
    );
  }
  if (!cc.contains('#include "crux_file_dialogs.h"')) {
    findings.add(
      'linux/runner/my_application.cc does not include crux_file_dialogs.h.',
    );
  }

  final activate = _functionBody(cc, 'my_application_activate');
  if (activate == null) {
    findings.add(
      'linux/runner/my_application.cc has no my_application_activate.',
    );
    return findings;
  }
  final renderer = activate.indexOf('crux_select_renderer_for_display(');
  final view = activate.indexOf('fl_view_new(');
  if (renderer < 0) {
    findings.add(
      'my_application_activate does not call '
      'crux_select_renderer_for_display.',
    );
  } else if (view < 0 || view < renderer) {
    findings.add(
      'crux_select_renderer_for_display must come before fl_view_new.',
    );
  }
  final plugins = activate.indexOf('fl_register_plugins(');
  final channel = activate.indexOf('crux_register_file_dialog_channel(view)');
  final bell = activate.indexOf('crux_tolerate_refused_x_bell(');
  if (channel < 0) {
    findings.add(
      'my_application_activate does not call '
      'crux_register_file_dialog_channel(view).',
    );
  } else if (plugins < 0 || channel < plugins) {
    findings.add(
      'crux_register_file_dialog_channel(view) must come after '
      'fl_register_plugins.',
    );
  }
  if (bell < 0) {
    findings.add(
      'my_application_activate does not call crux_tolerate_refused_x_bell.',
    );
  } else if (plugins < 0 || bell < plugins) {
    findings.add(
      'crux_tolerate_refused_x_bell must come after fl_register_plugins.',
    );
  }

  final create = _functionBody(cc, 'my_application_new') ?? '';
  final x11 = create.indexOf('crux_prefer_x11_when_only_display_is_set(');
  final bridge = create.indexOf(
    'crux_skip_accessibility_bridge_without_session_bus(',
  );
  if (x11 < 0) {
    findings.add(
      'my_application_new does not call '
      'crux_prefer_x11_when_only_display_is_set.',
    );
  } else if (bridge >= 0 && bridge < x11) {
    findings.add(
      'crux_prefer_x11_when_only_display_is_set must come before '
      'crux_skip_accessibility_bridge_without_session_bus.',
    );
  }
  if (bridge < 0) {
    findings.add(
      'my_application_new does not call '
      'crux_skip_accessibility_bridge_without_session_bus.',
    );
  }
  return findings;
}

String _stripCComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _stripHashComments(String source) =>
    source.replaceAll(RegExp(r'#[^\n]*'), '');

/// The text between the braces of the C function [name]'s definition, or
/// null when there is none.
String? _functionBody(String source, String name) {
  final head = RegExp(
    r'\b' + RegExp.escape(name) + r'\s*\([^)]*\)\s*\{',
  ).firstMatch(source);
  if (head == null) return null;
  var depth = 1;
  for (var i = head.end; i < source.length; i++) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}' && --depth == 0) return source.substring(head.end, i);
  }
  return null;
}
