# crux_about_dialog

The cross-suite **About dialog** for the EDACrux suite. One implementation of
the App → About box, rendered by all four Crux products.

Before this package each product hand-rolled its own About surface: WaveCrux
had a full ~640-line dialog; the other products shipped only
Material's stock `showAboutDialog` stub with a hardcoded name/version. This
package lifts WaveCrux's dialog into shared infrastructure so every product
gets the same surface — header with app icon + tier/edition/beta chips, a
build/version/platform info section, optional third-party attributions, a row
of action buttons, and the company branding banner.

## What's shared vs. per-product

The widget is deliberately **provider-agnostic** for product-specific data and
reads only the genuinely cross-suite state itself:

- **Read internally** from `crux_license`: the active `LicenseTier` (drives the
  embedded `EducationalBadge`) and `betaPeriodProvider` (drives the "Public
  Beta" chip). These are the same everywhere, so no product re-wires them.
- **Passed in** by the host: branding (`crux_app_info`'s `ApplicationBranding`),
  build metadata (`AsyncValue<ApplicationBuildInfo>`), the edition label, the
  localized chrome strings (`CruxAboutStrings`), the app icon widget, any
  third-party `AboutAttributionSection`s, and the ordered `AboutAction` buttons.

Localization follows the same caller-supplied-strings pattern as
`crux_license`'s `LicenseBadgeStrings`: the package ships an English
`CruxAboutStringsEn` default; each product provides an `AppLocalizations`-backed
subclass. Product-specific copy (app name, tagline, attribution text, button
labels) is passed as data, sourced from each product's own ARB files.

## Usage

```dart
CruxAboutDialog.show(
  context,
  title: l10n.aboutDialogTitle,
  tagline: l10n.aboutTagline,
  companyTagline: l10n.aboutCompanyName,
  appIcon: const GlowingAppIcon(size: 80),
  branding: ref.watch(applicationBrandingProvider),
  buildInfo: ref.watch(applicationBuildInfoProvider),
  editionLabel: edition == l10n.aboutEditionOpenCore ? '' : edition,
  strings: MyAppAboutStrings(l10n),
  attributions: [
    AboutAttributionSection(
      title: l10n.aboutSectionWellen,
      description: l10n.aboutWellenDescription,
      licenseHeader: l10n.aboutWellenLicenseHeader,
      licenseText: kWellenLicenseText,
    ),
  ],
  actions: [
    AboutAction(
      label: l10n.aboutButtonVisitWebsite,
      icon: Icons.language_outlined,
      onTap: (_) => launchUrl(Uri.parse(branding.websiteUrl)),
    ),
    AboutAction(
      label: l10n.aboutButtonCopyVersionInfo,
      icon: Icons.copy_outlined,
      onTap: info == null
          ? null
          : (ctx) async {
              await Clipboard.setData(
                ClipboardData(
                  text: aboutVersionInfoText(
                    appName: 'MyApp',
                    editionLabel: edition,
                    info: info,
                  ),
                ),
              );
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(l10n.aboutCopiedConfirmation)),
                );
              }
            },
    ),
  ],
);
```

`AboutAction.onTap` receives the **dialog's own** `BuildContext`, so snackbars
and pushed routes attach to the live dialog subtree rather than a stale
ancestor captured at construction time.

`CruxAboutDialog.show` presents a modal dialog on desktop and a pushed
full-screen route on mobile, matching the suite's adaptive convention.

## Dependencies

`flutter`, `flutter_riverpod`, `crux_app_info` (data shapes), `crux_license`
(tier/beta providers + `EducationalBadge`).
