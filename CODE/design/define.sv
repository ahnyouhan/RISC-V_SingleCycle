// ALU
`define ADD 4'b0000
`define SUB 4'b1000       
`define SLL 4'b0001
`define SRL 4'b0101
`define SRA 4'b1101
`define SLT 4'b0010
`define SLTU 4'b0011
`define XOR 4'b0100
`define OR 4'b0110
`define AND 4'b0111

`define BEQ 3'b000
`define BLT 3'b100
`define BNE 3'b001

`define BGE 3'b101
`define BLTU 3'b110
`define BGEU 3'b111

// OPCODE
`define OP_R_TYPE  7'b0110011 // RD = RS2 + RS1
`define OP_S_TYPE  7'b0100011 // SW, SH, SB
`define OP_IL_TYPE 7'b0000011 // LW, LH, LB, LBU, LHU
`define OP_I_TYPE  7'b0010011 // RD = RS1 + IMM
`define OP_B_TYPE  7'b1100011 // BEQ, BNE , branch
`define OP_U_TYPE_LUI    7'b0110111 // LUI   rd = imm
`define OP_U_TYPE_AUIPC  7'b0010111 // auipc rd = pc + imm
`define OP_JL_TYPE   7'b1100111 // JALR  rd = PC+4; PC = rs1 + imm
`define OP_J_TYPE    7'b1101111 // JAL   rd = PC+4; PC += imm




// S-type
`define SB 3'b000
`define SH 3'b001
`define SW 3'b010

//IL-type
`define LB  3'b000
`define LH  3'b001
`define LW  3'b010
`define LBU 3'b100
`define LHU 3'b101

