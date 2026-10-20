// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

/// Where there is no standard error (the web), the debug console.
void writeDebugStderr(String line) => debugPrint(line);
