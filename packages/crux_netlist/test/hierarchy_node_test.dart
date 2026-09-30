// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_netlist/crux_netlist.dart';
import 'package:test/test.dart';

/// [HierarchyNode]: the address the hierarchy browser, the push-in and
/// pop-out navigator and the per-scope schematic all work in.
///
/// Every model here is parsed from JSON through [YosysJsonParser], the way a
/// product builds one, and several are shapes Yosys would never write but a
/// file on disk can hold: no top module, a cell naming a module that is not
/// in the design, a module that instantiates itself, a hierarchy thousands of
/// levels deep, and a module with tens of thousands of instances. Navigation
/// must answer each of them — `null` where there is nothing to go to — and
/// never recurse on the model's behalf, because a cyclic hierarchy has no
/// bottom.
void main() {
  group('a well-formed hierarchy', () {
    final model = _parse(<String, Object?>{
      'soc': _module(
        top: true,
        cells: <String, String>{
          'u_cpu': 'cpu',
          'u_uart': 'uart',
          r'$and$soc.v:12$1': r'$and',
        },
      ),
      'cpu': _module(cells: <String, String>{'u_alu': 'alu'}),
      'alu': _module(),
      'uart': _module(),
    });

    test('the root is the top module, at an empty path', () {
      final root = HierarchyNode.rootOf(model)!;

      expect(root.isRoot, isTrue);
      expect(root.depth, 0);
      expect(root.path, isEmpty);
      expect(root.moduleName, 'soc');
      expect(root.displayName, 'soc');
      expect(root.canonicalPath(model), 'soc');
      expect(root.resolve(model)?.name, 'soc');
    });

    test('walking in names instances, and resolves their modules', () {
      final root = HierarchyNode.rootOf(model)!;
      final cpu = root.child(model, 'u_cpu')!;
      final alu = cpu.child(model, 'u_alu')!;

      expect(cpu.path, <String>['u_cpu']);
      expect(cpu.moduleName, 'cpu');
      expect(cpu.displayName, 'u_cpu', reason: 'the instance, not the module');
      expect(cpu.isRoot, isFalse);
      expect(alu.depth, 2);
      expect(alu.canonicalPath(model), 'soc.u_cpu.u_alu');
      expect(alu.resolve(model)?.name, 'alu');
    });

    test('only instances of modules in the design have children', () {
      final root = HierarchyNode.rootOf(model)!;

      expect(root.childInstanceNames(model), <String>['u_cpu', 'u_uart']);
      expect(
        root.child(model, r'$and$soc.v:12$1'),
        isNull,
        reason: 'a primitive has no inside to push into',
      );
      expect(
        root
            .child(model, 'u_cpu')!
            .child(model, 'u_alu')!
            .childInstanceNames(
              model,
            ),
        isEmpty,
      );
    });

    test('an instance of a black-box module is a cell, not a scope', () {
      // What synth_ice40 leaves behind: the cell library read for the
      // flow stays in the design as black-box modules, and every LUT and
      // flop instantiates one. Those instances are cells to draw and trace;
      // pushing into an SB_LUT4 shows five ports and nothing else.
      final ice40 = _parse(<String, Object?>{
        'service': _module(
          top: true,
          cells: <String, String>{
            'u_cpu': 'cpu',
            'lut_0': 'SB_LUT4',
            'ff_0': 'SB_DFF',
          },
        ),
        'cpu': _module(cells: <String, String>{'lut_1': 'SB_LUT4'}),
        'SB_LUT4': _module(blackBox: true),
        'SB_DFF': _module(blackBox: true),
      });
      final root = HierarchyNode.rootOf(ice40)!;

      expect(root.childInstanceNames(ice40), <String>['u_cpu']);
      expect(root.child(ice40, 'lut_0'), isNull);
      expect(root.child(ice40, 'ff_0'), isNull);
      final cpu = root.child(ice40, 'u_cpu')!;
      expect(cpu.childInstanceNames(ice40), isEmpty);
      expect(cpu.child(ice40, 'lut_1'), isNull);
      // A path that walks through a black box has no parent either: the
      // walk to it stops at the black box, so it is not an address the
      // browser can be at.
      const inside = HierarchyNode(
        path: <String>['lut_0', 'deeper'],
        moduleName: 'nothing',
      );
      expect(inside.parent(ice40), isNull);
    });

    test('walking out retraces the path, and stops at the root', () {
      final root = HierarchyNode.rootOf(model)!;
      final alu = root.child(model, 'u_cpu')!.child(model, 'u_alu')!;

      final cpu = alu.parent(model)!;
      expect(cpu, root.child(model, 'u_cpu'));
      expect(cpu.parent(model), root);
      expect(root.parent(model), isNull);
    });

    test('a node is a value: equal by path and module, not by identity', () {
      const a = HierarchyNode(
        path: <String>['u_cpu', 'u_alu'],
        moduleName: 'alu',
      );
      final b = HierarchyNode(
        path: List<String>.of(<String>['u_cpu', 'u_alu']),
        moduleName: 'alu',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(moduleName: 'other')));
      expect(a, isNot(a.copyWith(path: <String>['u_cpu', 'u_fpu'])));
      expect(a, isNot(a.copyWith(path: <String>['u_cpu'])));
      expect(a.copyWith(), a);
      expect(a.toString(), contains('u_cpu.u_alu'));
      expect(a.toString(), contains('alu'));
    });
  });

  group('a hierarchy that is not well formed', () {
    test('no module claims to be the top', () {
      final model = _parse(<String, Object?>{'a': _module(), 'b': _module()});

      expect(HierarchyNode.rootOf(model), isNull);
      // A node captured before the model was replaced still names itself.
      const stale = HierarchyNode(path: <String>['u_x'], moduleName: 'a');
      expect(stale.canonicalPath(model), 'a.u_x');
      expect(stale.parent(model), isNull);
    });

    test('a cell names a module that is not in the design', () {
      final model = _parse(<String, Object?>{
        'top': _module(top: true, cells: <String, String>{'u_ip': 'vendor_ip'}),
      });
      final root = HierarchyNode.rootOf(model)!;

      expect(root.child(model, 'u_ip'), isNull);
      expect(root.childInstanceNames(model), isEmpty);
    });

    test('an instance name that does not exist', () {
      final model = _parse(<String, Object?>{'top': _module(top: true)});
      expect(HierarchyNode.rootOf(model)!.child(model, 'u_nope'), isNull);
    });

    test('a node whose module left the design', () {
      // Re-elaboration replaced the model; the browser still holds a node.
      final model = _parse(<String, Object?>{'top': _module(top: true)});
      const gone = HierarchyNode(path: <String>['u_old'], moduleName: 'old');

      expect(gone.resolve(model), isNull);
      expect(gone.child(model, 'anything'), isNull);
      expect(gone.childInstanceNames(model), isEmpty);
    });

    test('a path that no longer walks has no parent', () {
      final model = _parse(<String, Object?>{
        'top': _module(top: true, cells: <String, String>{'u_a': 'a'}),
        'a': _module(),
      });
      const stale = HierarchyNode(
        path: <String>['u_renamed', 'u_leaf'],
        moduleName: 'leaf',
      );
      const intoPrimitive = HierarchyNode(
        path: <String>['u_a', 'u_b', 'u_c'],
        moduleName: 'c',
      );

      expect(stale.parent(model), isNull);
      expect(intoPrimitive.parent(model), isNull);
    });

    test('two modules both claim the top: the first in the file wins', () {
      final model = _parse(<String, Object?>{
        'first': _module(top: true),
        'second': _module(top: true),
      });
      expect(HierarchyNode.rootOf(model)!.moduleName, 'first');
    });
  });

  group('a cyclic hierarchy', () {
    // Recursive instantiation is not legal HDL and Yosys does not write it,
    // but a netlist file is input like any other. The model does not reject
    // it; what it must do is answer each navigation step without recursing,
    // so a consumer that walks the tree decides how far to go.
    test('a module that instantiates itself', () {
      final model = _parse(<String, Object?>{
        'top': _module(top: true, cells: <String, String>{'u_self': 'top'}),
      });
      var node = HierarchyNode.rootOf(model)!;

      for (var i = 1; i <= 50; i++) {
        expect(node.childInstanceNames(model), <String>['u_self']);
        node = node.child(model, 'u_self')!;
        expect(node.depth, i);
        expect(node.moduleName, 'top');
      }
      expect(node.parent(model)!.depth, 49);
      expect(node.canonicalPath(model).split('.'), hasLength(51));
    });

    test('two modules that instantiate each other', () {
      final model = _parse(<String, Object?>{
        'a': _module(top: true, cells: <String, String>{'u_b': 'b'}),
        'b': _module(cells: <String, String>{'u_a': 'a'}),
      });
      final root = HierarchyNode.rootOf(model)!;
      final b = root.child(model, 'u_b')!;
      final a2 = b.child(model, 'u_a')!;

      expect(a2.moduleName, 'a');
      expect(a2.parent(model), b);
      expect(b.parent(model), root);
    });

    test('nodes at different depths of a cycle are different nodes', () {
      // Worth pinning because it is the trap: a walker that keeps a visited
      // set of nodes will never see one twice in a cycle, since each lap has
      // a longer path. Cycle detection has to look at the modules on the
      // current path.
      final model = _parse(<String, Object?>{
        'top': _module(top: true, cells: <String, String>{'u_self': 'top'}),
      });
      final root = HierarchyNode.rootOf(model)!;
      final lap = root.child(model, 'u_self')!;

      expect(lap.moduleName, root.moduleName);
      expect(lap, isNot(root));
    });
  });

  group('size', () {
    test('a hierarchy five thousand levels deep', () {
      const depth = 5000;
      final modules = <String, Object?>{
        for (var i = 0; i < depth; i++)
          'm$i': _module(
            top: i == 0,
            cells: i + 1 < depth
                ? <String, String>{'u$i': 'm${i + 1}'}
                : const <String, String>{},
          ),
      };
      final model = _parse(modules);

      var node = HierarchyNode.rootOf(model)!;
      for (var i = 0; i + 1 < depth; i++) {
        node = node.child(model, 'u$i')!;
      }
      expect(node.depth, depth - 1);
      expect(node.moduleName, 'm${depth - 1}');
      // `parent` walks the whole path from the top; it must do so without
      // recursion, or the deepest node is the one that cannot go back up.
      expect(node.parent(model)!.moduleName, 'm${depth - 2}');
    });

    test('a module with twenty thousand instances', () {
      const fanOut = 20000;
      final model = _parse(<String, Object?>{
        'top': _module(
          top: true,
          cells: <String, String>{
            for (var i = 0; i < fanOut; i++) 'u_leaf_$i': 'leaf',
          },
        ),
        'leaf': _module(),
      });
      final root = HierarchyNode.rootOf(model)!;

      final names = root.childInstanceNames(model);
      expect(names, hasLength(fanOut));
      expect(names.first, 'u_leaf_0');
      expect(names.last, 'u_leaf_${fanOut - 1}');
      expect(root.child(model, 'u_leaf_12345')!.moduleName, 'leaf');
    });
  });
}

NetlistModel _parse(Map<String, Object?> modules) =>
    const YosysJsonParser().parse(
      jsonEncode(<String, Object?>{'creator': 'test', 'modules': modules}),
    );

/// A module with the given cell instances (instance name to cell type).
Map<String, Object?> _module({
  bool top = false,
  bool blackBox = false,
  Map<String, String> cells = const <String, String>{},
}) => <String, Object?>{
  'attributes': <String, Object?>{
    if (top) 'top': '00000000000000000000000000000001',
    if (blackBox) 'blackbox': '00000000000000000000000000000001',
  },
  'ports': <String, Object?>{},
  'cells': <String, Object?>{
    for (final cell in cells.entries)
      cell.key: <String, Object?>{
        'hide_name': 0,
        'type': cell.value,
        'parameters': <String, Object?>{},
        'attributes': <String, Object?>{},
        'port_directions': <String, Object?>{},
        'connections': <String, Object?>{},
      },
  },
  'netnames': <String, Object?>{},
};
