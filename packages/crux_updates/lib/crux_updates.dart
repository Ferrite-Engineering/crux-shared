// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite update-check mechanism for the EDACrux suite.
///
/// One implementation of "is there a newer release, and how do I tell the
/// user?" for every product in the suite: the version-manifest model with
/// fail-soft parsing and semver comparison, the HTTP fetch service and its
/// no-op counterpart, the Riverpod status notifier that drives launch,
/// periodic and manual checks, and the dismissible update banner.
///
/// Everything product-specific is configuration: the manifest URI, the product
/// name, and the download/store targets arrive as a `CruxUpdateConfig` through
/// `cruxUpdateConfigProvider`; the user-visible copy arrives as a
/// `CruxUpdateStrings` through `cruxUpdateStringsProvider`; the persisted
/// "automatically check for updates" setting, the observed-server-time sink,
/// the URL launcher and the build-info source are all injectable providers the
/// host overrides. See the package README for the wiring snippet.
library;

export 'src/crux_update_config.dart';
export 'src/crux_update_strings.dart';
export 'src/models/managed_install.dart';
export 'src/models/update_edition.dart';
export 'src/models/update_manifest.dart';
export 'src/models/update_policy.dart';
export 'src/models/update_status.dart';
export 'src/providers/managed_install_provider.dart';
export 'src/providers/update_check_service_provider.dart';
export 'src/providers/update_seam_providers.dart';
export 'src/providers/update_status_provider.dart';
export 'src/services/http_update_check_service.dart';
export 'src/services/managed_install_probe.dart';
export 'src/services/noop_update_check_service.dart';
export 'src/services/policy_constrained_update_check_service.dart';
export 'src/update_check_action.dart';
export 'src/update_check_service.dart';
export 'src/widgets/update_available_banner.dart';
export 'src/widgets/update_banner.dart';
export 'src/widgets/update_banner_metrics.dart';
