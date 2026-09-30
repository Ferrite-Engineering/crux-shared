// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// Canonical ids for the settings categories the suite shares.
///
/// The suite fixes the settings rail's category order and per-category icon, so
/// every product's Settings dialog reads the same, and for a long time nothing
/// enforced it: [CruxSettingsCategory] carried only an icon, a title and a
/// widget, so there was no stable handle a conformance test could assert
/// against. (The Pro extension seam, `CruxSettingsExtraCategory`, has had a
/// stable `pro.*` id since it shipped — the extension point was more
/// introspectable than the thing it extended.)
///
/// These are **identity**, not display text. They never reach the user, are
/// never localized, and must not be renamed to match a product's phrasing.
/// Name them for the slot, not for the label a product puts in it — the four
/// products title [productDefaults] four different ways and all four take that
/// one id. Shared code must not carry a single-product domain vocabulary;
/// `crux_workspace`'s charter-vocabulary guard enforces that.
///
/// A product exposes only the subset it has. Order is asserted by each
/// product's settings conformance test against [canonicalOrder].
abstract final class CruxSettingsCategoryId {
  /// Auto-check-updates, restore-tabs-on-launch, product general knobs.
  static const String general = 'general';

  /// Language, font/legibility knobs, colour theme presets.
  static const String appearance = 'appearance';

  /// Telemetry consent. Conditional — products render it only on a build
  /// whose pipeline can actually transmit.
  static const String privacy = 'privacy';

  /// The product's own defaults slot — the third rail position, whatever the
  /// product calls it.
  ///
  /// One id, four titles: each product supplies its own localized label for
  /// its rendering defaults, engine binaries, or simulator configuration. The
  /// slot is what the charter fixes; the wording is the product's.
  static const String productDefaults = 'product-defaults';

  /// WaveCrux's file-association and open-with handling.
  static const String fileHandling = 'file-handling';

  /// WaveCrux's mobile orientation lock.
  static const String orientation = 'orientation';

  /// External editor command and click-to-source presets.
  static const String editors = 'editors';

  /// WaveCrux's WCP remote-control server.
  static const String remoteControl = 'remote-control';

  /// The shared cross-probe (CXP) controls.
  static const String cxp = 'cxp';

  /// WaveCrux's decoder/translator extension management.
  static const String extensions = 'extensions';

  /// SimCrux's pass/fail detector configuration.
  static const String detectors = 'detectors';

  /// The keybinding editor.
  static const String shortcuts = 'shortcuts';

  /// WaveCrux's flagged AI assistant section.
  static const String ai = 'ai';

  /// The canonical rail order every product follows.
  ///
  /// A product's own categories must appear in this relative order; ids it
  /// does not implement are simply absent. Pro-contributed
  /// `CruxSettingsExtraCategory` entries always follow all of these, so they
  /// are deliberately not listed.
  static const List<String> canonicalOrder = <String>[
    general,
    appearance,
    privacy,
    productDefaults,
    fileHandling,
    orientation,
    editors,
    remoteControl,
    cxp,
    extensions,
    detectors,
    shortcuts,
    ai,
  ];
}

/// One selectable category in a master-detail Settings panel: a rail label
/// (icon + title) paired with the detail content it reveals.
///
/// The host product builds one per settings group it wants to expose and
/// passes the list to `CruxSettingsMasterDetail`. The [content] is typically
/// one or more `CruxSettingsCard`s.
@immutable
class CruxSettingsCategory {
  /// Creates a settings category.
  const CruxSettingsCategory({
    required this.id,
    required this.icon,
    required this.title,
    required this.content,
  });

  /// Stable, non-localized identity for this category — normally a
  /// [CruxSettingsCategoryId] constant.
  ///
  /// Exists so a conformance test can assert the canonical rail order and
  /// per-category icon without matching on display text, which is localized
  /// and therefore useless as a key. Pro-contributed categories carry their
  /// own `pro.*` ids from `CruxSettingsExtraCategory`.
  final String id;

  /// Leading icon shown in the rail row and (on wide layouts) the
  /// detail-pane title.
  final IconData icon;

  /// Already-localized category name shown in the rail and detail title.
  final String title;

  /// The category's detail content, rendered inside the scrollable detail
  /// pane when this category is selected.
  final Widget content;
}
