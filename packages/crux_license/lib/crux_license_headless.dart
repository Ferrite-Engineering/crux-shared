// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The headless licence tier resolver: what a product's command line and MCP
/// server ask instead of the desktop app's licence controller.
///
/// Flutter-free, like `crux_license_core.dart`, and proved so the same way:
/// `test/headless_license_tier_closure_test.dart` runs a probe importing only
/// this library on the standalone Dart VM and walks its import closure,
/// `crux_policy` included.
///
/// ```dart
/// import 'package:crux_license/crux_license_core.dart';     // tiers, gate
/// import 'package:crux_license/crux_license_headless.dart'; // the resolver
/// ```
///
/// ### Why a library of its own
///
/// Two products shipped a resolver of their own under the same class names
/// before this one existed, and their command-line files import
/// `crux_license_core.dart` beside it. Exporting the shared resolver from
/// that barrel would make every such name ambiguous in those files the moment
/// a product picked up this version, so the shared one lives here until each
/// product deletes its copy, and a host imports it on purpose.
library;

export 'src/headless_license_tier.dart';
