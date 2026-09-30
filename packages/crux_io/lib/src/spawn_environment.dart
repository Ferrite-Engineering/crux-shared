// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The value of the variable [name] in [environment], or `null` when it is
/// not set.
///
/// On Windows ([windows] true) variable names are case-insensitive, and the
/// search path is conventionally spelled `Path`. `Platform.environment`
/// already answers case-insensitively there, but a copy of it (a child
/// environment built with `Map.of`, say) does not, so an exact-case miss
/// falls back to a case-insensitive scan. POSIX names are case-sensitive and
/// get the exact lookup only.
String? spawnEnvironmentValue(
  Map<String, String> environment,
  String name, {
  required bool windows,
}) {
  final exact = environment[name];
  if (exact != null || !windows) return exact;
  final wanted = name.toUpperCase();
  for (final entry in environment.entries) {
    if (entry.key.toUpperCase() == wanted) return entry.value;
  }
  return null;
}
