// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0
//
// A register file and one plain register, for the memory cases of the source
// elaboration. Line numbers here are what the expectations in
// `mapping_test.dart` name.
module regfile (
    input clk,
    input we,
    input [1:0] waddr,
    input [1:0] raddr,
    input [7:0] wdata,
    output [7:0] rdata
);
  reg [7:0] cpuregs [0:3];
  reg [7:0] acc;
  always @(posedge clk) begin
    if (we) cpuregs[waddr] <= wdata + 8'd1;
    acc <= cpuregs[raddr];
  end
  assign rdata = acc;
endmodule
