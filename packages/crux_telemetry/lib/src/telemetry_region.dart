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

/// Whether the first-launch toggle must default to off, given the platform's
/// preferred [locales] and, where the platform can name one, its IANA
/// [timeZone].
///
/// **Deliberately over-inclusive.** It reads the user's *whole* preferred
/// locale list rather than only the first, and answers true if any entry names
/// an opt-in country. Someone in Berlin whose first preference is `en-US` and
/// whose second is `de-DE` gets the opt-in default, the error worth making:
/// a false positive costs one measured installation, a false negative is
/// collection without consent. Either signal is enough on its own; neither can
/// veto the other.
///
/// **A locale with no country is not evidence of anything**, and is treated as
/// such — `en` alone leaves the default on. Browsers commonly report a bare
/// language tag, which is why the second signal exists: the browser's resolved
/// time zone almost always carries a place, so a `de` or `en` locale paired
/// with `Europe/Berlin` answers true. Off the web no zone is supplied — the VM
/// exposes only an abbreviation, and `IST` is Dublin as well as Kolkata — so
/// desktop and mobile builds are placed by locale alone. The alternative,
/// treating "unknown" as opt-in, would flip a large share of the world's web
/// users off on the strength of no evidence, which is a much larger price than
/// the remaining gap costs.
///
/// Locale and time zone are the only local region signals that cost nothing
/// and collect nothing. The Worker's `country` stamp is more accurate and
/// cannot be used here: it is derived from an event that consent has not yet
/// permitted, so it arrives strictly after the moment this decision has to be
/// made.
bool telemetryRequiresOptIn(Iterable<Locale> locales, {String? timeZone}) =>
    telemetryTimeZoneRequiresOptIn(timeZone) ||
    locales.any((locale) {
      final country = locale.countryCode;
      return country != null &&
          kTelemetryOptInCountries.contains(country.toUpperCase());
    });

/// The position the first-launch toggle should arrive in for [locales] and
/// [timeZone].
///
/// The inverse of [telemetryRequiresOptIn], named for what the widget actually
/// consumes so no call site has to remember which way round the negation goes.
bool telemetryDefaultConsentFor(
  Iterable<Locale> locales, {
  String? timeZone,
}) => !telemetryRequiresOptIn(locales, timeZone: timeZone);
