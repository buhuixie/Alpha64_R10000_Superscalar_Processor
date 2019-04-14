
module Dcache_controller(
    input logic                                                                   clock, reset,
    //proc to cache            
    input logic [60:0]                                                            rd_in_addr,
    input logic [60:0]                                                            wr_in_addr,
    input logic                                                                   rd_en,
    input logic                                                                   wr_en,
    input logic [63:0]                                                            wr_data,

    //cache to proc                                 
    output logic [63:0]                                                           data,
    output logic                                                                  valid_data,
    output logic                                                                  valid_store, // tells if a store can be moved on.

    //Dcachemem to cache                                  
    input logic [63:0]                                                            rd1_data, 
    input logic                                                                   rd1_hit, wr1_hit,
    input logic                                                                   evicted_dirty,
    input logic                                                                   evicted_valid,
    input SASS_ADDR                                                               evicted_addr,
    input logic [63:0]                                                            evicted_data,

    // cache to Dcachemem                       
    output logic                                                                  wr1_en, wr1_dirty, wr1_from_mem, wr1_valid,
    output SASS_ADDR                                                              rd1_addr, wr1_addr,
    output logic [63:0]                                                           wr1_data,

    //MSHR to cache                                 
    input logic                                                                   mshr_valid,
    input logic                                                                   mshr_empty,

    // input logic [1:0][63:0]                                                       miss_data,
    // input logic [1:0]                                                             miss_data_valid,
    input logic [1:0]                                                             miss_addr_hit,

    input logic                                                                   mem_wr,
    input logic                                                                   mem_dirty,
    input logic [63:0]                                                            mem_data,
    input SASS_ADDR                                                               mem_addr,

    input logic                                                                   rd_wb_en,
    input logic                                                                   rd_wb_dirty,
    input logic [63:0]                                                            rd_wb_data,
    input SASS_ADDR                                                               rd_wb_addr,

    input logic                                                                   wr_wb_en,
    input logic                                                                   wr_wb_dirty,
    input logic [63:0]                                                            wr_wb_data,
    input SASS_ADDR                                                               wr_wb_addr,

    //cache to MSHR (loading)                                 
    output logic [2:0]                                                            miss_en,
    output SASS_ADDR [2:0]                                                        miss_addr,
    output logic [2:0][63:0]                                                      miss_data_in,
    output MSHR_INST_TYPE [2:0]                                                   inst_type,
    output logic [2:0][1:0]                                                       mshr_proc2mem_command,
    //cache to MSHR (searching)                                 
    output SASS_ADDR [1:0]                                                        search_addr,
    output MSHR_INST_TYPE [1:0]                                                   search_type,
    output [63:0]                                                                 search_wr_data,
    //cache to MSHR (Written back)                      
    output logic                                                                  stored_rd_wb,
    output logic                                                                  stored_wr_wb,
    output logic                                                                  stored_mem_wr,


    input  logic                                                                  write_back,
    output logic                                                                  cache_valid,
    output logic                                                                  halt_pipeline
);
//logics

logic [1:0] state, next_state;
logic [63:0] count, next_count;
logic write_back_stage;
SASS_ADDR write_back_addr;


//read cache outputs

//output data from mshr if exist otherwise from cache
assign data = rd1_data; 

//data is valid if it is read and if data is either in cache or mshr
assign valid_data = rd1_hit;

assign valid_store = (stored_wr_wb || miss_en[1]);


//set MSHR CMMD

//search mshr for rd1 data
assign search_addr[0] = rd1_addr;
assign search_type[0] = LOAD;

//search mshr for wr1 data
assign search_addr[1] = {wr_in_addr,3'b000};
assign search_type[1] = STORE;
assign search_wr_data = wr_data;

//if not in cache, enable to push data to the MSHR
assign miss_en[0] = (rd_en & !rd1_hit & !miss_addr_hit[0]);
//Miss from stores
assign miss_en[1] = (wr_en & !wr1_hit & !miss_addr_hit[1]);
//Store inst from evicts
assign miss_en[2] = (wr1_from_mem & evicted_dirty & evicted_valid);// when wr1 is from memory and it is dirty

//data sent to MSHR search
assign miss_addr[0] = rd1_addr;
assign miss_data_in[0] = {64'hDEADBEEFDEADBEEF};
assign inst_type[0] = LOAD;
assign mshr_proc2mem_command[0] = BUS_LOAD;

assign miss_addr[1] = wr1_addr;
assign miss_data_in[1]= wr_data;
assign inst_type[1] = STORE;
assign mshr_proc2mem_command[1] = BUS_LOAD;

assign miss_addr[2] = evicted_addr;
assign miss_data_in[2] = evicted_data;
assign inst_type[2] = EVICT;
assign mshr_proc2mem_command[2] = BUS_STORE;

//data to cache
//assign cachemem inputs
assign rd1_addr = {rd_in_addr,3'b000};



assign wr1_addr = (write_back_stage)              ?  write_back_addr :
                  (wr_en & wr1_hit)               ?  wr_in_addr      :
                  (wr_wb_en)                      ?  wr_wb_addr      :
                  (!wr_wb_en & rd_wb_en)          ?  rd_wb_addr      : mem_addr;

assign wr1_dirty = (wr_en & wr1_hit)               ?  1           :
                   (wr_wb_en)                      ?  wr_wb_dirty :
                   (!wr_wb_en & rd_wb_en)          ?  rd_wb_dirty : mem_dirty;

assign wr1_data = (wr_en & wr1_hit)               ?  wr_data    :
                  (wr_wb_en)                      ?  wr_wb_data :
                  (!wr_wb_en & rd_wb_en)          ?  rd_wb_data : mem_data;

assign wr1_valid = (write_back_stage)             ? 0 : 1;

assign wr1_from_mem = mem_wr | rd_wb_en | wr_wb_en | write_back_stage;

assign wr1_en = (wr1_hit & wr_en) | wr1_from_mem;

//inform MSHR that it is written
assign stored_rd_wb = !wr_en & rd_wb_en;
assign stored_wr_wb = !wr_en & !rd_wb_en & wr_wb_en;
assign stored_mem_wr = !wr_en & !rd_wb_en & !wr_wb_en & mem_wr;

//set the cache id valid or not
assign cache_valid = mshr_valid;

// to clear cache after prog done

always_comb begin
  if (write_back_stage && mshr_valid)
    next_count = count + 1;
  else
    next_count = count;
end

always_comb begin
  if (state == 0 && write_back) 
    next_state = 1;
  else if(write_back_stage && count >= `TOTAL_LINES)
    next_state = 2;
  else
    next_state = state;
end

assign halt_pipeline = (state == 2) && mshr_empty;
assign write_back_stage = state == 1;
assign write_back_addr = count & {{61{1'b1}},3'b000};

always_ff @(posedge clock) begin
  if(reset) begin
    state           <= `SD 0;
    count           <= `SD 0;
  end
  else begin
    state           <= `SD next_state;
    count           <= `SD next_count;
  end
end

endmodule
