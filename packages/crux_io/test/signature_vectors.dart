// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// `[field, field, text]` triples and the signature each had when the scheme
/// shipped in the lint product's baselines, before it moved here. Stored
/// baselines hold these values, so they never change: append, never edit.
/// Case 9's text is [longShippedText], kept out of the table for size.
const shippedSignatures = <(List<String>, String)>[
  (
    ['verilator/UNUSEDSIGNAL', '/proj/src/cpu.sv', "Signal is unused: 'clk'"],
    'df689510b132e3a3',
  ),
  (['verible/line-length', '/proj/src/alu.sv', ''], '737cbf3010e837ed'),
  (
    [
      'verilator/WIDTH',
      '/proj/src/mem.sv',
      'Operator\tADD\n\nexpects   8   bits,\r\ngot 16',
    ],
    '4263b367735923e2',
  ),
  (['r/x', '/f.sv', '   padded message   '], '4ad9bfb594eb0fcf'),
  (
    ['r/ws', '/f.sv', 'a b c d e\x0b\x0cf'],
    'f36e44a618b3faa9',
  ),
  (['r/emoji', '/f.sv', 'boom \u{1F4A5} here'], 'a08d6866e408334b'),
  (
    ['r/cjk', '/src/éè.sv', '信号 未使用'],
    '94a142e8d2e97cdf',
  ),
  (['r|x', '/a|b.sv', 'has | pipe | chars'], '55b5828300475b2d'),
  (['r/blank', '/f.sv', ' \t\n\r '], 'dd3b3d10470bee68'),
  (['r/long', '/f.sv', ''], '1ebed8ea9fa5bbb4'),
  (['\x00', '\x7f', '\x01\x80￿'], '97ba56f817dfc974'),
];

/// The text of shipped case 9.
final String longShippedText = 'x y ' * 400;

/// The text of shipped case [i].
String shippedText(int i) =>
    i == 9 ? longShippedText : shippedSignatures[i].$1[2];

/// FNV-1a 64 in `BigInt`, written from the algorithm's definition: an oracle
/// independent of the limb arithmetic under test, exact on the VM and in a
/// browser alike.
String referenceFnv1a64(String input) {
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  for (final unit in input.codeUnits) {
    hash = ((hash ^ BigInt.from(unit)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
