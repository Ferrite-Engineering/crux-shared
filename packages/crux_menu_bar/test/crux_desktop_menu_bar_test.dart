// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _A {
  openFile,
  closeFile,
  zoomIn,
  toggleTheme,
  commandPalette,
  submitIssue,
  about,
  checkForUpdates,
  settings,
  quit,
}

const _layout = <ActionCategory, List<List<_A>>>{
  ActionCategory.file: [
    [_A.openFile],
    [_A.closeFile],
  ],
  ActionCategory.view: [
    [_A.commandPalette],
    [_A.zoomIn],
    [_A.toggleTheme],
  ],
  ActionCategory.help: [
    [_A.submitIssue],
    [_A.checkForUpdates],
    [_A.about],
  ],
};

const _appActions = CruxAppMenuActions<_A>(
  about: _A.about,
  checkForUpdates: _A.checkForUpdates,
  settings: _A.settings,
  quit: _A.quit,
);

Widget _wrap({
  required TargetPlatform platform,
  void Function(_A)? onAction,
  bool Function(_A)? isVisible,
  bool Function(_A)? isEnabled,
  ShortcutActivator? Function(_A)? shortcutOf,
  String? editionLine,
}) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: CruxDesktopMenuBar<_A>(
    layout: _layout,
    appActions: _appActions,
    categoryLabel: (c) => c.name,
    categoryAcceleratorLabel: (c) => '&${c.name}',
    windowMenuLabel: 'Window',
    labelOf: (a) => a.name,
    shortcutOf: shortcutOf ?? (_) => null,
    isVisible: isVisible ?? (_) => true,
    isEnabled: isEnabled ?? (_) => true,
    onAction: onAction ?? (_) {},
    logo: const SizedBox.shrink(),
    editionLine: editionLine,
    child: const Scaffold(body: SizedBox.shrink()),
  ),
);

/// Renders an OS-supplied item distinctly from a product item. The two name
/// spaces overlap — `PlatformProvidedMenuItemType` has `about` and `quit`
/// members, and this suite's product actions are also called about and quit —
/// so an untagged comparison silently matches the wrong one.
String _provided(PlatformProvidedMenuItemType type) => 'provided:${type.name}';

/// The top-level menu labels of the rendered native menu bar, in order.
List<String> _macMenuLabels(WidgetTester tester) => tester
    .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
    .menus
    .whereType<PlatformMenu>()
    .map((m) => m.label)
    .toList();

/// The children of one native top-level menu, with `---` marking each group
/// boundary the OS will draw a separator at.
List<String> _macItems(WidgetTester tester, String menuLabel) {
  final menu = tester
      .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
      .menus
      .whereType<PlatformMenu>()
      .firstWhere((m) => m.label == menuLabel);
  final out = <String>[];
  for (final child in menu.menus) {
    if (child is PlatformMenuItemGroup) {
      if (out.isNotEmpty) out.add('---');
      for (final member in child.members) {
        out.add(
          member is PlatformProvidedMenuItem
              ? _provided(member.type)
              : member.label,
        );
      }
    } else if (child is PlatformProvidedMenuItem) {
      out.add(_provided(child.type));
    } else {
      out.add(child.label);
    }
  }
  return out;
}

/// The contents of the in-window top-level menu at [index], with `---` for
/// each [Divider]. Indexed positionally: `MnemonicMenuBar` wraps each title in
/// a private `MnemonicLabel` whose text is not readable from outside the
/// package, and the layout above yields exactly File / View / Help in order.
List<String> _windowItems(WidgetTester tester, int index) {
  final bar = tester.widget<MenuBar>(find.byType(MenuBar));
  final submenus = bar.children.whereType<SubmenuButton>().toList();
  return [
    for (final child in submenus[index].menuChildren)
      if (child is Divider)
        '---'
      else if (child is MenuItemButton)
        (child.child! as Text).data!,
  ];
}

void main() {
  group('macOS native menu bar', () {
    testWidgets('application menu is first, in About/Updates/Settings/Quit '
        'order, each in its own separator group', (tester) async {
      await tester.pumpWidget(_wrap(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();

      expect(_macMenuLabels(tester).first, 'app');
      // The Services/Hide run only materializes on a host that supplies it
      // (see _providedGroups); assert the product-owned items either way.
      expect(
        _macItems(
          tester,
          'app',
        ).where((e) => !e.startsWith('provided:')).toList(),
        ['about', '---', 'checkForUpdates', '---', 'settings', '---', 'quit'],
      );
    });

    testWidgets('no edition line renders no extra item at all', (
      tester,
    ) async {
      // The Open Core case, and every non-macOS platform. Rendering nothing is
      // what lets the host pass this unconditionally.
      await tester.pumpWidget(_wrap(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();

      expect(
        _macItems(tester, 'app').where((e) => !e.startsWith('provided:')).first,
        'about',
      );
    });

    testWidgets('the edition line is the FIRST item, above About', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          platform: TargetPlatform.macOS,
          editionLine: 'Enterprise edition — licensed by your organization',
        ),
      );
      await tester.pumpAndSettle();

      final items = _macItems(
        tester,
        'app',
      ).where((e) => !e.startsWith('provided:')).toList();
      expect(items.first, 'Enterprise edition — licensed by your organization');
      expect(items[1], '---', reason: 'it sits in its own separator group');
      expect(items[2], 'about');
    });

    testWidgets('the edition line is DISABLED — it is a statement, not an '
        'action', (tester) async {
      await tester.pumpWidget(
        _wrap(platform: TargetPlatform.macOS, editionLine: 'Pro edition — me'),
      );
      await tester.pumpAndSettle();

      final appMenu = tester
          .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
          .menus
          .whereType<PlatformMenu>()
          .firstWhere((m) => m.label == 'app');
      final first =
          (appMenu.menus.first as PlatformMenuItemGroup).members.first;
      expect(first.label, 'Pro edition — me');
      expect(
        first.onSelected,
        isNull,
        reason: 'a null onSelected is how PlatformMenuItem renders greyed out',
      );
    });

    testWidgets('application menu carries the standard macOS tail where the '
        'host provides it', (tester) async {
      await tester.pumpWidget(_wrap(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();

      final items = _macItems(tester, 'app');
      for (final type in [
        PlatformProvidedMenuItemType.servicesSubmenu,
        PlatformProvidedMenuItemType.hide,
        PlatformProvidedMenuItemType.hideOtherApplications,
        PlatformProvidedMenuItemType.showAllApplications,
      ]) {
        expect(
          items.contains(_provided(type)),
          PlatformProvidedMenuItem.hasMenu(type),
          reason: '${type.name} must appear exactly when the host provides it',
        );
      }
    });

    testWidgets('hoists About and Check for Updates out of Help', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();
      expect(_macItems(tester, 'help'), ['submitIssue']);
    });

    testWidgets('Settings and Quit never appear in File', (tester) async {
      await tester.pumpWidget(_wrap(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();
      expect(_macItems(tester, 'file'), ['openFile', '---', 'closeFile']);
    });

    testWidgets('inserts the standard Window menu directly before Help', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();

      final labels = _macMenuLabels(tester);
      final hostProvidesWindowItems = PlatformProvidedMenuItem.hasMenu(
        PlatformProvidedMenuItemType.minimizeWindow,
      );
      if (!hostProvidesWindowItems) {
        expect(labels, isNot(contains('Window')));
        return;
      }
      expect(labels.indexOf('Window'), labels.indexOf('help') - 1);
      expect(_macItems(tester, 'Window'), [
        _provided(PlatformProvidedMenuItemType.minimizeWindow),
        _provided(PlatformProvidedMenuItemType.zoomWindow),
        '---',
        _provided(PlatformProvidedMenuItemType.toggleFullScreen),
      ]);
    });

    testWidgets('a disabled action renders with a null onSelected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          platform: TargetPlatform.macOS,
          isEnabled: (a) => a != _A.closeFile,
        ),
      );
      await tester.pumpAndSettle();

      final file = tester
          .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
          .menus
          .whereType<PlatformMenu>()
          .firstWhere((m) => m.label == 'file');
      final items = file.menus
          .whereType<PlatformMenuItemGroup>()
          .expand((g) => g.members)
          .toList();
      expect(
        items.firstWhere((i) => i.label == 'openFile').onSelected,
        isNotNull,
      );
      expect(
        items.firstWhere((i) => i.label == 'closeFile').onSelected,
        isNull,
      );
    });

    testWidgets('a hidden category renders no menu at all', (tester) async {
      await tester.pumpWidget(
        _wrap(
          platform: TargetPlatform.macOS,
          isVisible: (a) =>
              a != _A.commandPalette && a != _A.zoomIn && a != _A.toggleTheme,
        ),
      );
      await tester.pumpAndSettle();
      expect(_macMenuLabels(tester), isNot(contains('view')));
    });

    testWidgets('drops a typing-hostile bare accelerator', (tester) async {
      await tester.pumpWidget(
        _wrap(
          platform: TargetPlatform.macOS,
          shortcutOf: (a) => switch (a) {
            _A.closeFile => const SingleActivator(LogicalKeyboardKey.escape),
            _A.openFile => const SingleActivator(
              LogicalKeyboardKey.keyO,
              meta: true,
            ),
            _ => null,
          },
        ),
      );
      await tester.pumpAndSettle();

      final file = tester
          .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
          .menus
          .whereType<PlatformMenu>()
          .firstWhere((m) => m.label == 'file');
      final items = file.menus
          .whereType<PlatformMenuItemGroup>()
          .expand((g) => g.members)
          .toList();
      expect(
        items.firstWhere((i) => i.label == 'openFile').shortcut,
        isNotNull,
      );
      expect(items.firstWhere((i) => i.label == 'closeFile').shortcut, isNull);
    });
  });

  group('Windows / Linux in-window menu bar', () {
    testWidgets('renders no branded app menu; File leads', (tester) async {
      await tester.pumpWidget(_wrap(platform: TargetPlatform.windows));
      await tester.pumpAndSettle();

      expect(find.byType(PlatformMenuBar), findsNothing);
      expect(find.byType(MenuBar), findsOneWidget);
      final bar = tester.widget<MenuBar>(find.byType(MenuBar));
      expect(bar.children.whereType<SubmenuButton>().length, 3);
    });

    testWidgets('folds Settings then Quit into the bottom of File', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(platform: TargetPlatform.linux));
      await tester.pumpAndSettle();

      expect(_windowItems(tester, 0), [
        'openFile',
        '---',
        'closeFile',
        '---',
        'settings',
        '---',
        'quit',
      ]);
    });

    testWidgets('keeps About and Check for Updates in Help', (tester) async {
      await tester.pumpWidget(_wrap(platform: TargetPlatform.windows));
      await tester.pumpAndSettle();

      expect(_windowItems(tester, 2), [
        'submitIssue',
        '---',
        'checkForUpdates',
        '---',
        'about',
      ]);
    });

    testWidgets('a disabled action renders with a null onPressed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          platform: TargetPlatform.windows,
          isEnabled: (a) => a != _A.zoomIn,
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<MenuBar>(find.byType(MenuBar));
      final items = bar.children
          .whereType<SubmenuButton>()
          .expand((s) => s.menuChildren)
          .whereType<MenuItemButton>()
          .toList();
      MenuItemButton byLabel(String label) =>
          items.firstWhere((i) => (i.child! as Text).data == label);
      expect(byLabel('zoomIn').onPressed, isNull);
      expect(byLabel('toggleTheme').onPressed, isNotNull);
    });

    testWidgets('keeps a bare accelerator as a display-only label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          platform: TargetPlatform.windows,
          shortcutOf: (a) => a == _A.closeFile
              ? const SingleActivator(LogicalKeyboardKey.escape)
              : null,
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<MenuBar>(find.byType(MenuBar));
      final closeFile = bar.children
          .whereType<SubmenuButton>()
          .expand((s) => s.menuChildren)
          .whereType<MenuItemButton>()
          .firstWhere((i) => (i.child! as Text).data == 'closeFile');
      expect(closeFile.shortcut, isNotNull);
    });
  });

  group('platform gating', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('renders no menu bar on $platform', (tester) async {
        await tester.pumpWidget(_wrap(platform: platform));
        await tester.pumpAndSettle();
        expect(find.byType(PlatformMenuBar), findsNothing);
        expect(find.byType(MenuBar), findsNothing);
      });
    }
  });
}
