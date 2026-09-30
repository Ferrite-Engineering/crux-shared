// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:test/test.dart';

/// A trivial product action enum used to verify that real consumer enums
/// can satisfy the [CruxAction] interface.
enum _TestProductAction implements CruxAction {
  openFile(category: ActionCategory.file),
  zoomIn(category: ActionCategory.view),
  showAbout(category: ActionCategory.help);

  const _TestProductAction({required this.category});

  @override
  final ActionCategory category;

  @override
  String get id => 'test.$name';
}

void main() {
  group('ActionCategory', () {
    test('has the documented eight values in declaration order', () {
      // Order is load-bearing: the shared menu bar walks `values` to lay out
      // the top-level menus, so this list is the suite's menu order. `edit`
      // sits between `file` and `view`, where VS Code and the platform
      // conventions put it.
      expect(ActionCategory.values, [
        ActionCategory.app,
        ActionCategory.file,
        ActionCategory.edit,
        ActionCategory.view,
        ActionCategory.navigate,
        ActionCategory.search,
        ActionCategory.tools,
        ActionCategory.help,
      ]);
    });
  });

  group('CruxAction interface', () {
    test('a product enum can implement CruxAction', () {
      const action = _TestProductAction.openFile;
      expect(action, isA<CruxAction>());
    });

    test('id and category are accessible via the interface type', () {
      const CruxAction action = _TestProductAction.zoomIn;
      expect(action.id, 'test.zoomIn');
      expect(action.category, ActionCategory.view);
    });

    test('different product enum values map to different categories', () {
      expect(_TestProductAction.openFile.category, ActionCategory.file);
      expect(_TestProductAction.zoomIn.category, ActionCategory.view);
      expect(_TestProductAction.showAbout.category, ActionCategory.help);
    });

    test('id values include the documented product prefix convention', () {
      for (final action in _TestProductAction.values) {
        expect(action.id, startsWith('test.'));
      }
    });

    test('generic code can iterate any product enum as List<CruxAction>', () {
      const List<CruxAction> actions = _TestProductAction.values;
      final categories = actions.map((a) => a.category).toSet();
      expect(categories, {
        ActionCategory.file,
        ActionCategory.view,
        ActionCategory.help,
      });
    });
  });
}
