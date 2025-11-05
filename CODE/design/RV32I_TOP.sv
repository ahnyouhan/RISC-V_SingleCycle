`timescale 1ns / 1ps

module RV32I_TOP (
    input logic clk,
    input logic rst
);
    logic [31:0] inst_code, inst_read_addr;
    logic [31:0] d_addr, d_write_data, d_read_data;
    logic        d_write_en;
    logic [ 2:0] s_type_controls, i_type_controls;
    logic branch;

    RV32I_Core U_RV32I_CPU (
        .*,
        .d_read_data(d_read_data)
    );
    //inst_mem U_INST_MEM (.*);
    data_mem U_DATA_MEM(
        .clk(clk),
        .d_write_en(d_write_en),
        .d_addr(d_addr),
        .d_write_data(d_write_data),
        .s_type_controls(s_type_controls),
        .i_type_controls(i_type_controls),
        .d_read_data(d_read_data)
    );


endmodule

module RV32I_Core (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] inst_code,
    input  logic [31:0] d_read_data,
    output logic [31:0] inst_read_addr,
    output logic        d_write_en,
    output logic [31:0] d_addr,
    output logic [31:0] d_write_data,


    output logic [ 2:0] s_type_controls,
    output logic [ 2:0] i_type_controls
);  
    logic [3:0] alu_controls;
    logic reg_write_en, w_aluSrcMux_sel;
    logic [2:0] w_reg_write_data_sel;
    logic branch, JALR_sel, JAL_sel;

    control_unit U_CTRL_UNIT (
        .inst_code    (inst_code),
        .alu_controls (alu_controls),
        .aluSrcMux_sel(w_aluSrcMux_sel),
        .reg_write_en (reg_write_en),
        .d_write_en   (d_write_en),
        .s_type_controls(s_type_controls),
        .i_type_controls(i_type_controls),
        .reg_write_data_sel(w_reg_write_data_sel),
        .JALR_sel(JALR_sel),
        .JAL_sel(JAL_sel),
        .branch(branch)

    );
    datapath U_DATAPATH (
        .clk           (clk),
        .rst           (rst),
        .inst_code     (inst_code),
        .alu_controls  (alu_controls),
        .reg_write_en  (reg_write_en),
        .aluSrcMux_sel (w_aluSrcMux_sel),
        .reg_write_data_sel(w_reg_write_data_sel),
        .d_read_data(d_read_data),
        .inst_read_addr(inst_read_addr),
        .d_addr        (d_addr),
        .d_write_data  (d_write_data),
        .branch(branch),
        .JALR_sel(JALR_sel),
        .JAL_sel(JAL_sel)
    );


endmodule
