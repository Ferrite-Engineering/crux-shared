# Changelog

## Unreleased

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
