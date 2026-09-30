# Changelog

## Unreleased

- **The agreement is reachable and operable from the keyboard and a screen
  reader.** It was stacked over the app with only a barrier, so on a first
  launch focus stayed on the hidden app: Tab walked its controls (each one
  silent), nothing ever landed in the dialog, and Enter could press a button
  behind it. `CruxEulaGate` now mounts it through `crux_a11y`'s
  `CruxModalGate`, which keeps the app out of focus and semantics while the
  agreement is up and moves focus to the app's first control, or to the next
  gate's, once it is accepted. The dialog is a `CruxModalSurface` announced by
  its title, focus opens on the agreement text, which is a Tab stop that
  scrolls with the arrow and Page keys, Tab cycles through the link, the
  checkbox and the buttons without leaving the dialog, and Escape does not
  dismiss it. `crux_a11y` is a new dependency.
- `CruxEulaStrings.documentLabel` ("Agreement text") names the scrolling
  agreement for a screen reader.

## 0.1.0

First release. Closes the last of the three things EULA section 2.1 promises:
the agreement was drafted, then published at `edacrux.app/eula`, and now the
applications actually present it.

- **`CruxEulaGate`** — mounts the agreement over the routed content until it is
  accepted, and renders its child untouched afterwards. Sits outside
  `TelemetryConsentGate` and inside any beta-expiry gate.

  The ordering against the telemetry disclosure is not a preference. That
  disclosure asks for consent to a term this agreement defines (section 8), so
  collecting it first would have the user answering a question about a contract
  they had not been shown — and it is the only ordering under which the EEA /
  UK / CH / KR opt-in default is defensible.

- **`CruxEulaAcceptanceStore`** — records **which version** was accepted, not a
  boolean.

  Section 2.3 requires active re-acceptance when the agreement changes
  substantively. A boolean cannot express "accepted, but an older one", so it
  would carry a 1.0 acceptance silently forward over a 2.0 agreement the user
  has never seen. Raising `kCruxEulaVersion` is therefore the entire re-prompt
  mechanism.

- **`CruxEulaAcceptanceDialog`** — the full agreement scrolling in the dialog, a
  checkbox that arms Accept, and a Decline that says "and quit" because section
  2.1 leaves no third outcome.

  The checkbox is load-bearing: an agreement dismissed by a user who never
  registered there was an agreement is weak evidence of assent.

  The surface also restates section 3 — that accepting is not a condition of any
  open-source licence, and the Apache-2.0 source stays available either way.
  Over a free, Apache-licensed application a blocking dialog reads as exactly
  such a condition unless it says otherwise.

- **`eula_document.dart` is generated**, by `tool/generate-eula-document.py`,
  from the markdown the agreement is maintained in. The agreement the
  applications present and the one counsel finalised come from a single source,
  and the generator is the only thing standing between them and a paraphrase.
  The published text is at https://edacrux.app/eula.

- **Not localized, by decision.** The agreement is executed in English; a
  translated EULA would be nine more legal texts able to drift from the one
  that binds. The chrome stays English so it does not imply otherwise.
