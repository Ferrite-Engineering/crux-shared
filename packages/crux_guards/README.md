# crux_guards

Static-guard scanners the four products run from their own `test/static/`
tests. Each was written, or was about to be written, once per product; here
it is written once, and each product keeps only a thin test with its own file
list and its own exemptions.

| Scanner | Rule |
|---|---|
| `cruxAuditOutlineText` | A `ColorScheme`'s `outline` token never colours text. Every `.outline` member access is a finding unless pinned to its file, line and trimmed text with a reason. |
| `cruxAuditUnusedL10nKeys` + `cruxArbMessageKeys` | Every key in the template ARB is read by some hand-written `lib/` code, or retained with a reason. |
| `cruxAuditRefAfterAwait` | A `ConsumerState`'s `ref`, or a `WidgetRef` parameter, is never used after an `await` without a `mounted` check in between. |
| `cruxAuditModalGuard` | Every `showDialog` / `showModalBottomSheet` / `showGeneralDialog` / `showCruxDialog` runs inside `ModalGuard.run(...)` (a `showCruxDialog` may pass `modalGuardKey:` instead), or its enclosing member is allowed with the reason it cannot be re-fired. |
| `cruxAuditDismissibleFormDialogs` | A dialog that holds typed input passes `barrierDismissible: false`; forms the scan cannot infer are declared as known forms. |
| `cruxAuditCruxDesktop` + `cruxParseDesktopAllowList` / `cruxFormatDesktopAllowList` | No raw Material pattern the Crux Desktop layer replaces (`showDialog`, `AlertDialog`, `SimpleDialog`, `SnackBar`, `showSnackBar`, `Icons.more_vert`, `Switch`, `Switch.adaptive`, `SwitchListTile`, `CheckboxListTile`), outside a phone-only call site or a per-file allow-list with exact counts that shrinks to empty. |
| `cruxAuditPrivateEmptyStates` | No private `*Empty*` / `*Placeholder*` class duplicates `CruxPanelEmptyState`, unless exempted with a reason. |
| `cruxAuditProcessExit` | No call or tear-off of `dart:io`'s `exit`: a product ends its own process with `crux_telemetry`'s `cruxExit`, which marks the session's exit clean first, unless the enclosing member is exempted with a reason. |

## Shape

Every scanner takes `CruxGuardSource`s (a path and the text) and returns a
`CruxGuardResult`: the findings, how many files it scanned and how many sites
matched, so the host can assert the scan was not vacuous. Nothing here reads
the disk or calls `test()`.

```dart
final result = cruxAuditRefAfterAwait(sources: libSources, exemptions: [
  CruxRefAfterAwaitExemption(
    file: 'lib/app.dart',
    function: '_handleQuit',
    reason: 'reads a root-container provider that outlives the widget',
  ),
]);
expect(result.isClean, isTrue, reason: result.describe());
expect(result.filesScanned, greaterThan(100));
```

## The Crux Desktop guard

`cruxAuditCruxDesktop` keeps a product's desktop layout on the Crux Desktop
widgets. Each finding names the pattern and its replacement:

| Pattern id | Replacement |
|---|---|
| `showDialog` | `showCruxDialog` |
| `AlertDialog` (and `AlertDialog.adaptive`), `SimpleDialog` | `CruxDialog` |
| `SnackBar`, `showSnackBar` | `showCruxInfoSnack` / `showCruxErrorSnack` |
| `Icons.more_vert` (and its `_outlined` / `_rounded` / `_sharp` variants) | `CruxOverflowMenu` (`Icons.more_horiz`) |
| `Switch`, `Switch.adaptive` | `CruxSwitch` |
| `SwitchListTile` (and `.adaptive`) | `CruxFormRow.toggle` |
| `CheckboxListTile` (and `.adaptive`) | `CruxFormRow.checkbox` |

Each product runs it from `test/static/` in the open core and in the Pro
overlay, over that repo's `lib/`, with an allow-list file of the sites not yet
migrated. The file shrinks to empty as they move:

```dart
import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:test/test.dart';

void main() {
  test('no raw Material pattern the Crux Desktop layer replaces', () {
    final sources = [
      for (final f in Directory('lib').listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        CruxGuardSource(
          path: f.path.replaceAll(r'\', '/'),
          source: f.readAsStringSync(),
        ),
    ];
    final result = cruxAuditCruxDesktop(
      sources: sources,
      allowances: cruxParseDesktopAllowList(
        File('test/static/crux_desktop_allowlist.txt').readAsStringSync(),
      ),
    );
    expect(result.isClean, isTrue, reason: result.describe());
    expect(result.filesScanned, greaterThan(100));
  });
}
```

The allow-list holds one entry per line, `file | pattern | count | reason`;
`#` starts a comment line:

```text
# Sites not yet on the Crux Desktop layer. Lower a count as each one moves.
lib/features/foo/foo_dialog.dart | showDialog | 2 | moves onto showCruxDialog with the rest of the foo dialogs
```

Counts are exact. A file with more unannotated sites than its count is a
finding per extra site; one with fewer is a finding telling the author to lower
the count; an entry with no site left is a finding to remove it. To seed the
file once, print the current sites and paste the output:

```dart
print(cruxFormatDesktopAllowList(
  cruxFindDesktopSites(sources),
  reason: 'not yet migrated to the Crux Desktop layer',
));
```

A call site that renders only in the phone layout keeps its Material widget
under a marker comment with a reason. The marker covers the statement or
member it sits above, never a whole file or class:

```dart
// crux-desktop: phone-only, the phone settings sheet keeps Material 3 toggles
final toggle = Switch(value: enabled, onChanged: onChanged);
```

A marker with no reason, and a marker that covers no site, are findings.

## Shared properties

- **Syntax, not text.** Each scanner parses with `package:analyzer`'s
  `parseString`, so a comment or a string never matches. None resolves types,
  and each states what that costs in its own documentation.
- **Exact lists.** An exemption or retention entry that matches nothing is a
  finding, so a list cannot outlive the code it describes.
- **Pure Dart.** No Flutter dependency, so a guard test can run under
  `dart test` as well as `flutter test`.
