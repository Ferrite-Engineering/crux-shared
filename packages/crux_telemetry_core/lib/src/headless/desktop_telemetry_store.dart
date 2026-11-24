// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_telemetry_core/src/models/telemetry_consent_state.dart';
import 'package:crux_telemetry_core/src/storage/telemetry_storage.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The four products whose desktop app records a telemetry consent.
enum CruxTelemetryProduct {
  /// WaveCrux.
  wavecrux('wavecrux', 'WaveCrux'),

  /// NetCrux.
  netcrux('netcrux', 'NetCrux'),

  /// LintCrux.
  lintcrux('lintcrux', 'LintCrux'),

  /// SimCrux.
  simcrux('simcrux', 'SimCrux');

  const CruxTelemetryProduct(this.slug, this.displayName);

  /// The `product` envelope field, one of the Worker's `PRODUCTS`.
  final String slug;

  /// The display name: the `User-Agent` token, and the Windows `ProductName`
  /// the desktop app's preferences directory is named after.
  final String displayName;
}

/// One place a desktop app records its telemetry consent and installation id,
/// read from another process.
///
/// Reads only. Nothing here ever writes, mints or deletes: the consent is the
/// desktop app's record, and a headless process that wrote it would be a
/// second consent channel.
abstract interface class DesktopTelemetryStore {
  /// The stored value for [key] (`kTelemetryConsentKey` or
  /// `kTelemetryInstallationIdKey`), or `null` when nothing is stored or the
  /// store cannot be read. Never throws.
  String? read(String key);
}

/// Runs a program and returns what it printed; `Process.runSync` in
/// production, a fake in tests.
typedef DesktopStoreProcessRunner =
    ProcessResult Function(String executable, List<String> arguments);

/// The macOS preferences domain a Flutter desktop app's `SharedPreferences`
/// writes, read through `defaults` so the answer is what `cfprefsd` holds now
/// rather than a property list on disk that may not have been written back
/// yet.
@immutable
class MacOsDefaultsTelemetryStore implements DesktopTelemetryStore {
  /// The store in preferences [domain] (a bundle identifier).
  const MacOsDefaultsTelemetryStore(this.domain, {this.run = Process.runSync});

  /// The preferences domain.
  final String domain;

  /// Runs `defaults`.
  final DesktopStoreProcessRunner run;

  @override
  String? read(String key) {
    try {
      final result = run('/usr/bin/defaults', <String>[
        'read',
        domain,
        '$kFlutterPreferencesPrefix$key',
      ]);
      if (result.exitCode != 0) return null;
      final out = result.stdout;
      if (out is! String) return null;
      return out.endsWith('\n') ? out.substring(0, out.length - 1) : out;
    } on Object {
      return null;
    }
  }

  @override
  String toString() => 'defaults $domain';
}

/// A JSON document of string values: the `shared_preferences.json` a Flutter
/// desktop app writes on Linux and Windows, or LintCrux's own store.
///
/// [directories] are tried in order and the first that exists is the one
/// read, the way `path_provider` on Linux picks its application directory;
/// when none exists nothing is stored.
@immutable
class JsonFileTelemetryStore implements DesktopTelemetryStore {
  /// The document [fileName] in the first existing of [directories], whose
  /// keys carry [keyPrefix].
  const JsonFileTelemetryStore(
    this.directories,
    this.fileName, {
    this.keyPrefix = '',
  });

  /// Where the document may be, in order.
  final List<String> directories;

  /// The document's name.
  final String fileName;

  /// What the writer puts in front of every key (`flutter.` for
  /// `SharedPreferences`).
  final String keyPrefix;

  @override
  String? read(String key) {
    try {
      for (final directory in directories) {
        if (!Directory(directory).existsSync()) continue;
        final file = File(p.join(directory, fileName));
        if (!file.existsSync()) return null;
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is! Map<String, Object?>) return null;
        final value = decoded['$keyPrefix$key'];
        return value is String ? value : null;
      }
      return null;
    } on Object {
      return null;
    }
  }

  @override
  String toString() => 'file ${directories.join(' | ')} $fileName';
}

/// The prefix `SharedPreferences` puts in front of every key it stores.
const String kFlutterPreferencesPrefix = 'flutter.';

/// Where [product]'s desktop app records its consent on this machine: the
/// edition this process belongs to ([pro]) first, the other edition second.
///
/// The open core and the Pro overlay are different applications to the
/// operating system (`com.ferriteengineering.wavecrux` and
/// `com.ferriteengineering.wavecruxPro` on macOS), so each records its own
/// answer and its own installation id; [DesktopTelemetryConsent] reads them
/// in this order. LintCrux keeps one store for both editions, outside the
/// preferences layer, so its list has one entry.
///
/// [operatingSystem], [environment] and [run] are injectable for tests.
/// Returns an empty list when the home or application-data variable the
/// platform needs is missing: no store, so no consent.
List<DesktopTelemetryStore> desktopTelemetryStores(
  CruxTelemetryProduct product, {
  required bool pro,
  String? operatingSystem,
  Map<String, String>? environment,
  DesktopStoreProcessRunner run = Process.runSync,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final env = environment ?? Platform.environment;
  final ctx = os == 'windows' ? p.windows : p.posix;
  String? variable(String name) {
    final value = env[name];
    return value == null || value.isEmpty ? null : value;
  }

  final home = variable('HOME');
  final appData = variable('APPDATA');
  final xdgData =
      variable('XDG_DATA_HOME') ??
      (home == null ? null : ctx.join(home, '.local', 'share'));

  if (product == CruxTelemetryProduct.lintcrux) {
    // LintCrux's adapter writes a plain file both editions share, so its
    // headless `--ci` path could read it; the path is
    // `lintcruxTelemetryStorePath` in LintCrux.
    final base = switch (os) {
      'macos' when home != null => ctx.join(
        home,
        'Library',
        'Application Support',
      ),
      'windows' => appData,
      'macos' => null,
      _ => xdgData,
    };
    if (base == null) return const <DesktopTelemetryStore>[];
    return <DesktopTelemetryStore>[
      JsonFileTelemetryStore(
        <String>[ctx.join(base, 'crux', 'telemetry')],
        'lintcrux.json',
      ),
    ];
  }

  DesktopTelemetryStore? edition({required bool proEdition}) {
    switch (os) {
      case 'macos':
        // PRODUCT_BUNDLE_IDENTIFIER of each edition's macOS runner.
        return MacOsDefaultsTelemetryStore(
          'com.ferriteengineering.${product.slug}${proEdition ? 'Pro' : ''}',
          run: run,
        );
      case 'windows':
        // `path_provider`'s application-support directory: the roaming
        // application data, then the runner's CompanyName and ProductName.
        if (appData == null) return null;
        return JsonFileTelemetryStore(
          <String>[
            ctx.join(
              appData,
              'com.ferriteengineering',
              '${product.displayName}${proEdition ? ' Pro' : ''}',
            ),
          ],
          'shared_preferences.json',
          keyPrefix: kFlutterPreferencesPrefix,
        );
      default:
        // `path_provider` on Linux: the XDG data directory named after the
        // runner's APPLICATION_ID, or after the executable when only that
        // older directory exists.
        if (xdgData == null) return null;
        final binary = '${product.slug}${proEdition ? '_pro' : ''}';
        return JsonFileTelemetryStore(
          <String>[
            ctx.join(xdgData, 'com.ferriteengineering.$binary'),
            ctx.join(xdgData, binary),
          ],
          'shared_preferences.json',
          keyPrefix: kFlutterPreferencesPrefix,
        );
    }
  }

  return <DesktopTelemetryStore>[
    ?edition(proEdition: pro),
    ?edition(proEdition: !pro),
  ];
}

/// What a desktop app recorded: its answer, and the installation id that
/// goes with it.
@immutable
class DesktopTelemetryAnswer {
  /// An answer of [consent], with [installationId], read from [store].
  const DesktopTelemetryAnswer(
    this.consent, {
    this.installationId,
    this.store,
  });

  /// Nothing recorded anywhere.
  static const DesktopTelemetryAnswer none = DesktopTelemetryAnswer(
    TelemetryConsentState.unset,
  );

  /// The recorded answer; [TelemetryConsentState.unset] when there is none.
  final TelemetryConsentState consent;

  /// The installation id the same app stored beside an `enabled` answer, when
  /// it is one the Worker accepts; `null` otherwise.
  final String? installationId;

  /// Where the answer was read; `null` when there was none.
  final DesktopTelemetryStore? store;

  /// Whether this answer lets an event be sent: an explicit `enabled` and an
  /// installation id to send it under. An id is never minted here: a process
  /// that minted one would create an identity the user never agreed to.
  bool get sendable =>
      consent == TelemetryConsentState.enabled && installationId != null;
}

/// The consent a product's desktop app recorded on this machine, read on
/// every [read] so an answer changed in the app takes effect at once.
@immutable
class DesktopTelemetryConsent {
  /// Reads [stores] in order (see [desktopTelemetryStores]).
  const DesktopTelemetryConsent(this.stores);

  /// Where to look, the edition this process belongs to first.
  final List<DesktopTelemetryStore> stores;

  /// The first answer recorded.
  ///
  /// A store holding no answer, `unset`, or a value this build does not
  /// recognise is passed over; the first `enabled` or `disabled` decides,
  /// because that is the answer the user gave to that edition, and an
  /// edition this process is not is consulted only when its own edition
  /// never asked. Never throws.
  DesktopTelemetryAnswer read() {
    for (final store in stores) {
      final consent = TelemetryConsentState.tryParse(
        store.read(kTelemetryConsentKey),
      );
      switch (consent) {
        case null || TelemetryConsentState.unset:
          continue;
        case TelemetryConsentState.disabled:
          return DesktopTelemetryAnswer(
            TelemetryConsentState.disabled,
            store: store,
          );
        case TelemetryConsentState.enabled:
          final id = store.read(kTelemetryInstallationIdKey);
          return DesktopTelemetryAnswer(
            TelemetryConsentState.enabled,
            installationId:
                id != null && kTelemetryInstallationIdPattern.hasMatch(id)
                ? id
                : null,
            store: store,
          );
      }
    }
    return DesktopTelemetryAnswer.none;
  }
}
