// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/src/x_display_facts.dart';

/// See `x_display_probe_ffi.dart`. A browser has no X display.
Future<XDisplayFacts?> readXDisplayFacts() async => null;
