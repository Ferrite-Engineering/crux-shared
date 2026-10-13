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

## Shared properties

- **Syntax, not text.** Each scanner parses with `package:analyzer`'s
  `parseString`, so a comment or a string never matches. None resolves types,
  and each states what that costs in its own documentation.
- **Exact lists.** An exemption or retention entry that matches nothing is a
  finding, so a list cannot outlive the code it describes.
- **Pure Dart.** No Flutter dependency, so a guard test can run under
  `dart test` as well as `flutter test`.
