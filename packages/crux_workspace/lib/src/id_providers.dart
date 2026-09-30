// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/src/pane_id.dart';
import 'package:crux_workspace/src/tab_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sentinel leaf provider that resolves to the [TabId] of the enclosing
/// per-tab `ProviderContainer`. Each tab container overrides this with its
/// own [TabId] when constructed via `TabContainerManager.containerFor`.
///
/// Reading this provider from the root scope throws [UnimplementedError]
/// because no tab is "active" at the root.
final Provider<TabId> tabIdProvider = Provider<TabId>(
  (ref) => throw UnimplementedError(
    'tabIdProvider must be overridden inside a per-tab ProviderContainer. '
    'Use TabContainerManager.containerFor(tabId) to create one.',
  ),
);

/// Sentinel leaf provider that resolves to the [PaneId] of the enclosing
/// per-pane `ProviderContainer`. Each pane container overrides this with
/// its own [PaneId] when constructed via `PaneContainerManager.containerFor`.
///
/// Reading this provider from the root scope throws [UnimplementedError]
/// because no pane is "active" at the root.
final Provider<PaneId> paneIdProvider = Provider<PaneId>(
  (ref) => throw UnimplementedError(
    'paneIdProvider must be overridden inside a per-pane ProviderContainer. '
    'Use PaneContainerManager.containerFor(paneId) to create one.',
  ),
);
