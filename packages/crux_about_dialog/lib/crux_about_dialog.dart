// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite About dialog for the EDACrux suite.
///
/// One `CruxAboutDialog` implementation rendered by every product in the
/// suite. Each product supplies its branding, build metadata,
/// edition label, localized chrome strings, an app icon, optional third-party
/// attribution sections, and the ordered list of action buttons; tier and
/// beta-period state come from `crux_license` providers so the embedded EDU
/// badge and "Public Beta" chip stay consistent across the suite.
///
/// Present it with `CruxAboutDialog.show` — a modal dialog on desktop, a
/// pushed full-screen route on mobile.
library;

export 'src/about_action.dart';
// `AboutSectionHeader` is internal chrome shared between the dialog body and
// the attribution section; it is deliberately not part of the public surface.
export 'src/about_attribution_section.dart' hide AboutSectionHeader;
export 'src/about_strings.dart';
export 'src/crux_about_dialog.dart';
export 'src/vendored_license.dart';
