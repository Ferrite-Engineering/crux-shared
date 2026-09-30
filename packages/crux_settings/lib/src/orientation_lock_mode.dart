// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// User preference for device orientation behaviour.
///
/// Applied via `SystemChrome.setPreferredOrientations` on mobile (phone /
/// tablet); ignored on desktop. The default ([auto]) follows the OS-level
/// auto-rotate setting.
enum OrientationLockMode {
  /// Follow the system auto-rotate setting (no lock).
  auto,

  /// Lock to landscape orientations (left and right).
  landscapeLock,

  /// Lock to portrait orientations (up and down).
  portraitLock,

  /// Sensor-driven — same set as [auto] on most platforms but kept as a
  /// distinct preference so users can express intent.
  sensor,
}
