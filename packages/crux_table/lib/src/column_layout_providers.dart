// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_table/src/column_layout.dart';
import 'package:crux_table/src/column_layout_codec.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// What a resize handle drives: the three things a drag on a header divider
/// does to a layout.
///
/// [CruxColumnLayoutNotifier] implements it, so a host hands its notifier to
/// the header; a host without Riverpod, or a test, supplies its own.
abstract interface class CruxColumnResizeController<C extends Enum> {
  /// Drags the divider after [column] by [dx] pixels in a table whose
  /// resizable columns span [tableWidth] pixels. Not saved until [commit].
  void resize(C column, double dx, double tableWidth);

  /// Saves the current widths. Called when a drag ends, so a drag writes
  /// once rather than on every pointer move.
  void commit();

  /// Restores and saves the default widths.
  void reset();
}

/// Notifier backing [CruxColumnLayoutProviders.layout].
class CruxColumnLayoutNotifier<C extends Enum>
    extends Notifier<CruxColumnLayout<C>>
    implements CruxColumnResizeController<C> {
  /// Creates the notifier for its providers. Constructed by
  /// [CruxColumnLayoutProviders]; a host never does.
  CruxColumnLayoutNotifier(this._providers);

  final CruxColumnLayoutProviders<C> _providers;

  @override
  CruxColumnLayout<C> build() => ref.read(_providers.launch);

  @override
  void resize(C column, double dx, double tableWidth) {
    state = state.resize(column, dx, tableWidth);
  }

  @override
  void commit() => unawaited(_save());

  @override
  void reset() {
    state = _providers.columns.defaults;
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await ref.read(_providers.settingsService).save(state);
    } on Object {
      // No preferences backend: the widths still apply to this session.
    }
  }
}

/// The Riverpod seam for one table's persisted column widths.
///
/// A host declares one per table, at the top level, and keeps it for the
/// life of the app:
///
/// ```dart
/// final resultColumnLayout = CruxColumnLayoutProviders<ResultColumn>(
///   columns: resultColumns,
///   prefsKey: 'myapp.resultColumnWeights',
///   name: 'resultColumnLayout',
/// );
/// ```
///
/// Three providers, and one loader:
///
/// - [settingsService] reads and writes the widths. Override it in tests
///   with a `SettingsService(codec, prefsOverride: prefs)`.
/// - [launch] is the layout persisted when this launch started. The host's
///   bootstrap resolves [load] before `runApp` and overrides it with
///   [launchOverride], so the first frame of a restored tab draws its
///   columns at their saved widths rather than jumping to them a moment
///   later. Tests get the defaults with no storage call.
/// - [layout] is the live layout, app-wide rather than per tab: every tab
///   shows the same columns, and a width the user dragged in one is the
///   width they want in the next. Its notifier is the
///   [CruxColumnResizeController] the header's dividers drive.
class CruxColumnLayoutProviders<C extends Enum> {
  /// Creates the providers for [columns], persisting under [prefsKey]. [name]
  /// names the providers for the Riverpod devtools.
  CruxColumnLayoutProviders({
    required this.columns,
    required String prefsKey,
    required String name,
  }) : codec = CruxColumnLayoutCodec<C>(prefsKey: prefsKey, columns: columns) {
    settingsService = Provider<SettingsService<CruxColumnLayout<C>>>(
      (_) => SettingsService<CruxColumnLayout<C>>(codec),
      name: '$name.settingsService',
    );
    launch = Provider<CruxColumnLayout<C>>(
      (_) => columns.defaults,
      name: '$name.launch',
    );
    layout = NotifierProvider<CruxColumnLayoutNotifier<C>, CruxColumnLayout<C>>(
      () => CruxColumnLayoutNotifier<C>(this),
      name: name,
    );
  }

  /// The columns whose widths these providers hold.
  final CruxTableColumns<C> columns;

  /// The codec [settingsService] persists through.
  final CruxColumnLayoutCodec<C> codec;

  /// The [SettingsService] that reads and writes the widths.
  late final Provider<SettingsService<CruxColumnLayout<C>>> settingsService;

  /// The widths persisted when this launch started; see [launchOverride].
  late final Provider<CruxColumnLayout<C>> launch;

  /// The live layout and its notifier.
  late final NotifierProvider<CruxColumnLayoutNotifier<C>, CruxColumnLayout<C>>
  layout;

  /// Loads the persisted widths, or the defaults on any failure.
  ///
  /// [service] is injectable for tests; production passes nothing.
  Future<CruxColumnLayout<C>> load({
    SettingsService<CruxColumnLayout<C>>? service,
  }) async {
    try {
      return await (service ?? SettingsService<CruxColumnLayout<C>>(codec))
          .load();
    } on Object {
      return columns.defaults;
    }
  }

  /// The override that makes [launch] answer [loaded]: the result of [load],
  /// handed to the root `ProviderScope` before the first frame.
  Override launchOverride(CruxColumnLayout<C> loaded) =>
      launch.overrideWithValue(loaded);
}
