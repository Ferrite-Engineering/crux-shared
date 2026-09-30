// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A host without `dart:io` — a browser. It has no process environment and no
/// operating system to report, so both lookups answer null.
library;

/// The process environment: none to read.
Map<String, String>? cxpHostEnvironment() => null;

/// The host operating system: none to ask.
String? cxpHostOperatingSystem() => null;
