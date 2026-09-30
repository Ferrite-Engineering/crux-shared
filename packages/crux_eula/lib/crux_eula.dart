// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// First-launch End User License Agreement acceptance for the EDACrux suite.
///
/// The agreement counsel finalised is compiled into `kCruxEulaDocument` by
/// `tool/generate-eula-document.py`, so the text the applications present and
/// the text published at `edacrux.app/eula` come from one source. Acceptance is
/// recorded as the **version** accepted, not a boolean, because EULA section
/// 2.3 requires active re-acceptance when the agreement changes.
///
/// A host mounts `CruxEulaGate` inside `MaterialApp`, outside any
/// `TelemetryConsentGate` and inside any beta-expiry gate, and binds
/// `cruxEulaStorageProvider` to its own preferences layer. The two optional
/// seams — `cruxEulaOnDeclineProvider` and `cruxEulaOpenOnlineProvider` —
/// hide their controls rather than render dead ones when left unbound.
library;

export 'src/crux_eula_strings.dart';
export 'src/eula_document.dart';
export 'src/providers/eula_acceptance_store.dart';
export 'src/providers/eula_seam_providers.dart';
export 'src/storage/eula_storage.dart';
export 'src/widgets/crux_eula_gate.dart';
export 'src/widgets/eula_acceptance_dialog.dart';
export 'src/widgets/eula_metrics.dart';
