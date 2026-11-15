`ifndef AXI_TYPES_SV
`define AXI_TYPES_SV

package axi_types_pkg;

  typedef enum bit {
    AXI_READ  = 1'b0,
    AXI_WRITE = 1'b1
  } axi_txn_type_e;

  typedef enum bit [1:0] {
    AXI_FIXED = 2'b00,
    AXI_INCR  = 2'b01,
    AXI_WRAP  = 2'b10
  } axi_burst_type_e;

  typedef enum bit [1:0] {
    AXI_OKAY   = 2'b00,
    AXI_EXOKAY = 2'b01,
    AXI_SLVERR = 2'b10,
    AXI_DECERR = 2'b11
  } axi_resp_e;

  typedef enum bit {
    AXI4      = 1'b0,
    AXI4_LITE = 1'b1
  } axi_mode_e;

  typedef enum bit {
    AXI_MASTER = 1'b0,
    AXI_SLAVE  = 1'b1
  } axi_agent_role_e;

  typedef enum int {
    ERR_NONE          = 0,
    ERR_RESP          = 1,
    ERR_TIMEOUT       = 2,
    ERR_DATA_CORRUPT  = 3
  } axi_err_type_e;

  typedef enum int {
    BP_NONE          = 0,
    BP_FIXED_DELAY   = 1,
    BP_RANDOM        = 2,
    BP_BURST         = 3,
    BP_INTERMITTENT  = 4,
    BP_CUSTOM        = 5
  } axi_bp_mode_e;

endpackage

`endif // AXI_TYPES_SV
