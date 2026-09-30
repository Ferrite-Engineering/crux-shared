# crux_eula

First-launch End User License Agreement acceptance for the EDACrux suite: the
agreement text compiled from counsel's final, a version-keyed acceptance store,
and the blocking acceptance surface. One implementation consumed by WaveCrux,
NetCrux, LintCrux and SimCrux.

## Why it exists

EULA section 2.1 says each application presents the agreement on first launch
and does not proceed until it is accepted — and that promise covers the **Open
Core** edition too, so a user who never buys anything still sees it. Four
products implementing that separately would be four chances to present four
subtly different agreements.

## What it does

- **Carries the agreement, rather than linking to it.** The full text scrolls
  inside the dialog. A user cannot have read what the application never showed
  them, and the online link is an addition to that, never a substitute.
- **Records the version accepted, not a boolean.** Section 2.3 requires active
  re-acceptance when the agreement changes substantively. A boolean would carry
  a 1.0 acceptance silently forward over a 2.0 agreement; raising
  `kCruxEulaVersion` is the whole re-prompt mechanism.
- **Arms Accept behind a checkbox.** Acceptance takes a deliberate second act
  rather than one reflexive click on the only enabled button.
- **Says that accepting is not a condition of any open-source licence.**
  Section 3's last paragraph promises exactly that, and a blocking dialog over
  an Apache-licensed application reads as such a condition unless it says
  otherwise.

## Wiring

Mount inside `MaterialApp`, **outside** `TelemetryConsentGate` and **inside**
any beta-expiry gate:

```dart
BetaExpiryGate(
  child: CruxEulaGate(
    isPhoneLayout: deviceClass.isPhoneClass,
    child: TelemetryConsentGate(
      child: routedContent,
    ),
  ),
)
```

The telemetry disclosure asks for consent to a term the agreement defines
(section 8), so collecting it first inverts the agreement. It is also the only
ordering under which the EEA / UK / CH / KR opt-in default is defensible.

Bind the persistence seam in the root `ProviderScope`; the two optional seams
hide their controls rather than render dead ones when left unbound:

```dart
ProviderScope(
  overrides: [
    cruxEulaStorageProvider.overrideWithValue(MyPrefsEulaStorage(prefs)),
    cruxEulaOnDeclineProvider.overrideWithValue(() => exit(0)),
    cruxEulaOpenOnlineProvider.overrideWithValue(
      () => launchUrl(Uri.parse('https://edacrux.app/eula')),
    ),
  ],
  child: app,
)
```

`cruxEulaStorageProvider` defaults to `InMemoryCruxEulaStorage`, which
re-presents the agreement on every launch. That is the intended shape of the
failure: a host that forgets the binding annoys its users, where a default that
remembered nothing *and* let the app through would ship an un-accepted build.

## Updating the agreement

The text is generated, not hand-written:

```bash
python3 tool/generate-eula-document.py <path/to/eula-final.md>
```

The published agreement is at <https://edacrux.app/eula>.

Raise `kCruxEulaVersion` in the same commit when the change is substantive —
that is what re-prompts every installation. Never raise it for a typographical
fix.

## Not localized, by decision

The agreement is executed in English and is not translated. A translated EULA
would be a second legal text to keep in step with counsel, in nine languages,
each able to drift from the one that actually binds. Since the document on
screen is English, the chrome around it stays English too: a localized frame
around an English contract implies a localized contract.

`CruxEulaStrings` exists so a host *can* substitute copy, not so it can be
translated.

## Testing

`resetCruxEulaAcceptance(storage)` puts an installation back to "never
accepted". Products surface it as `--reset-eula`, because once accepted the
dialog does not return until the version changes, which makes the one surface
every reviewer needs to check the hardest one to see twice.
