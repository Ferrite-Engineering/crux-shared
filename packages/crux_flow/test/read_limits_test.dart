// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/crux_flow.dart';
import 'package:crux_flow/src/read_limits.dart';
import 'package:crux_flow/src/value_equality.dart';
import 'package:test/test.dart';

void main() {
  group('describeFlowValue never echoes a long value', () {
    test('every JSON shape', () {
      expect(describeFlowValue(null), 'null');
      expect(describeFlowValue('ab'), '"ab"');
      expect(
        describeFlowValue('x' * 1000),
        allOf(
          contains('1000 characters'),
          hasLength(lessThan(100)),
        ),
      );
      expect(describeFlowValue(3.5), '3.5');
      expect(describeFlowValue(true), 'true');
      expect(describeFlowValue([1, 2]), 'a list of 2');
      expect(describeFlowValue({'a': 1}), 'an object of 1 keys');
      expect(describeFlowValue(DateTime(2026)), 'a DateTime');
    });
  });

  group('decodeFlowText', () {
    test('refuses bytes over the cap before decoding', () {
      expect(
        () => decodeFlowText(
          List.filled(11, 0x41),
          const FlowInputLimits(maxBytes: 10),
        ),
        throwsA(
          isA<FlowReadException>().having(
            (e) => e.failure,
            'failure',
            FlowReadFailure.tooLarge,
          ),
        ),
      );
      expect(decodeFlowText([0x41], FlowInputLimits.defaults), 'A');
    });
  });

  group('checkJsonDepth', () {
    test('counts only brackets outside strings, escapes included', () {
      checkJsonDepth(r'["\"[[[[", {"a": "\\"}]', 2);
      expect(
        () => checkJsonDepth('[[[', 2),
        throwsA(isA<FlowReadException>()),
      );
    });
  });

  group('deep equality', () {
    test('lists, maps and their nesting', () {
      expect(
        deepEquals(
          [
            1,
            {
              'a': [2],
            },
          ],
          [
            1,
            {
              'a': [2],
            },
          ],
        ),
        isTrue,
      );
      expect(
        deepEquals({'a': 1, 'b': 2}, {'b': 2, 'a': 1}),
        isFalse,
        reason: 'order is part of the value',
      );
      expect(deepEquals([1], [1, 2]), isFalse);
      expect(deepEquals({'a': 1}, {'a': 2}), isFalse);
      expect(deepEquals({'a': 1}, {'b': 1}), isFalse);
      expect(
        deepHash([
          1,
          {
            'a': [2],
          },
        ]),
        deepHash([
          1,
          {
            'a': [2],
          },
        ]),
      );
      final same = [1];
      expect(listEquals(same, same), isTrue);
      final map = {'a': 1};
      expect(mapEquals(map, map), isTrue);
    });
  });

  test('limits default to the documented values', () {
    expect(FlowInputLimits.defaults.maxBytes, 64 * 1024 * 1024);
    expect(FlowInputLimits.defaults.maxJsonDepth, 64);
    expect(FlowInputLimits.defaults.maxMetricKeyLength, 256);
    expect(FlowInputLimits.defaults.maxLineLength, 64 * 1024);
  });

  test('resource use has value equality', () {
    expect(
      const NextpnrResourceUse(used: 1, available: 2).hashCode,
      const NextpnrResourceUse(used: 1, available: 2).hashCode,
    );
    expect(
      const NextpnrResourceUse(used: 1, available: 2),
      isNot(const NextpnrResourceUse(used: 2, available: 2)),
    );
  });
}
