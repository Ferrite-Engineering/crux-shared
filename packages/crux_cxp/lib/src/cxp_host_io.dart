// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

/// The process environment.
Map<String, String>? cxpHostEnvironment() => Platform.environment;

/// The host operating system, in `Platform.operatingSystem` vocabulary.
String? cxpHostOperatingSystem() => Platform.operatingSystem;
