// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_status.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:meta/meta.dart';

/// Strings that say an educational licence is for non-commercial use: on the
/// status-bar chip ([statusLabel], [statusTooltip]) and in the mark stamped
/// on exports ([exportMark]).
///
/// An educational licence is free and every product reads it offline, so a
/// key could be passed around and nothing on our side would notice. These
/// strings are the deterrent: the holder's own address is on their screen,
/// and work exported under the licence says what it was made with.
///
/// Products supply an ARB-backed subclass; [CruxEduNoticeStringsEn] is the
/// English default.
@immutable
abstract class CruxEduNoticeStrings {
  /// Const constructor for subclasses.
  const CruxEduNoticeStrings();

  /// Text beside the EDU chip in the status bar, e.g. `Non-commercial use`.
  String get statusLabel;

  /// The chip's tooltip and screen-reader label. [email] and [validUntil]
  /// (`yyyy-MM-dd`) are each `null` when the licence does not record them.
  String statusTooltip({String? email, String? validUntil});

  /// The line stamped on an export made under an educational licence, e.g.
  /// `Made with WaveCrux Educational · Non-commercial use only`.
  String exportMark(String productName);
}

/// English [CruxEduNoticeStrings].
class CruxEduNoticeStringsEn extends CruxEduNoticeStrings {
  /// Creates the English string set.
  const CruxEduNoticeStringsEn();

  @override
  String get statusLabel => 'Non-commercial use';

  @override
  String statusTooltip({String? email, String? validUntil}) {
    final whom = email == null
        ? 'Educational license'
        : 'Educational license for $email';
    final until = validUntil == null ? '' : ' Valid until $validUntil.';
    return '$whom. For non-commercial teaching, learning and research '
        'only.$until';
  }

  @override
  String exportMark(String productName) =>
      'Made with $productName Educational · Non-commercial use only';
}

/// Whether [status] runs on an educational licence, from Keygen or
/// self-issued alike. Grace counts: it keeps the licensed tier.
bool cruxIsEduLicense(CruxLicenseStatus status) =>
    status.tier == LicenseTier.edu;

/// The mark to stamp on an export made under [status], or `null` when the
/// licence is not educational and the export carries no mark.
///
/// For exports a person looks at: images, PDFs, SVGs, printed or HTML
/// reports. Never for data a tool reads back (waveform dumps, netlists, CSV,
/// JSON, SARIF, scripts), where a stray line would break the reader.
String? cruxEduExportMark(
  CruxLicenseStatus status,
  String productName, {
  CruxEduNoticeStrings strings = const CruxEduNoticeStringsEn(),
}) => cruxIsEduLicense(status) ? strings.exportMark(productName) : null;
