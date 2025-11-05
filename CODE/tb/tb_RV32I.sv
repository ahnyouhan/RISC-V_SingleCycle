`timescale 1ns / 1ps

module tb_RV32I();
    logic clk=0, rst=1;

    RV32I_TOP dut(.*);

    always #5 clk = ~clk;

    initial begin
        #30;
        rst = 0;
        #400;
        $stop;
    end

endmodule
