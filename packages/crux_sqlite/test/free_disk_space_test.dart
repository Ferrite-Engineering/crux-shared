// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_sqlite/crux_sqlite.dart';
import 'package:crux_sqlite/src/free_disk_space_parse.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The free-space probe behind the pre-upgrade backup's size guard.
///
/// The guard exists to stop a `VACUUM INTO` from being attempted on a volume
/// that cannot hold it. An unknown answer (`null`) is safe: the backup write
/// is still the judge, and the migration does not run without it — see
/// `crux_pre_upgrade_backup_test.dart`. What is not safe is a **confident
/// number that is too large**, because that is the answer that waves the copy
/// through. So every sample below is checked for the number it must produce,
/// and every sample the parser cannot read must produce `null` — never a
/// neighbouring column.
///
/// The samples are the shapes `df -k -P` and `fsutil volume diskfree` print,
/// including the ones that broke the first parser: a filesystem name with a
/// space in it, a quota-limited Windows volume, and digit grouping by locale.
void main() {
  const header =
      'Filesystem     1024-blocks      Used Available Capacity '
      'Mounted on\n';

  group('df -k -P', () {
    test('an APFS volume on macOS', () {
      expect(
        parseDfPortableFreeBytes(
          '$header/dev/disk3s5     971350180 612345678 312345678    67%    '
          '/System/Volumes/Data\n',
        ),
        312345678 * 1024,
      );
    });

    test('an ext4 root on Linux', () {
      expect(
        parseDfPortableFreeBytes(
          '$header/dev/nvme0n1p2   490617784 123456789 342123456      27% /\n',
        ),
        342123456 * 1024,
      );
    });

    test('a translated header reads the same', () {
      expect(
        parseDfPortableFreeBytes(
          'Dateisystem    1024-Blöcke   Benutzt Verfügbar Kapazität '
          'Eingehängt auf\n'
          '/dev/sda1        102687672  52417728  45010628       54% /home\n',
        ),
        45010628 * 1024,
      );
    });

    test('a mount point with spaces in it', () {
      expect(
        parseDfPortableFreeBytes(
          '$header/dev/disk4s1 1000000 200000 800000 20% /Volumes/Lab Data\n',
        ),
        800000 * 1024,
      );
    });

    group('a filesystem name with spaces in it', () {
      // The defect. Read by position, each of these reported the Used column
      // (or the total) as free space — an answer many times too large.
      test('a network share', () {
        final free = parseDfPortableFreeBytes(
          '$header//alice@nas/Team Share        976762584 900000000  '
          '76762584      93% /Volumes/Team Share\n',
        );
        expect(free, 76762584 * 1024);
        expect(
          free,
          isNot(900000000 * 1024),
          reason: 'the Used column is not free space',
        );
      });

      test('a FUSE mount whose source has two spaces', () {
        expect(
          parseDfPortableFreeBytes(
            '${header}me@host:/srv/team lab data 1000 900 100 90% /mnt/team\n',
          ),
          100 * 1024,
        );
      });

      test('a source ending in something that looks like a number', () {
        expect(
          parseDfPortableFreeBytes(
            '$header//nas/archive 2024 5000 4000 1000 80% /mnt/archive\n',
          ),
          1000 * 1024,
        );
      });

      test("macOS's automounter map", () {
        // `map auto_home` has no size at all; zero is the honest answer.
        expect(
          parseDfPortableFreeBytes(
            '${header}map auto_home 0 0 0 100% /System/Volumes/Data/home\n',
          ),
          0,
        );
      });
    });

    test('a row wrapped after a long filesystem name', () {
      expect(
        parseDfPortableFreeBytes(
          '$header/dev/mapper/vg0-a-very-long-logical-volume-name\n'
          '                 102687672 52417728 45010628 54% /\n',
        ),
        45010628 * 1024,
      );
    });

    group('what it cannot read is unknown, never a guess', () {
      for (final (label, output) in <(String, String)>[
        ('nothing', ''),
        ('a header and no row', header),
        ('an error on stdout', 'df: /nope: No such file or directory\n'),
        ('a filesystem with no size', '${header}proc 0 0 0 - /proc\n'),
        ('a negative count', '$header/dev/sda1 100 200 -100 100% /\n'),
        (
          'a count too large for an int',
          '$header/dev/sda1 1 1 99999999999999999999 1% /\n',
        ),
        (
          'columns that are not numbers',
          '$header/dev/sda1 lots some plenty 5% /\n',
        ),
        ('no capacity column', '$header/dev/sda1 100 50 50 /\n'),
      ]) {
        test(label, () => expect(parseDfPortableFreeBytes(output), isNull));
      }
    });
  });

  group('fsutil volume diskfree', () {
    test('a current Windows build', () {
      expect(
        parseFsutilFreeBytes(
          'Total free bytes                :  76,787,392,512 ( 71.5 GB)\n'
          'Total bytes                     : 255,374,815,232 (237.8 GB)\n'
          'Total quota free bytes          :  76,787,392,512 ( 71.5 GB)\n'
          'Unavailable pledged bytes       :               0 (  0.0 KB)\n',
        ),
        76787392512,
      );
    });

    test('an older build, without grouping', () {
      expect(
        parseFsutilFreeBytes(
          'Total # of free bytes        : 76787392512\n'
          'Total # of bytes             : 255374815232\n'
          'Total # of avail free bytes  : 76787392512\n',
        ),
        76787392512,
      );
    });

    group('a volume with a quota reports what this user can write', () {
      // The defect. The first "free bytes" line is the volume's; a user
      // under a quota can write only the smaller figure.
      test('on a current build', () {
        expect(
          parseFsutilFreeBytes(
            'Total free bytes                :  76,787,392,512 ( 71.5 GB)\n'
            'Total bytes                     : 255,374,815,232 (237.8 GB)\n'
            'Total quota free bytes          :   1,073,741,824 (  1.0 GB)\n',
          ),
          1073741824,
        );
      });

      test('on an older build', () {
        expect(
          parseFsutilFreeBytes(
            'Total # of free bytes        : 76787392512\n'
            'Total # of bytes             : 255374815232\n'
            'Total # of avail free bytes  : 1073741824\n',
          ),
          1073741824,
        );
      });

      test('in whichever order the lines come', () {
        expect(
          parseFsutilFreeBytes(
            'Total quota free bytes : 5\nTotal free bytes : 9\n',
          ),
          5,
        );
      });
    });

    group('digit grouping by locale', () {
      // The defect in the other direction: a separator missing from a fixed
      // list cut the number at its first group, and 76 bytes free refused
      // the migration on a healthy volume.
      for (final (label, grouped) in <(String, String)>[
        ('comma', '76,787,392,512'),
        ('full stop', '76.787.392.512'),
        ('space', '76 787 392 512'),
        ('no-break space', '76\u00a0787\u00a0392\u00a0512'),
        ('narrow no-break space', '76\u202f787\u202f392\u202f512'),
        ('apostrophe', "76'787'392'512"),
        ('right single quote', '76\u2019787\u2019392\u2019512'),
      ]) {
        test(label, () {
          expect(
            parseFsutilFreeBytes('Total free bytes : $grouped ( 71,5 GB)\n'),
            76787392512,
          );
        });
      }
    });

    group('what it cannot read is unknown, never a guess', () {
      for (final (label, output) in <(String, String)>[
        ('nothing', ''),
        ('an error', 'Error:  Access is denied.\n'),
        (
          'a localized build',
          "Nombre total d'octets libres        : 76 787 392 512\n",
        ),
        ('a label with no number', 'Total free bytes : ( n/a )\n'),
        ('a label with no colon', 'Total free bytes 12345\n'),
        (
          'a number too large for an int',
          'Total free bytes : 99,999,999,999,999,999,999\n',
        ),
      ]) {
        test(label, () => expect(parseFsutilFreeBytes(output), isNull));
      }
    });
  });

  group('the probe on this machine', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('crux_free_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('answers for a real directory', () {
      final free = cruxFreeDiskBytes(dir.path);
      if (Platform.isWindows) {
        // fsutil's availability and permissions vary by edition; unknown is
        // an allowed answer there, a nonsensical one is not.
        if (free != null) expect(free, greaterThan(0));
        return;
      }
      expect(free, isNotNull, reason: 'df is on every POSIX host we ship to');
      expect(free, greaterThan(0));
    });

    test('a directory that does not exist is unknown, not an error', () {
      expect(cruxFreeDiskBytes(p.join(dir.path, 'no', 'such', 'dir')), isNull);
    });

    test('is what the backup guard uses unless a test says otherwise', () {
      expect(const CruxPreUpgradeBackup().freeDiskProbe, cruxFreeDiskBytes);
    });
  });
}
