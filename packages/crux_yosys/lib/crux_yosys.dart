// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite Yosys subprocess infrastructure for the EDACrux suite.
///
/// Exports `YosysRunner` (spawn yosys + capture write_json output),
/// `YosysAvailabilityService` (probe `yosys -V`),
/// `YosysDiagnosticParser` (structured stderr parsing),
/// `ProcessRunner` / `DefaultProcessRunner` / `ProcessRegistry` (the
/// tool-neutral subprocess seam), and the supporting immutable value
/// types. See the package README for the API surface and what
/// deliberately stays in each consumer.
library;

export 'src/process_registry.dart';
export 'src/process_runner.dart';
export 'src/yosys_availability.dart';
export 'src/yosys_availability_service.dart';
export 'src/yosys_diagnostic.dart';
export 'src/yosys_diagnostic_parser.dart';
export 'src/yosys_run.dart';
export 'src/yosys_runner.dart';
