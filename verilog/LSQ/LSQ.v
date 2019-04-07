`timescale 1ns/100ps

module SQ (
  input  logic                                   clock, reset, en, dispatch_en,
  input  logic            [`NUM_SUPER-1:0]       retire_en, rollback_en, D_cache_valid,
  input  logic            [$clog2(`NUM_LSQ)-1:0] SQ_rollback_idx,
  input  DECODER_SQ_OUT_t                        decoder_SQ_out,
  input  LQ_SQ_OUT_t                             LQ_SQ_out,
  input  ROB_SQ_OUT_t                            ROB_SQ_out,
  input  FU_SQ_OUT_t                             FU_SQ_out,
  output logic                                   SQ_valid,
  output SQ_ROB_OUT_t                            SQ_ROB_out,
  output SQ_RS_OUT_t                             SQ_RS_out,
  output SQ_LQ_OUT_t                             SQ_LQ_out,
  output SQ_D_CACHE_OUT_t                        SQ_D_cache_out
);

  logic      [$clog2(NUM_LSQ)-1:0]                  head, next_head, tail, next_tail, tail1, tail2, tail_plus_one, tail_plus_two, head_plus_one, head_plus_two, diff_tail, virtual_tail;
  logic      [`NUM_LSQ-1:0][$clog2(NUM_LSQ)-1:0]    sq_tmp_idx;
  SQ_ENTRY_t [`NUM_LSQ-1:0]                         sq, next_sq;
  logic      [63:0]                                 ld_value;
  logic      [`NUM_SUPER-1:0]                       wr_en;
  logic      [`NUM_SUPER-1:0][60:0]                 addr;
  logic      [`NUM_SUPER-1:0][63:0]                 value;
  logic      [`NUM_SUPER-1:0][`NUM_LSQ-1:0]         LD_match;
  logic      [`NUM_SUPER-1:0][$clog2(`NUM_LSQ)-1:0] sq_map_idx;
  logic      [`NUM_SUPER-1:0]                       LD_valid;
  logic      [`NUM_SUPER-1:0][63:0]                 LD_value;
  logic      [`NUM_SUPER-1:0]                       dispatch_valid;
  logic      [`NUM_SUPER-1:0]                       retire_valid;
  logic                                             valid1, valid2;

  assign tail_plus_one    = tail + 1;
  assign tail_plus_two    = tail + 2;
  assign head_plus_one    = head + 1;
  assign head_plus_two    = head + 2;
  assign head_map_idx     = {$clog2(`NUM_LSQ){1'b1}} - tail + head;
  assign next_tail        = rollback_en ? SQ_rollback_idx :
                            dispatch_en ? virtual_tail    : tail;
  assign SQ_RS_out.SQ_idx = '{tail2, tail1};
  assign LD_valid         = ld_hit;
  assign LD_value         = ld_value;
  assign SQ_LQ_out        = '{LD_valid, LD_value};
  assign wr_en            = retire_en & ROB_SQ_out.wr_mem;
  assign SQ_D_cache_out   = '{wr_en, addr, value};
  assign retire_valid     = '{valid2, valid1};
  assign SQ_ROB_out.valid = '{dispatch_valid, retire_valid};

  // Dispatch Valid
  always_comb begin
    case(decoder_SQ_out.wr_mem)
      2'b00: begin
        virtual_tail   = tail;
        dispatch_valid = `TRUE;
        tail1          = tail;
        tail2          = tail;
      end
      2'b01: begin
        virtual_tail   = tail_plus_one;
        dispatch_valid = tail_plus_one != head;
        tail1          = tail_plus_one;
        tail2          = tail_plus_one;
      end
      2'b10: begin
        virtual_tail   = tail_plus_one;
        dispatch_valid = tail_plus_one != head;
        tail1          = tail;
        tail2          = tail_plus_one;
      end
      2'b11: begin
        virtual_tail   = tail_plus_two;
        dispatch_valid = tail_plus_one != head && tail_plus_two != head;
        tail1          = tail_plus_one;
        tail2          = tail_plus_two;
      end
    endcase
  end

  always_comb begin
    next_sq = sq;
    // Dispatch
    if (dispatch_en) begin
      case(decoder_SQ_out.wr_mem)
        2'b01, 2'b10: next_sq[tail] = `SQ_ENTRY_RESET_PACKED;
        2'b11: begin
          next_sq[tail]          = `SQ_ENTRY_RESET_PACKED;
          next_sq[tail_plus_one] = `SQ_ENTRY_RESET_PACKED;
        end
      endcase
    end
    // Execute
    for (int i = 0; i < `NUM_SUPER; i++) begin
      if (FU_SQ_out.wr_mem[i] && FU_SQ_out.done[i]) begin
        next_sq[FU_LSQ_out.SQ_idx[i]] = '{FU_LSQ_out.result[i][63:3], `TRUE, FU_LSQ_out.T1_value[i]};
      end
    end
  end

  // Retire valid
  always_comb begin
    case(ROB_SQ_out.wr_mem)
      2'b00: begin
        valid1 = `TRUE;
        valid2 = `TRUE;
      end
      2'b01: begin
        valid1 = tail_plus_one != head;
        valid2 = `TRUE;
      end
      2'b10: begin
        valid1 = `TRUE;
        valid2 = tail_plus_one != head;
      end
      2'b11: begin
        valid1 = tail_plus_one != head;
        valid2 = valid1 && tail_plus_two != head;
      end
    endcase
  end

  // Retire
  always_comb begin
    case(ROB_SQ_out.wr_mem & retire_en)
      2'b00: begin
        next_head = head;
      end
      2'b01: begin
        next_head = head_plus_one;
      end
      2'b10: begin
        next_head = head_plus_one;
      end
      2'b11: begin
        next_head = head_plus_two;
      end
    endcase
  end

  // Retire addr and value
  always_comb begin
    for (int i = 0; i < `NUM_SUPER; i++) begin
      addr[i]  = sq[ROB_SQ_out.SQ_idx[i]].addr;
      value[i] = sq[ROB_SQ_out.SQ_idx[i]].value;
    end
  end

  // Age logic
  // Map SQ idx
  always_comb begin
    for (int j = 0; j < `NUM_LSQ; j++) begin
      sq_map_idx[j] = tail + j + 1;
    end
  end

  // Age logic
  always_comb begin
    ld_hit = {`NUM_SUPER{`FALSE}};
    ld_idx = {`NUM_SUPER{`FALSE}};
    for (int i = 0; i < `NUM_SUPER; i++) begin
      for (int j = `NUM_LSQ; j >= 0; j--) begin
        if (LQ_SQ_out.addr[i] == sq[sq_map_idx[j]].addr && sq[sq_map_idx[j]].valid && j >= head_map_idx) begin
          ld_hit[i] = `TRUE;
          ld_idx[i] = sq_map_idx[j];
          break;
        end
      end
    end
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      head <= `SD {($clog2(`NUM_LSQ)){1'b0}};
      tail <= `SD {($clog2(`NUM_LSQ)){1'b0}};
      sq   <= `SD `SQ_RESET;
    end else if (en) begin
      head <= `SD next_head;
      tail <= `SD next_tail;
      sq   <= `SD next_sq;
    end
  end
endmodule

module LQ (
  input  logic                                   clock, reset, en, dispatch_en,
  input  logic            [`NUM_SUPER-1:0]       rollback_en,
  input  logic            [$clog2(`NUM_LSQ)-1:0] SQ_rollback_idx,
  input  DECODER_LQ_OUT_t                        decoder_LQ_out,
  input  D_CACHE_LQ_OUT_t                        D_cache_LQ_out,
  input  FU_LQ_OUT_t                             FU_LQ_out,
  input  ROB_LQ_OUT_t                            ROB_LQ_out,
  output logic            [`NUM_SUPER-1:0]       LQ_valid,
  output LQ_SQ_OUT_t                             LQ_SQ_out,
  output LQ_ROB_OUT_t                            LQ_ROB_out,
  output LQ_FU_OUT_t                             LQ_FU_out,
  output LQ_RS_OUT_t                             LQ_RS_out
);

  logic      [$clog2(NUM_LSQ)-1:0] head, next_head, tail, next_tail;
  LQ_ENTRY_t [`NUM_LSQ-1:0]        lq, next_lq;

  assign next_tail = rollback_en ? LQ_rollback_idx :
                     dispatch_en ? virtual_tail    : tail;
  assign tail_plus_one = tail + 1;
  assign tail_plus_two = tail + 2;
  assign head_plus_one = head + 1;
  assign head_plus_two = head + 2;
  assign tail_map_idx  = tail - head;
  assign LQ_RS_out.LQ_idx = '{tail2, tail1};
  assign LQ_SQ_out  = '{FU_LQ_out.SQ_idx, FU_LQ_out.result};
  assign next_head  = LQ_retire_en ? head_plus_one : head;
  assign LQ_valid   = SQ_LQ_out.hit | D_cache_LQ_out.hit;
  assign LQ_FU_out  = '{SQ_LQ_out.value};
  assign LQ_violate = st_hit;

  // Dispatch valid
  always_comb begin
    case(decoder_SQ_out.wr_mem)
      2'b00: begin
        virtual_tail   = tail;
        dispatch_valid = `TRUE;
        tail1          = tail;
        tail2          = tail;
      end
      2'b01: begin
        virtual_tail   = tail_plus_one;
        dispatch_valid = tail_plus_one != head;
        tail1          = tail_plus_one;
        tail2          = tail_plus_one;
      end
      2'b10: begin
        virtual_tail   = tail_plus_one;
        dispatch_valid = tail_plus_one != head;
        tail1          = tail;
        tail2          = tail_plus_one;
      end
      2'b11: begin
        virtual_tail   = tail_plus_two;
        dispatch_valid = tail_plus_one != head && tail_plus_two != head;
        tail1          = tail_plus_one;
        tail2          = tail_plus_two;
      end
    endcase
  end

  // Age logic
  // Map LQ idx
  always_comb begin
    for (int j = 0; j < `NUM_LSQ; j++) begin
      lq_map_idx[j] = head + j;
    end
  end

  // Rollback
  always_comb begin
    st_hit = '{`NUM_SUPER{`FALSE}};
    st_idx = '{`NUM_SUPER{($clog2(`NUM_LSQ)){1'b0}}}
    for (int i = 0; i < `NUM_SUPER; i++) begin
      for (int j = 0; j < `NUM_LSQ; j++) begin
        if (SQ_LQ_out.addr[i] == lq[lq_map_idx[j]].addr && j < tail_map_idx) begin
          st_hit[i] = `TRUE;
          st_idx[i] = lq_map_idx[j];
          break;
        end
      end
    end
  end

  // Retire
  always_comb begin
    case(ROB_LQ_out.rd_mem & retire_en)
      2'b00: begin
        next_head = head;
      end
      2'b01: begin
        next_head = head_plus_one;
      end
      2'b10: begin
        next_head = head_plus_one;
      end
      2'b11: begin
        next_head = head_plus_two;
      end
    endcase
  end

  always_comb begin
    next_lq = lq;
    if (dispatch_en) begin
      case(ROB_LQ_out.rd_mem)
        2'b01, 2'b10: next_lq[tail] = `LQ_ENTRY_RESET_PACKED;
        2'b11: begin
          next_lq[tail]          = `LQ_ENTRY_RESET_PACKED;
          next_lq[tail_plus_one] = `LQ_ENTRY_RESET_PACKED;
        end
      endcase
    end
    for (int i = 0; i < `NUM_SUPER; i++) begin
      if (FU_LQ_out.done[i] && LQ_valid[i]) begin
        next_lq[FU_LSQ_out.LQ_idx[i]] = '{FU_LQ_out.result[i][63:3], `TRUE};
      end
    end
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      head <= `SD {($clog2(`NUM_LSQ)){1'b0}};
      tail <= `SD {($clog2(`NUM_LSQ)){1'b0}};
      lq   <= `SD `LQ_RESET;
    end else if (en) begin
      head <= `SD next_head;
      tail <= `SD next_tail;
      lq   <= `SD next_lq;
    end
  end
endmodule