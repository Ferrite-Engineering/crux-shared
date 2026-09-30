// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:test/test.dart';

/// Polls [condition] every [interval] until it returns true, failing the
/// enclosing test with [reason] when [timeout] elapses first.
///
/// The conformance suite waits on observable state transitions with
/// bounded polls instead of fixed sleeps: a poll settles as fast as the
/// code under test does, while a slow machine still gets the whole
/// [timeout] budget before the test fails.
Future<void> pollUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(interval);
  }
  if (condition()) return;
  fail('timed out after $timeout: $reason');
}
