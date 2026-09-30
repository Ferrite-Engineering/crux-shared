// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/models/update_manifest.dart';
import 'package:crux_updates/src/update_check_service.dart';

/// An [UpdateCheckService] that always reports "up to date".
///
/// Used as a safe fallback before the application build info has loaded (so the
/// real current version is known), on mobile store builds where
/// `CruxUpdateConfig.checkOnMobile` is off, and as a stand-in in tests and
/// builds where no manifest endpoint should be contacted. Allocation-free via
/// the `const` constructor.
class NoopUpdateCheckService implements UpdateCheckService {
  /// Creates the no-op service.
  const NoopUpdateCheckService();

  @override
  Future<UpdateInfo?> checkForUpdate() async => null;
}
