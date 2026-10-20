// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

/// Writes [line] to standard error.
void writeDebugStderr(String line) => stderr.writeln(line);
