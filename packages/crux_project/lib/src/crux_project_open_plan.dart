// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_project/src/crux_project_manifest.dart';
import 'package:meta/meta.dart';

/// Why a product could not open anything from a manifest.
enum CruxOpenRefusal {
  /// The manifest names no artifact of the kind this product consumes, and no
  /// fallback applied. Normal for a design whose lint project has not been
  /// created yet — a state to report plainly, not an error.
  kindAbsent,

  /// The manifest names the artifact, but the path does not exist on disk.
  /// Usually a dump that has not been regenerated.
  pathMissing,
}

/// What one product should do with a manifest.
///
/// Produced by [CruxProjectOpenPlanner.plan]. Either [artifactPath] is non-null
/// and the product hands it to its existing open flow unchanged, or [refusal]
/// explains why there is nothing to open.
///
/// [designId] is populated in **both** cases, because a product that cannot
/// open anything may still want to join the design's cross-probe identity.
@immutable
class CruxProjectOpenPlan {
  /// Creates a plan.
  const CruxProjectOpenPlan({
    required this.manifest,
    required this.designId,
    this.artifactPath,
    this.sources = const <String>[],
    this.top,
    this.refusal,
  });

  /// The manifest this plan came from.
  final CruxProjectManifest manifest;

  /// The CXP design id for this design.
  ///
  /// Derived from the manifest's **directory**, not from the artifact — that is
  /// what makes the manifest transparent. Opening
  /// `design/design.crux-project` and opening `design/sim/dump.vcd` directly
  /// must yield the same id, or half the suite's cross-probe silently stops
  /// joining. The manifest's file name plays no part, so renaming a legacy
  /// `.crux-project` keeps the id.
  final String designId;

  /// The file this product should open, or null when [refusal] is set.
  final String? artifactPath;

  /// Resolved RTL sources, for a product that elaborates rather than opens a
  /// single artifact (NetCrux with no `netlist` key).
  final List<String> sources;

  /// The declared top module, when the manifest names one.
  final String? top;

  /// Why nothing can be opened, or null on success.
  final CruxOpenRefusal? refusal;

  /// Whether the product has something to act on — an artifact or sources.
  bool get isActionable => artifactPath != null || sources.isNotEmpty;
}

/// Turns a manifest into a per-product open plan.
///
/// The whole point of putting this in the shared package rather than in four
/// products is the design-id rule: every product must derive it from the
/// manifest directory, the same way, or cross-probe between manifest-opened
/// designs stops working in a way nothing will notice until a user reports that
/// half their sends do nothing.
class CruxProjectOpenPlanner {
  /// Creates a planner.
  const CruxProjectOpenPlanner();

  /// Plans the open for a product that consumes the artifact key [kind].
  ///
  /// Kinds are opaque manifest keys; the caller owns the constant. See
  /// [CruxProjectManifest] for why this package does not name them.
  ///
  /// [fallbackKinds] are tried in order when [kind] is absent — an elaborating
  /// product passes its source key so a manifest with sources but no pre-built
  /// artifact still opens. [includeSources] makes the plan carry the resolved
  /// source list, which only an elaborating product needs.
  ///
  /// [exists] is injectable so tests do not need a filesystem; production
  /// callers use the default.
  CruxProjectOpenPlan plan(
    CruxProjectManifest manifest, {
    required String kind,
    List<String> fallbackKinds = const <String>[],
    bool includeSources = false,
    bool Function(String path)? exists,
  }) {
    final designId = cxpDesignIdForPath(manifest.directory);
    final sources = includeSources ? manifest.sources : const <String>[];
    final onDisk = exists ?? _defaultExists;

    String? chosen;
    for (final k in <String>[kind, ...fallbackKinds]) {
      final path = manifest.artifact(k);
      if (path != null) {
        chosen = path;
        break;
      }
    }

    if (chosen == null) {
      // Sources alone are actionable for an elaborating product, so this is
      // only a refusal when there is genuinely nothing.
      return CruxProjectOpenPlan(
        manifest: manifest,
        designId: designId,
        sources: sources,
        top: manifest.top,
        refusal: sources.isEmpty ? CruxOpenRefusal.kindAbsent : null,
      );
    }

    if (!onDisk(chosen)) {
      return CruxProjectOpenPlan(
        manifest: manifest,
        designId: designId,
        sources: sources,
        top: manifest.top,
        refusal: CruxOpenRefusal.pathMissing,
      );
    }

    return CruxProjectOpenPlan(
      manifest: manifest,
      designId: designId,
      artifactPath: chosen,
      sources: sources,
      top: manifest.top,
    );
  }

  static bool _defaultExists(String path) =>
      File(path).existsSync() || Directory(path).existsSync();
}
