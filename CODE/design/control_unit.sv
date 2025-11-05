`timescale 1ns / 1ps
`include "define.sv"

module control_unit (
    input  logic [31:0] inst_code,
    output logic [ 3:0] alu_controls,
    output logic        aluSrcMux_sel,
    output logic        reg_write_en,
    output logic        d_write_en,
    output logic [ 2:0] s_type_controls,
    output logic [ 2:0] i_type_controls,
    output logic [ 2:0] reg_write_data_sel,
    output logic        JALR_sel,
    output logic        JAL_sel,
    output logic        branch
);

    wire  [6:0] funct7 = inst_code[31:25];
    wire  [2:0] funct3 = inst_code[14:12];
    wire  [6:0] opcode = inst_code[6:0];

    logic [8:0] controls;

    assign {reg_write_data_sel, aluSrcMux_sel, reg_write_en, d_write_en, branch, JALR_sel, JAL_sel} = controls;

    // rom[0] = 32'b0000000_00001_00010_000_00011_0110011;
    always_comb begin
        case (opcode)
            // reg_write_data_sel, aluSrcMux_sel, reg_write_en, d_write_en, branch, JALR_sel, JAL_sel
            `OP_R_TYPE :      controls = 9'b000_0_1_0_0_0_0;
            `OP_S_TYPE :      controls = 9'b000_1_0_1_0_0_0;
            `OP_IL_TYPE:      controls = 9'b001_1_1_0_0_0_0;
            `OP_I_TYPE :      controls = 9'b000_1_1_0_0_0_0;
            `OP_B_TYPE :      controls = 9'b000_0_0_0_1_0_0;
            `OP_U_TYPE_LUI :  controls = 9'b010_0_1_0_0_0_0;
            `OP_U_TYPE_AUIPC: controls = 9'b011_0_1_0_0_0_0;
            `OP_JL_TYPE:  controls = 9'b100_0_1_0_0_1_1;
            `OP_J_TYPE:  controls =  9'b100_0_1_0_0_0_1;
            default    : controls = 5'b00000;

        endcase
    end

    always_comb begin
        case (opcode)
            // {function[5], function[2:0]}
            //R-type
            `OP_R_TYPE: alu_controls = {funct7[5], funct3};
            `OP_S_TYPE: alu_controls = `ADD;
            `OP_IL_TYPE: alu_controls = `ADD;
            `OP_I_TYPE : begin
                if({funct7[5], funct3} == 4'b1101) alu_controls = {1'b1, funct3};
                else alu_controls = { 1'b0, funct3};
            end
            `OP_B_TYPE: alu_controls = {1'b0, funct3};
            default: alu_controls = 4'bx;
        endcase
    end


    always_comb begin
        s_type_controls = 3'b000;
        i_type_controls = 3'b000;
        if (opcode == `OP_S_TYPE) begin  // <<<< S-type인지 먼저 확인
            case (funct3)
                `SB: s_type_controls = 3'b001;
                `SH: s_type_controls = 3'b010;
                `SW: s_type_controls = 3'b100;
                default: s_type_controls = 3'b000;
            endcase
        end else if (opcode == `OP_IL_TYPE) begin
            case (funct3)
                `LB:     i_type_controls = 3'b001;
                `LH:     i_type_controls = 3'b010;
                `LW:     i_type_controls = 3'b011;
                `LBU:    i_type_controls = 3'b100;
                `LHU:    i_type_controls = 3'b101;
                default: i_type_controls = 3'b000;
            endcase
        end
    end


endmodule
