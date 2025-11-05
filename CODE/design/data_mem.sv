`timescale 1ns / 1ps

module data_mem (
    input  logic        clk,
    input  logic        d_write_en,
    input  logic [31:0] d_addr,
    input  logic [31:0] d_write_data,
    input  logic [ 2:0] s_type_controls,
    input  logic [ 2:0] i_type_controls,
    output logic [31:0] d_read_data
);



    logic [7:0] data_mem[0:255];

    
    // Store (SB, SH, SW)
    always_ff @(posedge clk) begin
        if (d_write_en) begin
            //data_mem[d_addr] <= d_write_data;
            case (s_type_controls)
                3'b001: begin  // sb
                    data_mem[d_addr] <= d_write_data[7:0];
                end
                3'b010: begin  // sh
                    data_mem[d_addr]   <= d_write_data[7:0];
                    data_mem[d_addr+1] <= d_write_data[15:8];
                end
                3'b100: begin  // sw
                    data_mem[d_addr]   <= d_write_data[7:0];
                    data_mem[d_addr+1] <= d_write_data[15:8];
                    data_mem[d_addr+2] <= d_write_data[23:16];
                    data_mem[d_addr+3] <= d_write_data[31:24];
                end
            endcase
        end
    end
    // load (LB, LH, LW, LBU, LHU)
    always_comb begin
        case (i_type_controls)
            3'b001: begin  // LB
                d_read_data = {{24{data_mem[d_addr][7]}}, data_mem[d_addr]};
            end
            3'b010: begin  //LH
                d_read_data = {
                    {16{data_mem[d_addr+1][7]}},
                    data_mem[d_addr+1],
                    data_mem[d_addr]
                };
            end
            3'b011: begin  //LW
                d_read_data = {
                    data_mem[d_addr+3],
                    data_mem[d_addr+2],
                    data_mem[d_addr+1],
                    data_mem[d_addr]
                };
            end
            3'b100: begin  // LBU
                d_read_data = {24'b0, data_mem[d_addr]};
            end
            3'b101: begin  //LHU
                d_read_data = {16'b0, data_mem[d_addr+1], data_mem[d_addr]};
            end
            default: d_read_data = 32'b0;
        endcase

    end

endmodule
