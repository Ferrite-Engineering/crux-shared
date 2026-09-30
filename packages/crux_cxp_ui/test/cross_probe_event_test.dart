// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrossProbeEvent', () {
    final ts = DateTime(2026, 7, 25, 9, 30);

    test('value equality and hashCode', () {
      final a = CrossProbeEvent(
        kind: CrossProbeEventKind.selectionReceived,
        direction: CrossProbeEventDirection.inbound,
        peerLabel: 'SimCrux',
        summary: 'top.sample_a',
        messageKind: 'notify_selection',
        timestamp: ts,
      );
      final b = CrossProbeEvent(
        kind: CrossProbeEventKind.selectionReceived,
        direction: CrossProbeEventDirection.inbound,
        peerLabel: 'SimCrux',
        summary: 'top.sample_a',
        messageKind: 'notify_selection',
        timestamp: ts,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs when kind differs', () {
      final a = CrossProbeEvent(
        kind: CrossProbeEventKind.selectionSent,
        peerLabel: 'NetCrux',
        timestamp: ts,
      );
      final b = CrossProbeEvent(
        kind: CrossProbeEventKind.selectionReceived,
        peerLabel: 'NetCrux',
        timestamp: ts,
      );
      expect(a, isNot(equals(b)));
    });

    test('lifecycle constructors carry no direction', () {
      final connected = CrossProbeEvent.peerConnected(
        peerLabel: 'NetCrux',
        timestamp: ts,
      );
      final disconnected = CrossProbeEvent.peerDisconnected(
        peerLabel: 'NetCrux',
        timestamp: ts,
      );
      expect(connected.kind, CrossProbeEventKind.peerConnected);
      expect(connected.direction, isNull);
      expect(disconnected.kind, CrossProbeEventKind.peerDisconnected);
      expect(disconnected.direction, isNull);
    });
  });
}
