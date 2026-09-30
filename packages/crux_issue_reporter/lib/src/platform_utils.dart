// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

/// True when the app is running on a desktop host OS (Linux, macOS, Windows).
///
/// The issue reporter uses this for two host-platform questions the layout
/// system cannot answer: whether to present the reporter as a modal dialog
/// rather than a pushed route, and whether the Screenshot category is
/// available at all (the GitHub mobile new-issue form has no file attach, and
/// there is no file manager to reveal the PNG in).
bool get isCruxDesktopPlatform =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows;

/// True when running on a mobile host OS (iOS or Android) and not in a mobile
/// *browser*, which is web and reports the underlying OS.
bool get isCruxMobilePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);
