// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Implementation-flow results for the suite.
///
/// The models a flow run is read into (run, steps, verdict, timing paths,
/// source spans and their mapping), METRICS2.1 metric keys with the
/// LibreLane metric table, aggregation and comparison, and the readers for
/// nextpnr's report and log. Pure Dart, so the headless binaries can read a
/// run without Flutter.
///
/// Every reader bounds its input (bytes, JSON depth, key and line length)
/// and throws `FlowReadException`, a `FormatException`, for anything it
/// cannot read; nothing here opens a path a report names.
library;

export 'src/flow_kind.dart';
export 'src/flow_run.dart';
export 'src/flow_step.dart';
export 'src/flow_verdict.dart';
export 'src/metrics/metric_aggregation.dart' show aggregateMetrics;
export 'src/metrics/metric_definition.dart';
export 'src/metrics/metric_diff.dart';
export 'src/metrics/metric_filter.dart';
export 'src/metrics/metric_key.dart';
export 'src/metrics/metrics_document.dart';
export 'src/nextpnr/nextpnr_log_reader.dart';
export 'src/nextpnr/nextpnr_report_reader.dart';
export 'src/nextpnr/nextpnr_results.dart'
    show
        NextpnrClockFrequency,
        NextpnrLog,
        NextpnrReading,
        NextpnrReport,
        NextpnrResourceUse;
export 'src/read_limits.dart'
    show FlowInputLimits, FlowReadException, FlowReadFailure;
export 'src/rtl_mapping.dart';
export 'src/src_span.dart';
export 'src/timing_path.dart' hide nanosecondsToPicoseconds;
