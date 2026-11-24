// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The protocol revisions every suite server speaks, newest first.
///
/// `initialize` answers with the client's revision when it is one of these,
/// and with the first otherwise. Held here, once, so every server moves to a
/// new revision together.
const List<String> kMcpProtocolVersions = <String>[
  '2025-06-18',
  '2025-03-26',
  '2024-11-05',
];

/// The longest request line a server reads, in bytes, its newline included.
///
/// A longer line is answered with [kJsonRpcInvalidRequest] and an `id` of
/// null, and the server goes on reading at the next line.
const int kMcpMaxLineBytes = 4 * 1024 * 1024;

/// The longest `instructions` paragraph an `initialize` result carries, in
/// characters. It counts against the server's definition budget.
const int kMcpMaxInstructionsLength = 600;

/// JSON-RPC 2.0: the request line is not JSON.
const int kJsonRpcParseError = -32700;

/// JSON-RPC 2.0: not a request (not an object, no method, or a line past
/// [kMcpMaxLineBytes]).
const int kJsonRpcInvalidRequest = -32600;

/// JSON-RPC 2.0: no such method.
const int kJsonRpcMethodNotFound = -32601;

/// JSON-RPC 2.0: an unknown tool, or a `tools/call` with no tool name.
const int kJsonRpcInvalidParams = -32602;

/// JSON-RPC 2.0: the server failed while answering (a bug, never an answer).
const int kJsonRpcInternalError = -32603;
