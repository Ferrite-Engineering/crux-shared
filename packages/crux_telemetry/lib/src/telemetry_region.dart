// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart' show Locale;

/// Countries where the first-launch disclosure must arrive with the toggle
/// **off** — the EEA, the United Kingdom, Switzerland, and South Korea.
///
/// This overrides the suite's default-on decision for these regions and
/// nowhere else. The
/// reasoning is ePrivacy rather than GDPR: `installation_id` is a persistent
/// identifier **written to the user's device**, which is storage on terminal
/// equipment under Art. 5(3) and needs consent unless it is strictly necessary
/// to deliver something the user asked for. Feature analytics is not, by any
/// reading, and an opt-out default cannot supply consent.
///
/// The EEA is the EU 27 plus Iceland, Liechtenstein and Norway; the UK and
/// Switzerland are here because they carry their own equivalents of the same
/// rule, not because they are in the EEA. South Korea is here because PIPA is
/// a consent-first regime and the privacy policy names Korea alongside the
/// other three: the code and the policy have to agree.
const Set<String> kTelemetryOptInCountries = <String>{
  // EU 27.
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR',
  'DE', 'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL',
  'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE',
  // EEA, non-EU.
  'IS', 'LI', 'NO',
  // Own equivalents of the same rule.
  'GB', 'CH', 'KR',
};

/// The IANA prefix under which every zone is treated as an opt-in region.
///
/// Wider than [kTelemetryOptInCountries] on purpose: `Europe/Moscow`,
/// `Europe/Istanbul`, `Europe/Kyiv` and `Europe/Minsk` sit under it and none
/// of those countries is an opt-in region. That is the same trade
/// [telemetryRequiresOptIn] already makes with the locale list — a false
/// positive costs one measured installation, a false negative is collection
/// without consent — and listing the sixty-odd European zones one by one
/// would buy precision nobody needs at the cost of a list that rots every
/// time the IANA database renames one.
const String kTelemetryOptInTimeZonePrefix = 'Europe/';

/// IANA zones outside `Europe/` that place a machine in an opt-in region.
///
/// Territory the IANA database files elsewhere: the Atlantic islands of
/// Iceland, Portugal and Spain; Svalbard and Jan Mayen; Cyprus; Ceuta and
/// Melilla; the French overseas departments, where the GDPR applies in full;
/// and South Korea. No `Europe/` zone belongs here — the prefix covers those.
const Set<String> kTelemetryOptInTimeZones = <String>{
  'Atlantic/Reykjavik',
  'Atlantic/Azores',
  'Atlantic/Madeira',
  'Atlantic/Canary',
  'Arctic/Longyearbyen',
  'Atlantic/Jan_Mayen',
  'Asia/Nicosia',
  'Asia/Famagusta',
  'Africa/Ceuta',
  'America/Cayenne',
  'America/Guadeloupe',
  'America/Marigot',
  'America/Martinique',
  'Indian/Reunion',
  'Indian/Mayotte',
  'Asia/Seoul',
};

/// Whether an IANA [timeZone] places the machine in an opt-in region.
///
/// `null` — no zone available — is not evidence of anything and answers
/// false, for the same reason a locale with no country does. The match is
/// exact and case-sensitive because that is how browsers report the zone;
/// nothing here normalises, so `europe/berlin` falls through, and that is a
/// bug in the caller rather than a case this predicate should absorb.
bool telemetryTimeZoneRequiresOptIn(String? timeZone) =>
    timeZone != null &&
    (timeZone.startsWith(kTelemetryOptInTimeZonePrefix) ||
        kTelemetryOptInTimeZones.contains(timeZone));

/// Matches a Unicode region override, the `rg` key, in either spelling: the
/// POSIX-style keyword `@rg=gbzzzz` Apple platforms write into a locale
/// identifier, and the BCP 47 extension `-u-rg-gbzzzz`. The value is a region
/// subtag followed by a subdivision suffix, `zzzz` for "the whole region".
final RegExp _regionOverride = RegExp(
  r'(?:^|[@;\-_])rg[=\-]([a-z]{2})[a-z0-9]{1,4}',
  caseSensitive: false,
);

/// The countries a platform locale identifier names, upper-cased.
///
/// Accepts every spelling the platforms hand over: BCP 47 (`en-GB`,
/// `zh-Hans-CN`), POSIX (`en_GB.UTF-8`, `sr_RS@latin`), Apple identifiers
/// with a region override (`en_US@rg=gbzzzz`, which is how macOS and iOS
/// write "language US English, region United Kingdom"), and the BCP 47 form
/// of that override (`en-US-u-rg-gbzzzz`). An override contributes its
/// region **in addition to** the base country rather than instead of it: both
/// are settings the user made, and either is enough for
/// [telemetryRequiresOptIn].
///
/// A numeric region (`es-419`), a script, a variant, and the `C` and `POSIX`
/// locales name no country and contribute nothing.
Set<String> telemetryCountriesInLocaleId(String localeId) {
  final countries = <String>{};
  for (final match in _regionOverride.allMatches(localeId)) {
    countries.add(match.group(1)!.toUpperCase());
  }
  final base = localeId.split(RegExp('[.@]')).first;
  final subtags = base.split(RegExp('[-_]'));
  for (final subtag in subtags.skip(1)) {
    if (subtag.length == 4) continue;
    if (subtag.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(subtag)) {
      countries.add(subtag.toUpperCase());
    }
    break;
  }
  return countries;
}

/// Whether the first-launch toggle must default to off, given the platform's
/// preferred [locales], the countries its region settings name ([regions]),
/// and, where the platform can name one, its IANA [timeZone].
///
/// **Deliberately over-inclusive.** It reads the user's *whole* preferred
/// locale list rather than only the first, and answers true if any entry names
/// an opt-in country. Someone in Berlin whose first preference is `en-US` and
/// whose second is `de-DE` gets the opt-in default, the error worth making:
/// a false positive costs one measured installation, a false negative is
/// collection without consent. Every signal is enough on its own; none can
/// veto another.
///
/// **The region setting is its own signal.** The locale list is the user's
/// *languages*, and on macOS, iOS and Windows the region is set separately: a
/// laptop set to US English with its region set to the United Kingdom reports
/// `en-US` in the list and `GB` here. [regions] carries what
/// `telemetryPlatformRegionsProvider` reads from the operating system on
/// desktop and mobile, and is empty on the web, where a page cannot see it.
///
/// **A locale with no country is not evidence of anything**, and is treated as
/// such — `en` alone leaves the default on. Browsers commonly report a bare
/// language tag, which is why the time zone exists as a signal there: the
/// browser's resolved time zone almost always carries a place, so a `de` or
/// `en` locale paired with `Europe/Berlin` answers true. Off the web no zone is
/// supplied — the VM exposes only an abbreviation, and `IST` is Dublin as well
/// as Kolkata — and the region setting takes its place. The alternative,
/// treating "unknown" as opt-in, would flip a large share of the world's web
/// users off on the strength of no evidence, which is a much larger price than
/// the remaining gap costs.
///
/// Locale, region setting and time zone are the only local region signals
/// that cost nothing and collect nothing. The Worker's `country` stamp is more
/// accurate and cannot be used here: it is derived from an event that consent
/// has not yet permitted, so it arrives strictly after the moment this
/// decision has to be made.
bool telemetryRequiresOptIn(
  Iterable<Locale> locales, {
  String? timeZone,
  Iterable<String> regions = const <String>[],
}) =>
    telemetryTimeZoneRequiresOptIn(timeZone) ||
    regions.any(
      (country) => kTelemetryOptInCountries.contains(country.toUpperCase()),
    ) ||
    locales.any((locale) {
      final country = locale.countryCode;
      return country != null &&
          kTelemetryOptInCountries.contains(country.toUpperCase());
    });

/// The position the first-launch toggle should arrive in for [locales],
/// [regions] and [timeZone].
///
/// The inverse of [telemetryRequiresOptIn], named for what the widget actually
/// consumes so no call site has to remember which way round the negation goes.
bool telemetryDefaultConsentFor(
  Iterable<Locale> locales, {
  String? timeZone,
  Iterable<String> regions = const <String>[],
}) => !telemetryRequiresOptIn(locales, timeZone: timeZone, regions: regions);
