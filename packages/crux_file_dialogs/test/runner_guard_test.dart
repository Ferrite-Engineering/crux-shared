// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_file_dialogs/crux_file_dialogs_guards.dart';
import 'package:flutter_test/flutter_test.dart';

const _linuxCmake = '''
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(X11 REQUIRED IMPORTED_TARGET x11)
''';

const _runnerCmake = r'''
set(CRUX_FILE_DIALOGS_DIR
  "${CMAKE_SOURCE_DIR}/../crux-shared/packages/crux_file_dialogs/native/linux")
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${CMAKE_SOURCE_DIR}/../crux-shared/packages/crux_file_dialogs/native/linux/crux_file_dialogs.cc"
)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::X11)
target_include_directories(${BINARY_NAME} PRIVATE
  "${CMAKE_SOURCE_DIR}/../crux-shared/packages/crux_file_dialogs/native/linux")
''';

const _cc = '''
#include "flutter/generated_plugin_registrant.h"
#include "crux_file_dialogs.h"

static void my_application_activate(GApplication* application) {
  if (x) { y(); }
  crux_select_renderer_for_display("Product");
  FlView* view = fl_view_new(project);
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  crux_register_file_dialog_channel(view);
  crux_tolerate_refused_x_bell("Product");
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

MyApplication* my_application_new() {
  crux_refuse_to_start_without_display("Product");
  g_set_prgname(APPLICATION_ID);
  crux_prefer_x11_when_only_display_is_set();
  crux_skip_accessibility_bridge_without_session_bus("Product");
  return MY_APPLICATION(g_object_new(my_application_get_type(), nullptr));
}
''';

List<String> _check({
  String cc = _cc,
  String runner = _runnerCmake,
  String linux = _linuxCmake,
}) => cruxCheckLinuxRunnerFileDialogs(
  myApplicationCc: cc,
  runnerCmake: runner,
  linuxCmake: linux,
);

void main() {
  test('a wired runner has no findings', () {
    expect(_check(), isEmpty);
  });

  test('a runner that never registers the channel is reported', () {
    final findings = _check(
      cc: _cc.replaceFirst('crux_register_file_dialog_channel(view);', ''),
    );
    expect(findings.single, contains('crux_register_file_dialog_channel'));
  });

  test('a commented-out registration does not count', () {
    final findings = _check(
      cc: _cc.replaceFirst(
        'crux_register_file_dialog_channel(view);',
        '// crux_register_file_dialog_channel(view);',
      ),
    );
    expect(findings.single, contains('does not call'));
  });

  test('a registration before the plugins is reported', () {
    final findings = _check(
      cc: _cc
          .replaceFirst('  crux_register_file_dialog_channel(view);\n', '')
          .replaceFirst(
            '  if (x)',
            '  crux_register_file_dialog_channel(view);\n  if (x)',
          ),
    );
    expect(findings.single, contains('must come after'));
  });

  test('a missing bell handler, source, include or X11 is reported', () {
    expect(
      _check(cc: _cc.replaceFirst('crux_tolerate_refused_x_bell', 'nope')),
      [contains('crux_tolerate_refused_x_bell')],
    );
    expect(_check(cc: _cc.replaceFirst('#include "crux_file_dialogs.h"', '')), [
      contains('crux_file_dialogs.h'),
    ]);
    expect(
      _check(runner: _runnerCmake.replaceFirst('crux_file_dialogs.cc', 'x.cc')),
      [contains('does not compile')],
    );
    expect(_check(runner: _runnerCmake.replaceFirst('PkgConfig::X11', '')), [
      contains('PkgConfig::X11'),
    ]);
    expect(_check(linux: _linuxCmake.replaceFirst('X11', 'XX')), [
      contains('does not find X11'),
    ]);
  });

  test('a runner that keeps its own renderer probe is reported', () {
    final findings = _check(
      cc: _cc.replaceFirst('crux_select_renderer_for_display("Product");', ''),
    );
    expect(findings.single, contains('crux_select_renderer_for_display'));
  });

  test('a renderer choice after the view exists is reported', () {
    final findings = _check(
      cc: _cc
          .replaceFirst('crux_select_renderer_for_display("Product");\n', '')
          .replaceFirst(
            'fl_register_plugins(',
            'crux_select_renderer_for_display("Product");\n  '
                'fl_register_plugins(',
          ),
    );
    expect(findings.single, contains('before fl_view_new'));
  });

  test('a runner that leaves the accessibility bridge alone is reported', () {
    final findings = _check(
      cc: _cc.replaceFirst(
        'crux_skip_accessibility_bridge_without_session_bus("Product");',
        '',
      ),
    );
    expect(
      findings.single,
      contains('crux_skip_accessibility_bridge_without_session_bus'),
    );
  });

  test(
    'a runner that lets GTK pick Wayland under X forwarding is reported',
    () {
      final findings = _check(
        cc: _cc.replaceFirst('crux_prefer_x11_when_only_display_is_set();', ''),
      );
      expect(
        findings.single,
        contains('does not call crux_prefer_x11_when_only_display_is_set'),
      );
    },
  );

  test('a runner that attaches to the local desktop with no display is '
      'reported', () {
    final findings = _check(
      cc: _cc.replaceFirst(
        '  crux_refuse_to_start_without_display("Product");\n',
        '',
      ),
    );
    expect(
      findings.single,
      contains('does not call crux_refuse_to_start_without_display'),
    );
  });

  test('a commented-out display refusal does not count', () {
    final findings = _check(
      cc: _cc.replaceFirst(
        'crux_refuse_to_start_without_display("Product");',
        '// crux_refuse_to_start_without_display("Product");',
      ),
    );
    expect(findings.single, contains('does not call'));
  });

  test('a display refusal after the X11 preference is reported', () {
    final findings = _check(
      cc: _cc
          .replaceFirst(
            '  crux_refuse_to_start_without_display("Product");\n',
            '',
          )
          .replaceFirst(
            'crux_prefer_x11_when_only_display_is_set();',
            'crux_prefer_x11_when_only_display_is_set();\n'
                '  crux_refuse_to_start_without_display("Product");',
          ),
    );
    expect(
      findings.single,
      contains(
        'crux_refuse_to_start_without_display must come before '
        'crux_prefer_x11_when_only_display_is_set',
      ),
    );
  });

  test('an X11 preference after the bridge check is reported', () {
    final findings = _check(
      cc: _cc
          .replaceFirst('crux_prefer_x11_when_only_display_is_set();\n', '')
          .replaceFirst(
            'crux_skip_accessibility_bridge_without_session_bus("Product");',
            'crux_skip_accessibility_bridge_without_session_bus("Product");\n'
                '  crux_prefer_x11_when_only_display_is_set();',
          ),
    );
    expect(
      findings.single,
      contains(
        'crux_prefer_x11_when_only_display_is_set must come before '
        'crux_skip_accessibility_bridge_without_session_bus',
      ),
    );
  });
}
