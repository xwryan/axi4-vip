`timescale 1ns/1ps

module axi_checker_rule_tb;
  localparam int DATA_WIDTH = 64;
  localparam int ADDR_WIDTH = 32;
  localparam int ID_WIDTH   = 4;
  localparam int USER_WIDTH = 0;

  typedef enum int {
    PRIME_B_AFTER_AW_W,
    PRIME_BID_OUTSTANDING,
    PRIME_R_AFTER_AR,
    PRIME_RID_OUTSTANDING,
    PRIME_WLAST_MISSING,
    PRIME_WLAST_EARLY,
    PRIME_RLAST_MISSING,
    PRIME_RLAST_EARLY
  } reset_prime_kind_t;

  logic aclk = 0;
  logic aresetn;
  logic [ID_WIDTH-1:0] awid, bid, arid, rid;
  logic [ADDR_WIDTH-1:0] awaddr, araddr;
  logic [7:0] awlen, arlen;
  logic [2:0] awsize, arsize;
  logic [1:0] awburst, arburst, bresp, rresp;
  logic awlock, arlock;
  logic [3:0] awcache, arcache;
  logic [2:0] awprot, arprot;
  logic [3:0] awqos, arqos, awregion, arregion;
  logic awvalid, awready;
  logic [DATA_WIDTH-1:0] wdata, rdata;
  logic [DATA_WIDTH/8-1:0] wstrb;
  logic wlast, wvalid, wready;
  logic bvalid, bready;
  logic arvalid, arready;
  logic rlast, rvalid, rready;
  string scenario;
  longint unsigned write_pair_baseline;
  longint unsigned write_w_before_aw_bind_baseline;
  longint unsigned write_active_w_bind_baseline;
  longint unsigned write_complete_baseline;
  longint unsigned b_dependency_baseline;
  longint unsigned read_rid_selection_baseline;
  longint unsigned read_same_id_selection_baseline;
  longint unsigned read_different_id_interleave_baseline;
  longint unsigned recovery_sequence;

  always #5ns aclk = ~aclk;

  axi_protocol_checker #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .ID_WIDTH(ID_WIDTH),
    .USER_WIDTH(USER_WIDTH)
  ) dut (.*);

  task automatic clear_signals();
    awid='0; awaddr='0; awlen='0; awsize='0; awburst='0; awlock=0;
    awcache='0; awprot='0; awqos='0; awregion='0; awvalid=0; awready=0;
    wdata='0; wstrb='0; wlast=0; wvalid=0; wready=0;
    bid='0; bresp='0; bvalid=0; bready=0;
    arid='0; araddr='0; arlen='0; arsize='0; arburst='0; arlock=0;
    arcache='0; arprot='0; arqos='0; arregion='0; arvalid=0; arready=0;
    rid='0; rdata='0; rresp='0; rlast=0; rvalid=0; rready=0;
  endtask

  task automatic send_aw(
    input logic [ID_WIDTH-1:0] id,
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [7:0] len,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    @(negedge aclk);
    awid=id; awaddr=addr; awlen=len; awsize=size; awburst=burst;
    awvalid=1; awready=1;
    @(negedge aclk);
    awvalid=0; awready=0;
  endtask

  task automatic send_aw_w_same_cycle(
    input logic [ID_WIDTH-1:0] id,
    input logic [7:0] len,
    input logic last
  );
    @(negedge aclk);
    awid=id; awaddr=32'h0000_2000; awlen=len; awsize=3'd3;
    awburst=2'b01; awvalid=1; awready=1;
    wstrb='1; wlast=last; wvalid=1; wready=1;
    @(negedge aclk);
    awvalid=0; awready=0;
    wvalid=0; wready=0; wlast=0;
  endtask

  task automatic send_b(input logic [ID_WIDTH-1:0] id);
    @(negedge aclk);
    bid=id; bresp=2'b00; bvalid=1; bready=1;
    @(negedge aclk);
    bvalid=0; bready=0;
  endtask

  task automatic send_b_stalled(
    input logic [ID_WIDTH-1:0] id,
    input int unsigned stalled_cycles
  );
    @(negedge aclk);
    bid=id; bresp=2'b00; bvalid=1; bready=0;
    repeat (stalled_cycles) @(negedge aclk);
    bready=1;
    @(negedge aclk);
    bvalid=0; bready=0;
  endtask

  task automatic send_w_b_same_cycle(
    input logic [ID_WIDTH-1:0] id,
    input logic last
  );
    @(negedge aclk);
    wstrb='1; wlast=last; wvalid=1; wready=1;
    bid=id; bresp=2'b00; bvalid=1; bready=1;
    @(negedge aclk);
    wvalid=0; wready=0; wlast=0;
    bvalid=0; bready=0;
  endtask

  task automatic expect_write_counter_deltas(
    input string label,
    input longint unsigned pair_delta,
    input longint unsigned w_before_aw_bind_delta,
    input longint unsigned active_w_bind_delta,
    input longint unsigned complete_delta,
    input logic [ID_WIDTH-1:0] id,
    input longint unsigned id_complete_delta
  );
    if ((dut.write_pair_hit_count - write_pair_baseline) != pair_delta ||
        (dut.write_w_before_aw_bind_hit_count -
         write_w_before_aw_bind_baseline) != w_before_aw_bind_delta ||
        (dut.write_active_w_bind_hit_count -
         write_active_w_bind_baseline) != active_w_bind_delta ||
        (dut.write_complete_hit_count - write_complete_baseline) !=
          complete_delta ||
        dut.write_complete_by_id_hit_count[id] != id_complete_delta) begin
      $fatal(1,
        "WRITE_COUNTER_CHECK_FAILED %s pair=%0d pre_aw=%0d active=%0d complete=%0d id[%0d]=%0d",
        label,
        dut.write_pair_hit_count - write_pair_baseline,
        dut.write_w_before_aw_bind_hit_count -
          write_w_before_aw_bind_baseline,
        dut.write_active_w_bind_hit_count - write_active_w_bind_baseline,
        dut.write_complete_hit_count - write_complete_baseline,
        id, dut.write_complete_by_id_hit_count[id]);
    end
  endtask

  task automatic expect_write_outstanding(
    input string label,
    input longint unsigned total,
    input logic [ID_WIDTH-1:0] first_id,
    input longint unsigned first_count,
    input logic [ID_WIDTH-1:0] second_id,
    input longint unsigned second_count
  );
    if (dut.write_outstanding_count != total ||
        dut.write_outstanding_by_id_count[first_id] != first_count ||
        dut.write_outstanding_by_id_count[second_id] != second_count) begin
      $fatal(1,
        "WRITE_OUTSTANDING_CHECK_FAILED %s total=%0d id[%0d]=%0d id[%0d]=%0d",
        label, dut.write_outstanding_count,
        first_id, dut.write_outstanding_by_id_count[first_id],
        second_id, dut.write_outstanding_by_id_count[second_id]);
    end
  endtask

  task automatic send_w(input logic [7:0] strb, input logic last);
    @(negedge aclk);
    wstrb=strb; wlast=last; wvalid=1; wready=1;
    @(negedge aclk);
    wvalid=0; wready=0; wlast=0;
  endtask

  task automatic send_ar_id(
    input logic [ID_WIDTH-1:0] id,
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [7:0] len,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    @(negedge aclk);
    arid=id; araddr=addr; arlen=len; arsize=size; arburst=burst;
    arvalid=1; arready=1;
    @(negedge aclk);
    arvalid=0; arready=0;
  endtask

  task automatic send_ar(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [7:0] len,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    send_ar_id('0, addr, len, size, burst);
  endtask

  task automatic send_r(
    input logic [ID_WIDTH-1:0] id,
    input logic last
  );
    @(negedge aclk);
    rid=id; rdata=64'h0123_4567_89ab_cdef; rresp=2'b00;
    rlast=last; rvalid=1; rready=1;
    @(negedge aclk);
    rvalid=0; rready=0; rlast=0;
  endtask

  task automatic send_r_stalled(
    input logic [ID_WIDTH-1:0] id,
    input logic last,
    input int unsigned stalled_cycles
  );
    @(negedge aclk);
    rid=id; rdata=64'hfedc_ba98_7654_3210; rresp=2'b00;
    rlast=last; rvalid=1; rready=0;
    repeat (stalled_cycles) @(negedge aclk);
    rready=1;
    @(negedge aclk);
    rvalid=0; rready=0; rlast=0;
  endtask

  task automatic expect_response_counter_deltas(
    input string label,
    input longint unsigned b_dependency_delta,
    input longint unsigned rid_selection_delta,
    input longint unsigned same_id_selection_delta,
    input longint unsigned different_id_interleave_delta
  );
    if ((dut.b_dependency_check_hit_count - b_dependency_baseline) !=
          b_dependency_delta ||
        (dut.read_rid_selection_hit_count - read_rid_selection_baseline) !=
          rid_selection_delta ||
        (dut.read_same_id_selection_hit_count -
         read_same_id_selection_baseline) != same_id_selection_delta ||
        (dut.read_different_id_interleave_hit_count -
         read_different_id_interleave_baseline) !=
          different_id_interleave_delta) begin
      $fatal(1,
        "RESPONSE_COUNTER_CHECK_FAILED %s b=%0d rid=%0d same=%0d interleave=%0d",
        label,
        dut.b_dependency_check_hit_count - b_dependency_baseline,
        dut.read_rid_selection_hit_count - read_rid_selection_baseline,
        dut.read_same_id_selection_hit_count -
          read_same_id_selection_baseline,
        dut.read_different_id_interleave_hit_count -
          read_different_id_interleave_baseline);
    end
  endtask

  task automatic expect_read_recovery_consumed(
    input string label,
    input longint unsigned recovered_sequence
  );
    int queue_index;
    bit sequence_found;

    sequence_found = 1'b0;
    for (queue_index = 0;
         queue_index < dut.read_ar_queue.size();
         queue_index = queue_index + 1) begin
      if (dut.read_ar_queue[queue_index].sequence_number ==
            recovered_sequence)
        sequence_found = 1'b1;
    end
    if (sequence_found || dut.read_ar_queue.size() != 0)
      $fatal(1,
        "READ_RECOVERY_NOT_CONSUMED %s sequence=%0d found=%0d queue_size=%0d",
        label, recovered_sequence, sequence_found,
        dut.read_ar_queue.size());
  endtask

  task automatic expect_read_recovery_draining(
    input string label,
    input longint unsigned recovered_sequence
  );
    if (dut.read_ar_queue.size() != 1 ||
        dut.read_ar_queue[0].sequence_number != recovered_sequence ||
        dut.read_ar_queue[0].accepted_beat_count != 1 ||
        !dut.read_ar_queue[0].missing_reported)
      $fatal(1,
        "READ_RECOVERY_NOT_DRAINING %s sequence=%0d queue_size=%0d",
        label, recovered_sequence, dut.read_ar_queue.size());
  endtask

  task automatic expect_tracker_reset_state(input string label);
    if (dut.write_aw_queue.size() != 0 ||
        dut.write_w_queue.size() != 0 ||
        dut.write_complete_by_id_hit_count.num() != 0 ||
        dut.write_outstanding_by_id_count.num() != 0 ||
        dut.write_pair_hit_count != 0 ||
        dut.write_w_before_aw_bind_hit_count != 0 ||
        dut.write_active_w_bind_hit_count != 0 ||
        dut.write_complete_hit_count != 0 ||
        dut.write_outstanding_count != 0 ||
        dut.b_episode_active || dut.b_episode_legal ||
        dut.b_episode_id != '0 || dut.b_dependency_check_hit_count != 0 ||
        dut.read_ar_queue.size() != 0 || dut.read_next_sequence != 0 ||
        dut.r_episode_active || dut.r_episode_had_match ||
        dut.r_episode_id != '0 || dut.r_episode_last ||
        dut.r_episode_sequence != 0 ||
        dut.read_rid_selection_hit_count != 0 ||
        dut.read_same_id_selection_hit_count != 0 ||
        dut.read_different_id_interleave_hit_count != 0 ||
        dut.wlast_on_last_beat_violation_pulse ||
        dut.wlast_not_early_violation_pulse ||
        dut.b_after_aw_w_violation_pulse ||
        dut.b_id_outstanding_violation_pulse ||
        dut.r_after_ar_violation_pulse ||
        dut.r_id_outstanding_violation_pulse ||
        dut.rlast_on_last_beat_violation_pulse ||
        dut.rlast_not_early_violation_pulse ||
        dut.wlast_on_last_observed_beat != 0 ||
        dut.wlast_on_last_expected_beat != 0 ||
        dut.wlast_not_early_observed_beat != 0 ||
        dut.wlast_not_early_expected_beat != 0 ||
        dut.b_after_aw_w_observed_id != '0 ||
        dut.b_id_outstanding_observed_id != '0 ||
        dut.r_after_ar_observed_id != '0 ||
        dut.r_id_outstanding_observed_id != '0 ||
        dut.rlast_on_last_observed_id != '0 ||
        dut.rlast_on_last_observed_beat != 0 ||
        dut.rlast_on_last_expected_beat != 0 ||
        dut.rlast_not_early_observed_id != '0 ||
        dut.rlast_not_early_observed_beat != 0 ||
        dut.rlast_not_early_expected_beat != 0) begin
      $fatal(1, "TRACKER_RESET_NOT_CLEAN %s aw=%0d w=%0d credit=%0d ar=%0d",
        label, dut.write_aw_queue.size(), dut.write_w_queue.size(),
        dut.write_outstanding_count, dut.read_ar_queue.size());
    end
  endtask

  task automatic assert_sync_reset(input string label);
    @(negedge aclk);
    clear_signals();
    aresetn=0;
    #1ps;
    expect_tracker_reset_state(label);
    repeat (2) @(posedge aclk);
    @(negedge aclk);
    aresetn=1;
  endtask

  task automatic assert_async_reset(input string label);
    @(negedge aclk);
    clear_signals();
    aresetn=0;
    #1ps;
    expect_tracker_reset_state(label);
    #2ns;
    aresetn=1;
  endtask

  task automatic reset_primed_tracker(
    input string label,
    input bit asynchronous
  );
    if (asynchronous)
      assert_async_reset(label);
    else
      assert_sync_reset(label);
  endtask

  task automatic prime_violation_then_reset(
    input string label,
    input reset_prime_kind_t kind,
    input bit asynchronous
  );
    logic [ID_WIDTH-1:0] target_id;
    logic [ID_WIDTH-1:0] other_id;

    clear_signals();
    case (kind)
      PRIME_B_AFTER_AW_W: begin
        target_id=4'h1;
        send_aw(target_id, 32'h0000_6000, 8'd0, 3'd3, 2'b01);
        @(negedge aclk);
        bid=target_id; bresp=2'b00; bvalid=1; bready=1;
        @(posedge aclk);
        #1ps;
        if (!dut.b_after_aw_w_violation_pulse ||
            dut.b_id_outstanding_violation_pulse ||
            dut.b_after_aw_w_observed_id != target_id)
          $fatal(1,
            "RESET_PRIME_B_AFTER_AW_W_FAILED %s pulse=%0d other=%0d id=%0h",
            label, dut.b_after_aw_w_violation_pulse,
            dut.b_id_outstanding_violation_pulse,
            dut.b_after_aw_w_observed_id);
      end
      PRIME_BID_OUTSTANDING: begin
        target_id=4'h3;
        other_id=4'h2;
        send_aw(other_id, 32'h0000_6100, 8'd0, 3'd3, 2'b01);
        @(negedge aclk);
        bid=target_id; bresp=2'b00; bvalid=1; bready=1;
        @(posedge aclk);
        #1ps;
        if (!dut.b_id_outstanding_violation_pulse ||
            dut.b_after_aw_w_violation_pulse ||
            dut.b_id_outstanding_observed_id != target_id)
          $fatal(1,
            "RESET_PRIME_BID_OUTSTANDING_FAILED %s pulse=%0d other=%0d id=%0h",
            label, dut.b_id_outstanding_violation_pulse,
            dut.b_after_aw_w_violation_pulse,
            dut.b_id_outstanding_observed_id);
      end
      PRIME_R_AFTER_AR: begin
        target_id=4'h4;
        @(negedge aclk);
        rid=target_id; rdata=64'h4444_0000_0000_0001; rresp=2'b00;
        rlast=1; rvalid=1; rready=1;
        @(posedge aclk);
        #1ps;
        if (!dut.r_after_ar_violation_pulse ||
            dut.r_id_outstanding_violation_pulse ||
            dut.r_after_ar_observed_id != target_id)
          $fatal(1,
            "RESET_PRIME_R_AFTER_AR_FAILED %s pulse=%0d other=%0d id=%0h",
            label, dut.r_after_ar_violation_pulse,
            dut.r_id_outstanding_violation_pulse,
            dut.r_after_ar_observed_id);
      end
      PRIME_RID_OUTSTANDING: begin
        target_id=4'h6;
        other_id=4'h5;
        send_ar_id(other_id, 32'h0000_6200, 8'd0, 3'd3, 2'b01);
        @(negedge aclk);
        rid=target_id; rdata=64'h6666_0000_0000_0001; rresp=2'b00;
        rlast=1; rvalid=1; rready=1;
        @(posedge aclk);
        #1ps;
        if (!dut.r_id_outstanding_violation_pulse ||
            dut.r_after_ar_violation_pulse ||
            dut.r_id_outstanding_observed_id != target_id)
          $fatal(1,
            "RESET_PRIME_RID_OUTSTANDING_FAILED %s pulse=%0d other=%0d id=%0h",
            label, dut.r_id_outstanding_violation_pulse,
            dut.r_after_ar_violation_pulse,
            dut.r_id_outstanding_observed_id);
      end
      PRIME_WLAST_MISSING: begin
        send_aw(4'h7, 32'h0000_6300, 8'd0, 3'd3, 2'b01);
        @(negedge aclk);
        wstrb='1; wlast=0; wvalid=1; wready=1;
        @(posedge aclk);
        #1ps;
        if (!dut.wlast_on_last_beat_violation_pulse ||
            dut.wlast_not_early_violation_pulse ||
            dut.wlast_on_last_observed_beat != 1 ||
            dut.wlast_on_last_expected_beat != 1)
          $fatal(1,
            "RESET_PRIME_WLAST_MISSING_FAILED %s pulse=%0d beat=%0d expected=%0d",
            label, dut.wlast_on_last_beat_violation_pulse,
            dut.wlast_on_last_observed_beat,
            dut.wlast_on_last_expected_beat);
      end
      PRIME_WLAST_EARLY: begin
        send_aw(4'h8, 32'h0000_6400, 8'd2, 3'd3, 2'b01);
        @(negedge aclk);
        wstrb='1; wlast=1; wvalid=1; wready=1;
        @(posedge aclk);
        #1ps;
        if (!dut.wlast_not_early_violation_pulse ||
            dut.wlast_on_last_beat_violation_pulse ||
            dut.wlast_not_early_observed_beat != 1 ||
            dut.wlast_not_early_expected_beat != 3)
          $fatal(1,
            "RESET_PRIME_WLAST_EARLY_FAILED %s pulse=%0d beat=%0d expected=%0d",
            label, dut.wlast_not_early_violation_pulse,
            dut.wlast_not_early_observed_beat,
            dut.wlast_not_early_expected_beat);
      end
      PRIME_RLAST_MISSING: begin
        target_id=4'h9;
        send_ar_id(target_id, 32'h0000_6500, 8'd0, 3'd3, 2'b01);
        @(negedge aclk);
        rid=target_id; rdata=64'h9999_0000_0000_0001; rresp=2'b00;
        rlast=0; rvalid=1; rready=1;
        @(posedge aclk);
        #1ps;
        if (!dut.rlast_on_last_beat_violation_pulse ||
            dut.rlast_not_early_violation_pulse ||
            dut.rlast_on_last_observed_id != target_id ||
            dut.rlast_on_last_observed_beat != 1 ||
            dut.rlast_on_last_expected_beat != 1)
          $fatal(1,
            "RESET_PRIME_RLAST_MISSING_FAILED %s pulse=%0d id=%0h beat=%0d expected=%0d",
            label, dut.rlast_on_last_beat_violation_pulse,
            dut.rlast_on_last_observed_id,
            dut.rlast_on_last_observed_beat,
            dut.rlast_on_last_expected_beat);
      end
      PRIME_RLAST_EARLY: begin
        target_id=4'ha;
        send_ar_id(target_id, 32'h0000_6600, 8'd2, 3'd3, 2'b01);
        @(negedge aclk);
        rid=target_id; rdata=64'haaaa_0000_0000_0001; rresp=2'b00;
        rlast=1; rvalid=1; rready=1;
        @(posedge aclk);
        #1ps;
        if (!dut.rlast_not_early_violation_pulse ||
            dut.rlast_on_last_beat_violation_pulse ||
            dut.rlast_not_early_observed_id != target_id ||
            dut.rlast_not_early_observed_beat != 1 ||
            dut.rlast_not_early_expected_beat != 3)
          $fatal(1,
            "RESET_PRIME_RLAST_EARLY_FAILED %s pulse=%0d id=%0h beat=%0d expected=%0d",
            label, dut.rlast_not_early_violation_pulse,
            dut.rlast_not_early_observed_id,
            dut.rlast_not_early_observed_beat,
            dut.rlast_not_early_expected_beat);
      end
      default: $fatal(1, "unknown reset prime kind %0d", kind);
    endcase

    // Reset on the following negedge, before the named SVA can sample the
    // NBA-generated pulse at another positive edge.
    reset_primed_tracker(label, asynchronous);
  endtask

  task automatic prime_hit_counters_then_reset(input string label);
    // Complete one W burst before AW, then bind an active pre-AW W burst.
    send_w(8'hff, 1'b1);
    send_aw(4'hb, 32'h0000_6700, 8'd0, 3'd3, 2'b01);
    send_w(8'hff, 1'b0);
    send_aw(4'hc, 32'h0000_6800, 8'd1, 3'd3, 2'b01);
    send_w(8'hff, 1'b1);

    // Select the oldest of two same-ID records, then a non-head other ID.
    send_ar_id(4'hd, 32'h0000_6900, 8'd0, 3'd3, 2'b01);
    send_ar_id(4'hd, 32'h0000_6a00, 8'd0, 3'd3, 2'b01);
    send_r(4'hd, 1'b1);
    send_ar_id(4'he, 32'h0000_6b00, 8'd0, 3'd3, 2'b01);
    send_r(4'he, 1'b1);

    if (dut.write_w_before_aw_bind_hit_count == 0 ||
        dut.write_active_w_bind_hit_count == 0 ||
        dut.read_same_id_selection_hit_count == 0 ||
        dut.read_different_id_interleave_hit_count == 0)
      $fatal(1,
        "RESET_PRIME_HIT_COUNTERS_FAILED %s pre_aw=%0d active=%0d same=%0d interleave=%0d",
        label, dut.write_w_before_aw_bind_hit_count,
        dut.write_active_w_bind_hit_count,
        dut.read_same_id_selection_hit_count,
        dut.read_different_id_interleave_hit_count);
    assert_sync_reset(label);
  endtask

  task automatic prime_pending_then_reset(
    input string label,
    input bit asynchronous,
    input logic [ID_WIDTH-1:0] credit_id,
    input logic [ID_WIDTH-1:0] pending_id,
    input logic [ID_WIDTH-1:0] read_id
  );
    logic [ID_WIDTH-1:0] episode_read_id;

    episode_read_id = read_id + 1'b1;
    send_aw_w_same_cycle(credit_id, 8'd0, 1'b1);
    send_aw(pending_id, 32'h0000_6c00, 8'd1, 3'd3, 2'b01);
    send_w(8'hff, 1'b0);
    // Keep the original long AR pending, and use a later single-beat AR to
    // prime nonzero R episode LAST/sequence snapshots without a violation.
    send_ar_id(read_id, 32'h0000_6d00, 8'd1, 3'd3, 2'b01);
    send_ar_id(episode_read_id, 32'h0000_6e00, 8'd0, 3'd3, 2'b01);
    @(negedge aclk);
    bid=credit_id; bresp=2'b00; bvalid=1; bready=0;
    rid=episode_read_id; rdata=64'hdddd_0000_0000_0001; rresp=2'b00;
    rlast=1; rvalid=1; rready=0;
    @(posedge aclk);
    #1ps;
    if (dut.write_w_queue.size() != 1 ||
        dut.write_outstanding_count != 1 ||
        dut.read_ar_queue.size() != 2 ||
        !dut.b_episode_active || !dut.b_episode_legal ||
        dut.b_episode_id != credit_id ||
        !dut.r_episode_active || !dut.r_episode_had_match ||
        dut.r_episode_id != episode_read_id || !dut.r_episode_last ||
        dut.r_episode_sequence == 0)
      $fatal(1,
        "RESET_PENDING_SETUP_FAILED %s w=%0d credit=%0d ar=%0d b=%0d r=%0d",
        label, dut.write_w_queue.size(), dut.write_outstanding_count,
        dut.read_ar_queue.size(), dut.b_episode_active,
        dut.r_episode_active);
    if (!dut.write_outstanding_by_id_count.exists(credit_id) ||
        dut.write_outstanding_by_id_count[credit_id] != 1)
      $fatal(1, "RESET_PENDING_CREDIT_FAILED %s id=%0h", label, credit_id);
    if (!dut.write_w_queue[0].bound || dut.write_w_queue[0].completed ||
        dut.write_w_queue[0].missing_reported ||
        dut.write_w_queue[0].id != pending_id ||
        dut.write_w_queue[0].beat_count != 1 ||
        dut.read_ar_queue[0].id != read_id ||
        dut.read_ar_queue[0].accepted_beat_count != 0 ||
        dut.read_ar_queue[0].missing_reported ||
        dut.read_ar_queue[1].id != episode_read_id ||
        dut.read_ar_queue[1].sequence_number == 0 ||
        dut.read_ar_queue[1].accepted_beat_count != 0 ||
        dut.read_ar_queue[1].missing_reported)
      $fatal(1, "RESET_PENDING_DETAIL_FAILED %s", label);
    reset_primed_tracker(label, asynchronous);
  endtask

  initial begin
    clear_signals();
    aresetn=0;
    repeat (3) @(posedge aclk);
    @(negedge aclk);
    aresetn=1;

    write_pair_baseline = dut.write_pair_hit_count;
    write_w_before_aw_bind_baseline =
      dut.write_w_before_aw_bind_hit_count;
    write_active_w_bind_baseline = dut.write_active_w_bind_hit_count;
    write_complete_baseline = dut.write_complete_hit_count;
    b_dependency_baseline = dut.b_dependency_check_hit_count;
    read_rid_selection_baseline = dut.read_rid_selection_hit_count;
    read_same_id_selection_baseline =
      dut.read_same_id_selection_hit_count;
    read_different_id_interleave_baseline =
      dut.read_different_id_interleave_hit_count;

    if (!$value$plusargs("SCENARIO=%s", scenario))
      $fatal(1, "missing +SCENARIO");

    case (scenario)
      "ZERO_WSTRB": begin
        send_aw(4'h0, 32'h0000_1000, 8'd0, 3'd3, 2'b01);
        send_w(8'h00, 1'b1);
      end
      "WRAP_OFFSET": begin
        // Four 4-byte transfers. 0x18 is transfer-aligned and lies inside
        // the 0x10..0x1f wrap region; it need not equal the wrap boundary.
        send_aw(4'h0, 32'h0000_0018, 8'd3, 3'd2, 2'b10);
      end
      "AR_WRAP_OFFSET": begin
        send_ar(32'h0000_0018, 8'd3, 3'd2, 2'b10);
      end
      "CROSS_4KB": begin
        // Two 8-byte transfers starting at 0xff8 end at 0x1007.
        send_aw(4'h0, 32'h0000_0ff8, 8'd1, 3'd3, 2'b01);
      end
      "AR_CROSS_4KB": begin
        send_ar(32'h0000_0ff8, 8'd1, 3'd3, 2'b01);
      end
      "RESERVED_BURST": begin
        send_aw(4'h0, 32'h0000_1000, 8'd0, 3'd3, 2'b11);
      end
      "AR_RESERVED_BURST": begin
        send_ar(32'h0000_1000, 8'd0, 3'd3, 2'b11);
      end
      "FIXED_TOO_LONG": begin
        send_aw(4'h0, 32'h0000_1000, 8'd16, 3'd0, 2'b00);
      end
      "AR_FIXED_TOO_LONG": begin
        send_ar(32'h0000_1000, 8'd16, 3'd0, 2'b00);
      end
      "UNALIGNED_SINGLE_NEAR_4KB": begin
        // An unaligned single transfer is contained in the aligned
        // 0xff8..0xfff byte block and therefore does not cross 4KB.
        send_aw(4'h0, 32'h0000_0fff, 8'd0, 3'd3, 2'b01);
      end
      "AR_UNALIGNED_SINGLE_NEAR_4KB": begin
        send_ar(32'h0000_0fff, 8'd0, 3'd3, 2'b01);
      end
      "RESERVED_NEAR_4KB": begin
        // Reserved burst encoding has no burst-address semantics. Only the
        // encoding assertion should fire.
        send_aw(4'h0, 32'h0000_0ff8, 8'd1, 3'd3, 2'b11);
      end
      "AR_RESERVED_NEAR_4KB": begin
        send_ar(32'h0000_0ff8, 8'd1, 3'd3, 2'b11);
      end
      "AT_4KB_LIMIT": begin
        // Two aligned 8-byte transfers end exactly at 0xfff.
        send_aw(4'h0, 32'h0000_0ff0, 8'd1, 3'd3, 2'b01);
      end
      "AR_AT_4KB_LIMIT": begin
        send_ar(32'h0000_0ff0, 8'd1, 3'd3, 2'b01);
      end
      "WRAP_MISALIGNED": begin
        send_aw(4'h0, 32'h0000_001a, 8'd3, 3'd2, 2'b10);
      end
      "AR_WRAP_MISALIGNED": begin
        send_ar(32'h0000_001a, 8'd3, 3'd2, 2'b10);
      end
      "FIXED_MAX": begin
        send_aw(4'h0, 32'h0000_1000, 8'd15, 3'd0, 2'b00);
      end
      "AR_FIXED_MAX": begin
        send_ar(32'h0000_1000, 8'd15, 3'd0, 2'b00);
      end
      "WRITE_AW_BEFORE_W_CLEAN": begin
        send_aw(4'h1, 32'h0000_2000, 8'd1, 3'd3, 2'b01);
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b1);
        expect_write_counter_deltas(scenario, 1, 0, 0, 1, 4'h1, 1);
      end
      "WRITE_W_BEFORE_AW_CLEAN": begin
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b1);
        send_aw(4'h2, 32'h0000_2100, 8'd1, 3'd3, 2'b01);
        expect_write_counter_deltas(scenario, 1, 1, 0, 1, 4'h2, 1);
      end
      "WRITE_W_STARTS_BEFORE_AW_CLEAN": begin
        send_w(8'hff, 1'b0);
        send_aw(4'h3, 32'h0000_2200, 8'd1, 3'd3, 2'b01);
        send_w(8'hff, 1'b1);
        expect_write_counter_deltas(scenario, 1, 1, 1, 1, 4'h3, 1);
      end
      "WRITE_W_LAST_AND_AW_SAME_CYCLE_CLEAN": begin
        send_aw_w_same_cycle(4'h4, 8'd0, 1'b1);
        expect_write_counter_deltas(scenario, 1, 0, 0, 1, 4'h4, 1);
      end
      "WRITE_TWO_W_BEFORE_AW_CLEAN": begin
        send_w(8'hff, 1'b1);
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b1);
        send_aw(4'h5, 32'h0000_2300, 8'd0, 3'd3, 2'b01);
        send_aw(4'h6, 32'h0000_2400, 8'd1, 3'd3, 2'b01);
        expect_write_counter_deltas(scenario, 2, 2, 0, 2, 4'h5, 1);
        if (dut.write_complete_by_id_hit_count[4'h6] != 1)
          $fatal(1, "WRITE_COUNTER_CHECK_FAILED %s id[6]=%0d",
                 scenario, dut.write_complete_by_id_hit_count[4'h6]);
      end
      "WRITE_DIFFERENT_ID_B_REORDER_CLEAN": begin
        send_aw(4'h7, 32'h0000_2500, 8'd0, 3'd3, 2'b01);
        send_aw(4'h8, 32'h0000_2600, 8'd1, 3'd3, 2'b01);
        send_w(8'hff, 1'b1);
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b1);
        expect_write_outstanding(scenario, 2, 4'h7, 1, 4'h8, 1);
        send_b(4'h8);
        expect_write_outstanding(scenario, 1, 4'h7, 1, 4'h8, 0);
        send_b(4'h7);
        expect_write_outstanding(scenario, 0, 4'h7, 0, 4'h8, 0);
        expect_write_counter_deltas(scenario, 2, 0, 0, 2, 4'h7, 1);
        if (dut.write_complete_by_id_hit_count[4'h8] != 1)
          $fatal(1, "WRITE_COUNTER_CHECK_FAILED %s id[8]=%0d",
                 scenario, dut.write_complete_by_id_hit_count[4'h8]);
      end
      "WRITE_SAME_ID_RESPONSES_CLEAN": begin
        send_aw(4'h9, 32'h0000_2700, 8'd0, 3'd3, 2'b01);
        send_aw(4'h9, 32'h0000_2800, 8'd0, 3'd3, 2'b01);
        send_w(8'hff, 1'b1);
        expect_write_outstanding(scenario, 1, 4'h9, 1, 4'h0, 0);
        send_w_b_same_cycle(4'h9, 1'b1);
        // The B consumes the pre-edge credit and the new completion replaces
        // it.  A same-edge completion must not retroactively legalize B.
        expect_write_outstanding(scenario, 1, 4'h9, 1, 4'h0, 0);
        send_b(4'h9);
        expect_write_outstanding(scenario, 0, 4'h9, 0, 4'h0, 0);
        expect_write_counter_deltas(scenario, 2, 0, 0, 2, 4'h9, 2);
      end
      "B_AFTER_AW_W_CLEAN": begin
        send_aw(4'h1, 32'h0000_3100, 8'd0, 3'd3, 2'b01);
        send_w(8'hff, 1'b1);
        // A legal stalled response retains VALID and a stable payload.
        send_b_stalled(4'h1, 2);
        expect_response_counter_deltas(scenario, 1, 0, 0, 0);
      end
      "B_BEFORE_W_COMPLETE": begin
        send_aw(4'h2, 32'h0000_3200, 8'd0, 3'd3, 2'b01);
        send_b(4'h2);
      end
      "B_BEFORE_W_COMPLETE_STALLED": begin
        send_aw(4'h3, 32'h0000_3300, 8'd0, 3'd3, 2'b01);
        send_b_stalled(4'h3, 2);
      end
      "BID_NOT_OUTSTANDING": begin
        send_aw(4'h4, 32'h0000_3400, 8'd0, 3'd3, 2'b01);
        send_w(8'hff, 1'b1);
        send_b(4'h5);
        send_b(4'h4);
      end
      "READ_SINGLE_CLEAN": begin
        send_ar_id(4'h6, 32'h0000_3500, 8'd0, 3'd3, 2'b01);
        // A legal stalled beat retains VALID and every payload field.
        send_r_stalled(4'h6, 1'b1, 2);
        expect_response_counter_deltas(scenario, 0, 1, 0, 0);
      end
      "READ_INTERLEAVE_IDS_CLEAN": begin
        send_ar_id(4'h7, 32'h0000_3600, 8'd1, 3'd3, 2'b01);
        send_ar_id(4'h8, 32'h0000_3700, 8'd0, 3'd3, 2'b01);
        send_r(4'h7, 1'b0);
        send_r(4'h8, 1'b1);
        send_r(4'h7, 1'b1);
        expect_response_counter_deltas(scenario, 0, 3, 0, 1);
      end
      "READ_SAME_ID_ORDER_CLEAN": begin
        send_ar_id(4'h9, 32'h0000_3800, 8'd0, 3'd3, 2'b01);
        send_ar_id(4'h9, 32'h0000_3900, 8'd1, 3'd3, 2'b01);
        send_r(4'h9, 1'b1);
        send_r(4'h9, 1'b0);
        send_r(4'h9, 1'b1);
        expect_response_counter_deltas(scenario, 0, 3, 1, 0);
      end
      "RLAST_EARLY": begin
        send_ar_id(4'ha, 32'h0000_3a00, 8'd2, 3'd3, 2'b01);
        send_r(4'ha, 1'b1);
      end
      "RLAST_MISSING": begin
        send_ar_id(4'ha, 32'h0000_3b00, 8'd0, 3'd3, 2'b01);
        send_r(4'ha, 1'b0);
      end
      "RLAST_LATE": begin
        send_ar_id(4'ha, 32'h0000_3c00, 8'd0, 3'd3, 2'b01);
        send_r(4'ha, 1'b0);
        send_r(4'ha, 1'b1);
      end
      "RLAST_MISSING_THEN_NEXT_SAME_ID_CLEAN": begin
        send_ar_id(4'hb, 32'h0000_3d00, 8'd0, 3'd3, 2'b01);
        send_ar_id(4'hb, 32'h0000_3e00, 8'd0, 3'd3, 2'b01);
        send_r(4'hb, 1'b0);
        send_r(4'hb, 1'b1);
        send_r(4'hb, 1'b1);
      end
      "R_WITHOUT_AR": begin
        send_r(4'hc, 1'b1);
      end
      "R_WITHOUT_AR_STALLED": begin
        send_r_stalled(4'hc, 1'b1, 2);
      end
      "RID_NOT_OUTSTANDING": begin
        send_ar_id(4'hd, 32'h0000_3f00, 8'd0, 3'd3, 2'b01);
        send_r(4'he, 1'b1);
        send_r(4'hd, 1'b1);
      end
      "B_STALLED_EARLY_THEN_COMPLETES": begin
        send_aw(4'hf, 32'h0000_4000, 8'd0, 3'd3, 2'b01);
        @(negedge aclk);
        bid=4'hf; bresp=2'b00; bvalid=1; bready=0;
        repeat (2) @(negedge aclk);
        send_w(8'hff, 1'b1);
        @(negedge aclk);
        bready=1;
        @(negedge aclk);
        bvalid=0; bready=0;

        expect_write_outstanding(
          "B_STALLED_EARLY_RECOVERY", 0, 4'hf, 0, 4'h0, 0);

        send_aw(4'hf, 32'h0000_4100, 8'd0, 3'd3, 2'b01);
        send_w(8'hff, 1'b1);
        send_b(4'hf);
      end
      "R_STALLED_EARLY_THEN_AR": begin
        @(negedge aclk);
        rid=4'h1; rdata=64'h1111_2222_3333_4444; rresp=2'b00;
        rlast=1; rvalid=1; rready=0;
        repeat (2) @(negedge aclk);
        recovery_sequence = dut.read_next_sequence;
        send_ar_id(4'h1, 32'h0000_4200, 8'd0, 3'd3, 2'b01);
        @(negedge aclk);
        rready=1;
        @(negedge aclk);
        rvalid=0; rready=0; rlast=0;

        expect_read_recovery_consumed(
          "R_STALLED_EARLY_RECOVERY", recovery_sequence);

        send_ar_id(4'h1, 32'h0000_4300, 8'd0, 3'd3, 2'b01);
        send_r(4'h1, 1'b1);
      end
      "R_RECOVERY_RLAST_EARLY": begin
        @(negedge aclk);
        rid=4'h4; rdata=64'h4444_5555_6666_7777; rresp=2'b00;
        rlast=1; rvalid=1; rready=0;
        repeat (2) @(negedge aclk);
        recovery_sequence = dut.read_next_sequence;
        send_ar_id(4'h4, 32'h0000_4800, 8'd3, 3'd3, 2'b01);
        @(negedge aclk);
        rready=1;
        @(negedge aclk);
        rvalid=0; rready=0; rlast=0;
        expect_read_recovery_consumed(scenario, recovery_sequence);
      end
      "R_RECOVERY_RLAST_MISSING": begin
        @(negedge aclk);
        rid=4'h5; rdata=64'h5555_6666_7777_8888; rresp=2'b00;
        rlast=0; rvalid=1; rready=0;
        repeat (2) @(negedge aclk);
        recovery_sequence = dut.read_next_sequence;
        send_ar_id(4'h5, 32'h0000_4900, 8'd0, 3'd3, 2'b01);
        @(negedge aclk);
        rready=1;
        @(negedge aclk);
        rvalid=0; rready=0;
        expect_read_recovery_draining(scenario, recovery_sequence);
        send_r(4'h5, 1'b1);
        expect_read_recovery_consumed(scenario, recovery_sequence);
      end
      "B_HANDSHAKE_AND_NEXT_WRITE_COMPLETE_SAME_CYCLE": begin
        send_aw(4'h2, 32'h0000_4400, 8'd0, 3'd3, 2'b01);
        send_aw(4'h2, 32'h0000_4500, 8'd0, 3'd3, 2'b01);
        send_w(8'hff, 1'b1);
        send_w_b_same_cycle(4'h2, 1'b1);
        send_b(4'h2);
        expect_response_counter_deltas(scenario, 2, 0, 0, 0);
      end
      "OLD_RLAST_AND_NEXT_AR_SAME_ID_SAME_CYCLE": begin
        send_ar_id(4'h3, 32'h0000_4600, 8'd0, 3'd3, 2'b01);
        @(negedge aclk);
        rid=4'h3; rdata=64'haaaa_bbbb_cccc_dddd; rresp=2'b00;
        rlast=1; rvalid=1; rready=1;
        arid=4'h3; araddr=32'h0000_4700; arlen=8'd0; arsize=3'd3;
        arburst=2'b01; arvalid=1; arready=1;
        @(negedge aclk);
        rvalid=0; rready=0; rlast=0;
        arvalid=0; arready=0;
        send_r(4'h3, 1'b1);
        expect_response_counter_deltas(scenario, 0, 2, 0, 0);
      end
      "WLAST_EARLY": begin
        send_aw(4'ha, 32'h0000_2900, 8'd2, 3'd3, 2'b01);
        send_w(8'hff, 1'b1);
      end
      "WLAST_MISSING": begin
        send_aw(4'ha, 32'h0000_2a00, 8'd1, 3'd3, 2'b01);
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b0);
      end
      "WLAST_LATE": begin
        send_aw(4'ha, 32'h0000_2b00, 8'd1, 3'd3, 2'b01);
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b1);
      end
      "WLAST_MISSING_THEN_NEXT_WRITE_CLEAN": begin
        send_aw(4'hb, 32'h0000_2c00, 8'd1, 3'd3, 2'b01);
        send_aw(4'hc, 32'h0000_2d00, 8'd0, 3'd3, 2'b01);
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b1);
        send_w(8'hff, 1'b1);
        expect_write_counter_deltas(scenario, 2, 0, 0, 2, 4'hb, 1);
        if (dut.write_complete_by_id_hit_count[4'hc] != 1)
          $fatal(1, "WRITE_COUNTER_CHECK_FAILED %s id[12]=%0d",
                 scenario, dut.write_complete_by_id_hit_count[4'hc]);
      end
      "W_BEFORE_AW_WLAST_EARLY": begin
        send_w(8'hff, 1'b1);
        send_aw(4'hd, 32'h0000_2e00, 8'd1, 3'd3, 2'b01);
      end
      "W_BEFORE_AW_WLAST_LATE": begin
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b1);
        send_aw(4'he, 32'h0000_2f00, 8'd1, 3'd3, 2'b01);
      end
      "AW_ARRIVES_AFTER_EXPECTED_BEAT": begin
        send_w(8'hff, 1'b0);
        send_w(8'hff, 1'b0);
        send_aw(4'hf, 32'h0000_3000, 8'd1, 3'd3, 2'b01);
        send_w(8'hff, 1'b1);
      end
      "RESET_CLEARS_PENDING_CLEAN": begin
        prime_violation_then_reset(scenario, PRIME_B_AFTER_AW_W, 1'b0);
        prime_violation_then_reset(scenario, PRIME_BID_OUTSTANDING, 1'b0);
        prime_violation_then_reset(scenario, PRIME_R_AFTER_AR, 1'b0);
        prime_violation_then_reset(scenario, PRIME_RID_OUTSTANDING, 1'b0);
        prime_hit_counters_then_reset(scenario);
        // Preserve the original queue/credit/episode reset coverage.
        prime_pending_then_reset(scenario, 1'b0, 4'h1, 4'h2, 4'h3);
        send_aw_w_same_cycle(4'h2, 8'd0, 1'b1);
        send_b(4'h2);
        send_ar_id(4'h3, 32'h0000_5300, 8'd0, 3'd3, 2'b01);
        send_r(4'h3, 1'b1);
        expect_write_outstanding(scenario, 0, 4'h2, 0, 4'h0, 0);
        if (dut.read_ar_queue.size() != 0)
          $fatal(1, "RESET_PENDING_REUSE_FAILED ar=%0d",
                 dut.read_ar_queue.size());
      end
      "B_AFTER_RESET_INVALID": begin
        send_aw_w_same_cycle(4'h4, 8'd0, 1'b1);
        if (dut.write_outstanding_count != 1)
          $fatal(1, "B_AFTER_RESET_SETUP_FAILED credit=%0d",
                 dut.write_outstanding_count);
        assert_sync_reset(scenario);
        send_b(4'h4);
      end
      "R_AFTER_RESET_INVALID": begin
        send_ar_id(4'h5, 32'h0000_5400, 8'd0, 3'd3, 2'b01);
        if (dut.read_ar_queue.size() != 1)
          $fatal(1, "R_AFTER_RESET_SETUP_FAILED ar=%0d",
                 dut.read_ar_queue.size());
        assert_sync_reset(scenario);
        send_r(4'h5, 1'b1);
      end
      "AW_W_SAME_CYCLE_CLEAN": begin
        send_aw_w_same_cycle(4'h6, 8'd0, 1'b1);
        expect_write_counter_deltas(scenario, 1, 0, 0, 1, 4'h6, 1);
        expect_write_outstanding(scenario, 1, 4'h6, 1, 4'h0, 0);
        send_b(4'h6);
        expect_write_outstanding(scenario, 0, 4'h6, 0, 4'h0, 0);
        expect_response_counter_deltas(scenario, 1, 0, 0, 0);
      end
      "AR_R_SAME_CYCLE_INVALID": begin
        @(negedge aclk);
        arid=4'h7; araddr=32'h0000_5500; arlen=8'd0; arsize=3'd3;
        arburst=2'b01; arvalid=1; arready=1;
        rid=4'h7; rdata=64'h7777_8888_9999_aaaa; rresp=2'b00;
        rlast=1; rvalid=1; rready=1;
        @(negedge aclk);
        arvalid=0; arready=0;
        rvalid=0; rready=0; rlast=0;
        if (dut.read_ar_queue.size() != 1)
          $fatal(1, "AR_R_SAME_CYCLE_CONSUMED_NEW_AR ar=%0d",
                 dut.read_ar_queue.size());
        send_r(4'h7, 1'b1);
        if (dut.read_ar_queue.size() != 0)
          $fatal(1, "AR_R_SAME_CYCLE_RECOVERY_FAILED ar=%0d",
                 dut.read_ar_queue.size());
      end
      "AW_W_B_SAME_CYCLE_INVALID": begin
        @(negedge aclk);
        awid=4'h8; awaddr=32'h0000_5600; awlen=8'd0; awsize=3'd3;
        awburst=2'b01; awvalid=1; awready=1;
        wstrb='1; wlast=1; wvalid=1; wready=1;
        bid=4'h8; bresp=2'b00; bvalid=1; bready=1;
        @(negedge aclk);
        awvalid=0; awready=0;
        wvalid=0; wready=0; wlast=0;
        bvalid=0; bready=0;
        expect_write_outstanding(scenario, 1, 4'h8, 1, 4'h0, 0);
        send_b(4'h8);
        expect_write_outstanding(scenario, 0, 4'h8, 0, 4'h0, 0);
      end
      "W_RECOVERY_RESET_THEN_CLEAN": begin
        send_aw(4'h9, 32'h0000_5700, 8'd0, 3'd3, 2'b01);
        send_w(8'hff, 1'b0);
        repeat (2) @(posedge aclk);
        if (dut.write_w_queue.size() != 1 ||
            !dut.write_w_queue[0].missing_reported)
          $fatal(1, "W_RECOVERY_RESET_SETUP_FAILED");
        assert_sync_reset(scenario);
        send_aw_w_same_cycle(4'h9, 8'd0, 1'b1);
        send_b(4'h9);
        expect_write_outstanding(scenario, 0, 4'h9, 0, 4'h0, 0);
      end
      "R_RECOVERY_RESET_THEN_CLEAN": begin
        send_ar_id(4'ha, 32'h0000_5800, 8'd0, 3'd3, 2'b01);
        send_r(4'ha, 1'b0);
        repeat (2) @(posedge aclk);
        if (dut.read_ar_queue.size() != 1 ||
            !dut.read_ar_queue[0].missing_reported)
          $fatal(1, "R_RECOVERY_RESET_SETUP_FAILED");
        assert_sync_reset(scenario);
        send_ar_id(4'ha, 32'h0000_5900, 8'd0, 3'd3, 2'b01);
        send_r(4'ha, 1'b1);
        if (dut.read_ar_queue.size() != 0)
          $fatal(1, "R_RECOVERY_RESET_REUSE_FAILED ar=%0d",
                 dut.read_ar_queue.size());
      end
      "ASYNC_RESET_CLEARS_STATE_CLEAN": begin
        prime_violation_then_reset(scenario, PRIME_WLAST_MISSING, 1'b1);
        prime_violation_then_reset(scenario, PRIME_WLAST_EARLY, 1'b1);
        prime_violation_then_reset(scenario, PRIME_RLAST_MISSING, 1'b1);
        prime_violation_then_reset(scenario, PRIME_RLAST_EARLY, 1'b1);
        // Preserve the original pending/credit/episode asynchronous reset.
        prime_pending_then_reset(scenario, 1'b1, 4'hb, 4'hb, 4'hb);
        send_aw_w_same_cycle(4'hb, 8'd0, 1'b1);
        send_b(4'hb);
        send_ar_id(4'hb, 32'h0000_5c00, 8'd0, 3'd3, 2'b01);
        send_r(4'hb, 1'b1);
        expect_write_outstanding(scenario, 0, 4'hb, 0, 4'h0, 0);
        if (dut.read_ar_queue.size() != 0)
          $fatal(1, "ASYNC_RESET_REUSE_FAILED ar=%0d",
                 dut.read_ar_queue.size());
      end
      default: $fatal(1, "unknown scenario %s", scenario);
    endcase

    repeat (3) @(posedge aclk);
    $display("AXI_CHECKER_TEST_COMPLETE");
    $finish;
  end
endmodule
