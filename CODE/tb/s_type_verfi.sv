`timescale 1ns / 1ps

`define SB 3'b000
`define SH 3'b001
`define SW 3'b010

interface cpu_interface (
    input logic clk,
    input logic rst
);
    logic [31:0] inst_code;
    logic [31:0] d_read_data;
    logic [31:0] inst_read_addr;
    logic        d_write_en;
    logic [31:0] d_addr;
    logic [31:0] d_write_data;
    logic [ 2:0] s_type_controls;

endinterface

class transaction;
    rand logic [ 4:0] rs1,                                    rs2;
    rand logic [31:0] rs1_val,                                rs2_val;
    rand logic [11:0] imm;
    rand logic [ 2:0] s_type_controls;

    logic      [31:0] addr;  // rs1+imm
    logic      [31:0] store_data;  // 실제 저장할 데이

    constraint align {  // 하위비트 주소 정렬
        s_type_controls inside {`SB, `SH, `SW};
        if (s_type_controls == `SB) addr[1:0] == 2'b00; // 랜덤화 시 addr[1:0]이 2'b00만 나오도록 제한
        if (s_type_controls == `SH) addr[0] == 1'b0;
    }

    function void post_randomize();
        addr = rs1_val + $signed(imm);
        case (s_type_controls)
            `SB: store_data = rs2_val[7:0];
            `SH: store_data = rs2_val[15:0];
            `SW: store_data = rs2_val;
        endcase
    endfunction

    task display(string tag);
        $display(
            "%0t [%s] : rs1 = %0d(val=%0d) | rs2 = %0d(val=%0d) | addr(rs1+imm) = %0h | s_type = %0d | store_data = %0b",
            $time, tag, rs1, rs1_val, rs2, rs2_val, addr, s_type_controls,
            store_data);
    endtask  //display

endclass  //transaction

class generator;
    mailbox #(transaction) gen2drv;
    event gen_next_event;
    int total_count;

    function new(mailbox#(transaction) gen2drv, event gen_next_event);
        this.gen2drv = gen2drv;
        this.gen_next_event = gen_next_event;
    endfunction  //new()

    task run(int count);
        repeat (count) begin
            transaction tr = new();
            assert (tr.randomize())
            else $display("[GEN] tr.randomize() error!!!!!");
            tr.post_randomize();
            gen2drv.put(tr);

            tr.display("GEN");
            total_count++;
            @(gen_next_event);
        end
    endtask

endclass  //generator

class dirver;
    virtual cpu_interface cpu_if;
    mailbox #(transaction) gen2drv;
    mailbox #(transaction) drv2mon;
    logic [2:0] funct3;

    function new(mailbox#(transaction) gen2drv, mailbox#(transaction) drv2mon,
                 virtual cpu_interface cpu_if);
        this.gen2drv = gen2drv;
        this.drv2mon = drv2mon;
        this.cpu_if  = cpu_if;
    endfunction  //new()

    task reset();
        cpu_if.rst = 1;
        repeat (5) @(posedge cpu_if.clk);
        cpu_if.rst = 0;
    endtask

    task run();
        forever begin
            transaction tr;
            gen2drv.get(tr);
            @(posedge cpu_if.clk);

            cpu_if.d_addr          = tr.addr;
            cpu_if.d_write_data    = tr.store_data;
            cpu_if.d_write_en      = 1;  // store 동작 활성화
            cpu_if.s_type_controls = tr.s_type_controls;

            case (tr.s_type_controls)
                `SB: funct3 = 3'b000;
                `SH: funct3 = 3'b001;
                `SW: funct3 = 3'b010;
            endcase

            cpu_if.inst_code = {
                tr.imm[11:5], tr.rs2, tr.rs1, funct3, tr.imm[4:0], 7'b0100011
            };
            tr.display("DRV");
            drv2mon.put(tr);
        end
    endtask

endclass  //dirver

class monitor;
    virtual cpu_interface cpu_if;
    mailbox #(transaction) drv2mon;
    mailbox #(transaction) mon2scb;
    transaction tr;

    function new(mailbox#(transaction) drv2mon, mailbox#(transaction) mon2scb,
                 virtual cpu_interface cpu_if);
        this.drv2mon = drv2mon;
        this.mon2scb = mon2scb;
        this.cpu_if  = cpu_if;
    endfunction  //new()

    task run();
        forever begin
            drv2mon.get(tr);
            @(posedge cpu_if.clk);

            if (cpu_if.d_write_en) begin
                tr.addr            = cpu_if.d_addr;
                tr.store_data      = cpu_if.d_write_data;
                tr.s_type_controls = cpu_if.s_type_controls;
            end

            tr.display("MON");
            mon2scb.put(tr);
        end
    endtask  //run
endclass  //monitor

class scoreboard;
    transaction tr;
    virtual cpu_interface cpu_if;
    mailbox #(transaction) mon2scb;
    event gen_next_event;
    int pass_count = 0, fail_count = 0;
    logic [31:0] exp_data;

    function new(mailbox#(transaction) mon2scb, event gen_next_event,
                 virtual cpu_interface cpu_if);
        this.mon2scb = mon2scb;
        this.gen_next_event = gen_next_event;
        this.cpu_if = cpu_if;
    endfunction  //new()

    task run();
        forever begin
            mon2scb.get(tr);
            tr.display("SCB");
            case (tr.s_type_controls)
                `SB: exp_data = tr.rs2_val[7:0];
                `SH: exp_data = tr.rs2_val[15:0];
                `SW: exp_data = tr.rs2_val;
            endcase

            if(exp_data === tr.store_data)begin
                pass_count++;
                $display("-> PASS | expected data = %d, store data = %d", exp_data, tr.store_data);
            end else begin
                fail_count++;
                $display("-> FAIL | expected data = %d, store data = %d", exp_data, tr.store_data);
            end
            -> gen_next_event;
        end
    endtask

endclass  //scoreboard

class environment;
    generator  gen;
    driver     drv;
    monitor    mon;
    scoreboard scb;
    mailbox #(transaction) gen2drv, drv2mon, mon2scb;
    event gen_next_event;
    

    function new(virtual cpu_interface cpu_if);
        gen2drv = new();
        drv2mon = new();
        mon2scb = new();

        gen = new(gen2drv, gen_next_event);
        drv = new(gen2drv, drv2mon, cpu_if);
        mon = new(drv2mon, mon2scb, cpu_if);
        scb = new(mon2scb, gen_next_event, cpu_if);
    endfunction //new()

    task report();
        $display("==========================================");
        $display("=============== test report ==============");
        $display("==========================================");
        $display("== Total test : %d ==", gen.total_count);
        $display("== Pass test : %d ==", scb.pass_count);
        $display("== Fail test : %d ==", scb.fail_count);
        $display("==========================================");
        $display("== Test bench is finish ==");
        $display("==========================================");
    endtask // task run();

    task run();
        drv.reset();
        fork
            gen.run(50);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #1000;
        report();
        $stop;
    endtask

endclass


module s_type_verfi ();
    cpu_interface cpu_if();
    environment env;

    RV32I_TOP dut(
        .clk(cpu_if.clk),
        .rst(cpu_if.rst),
        .inst_code(cpu_if.inst_code),
        .inst_read_addr(cpu_if.inst_read_addr),
        .d_addr(cpu_if.d_addr),
        .d_write_data(cpu_if.d_write_data),
        .d_write_en(cpu_if.d_write_en),
        .s_type_controls(cpu_if.s_type_controls)
    );
    always #5 cpu_if.clk = ~cpu_if.clk;

    initial begin
        cpu_if.clk = 0;
        env = new(cpu_if);
        env.run();
    end
endmodule
