module axi_apb_bridge #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  input  logic                     CLK,
  input  logic                     RST,

  // AXI
  input  logic [ADDR_WIDTH-1:0]    S_AXI_ARADDR,
  input  logic                     S_AXI_ARVALID,
  output logic                     S_AXI_ARREADY,

  output logic [DATA_WIDTH-1:0]    S_AXI_RDATA,
  output logic [1:0]               S_AXI_RRESP,
  output logic                     S_AXI_RVALID,
  input  logic                     S_AXI_RREADY,

  input  logic [ADDR_WIDTH-1:0]    S_AXI_AWADDR,
  input  logic                     S_AXI_AWVALID,
  output logic                     S_AXI_AWREADY,

  input  logic [DATA_WIDTH-1:0]    S_AXI_WDATA,
  input  logic                     S_AXI_WVALID,
  output logic                     S_AXI_WREADY,

  output logic [1:0]               S_AXI_BRESP,
  output logic                     S_AXI_BVALID,
  input  logic                     S_AXI_BREADY,

  // APB
  output logic [ADDR_WIDTH-1:0]    M_APB_PADDR,
  output logic                     M_APB_PSEL,
  output logic                     M_APB_PENABLE,
  output logic                     M_APB_PWRITE,
  output logic [DATA_WIDTH-1:0]    M_APB_PWDATA,
  input  logic                     M_APB_PREADY,
  input  logic [DATA_WIDTH-1:0]    M_APB_PRDATA,
  input  logic                     M_APB_PSLVERR
);

  typedef enum logic [2:0] {
    IDLE_STATE,
    WRITE_ADDRESS_RECEIVED_STATE,
    WRITE_DATA_RECEIVED_STATE,
    PENABLE_WRITE_SIGNAL,
    WDATA_TRANSFERRED_STATE,
    READ_ADDRESS_RECEIVED_STATE,
    PENABLE_READ_SIGNAL,
    RDATA_TRANSFERRED_STATE
  } fsm_state_t;

  fsm_state_t present_state, next_state;

  logic [ADDR_WIDTH-1:0] sampled_address;
  logic [DATA_WIDTH-1:0] sampled_wdata;

  // State register
  always_ff @(posedge CLK or posedge RST) begin
    if (RST)
      present_state <= IDLE_STATE;
    else
      present_state <= next_state;
  end

  // FSM logic
  always_comb begin
    next_state = present_state;
    unique case (present_state)
      IDLE_STATE: begin
        if (S_AXI_ARVALID && !S_AXI_AWVALID)
          next_state = READ_ADDRESS_RECEIVED_STATE;
        else if (!S_AXI_ARVALID && S_AXI_AWVALID)
          next_state = WRITE_ADDRESS_RECEIVED_STATE;
        else if (S_AXI_ARVALID && S_AXI_AWVALID)
          next_state = READ_ADDRESS_RECEIVED_STATE;
      end
      WRITE_ADDRESS_RECEIVED_STATE: begin
        if (S_AXI_WVALID)
          next_state = WRITE_DATA_RECEIVED_STATE;
      end
      WRITE_DATA_RECEIVED_STATE: begin
        next_state = PENABLE_WRITE_SIGNAL;
      end
      PENABLE_WRITE_SIGNAL: begin
        if (M_APB_PREADY)
          next_state = WDATA_TRANSFERRED_STATE;
      end
      WDATA_TRANSFERRED_STATE: begin
        if (S_AXI_BREADY)
          next_state = IDLE_STATE;
      end
      READ_ADDRESS_RECEIVED_STATE: begin
        next_state = PENABLE_READ_SIGNAL;
      end
      PENABLE_READ_SIGNAL: begin
        if (M_APB_PREADY)
          next_state = RDATA_TRANSFERRED_STATE;
      end
      RDATA_TRANSFERRED_STATE: begin
        if (S_AXI_RREADY)
          next_state = IDLE_STATE;
      end
    endcase
  end

  // Outputs and control logic
  always_comb begin
    S_AXI_ARREADY = 0;
    S_AXI_AWREADY = 0;
    S_AXI_WREADY  = 0;
    S_AXI_BVALID  = 0;
    S_AXI_RVALID  = 0;

    M_APB_PSEL    = 0;
    M_APB_PENABLE = 0;
    M_APB_PWRITE  = 0;

    case (present_state)
      WRITE_ADDRESS_RECEIVED_STATE: begin
        S_AXI_AWREADY = 1;
        S_AXI_WREADY  = 1;
      end
      WRITE_DATA_RECEIVED_STATE: begin
        M_APB_PSEL   = 1;
        M_APB_PWRITE = 1;
      end
      PENABLE_WRITE_SIGNAL: begin
        M_APB_PSEL    = 1;
        M_APB_PWRITE  = 1;
        M_APB_PENABLE = 1;
      end
      WDATA_TRANSFERRED_STATE: begin
        S_AXI_BVALID = 1;
      end
      READ_ADDRESS_RECEIVED_STATE: begin
        S_AXI_ARREADY = 1;
        M_APB_PSEL    = 1;
      end
      PENABLE_READ_SIGNAL: begin
        M_APB_PSEL    = 1;
        M_APB_PENABLE = 1;
      end
      RDATA_TRANSFERRED_STATE: begin
        S_AXI_RVALID = 1;
      end
    endcase
  end

  // Sample address
  always_ff @(posedge CLK or posedge RST) begin
    if (RST)
      sampled_address <= '0;
    else if (present_state == IDLE_STATE) begin
      if (S_AXI_ARVALID)
        sampled_address <= S_AXI_ARADDR;
      else if (S_AXI_AWVALID)
        sampled_address <= S_AXI_AWADDR;
    end
  end

  // Sample write data
  always_ff @(posedge CLK or posedge RST) begin
    if (RST)
      sampled_wdata <= '0;
    else if ((present_state == WRITE_ADDRESS_RECEIVED_STATE && S_AXI_WVALID) ||
             (present_state == WDATA_TRANSFERRED_STATE && S_AXI_WVALID))
      sampled_wdata <= S_AXI_WDATA;
  end

  // APB outputs assignment
  always_ff @(posedge CLK or posedge RST) begin
    if (RST) begin
      M_APB_PWDATA <= '0;
      M_APB_PADDR  <= '0;
    end else begin
      if ((present_state == WRITE_ADDRESS_RECEIVED_STATE && S_AXI_WVALID) ||
          (present_state == WDATA_TRANSFERRED_STATE && S_AXI_WVALID)) begin
        M_APB_PADDR  <= sampled_address;
        M_APB_PWDATA <= S_AXI_WDATA;
      end else if (present_state == IDLE_STATE && S_AXI_ARVALID) begin
        M_APB_PADDR <= S_AXI_ARADDR;
      end else if (present_state == RDATA_TRANSFERRED_STATE && S_AXI_RREADY) begin
        M_APB_PADDR <= sampled_address;
      end
    end
  end

  // Write response
  always_ff @(posedge CLK or posedge RST) begin
    if (RST)
      S_AXI_BRESP <= 2'b00;
    else if (present_state == PENABLE_WRITE_SIGNAL && M_APB_PREADY)
      S_AXI_BRESP <= M_APB_PSLVERR ? 2'b11 : 2'b00;
  end

  // Read data
  always_ff @(posedge CLK or posedge RST) begin
    if (RST)
      S_AXI_RDATA <= '0;
    else if (present_state == PENABLE_READ_SIGNAL && M_APB_PREADY && !M_APB_PSLVERR)
      S_AXI_RDATA <= M_APB_PRDATA;
    else
      S_AXI_RDATA <= '0;
  end

  // Read response
  always_ff @(posedge CLK or posedge RST) begin
    if (RST)
      S_AXI_RRESP <= 2'b00;
    else if (present_state == PENABLE_READ_SIGNAL && M_APB_PREADY)
      S_AXI_RRESP <= M_APB_PSLVERR ? 2'b11 : 2'b00;
  end

endmodule
