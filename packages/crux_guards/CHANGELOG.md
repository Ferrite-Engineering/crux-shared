# Changelog

## Unreleased

- **Export namespace narrowed by 3 symbols.** `kCruxDesktopPhoneOnlyMarker`, `kCruxModalOpeners`, `kCruxTypedInputMarkers` left the barrel. No product build and no other package referenced them, so none was deprecated first; the declarations are unchanged and stay under `lib/src/`.

- `CruxDesktopPattern.segmentedButton`, `.dropdownButton` and
  `.dropdownButtonFormField`: the Crux Desktop guard flags `SegmentedButton`,
  `DropdownButton` and `DropdownButtonFormField` constructions (with or
  without type arguments, `const`, or an import prefix) and names
  `CruxSegmentedControl` and `CruxPopUpButton` (`CruxPopUpFormField` in a
  validating form). Allow-list files take the ids `SegmentedButton`,
  `DropdownButton` and `DropdownButtonFormField`; the phone-only marker
  covers them as it covers the others.

- `cruxAuditCruxDesktop` + `CruxDesktopPattern`, `CruxDesktopSite`,
  `cruxFindDesktopSites`, `CruxDesktopAllowance`, `cruxParseDesktopAllowList`,
  `cruxFormatDesktopAllowList` and `kCruxDesktopPhoneOnlyMarker`: no raw
  Material pattern the Crux Desktop layer replaces (`showDialog`,
  `AlertDialog`, `SimpleDialog`, `SnackBar`, `showSnackBar`,
  `Icons.more_vert`, `Switch`, `Switch.adaptive`, `SwitchListTile`,
  `CheckboxListTile`), each finding naming its replacement. Constructions
  match in both unresolved forms (`AlertDialog(` and `const AlertDialog(`),
  through an import prefix too. A call site marked
  `// crux-desktop: phone-only, <reason>` is exempt; a marker without a
  reason or covering no site is a finding. The rest are absorbed by a
  per-file allow-list with exact counts, parsed from and seeded as text.
- `showCruxDialog` is a modal opener for `cruxFindDialogSites`,
  `cruxAuditModalGuard` and `cruxAuditDismissibleFormDialogs`. It is guarded
  inside `ModalGuard.run` or when it passes `modalGuardKey:` (anything but
  the literal `null`), and is dismissible unless it passes
  `barrierDismissible: false`.

- `cruxAuditProcessExit` + `CruxProcessExitExemption`: no product ends its
  own process with `dart:io`'s `exit` (a call, a tear-off, or either through
  a prefix), because that skips the unclean-shutdown detector's clean-exit
  path and the next launch counts a normal quit as a crash. Products call
  `crux_telemetry`'s `cruxExit`. Shadowing declarations and member accesses
  on other objects do not match; an exemption that matches nothing is a
  finding.

- Three guards lifted from the Pro overlays' copies, each with exact
  accounting (an entry that matches nothing is a finding):
  - `cruxAuditModalGuard` + `CruxModalGuardAllowance`: every `showDialog`,
    `showModalBottomSheet` and `showGeneralDialog` sits inside
    `ModalGuard.run(...)`, or its enclosing member is allowed with a reason.
    One default-guarded rule replaces the four copies' different
    reachability heuristics.
  - `cruxAuditDismissibleFormDialogs` + `CruxKnownFormDialog` +
    `CruxDismissibleFormAllowance`: a dialog that holds typed input (its
    call names `TextEditingController` / `TextField` / `TextFormField`, or a
    class that does, itself or through its `State`) passes
    `barrierDismissible: false` (`isDismissible: false` for a sheet).
    Classes resolve across `sources` and `classSources`.
  - `cruxAuditPrivateEmptyStates` + `CruxEmptyStateExemption`: no private
    class named `*Empty*` / `*Placeholder*` outside the exemptions
    (`includePublic` widens it to public classes).
- `cruxFindDialogSites`, `CruxDialogSite` and `CruxClassIndex`: the shared
  dialog-site scan, keyed `path#member`, for a host's own canaries.

## 0.1.0

- Initial release: the shared home for static guards that were copied, or
  about to be copied, into each product.
- `cruxAuditOutlineText` and `CruxOutlineExemption`: the open cores'
  `outline_text_guard_test`, lifted. Reads tokens, so prose never matches,
  and accounts exactly: an exemption that matches nothing is a finding.
- `cruxAuditUnusedL10nKeys`, `CruxL10nRetention` and `cruxArbMessageKeys`:
  every template-ARB key is read by an identifier in the parsed `lib/`, or
  retained with a reason; a stale retention is a finding.
- `cruxAuditRefAfterAwait` and `CruxRefAfterAwaitExemption`: a widget's
  `ref` used after an `await` with no `mounted` check in between, in a
  `ConsumerState` or a function taking a `WidgetRef`, closures included. An
  await in a branch that leaves by `return`/`throw`/`break`/`continue` does
  not count.
- `CruxGuardSource`, `CruxGuardFinding`, `CruxGuardResult`.
