// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/src/providers/telemetry_seam_providers.dart';
import 'package:crux_telemetry/src/storage/telemetry_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// The shape the ingestion Worker enforces on `installation_id`.
///
/// Validated on the **read** path, not just the write path: a value that has
/// been hand-edited, truncated, or written by some future build would be
/// rejected by the Worker with a 400 that costs the whole batch, and the batch
/// is not the guilty party. A malformed stored id is re-minted instead.
final RegExp kTelemetryInstallationIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Mints a fresh installation id.
///
/// A **random** v4 UUID from `package:uuid`, whose default generator is
/// `Random.secure()`. Never derived from anything the machine already knows
/// about itself — no MAC address, no serial, no hostname, no disk id, no hash
/// of any of them. The point is not that a fingerprint would be unreadable; it
/// is that a fingerprint would be *stable across reinstalls and correlatable
/// with other data*, and a random UUID is neither.
String mintTelemetryInstallationId() => const Uuid().v4();

/// The installation id sent as the `installation_id` envelope field.
///
/// Minted once on first use and persisted; every later launch reads the same
/// value back, which is what makes "distinct installations" — the headline
/// daily-actives metric — countable at all. Two fresh installs necessarily get
/// two different ids, because the id is drawn from a CSPRNG rather than
/// computed from the host.
final FutureProvider<String> telemetryInstallationIdProvider =
    FutureProvider<String>((ref) async {
      final storage = ref.read(telemetryStorageProvider);

      final stored = await storage.read(kTelemetryInstallationIdKey);
      if (stored != null && kTelemetryInstallationIdPattern.hasMatch(stored)) {
        return stored;
      }

      final minted = mintTelemetryInstallationId();
      await storage.write(kTelemetryInstallationIdKey, minted);
      return minted;
    }, name: 'telemetryInstallationIdProvider');
