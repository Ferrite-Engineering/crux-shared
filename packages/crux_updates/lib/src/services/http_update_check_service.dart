// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_updates/src/crux_update_config.dart';
import 'package:crux_updates/src/models/update_manifest.dart';
import 'package:crux_updates/src/update_check_service.dart';
import 'package:http/http.dart' as http;

/// Live [UpdateCheckService] that fetches and parses a product's public version
/// manifest, then compares it against the running build's [currentVersion].
///
/// This is the **default** binding (no secret is involved in a public manifest
/// fetch). The check transmits only the product name, app version and OS — and
/// only via a `User-Agent` header — never any file, design, signal, or identity
/// data.
///
/// Honors the [UpdateCheckService] contract: it returns `null` when current and
/// throws exactly one typed [UpdateCheckException] on any network or parse
/// failure, never a raw transport error.
class HttpUpdateCheckService implements UpdateCheckService {
  /// Creates a service that compares [config]'s manifest against
  /// [currentVersion].
  ///
  /// [osName] is sent in the `User-Agent` for the server-side usage signal.
  /// Inject [client] in tests; production defaults to a fresh [http.Client].
  HttpUpdateCheckService({
    required this.config,
    required this.currentVersion,
    this.osName = '',
    this.onServerTimeObserved,
    this.mobileStore,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// The product configuration supplying the manifest URI, the `User-Agent`
  /// product token, and the fetch timeout.
  final CruxUpdateConfig config;

  /// The running build's version string, compared against `latest.version`.
  final String currentVersion;

  /// The running OS label, included in the `User-Agent` (may be empty).
  final String osName;

  /// Invoked with the manifest's `server_time` on **every** successful fetch
  /// (whether or not an update is offered), so the persisted observed server
  /// time can feed `crux_license`'s beta-expiry clock-tampering hardening.
  /// `null` server times are skipped.
  final void Function(DateTime serverTime)? onServerTimeObserved;

  /// The app store this build ships through (`ios`, `android`), or null for
  /// a desktop build. A store build compares itself with the manifest's
  /// `mobile.<store>` release, never with `latest` (the desktop release),
  /// and is offered nothing when the manifest lists no release for its
  /// store.
  final String? mobileStore;

  final http.Client _client;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    final http.Response response;
    try {
      response = await _client
          .get(config.manifestUri, headers: {'User-Agent': _userAgent})
          .timeout(config.checkTimeout);
    } on Object catch (error) {
      // SocketException, TimeoutException, ClientException, … — all collapse to
      // the single typed failure so nothing raw escapes.
      throw UpdateCheckException('network', error);
    }

    if (response.statusCode != 200) {
      throw UpdateCheckException('http ${response.statusCode}');
    }

    final manifest = UpdateManifest.tryParse(response.body);
    if (manifest == null) {
      // The model fails soft (returns null); the *service* treats an
      // unparseable manifest as a failure so the manual check can report it.
      throw const UpdateCheckException('parse');
    }

    final latest = manifest.latest;

    // Record the authoritative server time on every successful fetch, before
    // the newer/min-supported gate — beta-expiry hardening needs it even when
    // the running build is already current.
    final serverTime = latest.serverTime;
    if (serverTime != null) onServerTimeObserved?.call(serverTime);

    // A store build is offered what its store has live, not the desktop
    // release: desktop releases ship ahead of, or without, a store release.
    final offer = manifest.releaseFor(mobileStore);
    if (offer == null) return null;

    if (!offer.isNewerThan(currentVersion)) return null;

    // A newer version always surfaces. When the running build is below the
    // manifest's min_supported_version floor it is no longer supported, so the
    // update is forced (non-dismissible) regardless of the manifest's own
    // `mandatory` flag.
    if (!offer.meetsMinSupported(currentVersion) && !offer.mandatory) {
      return offer.copyWith(mandatory: true);
    }
    return offer;
  }

  String get _userAgent {
    final suffix = osName.isEmpty ? '' : ' ($osName)';
    return '${config.productName}/$currentVersion$suffix';
  }
}
