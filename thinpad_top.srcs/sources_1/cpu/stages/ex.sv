/*
EX模块：
    执行阶段，这里实际是一个ALU
*/

`include "cpu_defs.vh"

module ex(
    input  logic            rst,

    input  aluop_t          aluop_i,                    // ALU运算类型
    input  word_t           reg1_i,                     // 源操作数1
    input  word_t           reg2_i,                     // 源操作数2
    input  reg_addr_t       wd_i,                       // 要写入的寄存器编号
    input  logic            wreg_i,                     // 是否要写寄存器

    input  word_t           hi_i,                       // hilo寄存器中的hi值
    input  word_t           lo_i,                       // hilo寄存器中的lo值

    input  word_t           mem_hi_i,                   // mem阶段的可能更新的hi值（数据回传）
    input  word_t           mem_lo_i,                   // mem阶段的可能更新的lo值（数据回传）
    input  logic            mem_whilo_i,                // mem阶段要不要写hilo（数据回传）

    input  logic            mem_cp0_reg_we,             // mem阶段是否要写CP0
    input  reg_addr_t       mem_cp0_reg_write_addr,     // mem阶段要写的CP0的地址
    input  word_t           mem_cp0_reg_data,           // mem阶段要写CP0的值

    input  logic            wb_cp0_reg_we,              // wb阶段是否要写CP0
    input  reg_addr_t       wb_cp0_reg_write_addr,      // wb阶段要写的CP0的地址
    input  word_t           wb_cp0_reg_data,            // wb阶段要写CP0的值

    input  word_t           cp0_reg_data_i,             // 直接从CP0读入的数

    input  word_t           wb_hi_i,                    // wb阶段的可能更新的hi值（数据回传）
    input  word_t           wb_lo_i,                    // wb阶段的可能更新的lo值（数据回传）
    input  logic            wb_whilo_i,                 // wb阶段要不要写hilo（数据回传）

    input  logic            in_delayslot_i,             // 当前的指令在不在延迟槽（会在异常处理的地方用到暂时没有用）
    input  addr_t           return_addr_i,              // 要返回的地址

    input  word_t           inst_i,                     // 指令码

    input  word_t           except_type_i,              // 异常类型输入
    input  addr_t           current_inst_addr_i,        // 当前指令地址

    output reg_addr_t       wd_o,                       // 要写入的寄存器的编号
    output logic            wreg_o,                     // 是否要写入寄存器
    output word_t           wdata_o,                    // 要写入的数据

    output word_t           hi_o,                       // 要写入的hi值
    output word_t           lo_o,                       // 要写入的lo值
    output logic            whilo_o,                    // 是否要写入hilo寄存器

    output aluop_t          aluop_o,                    // 该信号为后续阶段做准备
    output word_t           mem_addr_o,                 // 该信号为后续阶段做准备，是访存阶段需要的地址
    output word_t           reg2_o,                     // 该信号为后续阶段做准备，是访存阶段要存储的数据

    output reg_addr_t       cp0_reg_read_addr_o,        // 要从CP0读入的地址

    output logic            cp0_reg_we_o,               // 传给下一级是否要写CP0
    output reg_addr_t       cp0_reg_write_addr_o,       // 传给下一级要写的CP0的地址
    output word_t           cp0_reg_data_o,             // 传给下一级要写的CP0的数

    output logic            stallreq_o,                 // 请求暂停流水

    output word_t           except_type_o,              // 异常类型
    output logic            in_delayslot_o,             // 执行阶段的是否在延迟槽中
    output addr_t           current_inst_addr_o         // 当前指令的地址
);

// 暂停，目前设置为0
assign stallreq_o = 0;

// 把输入的aluop和reg2直接输出即可
assign aluop_o = aluop_i;
assign reg2_o = reg2_i;

// 计算访存地址的值
assign mem_addr_o = reg1_i + {{16{inst_i[15]}}, inst_i[15:0]};

// 最新的hi, lo寄存器的值
word_t hi, lo;

// 异常
logic trap_assert, ov_assert;

// 一些结果线
logic overflow, reg1_lt_reg2;
word_t reg2_i_mux, result_sum;
logic [`WORD_WIDTH_LOG2:0] result_clz, result_clo; // 注意这里的长度是6位的，前导零可能有32个

`ifdef MUL_ON
    word_t opdata1_mult, opdata2_mult;
    dword_t hilo_temp, result_mul;
`endif

// 异常相关
assign except_type_o = {except_type_i[31:12], ov_assert, trap_assert, except_type_i[9:8], 8'h0};
assign in_delayslot_o = in_delayslot_i;
assign current_inst_addr_o = current_inst_addr_i;

`ifndef TRAP_ON
    assign trap_assert = 0;
`endif

// 如果是减法或者有符号比较则reg2取相反数，否则不变（目的是转换成加法）
assign reg2_i_mux = (
                    `ifdef TRAP_ON
                        (aluop_i == EXE_TLT_OP)  ||
                        (aluop_i == EXE_TLTI_OP) ||
                        (aluop_i == EXE_TGE_OP)  ||
                        (aluop_i == EXE_TGEI_OP) ||
                    `endif
                        (aluop_i == EXE_SUB_OP)  ||
                        (aluop_i == EXE_SUBU_OP) ||
                        (aluop_i == EXE_SLT_OP)
                     )
                     ? ((~reg2_i) + 1) : reg2_i;

assign result_sum = reg1_i + reg2_i_mux;

// 正正和为负，或者负负和为正，则溢出（有符号）
assign overflow = ((!reg1_i[31] && !reg2_i_mux[31]) && result_sum[31]) || ((reg1_i[31] && reg2_i_mux[31]) && (!result_sum[31]));

/*
reg1是否小于reg2：
    第一个情况是SLT有符号比较时：A 1为负2为正 B 同号并且相减为负
    第二个情况是无符号比较：直接比
*/
assign reg1_lt_reg2 = (
                        `ifdef TRAP_ON
                            (aluop_i == EXE_TLT_OP)  ||
                            (aluop_i == EXE_TLTI_OP) ||
                            (aluop_i == EXE_TGE_OP)  ||
                            (aluop_i == EXE_TGEI_OP) ||
                        `endif
                            (aluop_i == EXE_SLT_OP)
                        )
                        ? ((reg1_i[31] && !reg2_i[31]) || ((reg1_i[31] == reg2_i[31]) && result_sum[31])) : (reg1_i < reg2_i);

// 前导零和前导一
count_lead_zero clz_inst(.in( reg1_i), .out(result_clz) );
count_lead_zero clo_inst(.in(~reg1_i), .out(result_clo) );

`ifdef MUL_ON
    // 乘法：如果是负数先取相反数
    assign opdata1_mult = (((aluop_i == EXE_MUL_OP) || (aluop_i == EXE_MULT_OP)) && reg1_i[31]) ? ((~reg1_i) + 1) : reg1_i;
    assign opdata2_mult = (((aluop_i == EXE_MUL_OP) || (aluop_i == EXE_MULT_OP)) && reg2_i[31]) ? ((~reg2_i) + 1) : reg2_i;
    assign hilo_temp = opdata1_mult * opdata2_mult;
`endif

// 乘法结果
`ifdef MUL_ON
    always_comb begin
        if (rst == 1'b1) begin
            result_mul <= 0;
        end else begin
            case (aluop_i)
                EXE_MULT_OP, EXE_MUL_OP: begin
                    result_mul <= (reg1_i[31] ^ reg2_i[31]) ? ((~hilo_temp) + 1) : hilo_temp; // 结果修正
                end
                default: begin // EXE_MULTU_OP
                    result_mul <= hilo_temp;
                end
            endcase
        end
    end
`endif

// 自陷指令
`ifdef TRAP_ON
    always_comb begin
        if (rst) begin
            trap_assert <= 0;
        end else begin
            case (aluop_i)
                EXE_TEQ_OP, EXE_TEQI_OP: begin
                    trap_assert <= (reg1_i == reg2_i);
                end
                EXE_TGE_OP, EXE_TGEI_OP, EXE_TGEIU_OP, EXE_TGEIU_OP: begin
                    trap_assert <= ~reg1_lt_reg2;
                end
                EXE_TLT_OP, EXE_TLTI_OP, EXE_TLTIU_OP, EXE_TLTU_OP: begin
                    trap_assert <= reg1_lt_reg2;
                end
                EXE_TNE_OP, EXE_TNEI_OP: begin
                    trap_assert <= (reg1_i != reg2_i);
                end
                default: begin
                    trap_assert <= 0;
                end
            endcase
        end
    end
`endif

// 运算结果（要写入寄存器的值）
always_comb begin
    if (rst == 1'b1) begin
        {wdata_o, cp0_reg_read_addr_o} <= 0;
    end else begin
        cp0_reg_read_addr_o <= 0;
        case (aluop_i)
            EXE_OR_OP: begin
                wdata_o <= reg1_i | reg2_i;
            end
            EXE_AND_OP: begin
                wdata_o <= reg1_i & reg2_i;
            end
            EXE_XOR_OP: begin
                wdata_o <= reg1_i ^ reg2_i;
            end
            EXE_NOR_OP: begin
                wdata_o <= ~(reg1_i | reg2_i);
            end
            EXE_SLL_OP: begin // 逻辑左移
                wdata_o <= reg2_i << reg1_i[4:0];
            end
            EXE_SRL_OP: begin // 逻辑右移
                wdata_o <= reg2_i >> reg1_i[4:0];
            end
            EXE_SRA_OP: begin // 算术右移
                wdata_o <= (({32{reg2_i[31]}} << (6'd32 - {1'b0, reg1_i[4:0]}))) | (reg2_i >> reg1_i[4:0]);
            end
        `ifdef MUL_ON
            EXE_MUL_OP, EXE_MULT_OP, EXE_MULTU_OP: begin
                wdata_o <= result_mul[`WORD_WIDTH-1:0];
            end
        `endif
            EXE_SLT_OP, EXE_SLTU_OP: begin
                wdata_o <= reg1_lt_reg2;
            end
            EXE_ADD_OP, EXE_ADDU_OP, EXE_ADDI_OP, EXE_ADDIU_OP, EXE_SUB_OP, EXE_SUBU_OP: begin
                wdata_o <= result_sum;
            end
            EXE_CLZ_OP: begin
                wdata_o <= {`CLZO_FILL'b0, result_clz};
            end
            EXE_CLO_OP: begin
                wdata_o <= {`CLZO_FILL'b0, result_clo};
            end
            EXE_MFHI_OP: begin
                wdata_o <= hi;
            end
            EXE_MFLO_OP: begin
                wdata_o <= lo;
            end
            EXE_MOVZ_OP: begin
                wdata_o <= reg1_i;
            end
            EXE_MOVN_OP: begin
                wdata_o <= reg1_i;
            end
            EXE_J_OP, EXE_JAL_OP, EXE_JALR_OP, EXE_JR_OP, EXE_BEQ_OP, EXE_BGEZ_OP, EXE_BGEZAL_OP, EXE_BGTZ_OP, EXE_BLEZ_OP, EXE_BLTZ_OP, EXE_BLTZAL_OP, EXE_BNE_OP: begin
                wdata_o <= return_addr_i;
            end
            EXE_MFC0_OP: begin
                cp0_reg_read_addr_o <= inst_i[15:11];
                wdata_o <= cp0_reg_data_i;
                if (mem_cp0_reg_we && mem_cp0_reg_write_addr == inst_i[15:11]) begin
                    wdata_o <= mem_cp0_reg_data;
                end else if (wb_cp0_reg_we && wb_cp0_reg_write_addr == inst_i[15:11]) begin
                    wdata_o <= wb_cp0_reg_data;
                end
            end
            default: begin // EXE_NOP_OP, EXE_MTHI_OP, EXE_MTLO_OP
                wdata_o <= 0;
            end
        endcase
    end
end

// 当前最新的hilo的值，这里有mem和wb的数据前传
always_comb begin
    if (rst == 1'b1) begin
        {hi, lo} <= 0;
    end else if (mem_whilo_i == 1) begin
        {hi, lo} <= {mem_hi_i, mem_lo_i};
    end else if (wb_whilo_i == 1) begin
        {hi, lo} <= {wb_hi_i, wb_lo_i};
    end else begin
        {hi, lo} <= {hi_i, lo_i};
    end
end

// 将要写入的hi, lo的值
always_comb begin
    if (rst == 1) begin
        {whilo_o, hi_o, lo_o} <= 0;
    end else begin
        case (aluop_i)
        `ifdef MUL_ON
            EXE_MULT_OP, EXE_MULTU_OP: begin // EXE_MUL_OP写寄存器，不写hilo寄存器
                whilo_o <= 1;
                {hi_o, lo_o} <= result_mul;
            end
        `endif
            EXE_MTHI_OP: begin
                whilo_o <= 1;
                {hi_o, lo_o} <= {reg1_i, lo};
            end
            EXE_MTLO_OP: begin
                whilo_o <= 1;
                {hi_o, lo_o} <= {hi, reg1_i};
            end
            default: begin
                {whilo_o, hi_o, lo_o} <= 0;
            end
        endcase
    end
end

// 是否写入寄存器和要写入的寄存器编号
always_comb begin
    wd_o <= wd_i;	 	 	
    case (aluop_i)
        EXE_ADD_OP, EXE_ADDI_OP, EXE_SUB_OP: begin
            wreg_o <= ~overflow; // 如果溢出就不写寄存器了
            ov_assert <= overflow;
        end
        default: begin
            wreg_o <= wreg_i;
            ov_assert <= 0;
        end
    endcase
end

// MTC0
always_comb begin
    if (rst || aluop_i != EXE_MTC0_OP) begin
        {cp0_reg_write_addr_o, cp0_reg_we_o, cp0_reg_data_o} <= 0;
    end else begin
        cp0_reg_write_addr_o <= inst_i[15:11];
        cp0_reg_we_o <= 1;
        cp0_reg_data_o <= reg1_i;
    end
end

endmodule