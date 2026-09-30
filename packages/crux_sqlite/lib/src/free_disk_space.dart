// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_sqlite/src/free_disk_space_parse.dart';

/// Answers "how many bytes are free on the volume holding `directory`?", or
/// `null` when it cannot be determined.
///
/// Injectable so the backup size guard can be tested without a full disk —
/// filling a real volume in a unit test is not an available move.
typedef CruxFreeDiskProbe = int? Function(String directory);

/// Free bytes on the volume holding [directory], or `null` when unknown.
///
/// **`null` means "unknown", never "zero".** Every caller must treat it as
/// "proceed and find out" rather than "refuse": a probe that cannot answer is
/// not evidence of a full disk, and refusing to back up on the strength of a
/// failed `df` would block migrations on every platform whose output we did
/// not anticipate. "Proceed" is safe because the backup is still the judge:
/// a `VACUUM INTO` that runs out of room fails, and the migration does not
/// run without it.
///
/// **What must never come back is a confident number that is too large.**
/// That is the one answer that defeats the guard: the backup is attempted on
/// a volume that cannot hold it, filling the user's disk until the write
/// fails, or it succeeds with less room left than the headroom promised. So
/// the parsers read the caller's own free space, not the volume's, and answer
/// `null` for any output they do not recognise rather than a nearby column.
///
/// Implemented by shelling out because Dart has no `statvfs` binding and this
/// package may not take an FFI dependency to get one — it is consumed by two
/// products' `dart build cli` binaries, where the transitive graph is already
/// load-bearing. The cost is acceptable because of *when* it runs: only once a
/// database has already exceeded `kCruxBackupSizeGuardBytes`, which no
/// retention-bounded Crux database ever does. On the ordinary path this
/// function is never called at all.
int? cruxFreeDiskBytes(String directory) {
  try {
    if (Platform.isWindows) return _windowsFreeBytes(directory);
    return _posixFreeBytes(directory);
  } on Object {
    // ProcessException, a missing binary, a sandbox that forbids exec — all of
    // them mean "unknown", which is what the contract above promises.
    return null;
  }
}

/// `df -k -P` — `-P` is the POSIX output format, which guarantees one line per
/// filesystem. Without it a long device name wraps onto a second line and the
/// column indices shift. [parseDfPortableFreeBytes] reads the result.
///
/// Spawned by name: off Windows `execvp` searches `PATH` only, never the
/// current directory, so there is no launch-directory binary to guard
/// against. The Windows probe below is the one that needs resolving.
int? _posixFreeBytes(String directory) {
  final result = Process.runSync('df', <String>['-k', '-P', directory]);
  if (result.exitCode != 0) return null;
  return parseDfPortableFreeBytes(result.stdout.toString());
}

/// `fsutil volume diskfree <dir>`, read by [parseFsutilFreeBytes].
///
/// `fsutil` is resolved to an absolute path first. On Windows a bare name is
/// searched for in the launching process's current directory before `PATH`,
/// so a planted `fsutil.exe` there could report whatever free space it liked.
/// When nothing on `PATH` answers to the name, the resolver throws the same
/// `ProcessException` a missing binary does, [cruxFreeDiskBytes] turns it into
/// "unknown", and the contract above already treats that as "proceed and find
/// out".
int? _windowsFreeBytes(String directory) {
  final fsutil = requireSpawnExecutableForHost('fsutil');
  final result = Process.runSync(fsutil, <String>[
    'volume',
    'diskfree',
    directory,
  ]);
  if (result.exitCode != 0) return null;
  return parseFsutilFreeBytes(result.stdout.toString());
}
