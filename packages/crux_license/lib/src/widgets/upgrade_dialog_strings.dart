// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Localized strings consumed by `CruxUpgradeDialog` and by the locked panel
/// of `CruxGatedSettingsBody`, which says the same sentence.
///
/// Products supply an `AppLocalizations`-backed subclass that maps each
/// member to the appropriate ARB-generated string so the dialog never bakes
/// in English text. The English-only [CruxUpgradeDialogStringsEn] default is
/// provided so callers can drop the dialog into a prototype, test, or demo
/// without wiring localization first.
///
/// ## The copy contract
///
/// This dialog is where a user who reached for a paid feature decides whether
/// to buy it, so every product says the same thing in the same words. In
/// English:
///
/// * [title]: `Upgrade Required`.
/// * [body]: `“<feature>” requires <tier>.`
/// * [tierNamePro], [tierNameEnterprise]: `<Product> Pro`,
///   `<Product> Enterprise`.
/// * [dismissLabel]: `OK`.
/// * [seePricingLabel]: `See pricing`.
///
/// And the rules behind them:
///
/// * [body] **names the feature**, always. A body that drops `featureName`,
///   or a caller that passes a generic "this feature", tells the user they
///   were refused without saying what for.
/// * The tier is **product-qualified prose**: what the pricing page sells, not
///   the badge chip's abbreviation (`PRO`, `ENT`), which sits beside the title
///   already.
/// * [dismissLabel] is the platform's own OK
///   (`MaterialLocalizations.okButtonLabel`) in every locale, so it matches
///   every other OK the app renders.
/// * One sentence. A second one ("your current license does not include
///   this") is not added: a user with no licence has no current licence, and
///   "requires" has already said it.
///
/// A product binds these strings **once** — open core and Pro overlay read
/// the same adapter — and each product's own tests hold its adapter to this
/// contract in every locale it ships.
@immutable
abstract class CruxUpgradeDialogStrings {
  /// Const constructor for subclasses.
  const CruxUpgradeDialogStrings();

  /// Dialog title: `Upgrade Required`.
  String get title;

  /// Dialog body naming the activated feature and the tier that unlocks
  /// it: `“$featureName” requires $tierName.` [featureName] is the localized
  /// name of what the user reached for; [tierName] is [tierNamePro] or
  /// [tierNameEnterprise].
  String body(String featureName, String tierName);

  /// Prose name of the Pro tier used inside [body], qualified with the
  /// product name (`WaveCrux Pro`). Distinct from the badge chip label
  /// (`PRO`).
  String get tierNamePro;

  /// Prose name of the Enterprise tier used inside [body], qualified with the
  /// product name (`WaveCrux Enterprise`).
  String get tierNameEnterprise;

  /// Label of the dismiss button: the platform's OK.
  String get dismissLabel;

  /// Label of the action that opens the pricing page, e.g. "See pricing".
  ///
  /// Rendered only when the caller supplies somewhere to go. A dialog that
  /// says a feature needs Pro and then offers no way to get Pro is a dead end,
  /// and it is the moment a user is most willing to act.
  String get seePricingLabel;
}

/// Default English [CruxUpgradeDialogStrings] used when callers do not
/// supply their own. Follows the copy contract, except that it cannot
/// product-qualify the tier names: it does not know which product it is in.
/// Every product supplies its own adapter, and that one qualifies them.
class CruxUpgradeDialogStringsEn extends CruxUpgradeDialogStrings {
  /// Creates the default English string set.
  const CruxUpgradeDialogStringsEn();

  @override
  String get title => 'Upgrade Required';

  @override
  String body(String featureName, String tierName) =>
      '“$featureName” requires $tierName.';

  @override
  String get tierNamePro => 'Pro';

  @override
  String get tierNameEnterprise => 'Enterprise';

  @override
  String get dismissLabel => 'OK';

  @override
  String get seePricingLabel => 'See pricing';
}
