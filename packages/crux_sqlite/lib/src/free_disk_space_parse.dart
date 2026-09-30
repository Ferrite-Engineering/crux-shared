// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:math' as math;

/// Free bytes in the output of `df -k -P <dir>`, or `null` when it cannot be
/// read.
///
/// The row is found by its **capacity** column — the first `NN%` token with
/// three integers (total, used, available) before it — rather than by
/// position. `-P` guarantees one row per filesystem; it does not guarantee a
/// filesystem name without spaces, and a network share or FUSE mount named
/// `//nas/Team Share` or `host:/srv/team data` shifts every positional column
/// right. Read by position, that row reports the **Used** column as free
/// space: a confident answer that is wrong in the one direction this probe
/// exists to prevent. The mount point can hold spaces too, which is why the
/// columns are not read from the right either.
///
/// A capacity of `-` (a filesystem with no size, such as `proc`) matches
/// nothing and is unknown. So is a negative count, a count too large for an
/// int, and any output this does not recognise.
int? parseDfPortableFreeBytes(String output) {
  final lines = const LineSplitter()
      .convert(output)
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.length < 2) return null;
  // Everything after the header, as one run of tokens: a non-POSIX `df` that
  // wraps a long filesystem name onto a line of its own still reads.
  final fields = lines.skip(1).join(' ').trim().split(RegExp(r'\s+'));
  for (var i = 3; i < fields.length; i++) {
    if (!_capacity.hasMatch(fields[i])) continue;
    final total = int.tryParse(fields[i - 3]);
    final used = int.tryParse(fields[i - 2]);
    final available = int.tryParse(fields[i - 1]);
    if (total == null || used == null || available == null) continue;
    if (available < 0) return null;
    return available * 1024;
  }
  return null;
}

final RegExp _capacity = RegExp(r'^\d{1,3}%$');

/// Free bytes in the output of `fsutil volume diskfree <dir>`, or `null` when
/// it cannot be read.
///
/// `fsutil` prints more than one "free bytes" line, and they are not the same
/// figure. Older builds print "Total # of free bytes" (the volume's) and
/// "Total # of avail free bytes" (the caller's); current builds print "Total
/// free bytes" and "Total quota free bytes". On a volume with a quota the
/// caller's figure is the smaller one, and it is the only one a write by this
/// user can use — so the **smallest** of them is the answer. Taking the first
/// reported the whole volume's free space to a user who could write a
/// fraction of it.
///
/// The number is grouped by the user's locale: `,` `.` a space, a no-break
/// space, a narrow no-break space or an apostrophe. Every non-digit before
/// the `( 36.9 GB)` suffix is dropped rather than a separator list kept,
/// because a separator missing from the list truncated `76'787'392'512` to
/// `76` — a false "disk full" that blocked the migration.
///
/// A localized `fsutil` whose labels do not say "free bytes" is unknown.
int? parseFsutilFreeBytes(String output) {
  int? smallest;
  for (final line in const LineSplitter().convert(output)) {
    if (!line.toLowerCase().contains('free byte')) continue;
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    var value = line.substring(colon + 1);
    final suffix = value.indexOf('(');
    if (suffix >= 0) value = value.substring(0, suffix);
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) continue;
    final bytes = int.tryParse(digits);
    if (bytes == null) continue;
    smallest = smallest == null ? bytes : math.min(smallest, bytes);
  }
  return smallest;
}
