# Changelog

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
