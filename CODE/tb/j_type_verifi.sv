`timescale 1ns / 1ps
`define OP_JAL 7'b1101111 // JAL Opcode
`define OP_JALR 7'b1100111 // JALR Opcode
`define F3_JALR 3'b000     // JALR funct3

interface cpu_interface (
    input logic clk
);
    logic        reset;
    logic [31:0] inst_code;

    // DUT interface (register)

    logic [ 4:0] write_addr;
    logic        reg_write_en;
    logic [31:0] write_data;
    logic [31:0] pc;
    logic [31:0] next_pc;
endinterface

// ---------------- transaction ----------------
class transaction;
    rand bit is_jal;  // 1: jal, 0: jalr
    rand logic [4:0] write_addr;
    rand logic [4:0] rs1;
    rand logic [11:0] imm_jalr;
    rand logic [19:0] imm_jal;

    logic [31:0] inst_code;
    logic [31:0] rs1_val;  // jalr에서 rs1사용

    logic [31:0] exp_rd_val;  // rd 에 저장할 예상값 (pc+4)
    logic [31:0] exp_next_pc;

    logic [31:0] actual_rd_val;
    logic [31:0] actual_next_pc;

    constraint force_even_distribution_c {
        is_jal dist {
            1 := 50,
            0 := 50
        };
    }

    constraint imm_align_c {
        // JAL: 4바이트 정렬
        (is_jal) -> (imm_jal[1:0] == 2'b00);

        // JALR: 2바이트 정렬
        (!is_jal) ->
        (imm_jalr[0] == 1'b0);  //홀수여도 상관없지만 짝수로
    }

    // JALR 사용 시 rs1은 0이 아니도록 제한 (x0 레지스터는 read-only)
    constraint rs1_c {(!is_jal) -> (rs1 != 0);}
    // rd는 0이 아니도록 제한 (x0 레지스터는 write 불가)
    constraint rd_c {write_addr != 0;}
    constraint jal_jalr_c {
        // is_jal이 1일 확률과 0일 확률을 50:50으로 설정
        is_jal dist {
            1 := 50,
            0 := 50
        };
    }
    function void build_instr();
        if (is_jal) begin
            // JAL : {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode}
            logic [20:0] imm_j_with_zero;
            imm_j_with_zero = {imm_jal, 1'b0};

            inst_code = {
                imm_j_with_zero[20],  // imm[20]
                imm_j_with_zero[10:1],  // imm[10:1]
                imm_j_with_zero[11],  // imm[11]
                imm_j_with_zero[19:12],  // imm[19:12]
                write_addr,
                `OP_JAL
            };

        end else begin
            // JALR : {imm[11:0], rs1, funct3, rd, opcode}
            inst_code = {imm_jalr, rs1, `F3_JALR, write_addr, `OP_JALR};
        end
    endfunction

    function void calc_expected(logic [31:0] current_pc);
        logic signed [31:0] s_imm;

        // [수정 1] next_pc를 먼저 계산합니다.
        if (is_jal) begin
            s_imm = $signed({{11{imm_jal[19]}}, imm_jal, 1'b0});
            exp_next_pc = current_pc + s_imm;
        end else begin  // JALR
            s_imm = $signed({{20{imm_jalr[11]}}, imm_jalr});
            exp_next_pc = (rs1_val + s_imm);
        end

        // rd에 저장되는 값은 next_pc의 관점에서 현재 명령어의 다음 주소이므로,
        // 현재 PC+4로 계산
        // DUT의 실제 동작인 current_pc + 4와 일치시키기
        exp_rd_val = current_pc + 4;
    endfunction

    function string get_inst_name();
        return is_jal ? "JAL" : "JALR";
    endfunction

    task display(string tag);
        $display("%0t [%s] instr=0x%0h(%s) | rd=x%0d | rs1=x%0d", $time, tag,
                 inst_code, get_inst_name(), write_addr, (is_jal ? 5'bx : rs1));
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
                assert (tr.randomize() with {rs1 != prev_write_addr;});
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
            #1ps;

            // rs1_val 읽고 expected 계산 (JALR일 경우에만 필요)
            if (!tr.is_jal) begin
                tr.rs1_val = tb_verifi_cpu.dut.U_RV32I_CPU.U_DATAPATH.U_REG_FILE.reg_file[tr.rs1];
            end

            tr.calc_expected(cpu_if.pc);

            $display(
                "%0t [DRV] Driving inst=0x%0h (%s) | rs1_val=%0d | exp_next_pc=%0d | exp_rd_val=%0d",
                $time, tr.inst_code, tr.get_inst_name(), tr.rs1_val,
                tr.exp_next_pc, tr.exp_rd_val);


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

            // [수정] clock을 한 번만 기다려 next_pc와 write_data를 모두 샘플링
            @(posedge cpu_if.clk);
            tr.actual_next_pc = cpu_if.next_pc;

            if (cpu_if.reg_write_en && cpu_if.write_addr == tr.write_addr) begin
                tr.actual_rd_val = cpu_if.write_data;
            end else begin
                tr.actual_rd_val = 32'bx;
            end

            $display(
                "%0t [MON] ACTUAL NextPC=%0d | Rd_Val=%0d -- EXPECTED NextPC=%0d | Rd_Val=%0d",
                $time, tr.actual_next_pc, tr.actual_rd_val, tr.exp_next_pc,
                tr.exp_rd_val);
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

            if (tr.actual_next_pc === tr.exp_next_pc && tr.actual_rd_val === tr.exp_rd_val) begin
                pass_count++;
                $display("[SCB PASS] %s | NextPC=%0d | Rd_Val=%0d",
                         tr.get_inst_name(), tr.actual_next_pc,
                         tr.actual_rd_val);
            end else begin
                fail_count++;
                $display(
                    "[SCB FAIL] %s | ACTUAL NextPC=%0d Rd_Val=%0d | EXP NextPC=%0d Rd_Val=%0d",
                    tr.get_inst_name(), tr.actual_next_pc, tr.actual_rd_val,
                    tr.exp_next_pc, tr.exp_rd_val);
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

    assign cpu_if.pc = dut.U_RV32I_CPU.U_DATAPATH.inst_read_addr;
    assign cpu_if.next_pc = dut.U_RV32I_CPU.U_DATAPATH.w_pc_next;
    assign cpu_if.reg_write_en = dut.U_RV32I_CPU.reg_write_en;
    assign cpu_if.write_addr = dut.U_RV32I_CPU.U_DATAPATH.inst_code[11:7];
    assign cpu_if.write_data = dut.U_RV32I_CPU.U_DATAPATH.w_reg_write_data_out;

    initial clk = 0;
    always #5 clk = ~clk;

    always_comb begin
        dut.inst_code = cpu_if.inst_code;
    end

    initial begin
        env = new(cpu_if);



        env.run(50);
    end
endmodule
