# crux_a11y

Accessibility workarounds and guards shared by the EDACrux products.

## Why it exists

The desktop accessibility bridge in the Flutter engine
(`shell/platform/common/accessibility_bridge.cc`, shared by macOS, Windows and
Linux) rejects any semantics update that serializes a node no other node lists
in its `childrenInTraversalOrder`. After one rejection the native tree stops
following the app, so a screen reader keeps describing the previous screen. In
release builds a related null dereference in the same file can also terminate
the process. Two framework widgets produce such a node in ordinary use:

- `Slider` inside a dialog or pushed route
  ([flutter/flutter#190357](https://github.com/flutter/flutter/issues/190357)).
- `Tooltip` hosted directly inside a `MenuAnchor` builder, the moment the
  tooltip appears
  ([flutter/flutter#182444](https://github.com/flutter/flutter/issues/182444)).

## What is here

| Export | Use |
|---|---|
| `CruxSlider` (`crux_a11y.dart`) | Drop-in for `Slider` anywhere a dialog or route hosts it. Same parameters, same look, same keyboard and screen-reader behaviour; the value indicator's portal is confined to a private `Overlay`. |
| `CruxModalGate`, `CruxModalSurface` (`crux_a11y.dart`) | A modal surface that cannot be a route, such as a licence agreement or consent disclosure mounted above the `Navigator`. The gate keeps the app behind the surface out of focus and semantics, so Tab and Enter cannot reach it, and moves focus to the app's first control when the surface closes. The surface names the dialog for a screen reader, keeps Tab cycling inside it, and consumes Escape. |
| `CruxScrollRegion` (`crux_a11y.dart`) | A block of scrolling text as one named Tab stop that scrolls with the arrow keys, Page Up/Down, Home and End, with a focus outline. |
| `walkFocus`, `FocusWalk`, `FocusStop`, `expectCleanFocusWalk`, `expectFocusAnnounced`, `describeFocus`, `expectFocusWalkGolden`, `AnnouncementRecorder` (`crux_a11y_testing.dart`) | The focus walk. Enable semantics, pump a surface, and `walkFocus` presses Tab until focus cycles, recording at each stop what the desktop bridge gives NVDA or VoiceOver. `expectCleanFocusWalk` fails on the defects a label scan cannot see; `expectFocusAnnounced` checks focus landed somewhere named; `expectFocusWalkGolden` pins the transcript as a text file (`flutter test --update-goldens` rewrites it); `AnnouncementRecorder` captures what `SemanticsService.sendAnnouncement` speaks. |
| `SemanticsOrphanGuard`, `SemanticsOrphanTestBinding`, `SemanticsOrphanRecording` (`crux_a11y_testing.dart`) | Widget-test harness. Install the binding, enable semantics with `tester.ensureSemantics()`, drive the surface, then `SemanticsOrphanGuard.instance.check()`. Fails with the offending node and the update it appeared in. |

## The focus walk

A label scan answers "does every control have a name". A screen reader user
asks different questions — what is focused when the window opens, what is
heard at each Tab, whether the order makes sense, whether a failure is ever
spoken — and every one of them can be wrong with every label present. The
focus walk turns those questions into assertions:

| Rule | What the user hears |
|---|---|
| `silentStop` | Nothing: focus moved to a widget with no semantics node of its own |
| `namelessStop` | "text", "grouping", "check box" — a bare role |
| `twoNames` | One control announced under two names ("Stats. Show Statistics") |
| `containerRepeatsName` | "Statistics grouping, Show Statistics button" |
| `unspeakableGlyph` | "Diagnostics ? Logs" — an arrow read as a question mark |
| `offscreenStop` | A stop on a row the list built below the visible area |
| `noCycle` | A trap, or an order too long to finish |

The model follows `shell/platform/common/accessibility_bridge.cc`: the label
is the accessible name, the tooltip the description, the role comes from the
flags in the bridge's order, and the semantics hint is dropped because the
desktop bridges never expose it. It is a model, not NVDA: it is exact about
what Flutter serializes and approximate about how a given screen reader words
it, which is why the transcript is kept as a golden rather than asserted
line by line in most tests.

```dart
testWidgets('the start screen is announced and walks cleanly', (tester) async {
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();

  expectFocusAnnounced(tester, named: 'Open File', context: 'launch');
  final walk = await walkFocus(tester);
  expectCleanFocusWalk(walk);
  expectFocusWalkGolden(walk, 'test/a11y/goldens/start_screen.txt');
  handle.dispose();
});
```

For a `MenuAnchor` whose builder returns a `Tooltip`, insert
`Semantics(container: true, child: ...)` between them; the two overlay
anchors then land in different semantics nodes and neither loses its
identifier. There is no widget for that because the boundary is the fix.

## Example

```dart
void main() {
  SemanticsOrphanTestBinding.ensureInitialized();

  testWidgets('settings dialog serializes no orphan', (tester) async {
    SemanticsOrphanGuard.instance.reset();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    handle.dispose();
    SemanticsOrphanGuard.instance.check(context: 'settings dialog');
  });
}
```
