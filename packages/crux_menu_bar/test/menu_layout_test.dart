// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Action { alpha, beta, gamma, delta, about, settings, quit, updates }

void main() {
  group('cruxEntriesForGroups', () {
    List<String> render(
      List<List<_Action>> groups,
      bool Function(_Action) visible,
    ) => [
      for (final entry in cruxEntriesForGroups(groups, visible))
        switch (entry) {
          CruxSeparatorEntry<_Action>() => '---',
          CruxActionEntry<_Action>(:final action) => action.name,
        },
    ];

    test('inserts one separator between consecutive non-empty groups', () {
      expect(
        render(
          const [
            [_Action.alpha],
            [_Action.beta, _Action.gamma],
          ],
          (_) => true,
        ),
        ['alpha', '---', 'beta', 'gamma'],
      );
    });

    test('collapses an emptied group without a dangling separator', () {
      expect(
        render(
          const [
            [_Action.alpha],
            [_Action.beta],
            [_Action.gamma],
          ],
          (a) => a != _Action.beta,
        ),
        ['alpha', '---', 'gamma'],
      );
    });

    test('never leads with a separator when the first group is emptied', () {
      expect(
        render(
          const [
            [_Action.alpha],
            [_Action.beta],
          ],
          (a) => a != _Action.alpha,
        ),
        ['beta'],
      );
    });

    test('drops individually hidden actions but keeps their group', () {
      expect(
        render(
          const [
            [_Action.alpha, _Action.beta],
            [_Action.gamma],
          ],
          (a) => a != _Action.alpha,
        ),
        ['beta', '---', 'gamma'],
      );
    });

    test('yields nothing when everything is hidden', () {
      expect(
        render(
          const [
            [_Action.alpha],
            [_Action.beta],
          ],
          (_) => false,
        ),
        isEmpty,
      );
    });
  });

  group('cruxMenuLayoutActions', () {
    test('flattens every action across categories and groups', () {
      const layout = <ActionCategory, List<List<_Action>>>{
        ActionCategory.file: [
          [_Action.alpha],
          [_Action.beta],
        ],
        ActionCategory.help: [
          [_Action.gamma, _Action.delta],
        ],
      };
      expect(cruxMenuLayoutActions(layout), {
        _Action.alpha,
        _Action.beta,
        _Action.gamma,
        _Action.delta,
      });
    });
  });

  group('CruxAppMenuActions', () {
    const withUpdates = CruxAppMenuActions<_Action>(
      about: _Action.about,
      settings: _Action.settings,
      quit: _Action.quit,
      checkForUpdates: _Action.updates,
    );
    const withoutUpdates = CruxAppMenuActions<_Action>(
      about: _Action.about,
      settings: _Action.settings,
      quit: _Action.quit,
    );

    test('macHoisted covers every action the macOS app menu owns', () {
      expect(withUpdates.macHoisted, {
        _Action.about,
        _Action.settings,
        _Action.quit,
        _Action.updates,
      });
      expect(withoutUpdates.macHoisted, {
        _Action.about,
        _Action.settings,
        _Action.quit,
      });
    });

    test('desktopFolded is Settings + Quit only — About stays in Help', () {
      expect(withUpdates.desktopFolded, {_Action.settings, _Action.quit});
      expect(withUpdates.desktopFolded, isNot(contains(_Action.about)));
      expect(withUpdates.desktopFolded, isNot(contains(_Action.updates)));
    });
  });

  group('ActionCategory', () {
    test('orders Edit between File and View, matching VS Code', () {
      expect(
        ActionCategory.values,
        containsAllInOrder([
          ActionCategory.app,
          ActionCategory.file,
          ActionCategory.edit,
          ActionCategory.view,
          ActionCategory.navigate,
          ActionCategory.search,
          ActionCategory.tools,
          ActionCategory.help,
        ]),
      );
    });
  });
}
