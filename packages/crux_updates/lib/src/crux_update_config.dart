// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

/// Default wait for a manifest fetch before it is treated as a failure.
const Duration kUpdateCheckTimeout = Duration(seconds: 10);

/// Default period of the background auto-check.
const Duration kUpdateCheckInterval = Duration(hours: 24);

/// Everything the update mechanism needs to know about the *product* it is
/// checking updates for.
///
/// The one piece of per-product configuration in `crux_updates`. Each product
/// supplies exactly one instance through `cruxUpdateConfigProvider`, which has
/// no default binding — a product that forgets to override it throws at the
/// first read (app wiring) rather than silently never checking for updates.
///
/// ```dart
/// final netCruxUpdateConfig = CruxUpdateConfig(
///   productName: 'NetCrux',
///   manifestUri: 'https://updates.netcrux.app/manifest.json',
///   downloadPageUri: 'https://netcrux.app/download',
/// );
/// ```
@immutable
class CruxUpdateConfig {
  /// Creates an update configuration from URL literals.
  ///
  /// The endpoints are taken as `String`s and parsed here so a product can
  /// declare them as plain literals rather than sprinkling [Uri.parse] over its
  /// wiring. A malformed URL throws [FormatException] at construction — the
  /// same wiring moment the missing-override case throws — never mid-fetch.
  /// Use [CruxUpdateConfig.fromUris] when the caller already holds [Uri]s.
  CruxUpdateConfig({
    required this.productName,
    required String manifestUri,
    required String downloadPageUri,
    String? appStoreUri,
    String? playStoreUri,
    this.checkOnMobile = false,
    this.checkTimeout = kUpdateCheckTimeout,
    this.checkInterval = kUpdateCheckInterval,
  }) : manifestUri = Uri.parse(manifestUri),
       downloadPageUri = Uri.parse(downloadPageUri),
       appStoreUri = appStoreUri == null ? null : Uri.parse(appStoreUri),
       playStoreUri = playStoreUri == null ? null : Uri.parse(playStoreUri);

  /// Creates a configuration from already-parsed [Uri]s.
  const CruxUpdateConfig.fromUris({
    required this.productName,
    required this.manifestUri,
    required this.downloadPageUri,
    this.appStoreUri,
    this.playStoreUri,
    this.checkOnMobile = false,
    this.checkTimeout = kUpdateCheckTimeout,
    this.checkInterval = kUpdateCheckInterval,
  });

  /// The product's display name, e.g. `NetCrux`.
  ///
  /// Used verbatim in two places: the `User-Agent` sent with the manifest fetch
  /// (`NetCrux/1.2.0 (macOS 15.0)`) and — via the English default
  /// `CruxUpdateStringsEn` — the banner message. Products that localize the
  /// banner bake their own name into their ARB string instead, so this only
  /// reaches the UI in the unlocalized default. Keep it a single token without
  /// spaces so the `User-Agent` stays well-formed.
  final String productName;

  /// The public version-manifest endpoint, e.g.
  /// `https://updates.netcrux.app/manifest.json`.
  final Uri manifestUri;

  /// The product's desktop download page — the "Update Now" target on desktop
  /// and web.
  final Uri downloadPageUri;

  /// The product's App Store listing, or `null` when it does not ship on iOS.
  /// Falls back to [downloadPageUri] in [updateTargetFor].
  final Uri? appStoreUri;

  /// The product's Play Store listing, or `null` when it does not ship on
  /// Android. Falls back to [downloadPageUri] in [updateTargetFor].
  final Uri? playStoreUri;

  /// Whether the update check runs on iOS/Android at all. Defaults to `false`.
  ///
  /// Mobile builds update through their app store, so an in-app check is
  /// redundant there — and skipping it keeps the mobile build free of any
  /// outbound network request, which the App Store / Play Store privacy
  /// declarations ("Data Not Collected") depend on. A product whose mobile
  /// build carries a beta expiry that needs the manifest's `server_time` can
  /// opt back in.
  final bool checkOnMobile;

  /// How long a manifest fetch may take before it counts as a failure.
  final Duration checkTimeout;

  /// How often the background auto-check runs.
  final Duration checkInterval;

  /// Resolves the "Update Now" target for the running platform.
  ///
  /// Desktop (and web) deep-link to [downloadPageUri]; iOS/iPadOS to
  /// [appStoreUri] and Android to [playStoreUri] when those are configured,
  /// falling back to [downloadPageUri] when they are not. Pure and
  /// platform-parameterized so the mapping is unit-testable without a host.
  Uri updateTargetFor(TargetPlatform platform, {bool isWeb = false}) {
    if (isWeb) return downloadPageUri;
    return switch (platform) {
      TargetPlatform.iOS => appStoreUri ?? downloadPageUri,
      TargetPlatform.android => playStoreUri ?? downloadPageUri,
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia => downloadPageUri,
    };
  }

  /// Returns a copy with the given fields replaced.
  CruxUpdateConfig copyWith({
    String? productName,
    Uri? manifestUri,
    Uri? downloadPageUri,
    Uri? appStoreUri,
    Uri? playStoreUri,
    bool? checkOnMobile,
    Duration? checkTimeout,
    Duration? checkInterval,
  }) {
    return CruxUpdateConfig.fromUris(
      productName: productName ?? this.productName,
      manifestUri: manifestUri ?? this.manifestUri,
      downloadPageUri: downloadPageUri ?? this.downloadPageUri,
      appStoreUri: appStoreUri ?? this.appStoreUri,
      playStoreUri: playStoreUri ?? this.playStoreUri,
      checkOnMobile: checkOnMobile ?? this.checkOnMobile,
      checkTimeout: checkTimeout ?? this.checkTimeout,
      checkInterval: checkInterval ?? this.checkInterval,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxUpdateConfig &&
          runtimeType == other.runtimeType &&
          productName == other.productName &&
          manifestUri == other.manifestUri &&
          downloadPageUri == other.downloadPageUri &&
          appStoreUri == other.appStoreUri &&
          playStoreUri == other.playStoreUri &&
          checkOnMobile == other.checkOnMobile &&
          checkTimeout == other.checkTimeout &&
          checkInterval == other.checkInterval;

  @override
  int get hashCode => Object.hash(
    productName,
    manifestUri,
    downloadPageUri,
    appStoreUri,
    playStoreUri,
    checkOnMobile,
    checkTimeout,
    checkInterval,
  );

  @override
  String toString() =>
      'CruxUpdateConfig(productName: $productName, '
      'manifestUri: $manifestUri, downloadPageUri: $downloadPageUri, '
      'checkOnMobile: $checkOnMobile)';
}
