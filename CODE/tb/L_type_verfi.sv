`timescale 1ns / 1ps

`define OP_IL_TYPE 7'b0000011 // LW, LH, LB, LBU, LHU

`define LB 3'b000
`define LH 3'b001
`define LW 3'b010
`define LBU 3'b100
`define LHU 3'b101

interface cpu_interface (
    input logic clk
);
    logic        reset;
    logic [31:0] inst_code;

    // DUT interface
    logic [31:0] d_addr;
    logic [31:0] d_read_data;
    logic [ 2:0] l_type_controls;
endinterface

// ---------------- transaction ----------------
class transaction;
    rand logic [4:0] rs1;
    rand logic [11:0] imm;
    rand logic [2:0] funct3;
    rand logic [4:0] write_addr;  // rd

    logic [31:0] inst_code;
    logic [31:0] rs1_val;
    logic [31:0] exp_addr;
    logic [31:0] exp_read_data;
    logic [31:0] actual_addr;
    logic [31:0] actual_read_data;

    // constraints
    constraint rs1_rd_diff_c { rs1 != write_addr; }
    constraint funct3_c {funct3 inside {`LW, `LH, `LB};}
    constraint rs_c {rs1 inside {[1 : 21]};}
    constraint imm_list_c {
        imm inside {5, 12, 7, 23, 1, 9, 34, 56, 78, 19, 2, 45, 67, 89, 10, 33,
                    21, 4, 6, 8, 11, 13, 15, 17, 20, 22, 24, 26, 28, 30};
    }

    // alignment for LH/LW
    constraint imm_align_c {
        (funct3 == `LW) -> (imm % 4 == 0);
        (funct3 == `LH) -> (imm % 2 == 0);
    }

    function void build_instr();
        inst_code = {imm[11:0], rs1, funct3, write_addr, `OP_IL_TYPE};
    endfunction

    function void calc_expected(logic [7:0] virtual_mem[0:255]);
        logic signed [31:0] s_imm;
        s_imm = $signed({{20{imm[11]}}, imm});

        if (^rs1_val === 1'bx) begin
            exp_addr      = 32'hxxxxxxxx;
            exp_read_data = 32'hxxxxxxxx;
            return;
        end

        exp_addr = rs1_val + s_imm;

        // address bounds check
        if (exp_addr < 0 || exp_addr > 32'd255) begin
            exp_read_data = 32'hxxxxxxxx;
            return;
        end

        case (funct3)
            `LB: begin
                exp_read_data = {
                    {24{virtual_mem[exp_addr][7]}}, virtual_mem[exp_addr]
                };
            end
            `LH: begin
                if (exp_addr + 1 > 32'd255) exp_read_data = 32'hxxxxxxxx;
                else
                    exp_read_data = {
                        {16{virtual_mem[exp_addr+1][7]}},
                        virtual_mem[exp_addr+1],
                        virtual_mem[exp_addr]
                    };
            end
            `LW: begin
                if (exp_addr + 3 > 32'd255) exp_read_data = 32'hxxxxxxxx;
                else
                    exp_read_data = {
                        virtual_mem[exp_addr+3],
                        virtual_mem[exp_addr+2],
                        virtual_mem[exp_addr+1],
                        virtual_mem[exp_addr]
                    };
            end
            default: exp_read_data = 32'hxxxxxxxx;
        endcase
    endfunction

    function string get_inst_name();
        case (funct3)
            `LB: return "LB";
            `LH: return "LH";
            `LW: return "LW";
            default: return "UNKNOWN";
        endcase
    endfunction

    task display(string tag);
        $display(
            "%0t [%s] instr=0x%0h(%s) | rs1=x%0d | rd=%0d | imm=%0d | exp_addr=%0d | exp_data=%0d",
            $time, tag, inst_code, get_inst_name(), rs1, write_addr,
            $signed({{20{imm[11]}}, imm}), exp_addr, exp_read_data);
    endtask
endclass

// ---------------- generator ----------------
class generator;
    mailbox #(transaction) gen2drv;
    event gen_next_event;
    int total_count;
    transaction tr;
    logic [4:0] prev_write_addr = 0;  // 이전 rd 저장

    function new(mailbox#(transaction) gen2drv, event gen_next_event);
        this.gen2drv = gen2drv;
        this.gen_next_event = gen_next_event;
    endfunction

    task run(int n, logic [7:0] virtual_mem[0:255]);
        repeat (n) begin
            tr = new();

            // 이전 명령어의 목적지 레지스터(prev_write_addr)를
        // 현재 명령어의 소스 레지스터(rs1)로 사용하지 않도록 제약
            if (prev_write_addr != 0) begin
                assert (tr.randomize() with {
                    rs1 != prev_write_addr;
                });
            end else begin
                assert (tr.randomize());
            end

            tr.build_instr();
            gen2drv.put(tr);
            tr.display("GEN");
            total_count++;

            @(gen_next_event);
        end
    endtask
endclass

// ---------------- driver ----------------
class driver;
    virtual cpu_interface  cpu_if;
    mailbox #(transaction) gen2drv, drv2mon;

    function new(mailbox#(transaction) gen2drv, mailbox#(transaction) drv2mon,
                 virtual cpu_interface cpu_if);
        this.gen2drv = gen2drv;
        this.drv2mon = drv2mon;
        this.cpu_if  = cpu_if;
    endfunction

    task reset();
        cpu_if.reset = 1;
        cpu_if.inst_code = 32'bx;
        repeat (3) @(posedge cpu_if.clk);
        cpu_if.reset = 0;
    endtask

    task run();
        forever begin
            transaction tr;
            gen2drv.get(tr);

            @(posedge cpu_if.clk);

            // rs1_val 읽고 expected 계산
            tr.rs1_val = tb_verifi_cpu.dut.U_RV32I_CPU.U_DATAPATH.U_REG_FILE.reg_file[tr.rs1];
            tr.calc_expected(tb_verifi_cpu.env.virtual_mem);

            $display(
                "%0t [DRV] Driving inst=0x%0h (%s) | rs1_val=%0d | exp_addr=%0d | exp_data=%0d",
                $time, tr.inst_code, tr.get_inst_name(), tr.rs1_val,
                tr.exp_addr, tr.exp_read_data);

            cpu_if.inst_code = tr.inst_code;
            drv2mon.put(tr);
        end
    endtask
endclass

// ---------------- monitor ----------------
class monitor;
    virtual cpu_interface  cpu_if;
    mailbox #(transaction) drv2mon, mon2scb;

    function new(mailbox#(transaction) drv2mon, mailbox#(transaction) mon2scb,
                 virtual cpu_interface cpu_if);
        this.drv2mon = drv2mon;
        this.mon2scb = mon2scb;
        this.cpu_if  = cpu_if;
    endfunction

    task run(int n);
        repeat (n) begin
            transaction tr;
            drv2mon.get(tr);

            repeat (3) @(posedge cpu_if.clk);

            tr.actual_addr = cpu_if.d_addr;
            tr.actual_read_data = cpu_if.d_read_data;

            $display(
                "%0t [MON] ACTUAL Addr=%0d | Data=%0d | Expected Addr=%0d | Data=%0d",
                $time, tr.actual_addr, tr.actual_read_data, tr.exp_addr,
                tr.exp_read_data);

            mon2scb.put(tr);
        end
    endtask
endclass

// ---------------- scoreboard ----------------
class scoreboard;
    virtual cpu_interface cpu_if;
    mailbox #(transaction) mon2scb;
    event gen_next_event;
    int pass_count, fail_count;
    transaction tr;

    function new(mailbox#(transaction) mon2scb, event gen_next_event,
                 virtual cpu_interface cpu_if);
        this.mon2scb = mon2scb;
        this.gen_next_event = gen_next_event;
        this.cpu_if = cpu_if;
    endfunction

    task run(int n);
        repeat (n) begin
            mon2scb.get(tr);

            if(tr.actual_addr === tr.exp_addr && tr.actual_read_data === tr.exp_read_data) begin
                pass_count++;
                $display("[SCB PASS] %s | Addr=%0d | Data=%0d",
                         tr.get_inst_name(), tr.actual_addr,
                         tr.actual_read_data);
            end else begin
                fail_count++;
                $display(
                    "[SCB FAIL] %s | ACTUAL Addr=%0d Data=%0d | EXP Addr=%0d Data=%0d",
                    tr.get_inst_name(), tr.actual_addr, tr.actual_read_data,
                    tr.exp_addr, tr.exp_read_data);
            end
            ->gen_next_event;
        end
        $display("------------------------------------------------");
        $display("SUMMARY :: TOTAL=%0d | PASS=%0d | FAIL=%0d",
                 pass_count + fail_count, pass_count, fail_count);
        $display("------------------------------------------------");
    endtask
endclass

// ---------------- environment ----------------
class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;
    mailbox #(transaction) gen2drv, drv2mon, mon2scb;
    event gen_next_event;
    virtual cpu_interface cpu_if;
    logic [7:0] virtual_mem[0:255];

    function new(virtual cpu_interface cpu_if);
        this.cpu_if = cpu_if;
        gen2drv = new();
        drv2mon = new();
        mon2scb = new();

        gen = new(gen2drv, gen_next_event);
        drv = new(gen2drv, drv2mon, cpu_if);
        mon = new(drv2mon, mon2scb, cpu_if);
        scb = new(mon2scb, gen_next_event, cpu_if);
    endfunction

    task run(int n);
        drv.reset();
        fork
            gen.run(n, virtual_mem);
            drv.run();
            mon.run(n);
            scb.run(n);
        join_any
        #2000;
        $stop;
    endtask
endclass

// ---------------- testbench ----------------
module tb_verifi_cpu ();
    logic clk;
    cpu_interface cpu_if (clk);
    environment env;

    RV32I_TOP dut (
        .clk(clk),
        .rst(cpu_if.reset)
    );

    assign cpu_if.d_addr = dut.U_RV32I_CPU.d_addr;
    assign cpu_if.d_read_data = dut.U_DATA_MEM.d_read_data;
    assign cpu_if.l_type_controls = dut.U_RV32I_CPU.i_type_controls;

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        force dut.U_RV32I_CPU.inst_code = cpu_if.inst_code;
    end

    initial begin
        env = new(cpu_if);

        // Register file init
        dut.U_RV32I_CPU.U_DATAPATH.U_REG_FILE.reg_file[0] = 0;
        for (int i = 1; i < 32; i++)
        dut.U_RV32I_CPU.U_DATAPATH.U_REG_FILE.reg_file[i] = 0;

        // Virtual memory init
        for (int i = 0; i < 256; i++) begin
            env.virtual_mem[i] = i;
            dut.U_DATA_MEM.data_mem[i] = i;
        end

        env.run(50);
    end
endmodule
