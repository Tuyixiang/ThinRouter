// Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2018.3 (lin64) Build 2405991 Thu Dec  6 23:36:41 MST 2018
// Date        : Sun Dec 22 09:58:07 2019
// Host        : parallels-Parallels-Virtual-Platform running 64-bit Ubuntu 18.04.3 LTS
// Command     : write_verilog -force -mode synth_stub
//               /media/psf/Home/Desktop/cod19grp4/thinpad_top.srcs/sources_1/ip/pll/pll_stub.v
// Design      : pll
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a100tfgg676-2L
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module pll(clk_100M, clk_125M, clk_200M, clk_20M, reset, 
  locked, clk_in1)
/* synthesis syn_black_box black_box_pad_pin="clk_100M,clk_125M,clk_200M,clk_20M,reset,locked,clk_in1" */;
  output clk_100M;
  output clk_125M;
  output clk_200M;
  output clk_20M;
  input reset;
  output locked;
  input clk_in1;
endmodule
