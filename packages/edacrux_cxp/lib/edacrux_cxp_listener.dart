// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The pieces a program that listens for peers shares with one that only
/// dials them.
///
/// A program that only dials peers (the `CxpProbe` client) never needs this
/// library: the transports in `package:edacrux_cxp/edacrux_cxp.dart` apply the newline
/// framing themselves. It is a second entry point so that the listener the
/// Crux apps use, which lives in their own package, shares one splitter and
/// one network-path rule with the client instead of carrying copies, without
/// either becoming part of the surface an ordinary client is versioned
/// against.
library;

export 'src/cxp_network_path.dart';
export 'src/line_framing.dart';
