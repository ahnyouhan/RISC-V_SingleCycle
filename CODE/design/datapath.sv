`timescale 1ns / 1ps
`include "define.sv"

module datapath (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] inst_code,
    input  logic [ 3:0] alu_controls,
    input  logic        reg_write_en,
    input  logic        aluSrcMux_sel,
    input  logic [ 2:0] reg_write_data_sel,
    input  logic        branch,
    input  logic        JALR_sel,
    input  logic        JAL_sel,
    input  logic [31:0] d_read_data,
    output logic [31:0] inst_read_addr,
    output logic [31:0] d_addr,
    output logic [31:0] d_write_data
);

    logic [31:0] w_rf_read_data1, w_rf_read_data2, w_alu_result;
    logic [31:0]
        w_imm_Ext,
        w_aluSrcMux_out,
        w_reg_write_data_out,
        w_pc_jalr_mux_out,
        w_pc_next,
        w_pc_4_out,
        w_ImmPcRs1_out; //w_auipc_out;
    logic pc_mux_sel, btaken;
    //logic [31:0] w_auipc_out;

    assign d_addr = w_alu_result;
    assign d_write_data = w_rf_read_data2;
    assign pc_mux_sel = (branch & btaken) | JAL_sel;

    pc_adder U_IMM_PC_RS1_ADDER (
        .a  (w_imm_Ext),
        .b  (w_pc_jalr_mux_out),
        .sum(w_ImmPcRs1_out)
    );

    mux_2x1 U_JALR_MUX (
        .sel(JALR_sel),
        .x0(inst_read_addr),  
        .x1(w_rf_read_data1),   
        .y(w_pc_jalr_mux_out)     
    );

    mux_2x1 U_PC_MUX_Btype (
        .sel(pc_mux_sel),
        .x0(w_pc_4_out),   
        .x1(w_ImmPcRs1_out),  
        .y(w_pc_next)     
    );

    pc_adder U_PC_ADDER (
        .a  (32'd4),
        .b  (inst_read_addr),
        .sum(w_pc_4_out)
    );
    program_counter U_PC (
        .clk(clk),
        .rst(rst),
        .pc_next(w_pc_next),
        .pc(inst_read_addr)
    );

    register_file U_REG_FILE (
        .clk(clk),
        .read_addr1(inst_code[19:15]),
        .read_addr2(inst_code[24:20]),
        .write_addr(inst_code[11:7]),
        .reg_write_en(reg_write_en),
        .write_data(w_reg_write_data_out),
        .read_data1(w_rf_read_data1),
        .read_data2(w_rf_read_data2)
    );

    mux_5x1 U_RegWdataMux (
        .sel(reg_write_data_sel),
        .x0(w_alu_result),  // 0 : regFile R2
        .x1(d_read_data),  // 1: imm [31:0]
        .x2(w_imm_Ext),   //lui 
        .x3(w_ImmPcRs1_out),   //auipc
        .x4(w_pc_4_out),   // pc+4
        .y(w_reg_write_data_out)  // to ALU R2
    );
    ALU U_ALU (
        .a(w_rf_read_data1),
        .b(w_aluSrcMux_out),
        .alu_controls(alu_controls),
        .alu_result(w_alu_result),
        .btaken(btaken)
    );

    mux_2x1 U_AluSrcMux (
        .sel(aluSrcMux_sel),
        .x0 (w_rf_read_data2),  // 0 : regFile R2
        .x1 (w_imm_Ext),        // 1: imm [31:0]
        .y  (w_aluSrcMux_out)   // to ALU R2
    );

    extend U_Extend (
        .inst_code(inst_code),
        .imm_Ext  (w_imm_Ext)
    );

endmodule


module program_counter (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] pc_next,
    output logic [31:0] pc
);
    register U_PC_REG (
        .clk(clk),
        .rst(rst),
        .d  (pc_next),
        .q  (pc)
    );
endmodule

module register (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] d,
    output logic [31:0] q
);
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            q <= 0;
        end else begin
            q <= d;
        end
    end
endmodule

module register_file (
    input               clk,
    input  logic [ 4:0] read_addr1,
    input  logic [ 4:0] read_addr2,
    input  logic [ 4:0] write_addr,
    input  logic        reg_write_en,
    input  logic [31:0] write_data,
    output logic [31:0] read_data1,
    output logic [31:0] read_data2
);
    logic [31:0] reg_file[0:31];  //32 bit 32개

    initial begin
        for(int i=0; i<32; i++) begin
            reg_file[i] = i;
        end
    end
    

    always_ff @(posedge clk) begin
        if (reg_write_en) begin
            reg_file[write_addr] <= write_data;
        end
    end

    assign read_data1 = (read_addr1 != 0) ? reg_file[read_addr1] : 0;
    assign read_data2 = (read_addr2 != 0) ? reg_file[read_addr2] : 0;

endmodule

module ALU (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [ 3:0] alu_controls,
    output logic [31:0] alu_result,
    output logic        btaken
);

    always_comb begin
        case (alu_controls)
            `ADD: alu_result = a + b;
            `SUB: alu_result = a - b;
            `SLL: alu_result = a << b[4:0];
            `SRL: alu_result = a >> b[4:0];
            `SRA: alu_result = $signed(a) >>> b[4:0];
            `SLT: alu_result = ($signed(a) < $signed(b)) ? 32'h1 : 32'h0;
            `SLTU: alu_result = (a < b) ? 32'h1 : 32'h0;
            `XOR: alu_result = a ^ b;
            `OR: alu_result = a | b;
            `AND: alu_result = a & b;
            default: alu_result = 32'bx;
        endcase
    end

    //branch
    always_comb begin
        case (alu_controls[2:0])
            `BEQ: btaken = ($signed(a) == $signed(b));
            `BNE: btaken = ($signed(a) != $signed(b));
            `BLT: btaken = ($signed(a) < $signed(b));
            `BGE: btaken = ($signed(a) >= $signed(b));
            `BLTU: btaken = ($unsigned(a) < $unsigned(b));
            `BGEU: btaken = ($unsigned(a) >= $unsigned(b));
            default: btaken = 1'b0;
        endcase
    end
endmodule

module extend (
    input  logic [31:0] inst_code,
    output logic [31:0] imm_Ext
);

    wire [6:0] opcode = inst_code[6:0];
    wire [2:0] funct3 = inst_code[14:12];

    always_comb begin
        case (opcode)
            `OP_R_TYPE: imm_Ext = 32'bx;
            // 20 literal 1'b0, imm[[11:5] 7bit, imm[4:0] 5bit
            `OP_S_TYPE:       imm_Ext = {{20{inst_code[31]}}, inst_code[31:25], inst_code[11:7]};
            `OP_IL_TYPE:      imm_Ext = {{20{inst_code[31]}}, inst_code[31:20]};
            `OP_I_TYPE:       imm_Ext = {{20{inst_code[31]}}, inst_code[31:20]};
            `OP_B_TYPE:       imm_Ext = {{20{inst_code[31]}}, inst_code[7], inst_code[30:25], inst_code[11:8], 1'b0};
            `OP_U_TYPE_LUI  : imm_Ext = {inst_code[31:12], 12'b0};
            `OP_U_TYPE_AUIPC: imm_Ext = {inst_code[31:12], 12'b0};
            `OP_JL_TYPE: imm_Ext = {{20{inst_code[31]}},inst_code[31:20]};
            `OP_J_TYPE: imm_Ext = {{11{inst_code[31]}},   // sign-extension
                          inst_code[31],        // imm[20]
                          inst_code[19:12],     // imm[19:12]
                          inst_code[20],        // imm[11]
                          inst_code[30:21],     // imm[10:1]
                          1'b0};
            default: imm_Ext = 32'bx;
        endcase
    end
endmodule

module mux_2x1 (
    input               sel,
    input  logic [31:0] x0,   // 0 : regFile R2
    input  logic [31:0] x1,   // 1: imm [31:0]
    output logic [31:0] y     // to ALU R2
);
    assign y = sel ? x1 : x0;
endmodule

module pc_adder (
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] sum
);

    assign sum = a + b;

endmodule

module mux_5x1 (
    input        [2:0]  sel,
    input  logic [31:0] x0,
    input  logic [31:0] x1,
    input  logic [31:0] x2,
    input  logic [31:0] x3,
    input  logic [31:0] x4,
    output logic [31:0] y


);
    assign y = (sel == 0) ? x0 : (sel == 1) ? x1 : (sel == 2) ? x2 : (sel ==3) ? x3 : x4;
endmodule
