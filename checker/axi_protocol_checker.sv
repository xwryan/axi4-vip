// checker/axi_protocol_checker.sv
// SVA Protocol Checker for AXI4 -- non-intrusive, attached via bind
`ifndef AXI_PROTOCOL_CHECKER_SV
`define AXI_PROTOCOL_CHECKER_SV

module axi_protocol_checker #(
  parameter int DATA_WIDTH = 64,
  parameter int ADDR_WIDTH = 32,
  parameter int ID_WIDTH   = 4,
  parameter int USER_WIDTH = 0
)(
  input logic                    aclk,
  input logic                    aresetn,

  // Write Address Channel (AW)
  input logic [ID_WIDTH-1:0]     awid,
  input logic [ADDR_WIDTH-1:0]   awaddr,
  input logic [7:0]              awlen,
  input logic [2:0]              awsize,
  input logic [1:0]              awburst,
  input logic                    awlock,
  input logic [3:0]              awcache,
  input logic [2:0]              awprot,
  input logic [3:0]              awqos,
  input logic [3:0]              awregion,
  input logic                    awvalid,
  input logic                    awready,

  // Write Data Channel (W)
  input logic [DATA_WIDTH-1:0]   wdata,
  input logic [DATA_WIDTH/8-1:0] wstrb,
  input logic                    wlast,
  input logic                    wvalid,
  input logic                    wready,

  // Write Response Channel (B)
  input logic [ID_WIDTH-1:0]     bid,
  input logic [1:0]              bresp,
  input logic                    bvalid,
  input logic                    bready,

  // Read Address Channel (AR)
  input logic [ID_WIDTH-1:0]     arid,
  input logic [ADDR_WIDTH-1:0]   araddr,
  input logic [7:0]              arlen,
  input logic [2:0]              arsize,
  input logic [1:0]              arburst,
  input logic                    arlock,
  input logic [3:0]              arcache,
  input logic [2:0]              arprot,
  input logic [3:0]              arqos,
  input logic [3:0]              arregion,
  input logic                    arvalid,
  input logic                    arready,

  // Read Data Channel (R)
  input logic [ID_WIDTH-1:0]     rid,
  input logic [DATA_WIDTH-1:0]   rdata,
  input logic [1:0]              rresp,
  input logic                    rlast,
  input logic                    rvalid,
  input logic                    rready
);

  // =========================================================================
  // Local parameters
  // =========================================================================
  localparam int MAX_BUS_BYTES     = DATA_WIDTH / 8;
  localparam int MAX_SIZE_ENCODING = $clog2(MAX_BUS_BYTES); // e.g. 3 for 64-bit bus

  // WRAP burst legal lengths (awlen = N-1): 2->1, 4->3, 8->7, 16->15
  localparam bit [7:0] WRAP_LEN_2  = 8'd1;
  localparam bit [7:0] WRAP_LEN_4  = 8'd3;
  localparam bit [7:0] WRAP_LEN_8  = 8'd7;
  localparam bit [7:0] WRAP_LEN_16 = 8'd15;

  function automatic longint unsigned transfer_bytes(input logic [2:0] size);
    return 64'd1 << size;
  endfunction

  function automatic bit crosses_4kb(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [7:0] len,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    longint unsigned start_addr;
    longint unsigned aligned_addr;
    longint unsigned beat_bytes;
    longint unsigned span_bytes;
    longint unsigned first_addr;
    longint unsigned last_addr;

    start_addr = $unsigned(addr);
    beat_bytes = transfer_bytes(size);
    aligned_addr = (start_addr / beat_bytes) * beat_bytes;
    case (burst)
      2'b00: begin
        first_addr = aligned_addr;
        span_bytes = beat_bytes;
      end
      2'b01: begin
        first_addr = aligned_addr;
        span_bytes = ($unsigned(len) + 64'd1) * beat_bytes;
      end
      2'b10: begin
        span_bytes = ($unsigned(len) + 64'd1) * beat_bytes;
        first_addr = (start_addr / span_bytes) * span_bytes;
      end
      default: begin
        return 1'b0;
      end
    endcase
    last_addr = first_addr + span_bytes - 1;
    return (first_addr >> 12) != (last_addr >> 12);
  endfunction

  // =========================================================================
  // Ordered write-burst tracker
  //
  // AXI4 permits write data to arrive before its address.  AW records and W
  // bursts are therefore captured independently and paired in arrival order.
  // A W burst is delimited only by an accepted WLAST; after a missing WLAST,
  // later beats remain in the same recovery burst until a real WLAST arrives.
  // =========================================================================
  typedef struct {
    logic [ID_WIDTH-1:0] id;
    logic [7:0]          len;
  } write_aw_record_t;

  typedef struct {
    bit                  bound;
    bit                  completed;
    bit                  missing_reported;
    bit                  started_without_aw;
    logic [ID_WIDTH-1:0] id;
    logic [7:0]          len;
    int unsigned         beat_count;
  } write_w_record_t;

  write_aw_record_t write_aw_queue[$];
  write_w_record_t  write_w_queue[$];

  // Public coverage counters used by the directed checker regression and by
  // later response-channel tracking.  They deliberately count completed
  // pairings rather than assertion attempts.
  longint unsigned write_pair_hit_count;
  longint unsigned write_w_before_aw_bind_hit_count;
  longint unsigned write_active_w_bind_hit_count;
  longint unsigned write_complete_hit_count;
  longint unsigned write_complete_by_id_hit_count
    [logic [ID_WIDTH-1:0]];
  longint unsigned write_outstanding_count;
  longint unsigned write_outstanding_by_id_count
    [logic [ID_WIDTH-1:0]];

  // B is classified when VALID first presents a response, independently of
  // READY.  The episode snapshot prevents a stalled response from reporting
  // the same dependency violation on every cycle.
  bit                  b_episode_active;
  bit                  b_episode_legal;
  logic [ID_WIDTH-1:0] b_episode_id;
  longint unsigned     b_dependency_check_hit_count;

  logic                b_after_aw_w_violation_pulse;
  logic                b_id_outstanding_violation_pulse;
  logic [ID_WIDTH-1:0] b_after_aw_w_observed_id;
  logic [ID_WIDTH-1:0] b_id_outstanding_observed_id;

  logic        wlast_on_last_beat_violation_pulse;
  logic        wlast_not_early_violation_pulse;
  int unsigned wlast_on_last_observed_beat;
  int unsigned wlast_on_last_expected_beat;
  int unsigned wlast_not_early_observed_beat;
  int unsigned wlast_not_early_expected_beat;

  task automatic flag_wlast_missing(
    input int unsigned observed_beat,
    input int unsigned expected_beat
  );
    wlast_on_last_beat_violation_pulse <= 1'b1;
    wlast_on_last_observed_beat <= observed_beat;
    wlast_on_last_expected_beat <= expected_beat;
  endtask

  task automatic flag_wlast_early(
    input int unsigned observed_beat,
    input int unsigned expected_beat
  );
    wlast_not_early_violation_pulse <= 1'b1;
    wlast_not_early_observed_beat <= observed_beat;
    wlast_not_early_expected_beat <= expected_beat;
  endtask

  task automatic retire_completed_write(input int queue_index);
    logic [ID_WIDTH-1:0] completed_id;

    completed_id = write_w_queue[queue_index].id;
    write_complete_hit_count = write_complete_hit_count + 1;
    if (write_complete_by_id_hit_count.exists(completed_id))
      write_complete_by_id_hit_count[completed_id] =
        write_complete_by_id_hit_count[completed_id] + 1;
    else
      write_complete_by_id_hit_count[completed_id] = 1;
    write_outstanding_count = write_outstanding_count + 1;
    if (write_outstanding_by_id_count.exists(completed_id))
      write_outstanding_by_id_count[completed_id] =
        write_outstanding_by_id_count[completed_id] + 1;
    else
      write_outstanding_by_id_count[completed_id] = 1;
    write_w_queue.delete(queue_index);
  endtask

  task automatic pair_oldest_write_records();
    int queue_index;
    int unbound_index;
    int unsigned expected_beats;
    write_aw_record_t aw_record;
    write_w_record_t w_record;

    while (write_aw_queue.size() != 0) begin
      unbound_index = -1;
      for (queue_index = 0;
           queue_index < write_w_queue.size();
           queue_index = queue_index + 1) begin
        if (!write_w_queue[queue_index].bound && unbound_index == -1)
          unbound_index = queue_index;
      end

      if (unbound_index == -1)
        return;

      aw_record = write_aw_queue.pop_front();
      w_record = write_w_queue[unbound_index];
      w_record.bound = 1'b1;
      w_record.id = aw_record.id;
      w_record.len = aw_record.len;
      expected_beats = int'(aw_record.len) + 1;

      write_pair_hit_count = write_pair_hit_count + 1;
      if (w_record.started_without_aw) begin
        write_w_before_aw_bind_hit_count =
          write_w_before_aw_bind_hit_count + 1;
        if (!w_record.completed)
          write_active_w_bind_hit_count =
            write_active_w_bind_hit_count + 1;
      end

      if (w_record.completed) begin
        if (w_record.beat_count < expected_beats)
          flag_wlast_early(w_record.beat_count, expected_beats);
        else if (w_record.beat_count > expected_beats)
          flag_wlast_missing(w_record.beat_count, expected_beats);

        write_w_queue[unbound_index] = w_record;
        retire_completed_write(unbound_index);
      end else begin
        if (w_record.beat_count >= expected_beats &&
            !w_record.missing_reported) begin
          flag_wlast_missing(w_record.beat_count, expected_beats);
          w_record.missing_reported = 1'b1;
        end
        write_w_queue[unbound_index] = w_record;
      end
    end
  endtask

  function automatic bit has_incomplete_write_for_id(
    input logic [ID_WIDTH-1:0] response_id
  );
    int queue_index;

    for (queue_index = 0;
         queue_index < write_aw_queue.size();
         queue_index = queue_index + 1) begin
      if (write_aw_queue[queue_index].id == response_id)
        return 1'b1;
    end

    for (queue_index = 0;
         queue_index < write_w_queue.size();
         queue_index = queue_index + 1) begin
      if (write_w_queue[queue_index].bound &&
          !write_w_queue[queue_index].completed &&
          write_w_queue[queue_index].id == response_id)
        return 1'b1;
    end

    return 1'b0;
  endfunction

  // One process owns all B/AW/W state.  It classifies and consumes the pre-edge
  // B episode first, then accepts AW and W, so a same-edge completion cannot
  // retroactively legalize the response.  AW still precedes W internally so
  // an AW and first/last W beat on one edge can be paired immediately.
  always @(posedge aclk or negedge aresetn) begin : write_burst_tracker
    int queue_index;
    int active_index;
    int unsigned expected_beats;
    bit b_was_active;
    bit b_new_episode;
    bit b_has_credit;
    bit b_has_incomplete;
    logic [ID_WIDTH-1:0] response_id;
    write_aw_record_t new_aw_record;
    write_w_record_t active_record;

    if (!aresetn) begin
      write_aw_queue.delete();
      write_w_queue.delete();
      write_complete_by_id_hit_count.delete();
      write_outstanding_by_id_count.delete();
      write_pair_hit_count = 0;
      write_w_before_aw_bind_hit_count = 0;
      write_active_w_bind_hit_count = 0;
      write_complete_hit_count = 0;
      write_outstanding_count = 0;
      b_episode_active = 1'b0;
      b_episode_legal = 1'b0;
      b_episode_id = '0;
      b_dependency_check_hit_count = 0;
      b_after_aw_w_violation_pulse <= 1'b0;
      b_id_outstanding_violation_pulse <= 1'b0;
      b_after_aw_w_observed_id <= '0;
      b_id_outstanding_observed_id <= '0;
      wlast_on_last_beat_violation_pulse <= 1'b0;
      wlast_not_early_violation_pulse <= 1'b0;
      wlast_on_last_observed_beat <= 0;
      wlast_on_last_expected_beat <= 0;
      wlast_not_early_observed_beat <= 0;
      wlast_not_early_expected_beat <= 0;
    end else begin
      // Pulses and their diagnostics form a one-cycle pipeline into the SVA
      // below.  Nonblocking updates preserve the previous diagnostic when an
      // adjacent-cycle violation is being reported.
      wlast_on_last_beat_violation_pulse <= 1'b0;
      wlast_not_early_violation_pulse <= 1'b0;
      b_after_aw_w_violation_pulse <= 1'b0;
      b_id_outstanding_violation_pulse <= 1'b0;

      // Snapshot a newly presented response before any state on this edge is
      // advanced.  A current matching AW affects only the diagnostic label;
      // it cannot make the response legal.
      b_was_active = b_episode_active;
      b_new_episode = !b_was_active && bvalid;
      if (b_new_episode) begin
        b_dependency_check_hit_count = b_dependency_check_hit_count + 1;
        b_has_credit =
          write_outstanding_by_id_count.exists(bid) &&
          write_outstanding_by_id_count[bid] != 0;
        b_has_incomplete = has_incomplete_write_for_id(bid);

        b_episode_id = bid;
        b_episode_legal = b_has_credit;
        if (!b_has_credit) begin
          if (b_has_incomplete ||
              (awvalid && awready && awid == bid)) begin
            b_after_aw_w_violation_pulse <= 1'b1;
            b_after_aw_w_observed_id <= bid;
          end else begin
            b_id_outstanding_violation_pulse <= 1'b1;
            b_id_outstanding_observed_id <= bid;
          end
        end

        b_episode_active = !bready;
      end else if (b_was_active) begin
        if (!bvalid || bready)
          b_episode_active = 1'b0;
      end

      // Only a handshake consumes a response credit.  An episode that was
      // illegal when first presented may use a matching credit that completed
      // while it was stalled, allowing deterministic recovery without erasing
      // the already reported violation.
      if (bvalid && bready) begin
        response_id = b_new_episode ? bid : b_episode_id;
        if (write_outstanding_by_id_count.exists(response_id) &&
            write_outstanding_by_id_count[response_id] != 0) begin
          write_outstanding_count = write_outstanding_count - 1;
          if (write_outstanding_by_id_count[response_id] == 1)
            write_outstanding_by_id_count.delete(response_id);
          else
            write_outstanding_by_id_count[response_id] =
              write_outstanding_by_id_count[response_id] - 1;
        end
      end

      if (awvalid && awready) begin
        new_aw_record.id = awid;
        new_aw_record.len = awlen;
        write_aw_queue.push_back(new_aw_record);
      end

      pair_oldest_write_records();

      if (wvalid && wready) begin
        active_index = -1;
        for (queue_index = 0;
             queue_index < write_w_queue.size();
             queue_index = queue_index + 1) begin
          if (!write_w_queue[queue_index].completed && active_index == -1)
            active_index = queue_index;
        end

        if (active_index == -1) begin
          active_record.bound = 1'b0;
          active_record.completed = 1'b0;
          active_record.missing_reported = 1'b0;
          active_record.started_without_aw =
            (write_aw_queue.size() == 0);
          active_record.id = '0;
          active_record.len = '0;
          active_record.beat_count = 0;
          write_w_queue.push_back(active_record);
          active_index = write_w_queue.size() - 1;
          pair_oldest_write_records();

          // Pairing can retire a completed pre-AW record, but the newly
          // created active record remains and may have shifted in the queue.
          active_index = -1;
          for (queue_index = 0;
               queue_index < write_w_queue.size();
               queue_index = queue_index + 1) begin
            if (!write_w_queue[queue_index].completed && active_index == -1)
              active_index = queue_index;
          end
        end

        active_record = write_w_queue[active_index];
        if (active_record.beat_count != 32'hffff_ffff)
          active_record.beat_count = active_record.beat_count + 1;

        if (active_record.bound) begin
          expected_beats = int'(active_record.len) + 1;
          if (wlast && active_record.beat_count < expected_beats)
            flag_wlast_early(active_record.beat_count, expected_beats);
          else if (!wlast &&
                   active_record.beat_count >= expected_beats &&
                   !active_record.missing_reported) begin
            flag_wlast_missing(active_record.beat_count, expected_beats);
            active_record.missing_reported = 1'b1;
          end
        end

        if (wlast)
          active_record.completed = 1'b1;
        write_w_queue[active_index] = active_record;

        if (active_record.bound && active_record.completed)
          retire_completed_write(active_index);
      end
    end
  end

  // =========================================================================
  // Ordered read-burst and R presentation tracker
  //
  // The queue preserves global AR acceptance order.  R selects the first
  // matching RID, which permits different-ID interleave while keeping same-ID
  // bursts strictly ordered.  A missing expected RLAST enters drain on the
  // matched record until a real accepted RLAST retires that record.
  // =========================================================================
  typedef struct {
    logic [ID_WIDTH-1:0] id;
    logic [7:0]          len;
    int unsigned         accepted_beat_count;
    longint unsigned     sequence_number;
    bit                  missing_reported;
  } read_ar_record_t;

  read_ar_record_t read_ar_queue[$];
  longint unsigned read_next_sequence;

  bit                  r_episode_active;
  bit                  r_episode_had_match;
  logic [ID_WIDTH-1:0] r_episode_id;
  logic                r_episode_last;
  longint unsigned     r_episode_sequence;

  longint unsigned read_rid_selection_hit_count;
  longint unsigned read_same_id_selection_hit_count;
  longint unsigned read_different_id_interleave_hit_count;

  logic                r_after_ar_violation_pulse;
  logic                r_id_outstanding_violation_pulse;
  logic                rlast_on_last_beat_violation_pulse;
  logic                rlast_not_early_violation_pulse;
  logic [ID_WIDTH-1:0] r_after_ar_observed_id;
  logic [ID_WIDTH-1:0] r_id_outstanding_observed_id;
  logic [ID_WIDTH-1:0] rlast_on_last_observed_id;
  logic [ID_WIDTH-1:0] rlast_not_early_observed_id;
  int unsigned         rlast_on_last_observed_beat;
  int unsigned         rlast_on_last_expected_beat;
  int unsigned         rlast_not_early_observed_beat;
  int unsigned         rlast_not_early_expected_beat;

  task automatic classify_read_last(
    input bit                  missing_reported,
    input int unsigned         accepted_beat_count,
    input logic [7:0]          burst_len,
    input logic [ID_WIDTH-1:0] response_id,
    input logic                actual_last
  );
    int unsigned observed_beat;
    int unsigned expected_beats;

    if (missing_reported)
      return;

    observed_beat = accepted_beat_count + 1;
    expected_beats = int'(burst_len) + 1;
    if (actual_last && observed_beat < expected_beats) begin
      rlast_not_early_violation_pulse <= 1'b1;
      rlast_not_early_observed_id <= response_id;
      rlast_not_early_observed_beat <= observed_beat;
      rlast_not_early_expected_beat <= expected_beats;
    end else if (!actual_last && observed_beat == expected_beats) begin
      rlast_on_last_beat_violation_pulse <= 1'b1;
      rlast_on_last_observed_id <= response_id;
      rlast_on_last_observed_beat <= observed_beat;
      rlast_on_last_expected_beat <= expected_beats;
    end
  endtask

  always @(posedge aclk or negedge aresetn) begin : read_burst_tracker
    int queue_index;
    int match_index;
    int matching_count;
    int consume_index;
    int unsigned expected_beats;
    bit r_was_active;
    bit r_new_episode;
    bit consume_had_match;
    logic [ID_WIDTH-1:0] consume_id;
    logic consume_last;
    longint unsigned consume_sequence;
    read_ar_record_t selected_record;
    read_ar_record_t new_ar_record;

    if (!aresetn) begin
      read_ar_queue.delete();
      read_next_sequence = 0;
      r_episode_active = 1'b0;
      r_episode_had_match = 1'b0;
      r_episode_id = '0;
      r_episode_last = 1'b0;
      r_episode_sequence = 0;
      read_rid_selection_hit_count = 0;
      read_same_id_selection_hit_count = 0;
      read_different_id_interleave_hit_count = 0;
      r_after_ar_violation_pulse <= 1'b0;
      r_id_outstanding_violation_pulse <= 1'b0;
      rlast_on_last_beat_violation_pulse <= 1'b0;
      rlast_not_early_violation_pulse <= 1'b0;
      r_after_ar_observed_id <= '0;
      r_id_outstanding_observed_id <= '0;
      rlast_on_last_observed_id <= '0;
      rlast_not_early_observed_id <= '0;
      rlast_on_last_observed_beat <= 0;
      rlast_on_last_expected_beat <= 0;
      rlast_not_early_observed_beat <= 0;
      rlast_not_early_expected_beat <= 0;
    end else begin
      r_after_ar_violation_pulse <= 1'b0;
      r_id_outstanding_violation_pulse <= 1'b0;
      rlast_on_last_beat_violation_pulse <= 1'b0;
      rlast_not_early_violation_pulse <= 1'b0;

      r_was_active = r_episode_active;
      r_new_episode = !r_was_active && rvalid;
      match_index = -1;
      matching_count = 0;

      if (r_new_episode) begin
        // Find the oldest pre-edge AR with matching RID.  AR accepted on this
        // edge is considered only for choosing the dependency diagnostic.
        for (queue_index = 0;
             queue_index < read_ar_queue.size();
             queue_index = queue_index + 1) begin
          if (read_ar_queue[queue_index].id == rid) begin
            matching_count = matching_count + 1;
            if (match_index == -1)
              match_index = queue_index;
          end
        end

        r_episode_id = rid;
        r_episode_last = rlast;
        r_episode_had_match = (match_index != -1);

        if (match_index != -1) begin
          selected_record = read_ar_queue[match_index];
          r_episode_sequence = selected_record.sequence_number;
          read_rid_selection_hit_count =
            read_rid_selection_hit_count + 1;
          if (matching_count > 1)
            read_same_id_selection_hit_count =
              read_same_id_selection_hit_count + 1;
          if (match_index > 0)
            read_different_id_interleave_hit_count =
              read_different_id_interleave_hit_count + 1;

          classify_read_last(
            selected_record.missing_reported,
            selected_record.accepted_beat_count,
            selected_record.len,
            rid,
            rlast);
        end else begin
          r_episode_sequence = 0;
          if (read_ar_queue.size() == 0 ||
              (arvalid && arready && arid == rid)) begin
            r_after_ar_violation_pulse <= 1'b1;
            r_after_ar_observed_id <= rid;
          end else begin
            r_id_outstanding_violation_pulse <= 1'b1;
            r_id_outstanding_observed_id <= rid;
          end
        end

        r_episode_active = !rready;
      end else if (r_was_active) begin
        if (!rvalid || rready)
          r_episode_active = 1'b0;
      end

      // Resolve the episode identity before mutating the queue.  A legal
      // stalled episode follows its original sequence.  An initially invalid
      // episode may recover using an AR that arrived during the stall.
      if (rvalid && rready) begin
        consume_had_match = r_new_episode ?
          (match_index != -1) : r_episode_had_match;
        consume_id = r_new_episode ? rid : r_episode_id;
        consume_last = r_new_episode ? rlast : r_episode_last;
        consume_sequence = r_new_episode ?
          ((match_index != -1) ?
           read_ar_queue[match_index].sequence_number : 0) :
          r_episode_sequence;
        consume_index = -1;

        if (consume_had_match) begin
          for (queue_index = 0;
               queue_index < read_ar_queue.size();
               queue_index = queue_index + 1) begin
            if (read_ar_queue[queue_index].sequence_number ==
                  consume_sequence &&
                consume_index == -1)
              consume_index = queue_index;
          end
        end else begin
          for (queue_index = 0;
               queue_index < read_ar_queue.size();
               queue_index = queue_index + 1) begin
            if (read_ar_queue[queue_index].id == consume_id &&
                consume_index == -1)
              consume_index = queue_index;
          end
        end

        if (consume_index != -1) begin
          selected_record = read_ar_queue[consume_index];
          // An episode that had no AR at presentation retains its dependency
          // violation, but a late AR found for recovery supplies the LEN and
          // beat state needed to classify the snapshotted RLAST before any
          // record update or deletion.
          if (!consume_had_match)
            classify_read_last(
              selected_record.missing_reported,
              selected_record.accepted_beat_count,
              selected_record.len,
              consume_id,
              consume_last);

          if (selected_record.accepted_beat_count != 32'hffff_ffff)
            selected_record.accepted_beat_count =
              selected_record.accepted_beat_count + 1;

          expected_beats = int'(selected_record.len) + 1;
          if (consume_last) begin
            read_ar_queue.delete(consume_index);
          end else begin
            if (selected_record.accepted_beat_count >= expected_beats)
              selected_record.missing_reported = 1'b1;
            read_ar_queue[consume_index] = selected_record;
          end
        end
      end

      // Accept AR only after the pre-edge R classification/consumption.
      if (arvalid && arready) begin
        new_ar_record.id = arid;
        new_ar_record.len = arlen;
        new_ar_record.accepted_beat_count = 0;
        new_ar_record.sequence_number = read_next_sequence;
        new_ar_record.missing_reported = 1'b0;
        read_next_sequence = read_next_sequence + 1;
        read_ar_queue.push_back(new_ar_record);
      end
    end
  end

  // =========================================================================
  // Assertions -- clocked on posedge aclk, disabled during reset
  // =========================================================================

  // -------------------------------------------------------------------------
  // 1. VALID stability: once asserted, VALID must not deassert before READY
  // -------------------------------------------------------------------------

  // AW channel VALID stability
  property p_awvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> awvalid;
  endproperty
  AST_AWVALID_STABLE: assert property (p_awvalid_stable)
    else $error("[AXI CHK] AWVALID deasserted before AWREADY");

  // W channel VALID stability
  property p_wvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> wvalid;
  endproperty
  AST_WVALID_STABLE: assert property (p_wvalid_stable)
    else $error("[AXI CHK] WVALID deasserted before WREADY");

  // B channel VALID stability
  property p_bvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) |=> bvalid;
  endproperty
  AST_BVALID_STABLE: assert property (p_bvalid_stable)
    else $error("[AXI CHK] BVALID deasserted before BREADY");

  // AR channel VALID stability
  property p_arvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> arvalid;
  endproperty
  AST_ARVALID_STABLE: assert property (p_arvalid_stable)
    else $error("[AXI CHK] ARVALID deasserted before ARREADY");

  // R channel VALID stability
  property p_rvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> rvalid;
  endproperty
  AST_RVALID_STABLE: assert property (p_rvalid_stable)
    else $error("[AXI CHK] RVALID deasserted before RREADY");

  // -------------------------------------------------------------------------
  // 2. Payload stability: payload must not change while VALID is high and
  //    READY is low (AW, W, B, AR, R channels)
  // -------------------------------------------------------------------------

  // AW payload stability
  property p_awpayload_stable;
    @(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=>
      ($stable(awid)     && $stable(awaddr)   && $stable(awlen)  &&
       $stable(awsize)   && $stable(awburst)  && $stable(awlock) &&
       $stable(awcache)  && $stable(awprot)   && $stable(awqos)  &&
       $stable(awregion));
  endproperty
  AST_AWPAYLOAD_STABLE: assert property (p_awpayload_stable)
    else $error("[AXI CHK] AW payload changed while AWVALID high and AWREADY low");

  // W payload stability
  property p_wpayload_stable;
    @(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=>
      ($stable(wdata) && $stable(wstrb) && $stable(wlast));
  endproperty
  AST_WPAYLOAD_STABLE: assert property (p_wpayload_stable)
    else $error("[AXI CHK] W payload changed while WVALID high and WREADY low");

  // B payload stability
  property p_bpayload_stable;
    @(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) |=>
      ($stable(bid) && $stable(bresp));
  endproperty
  AST_BPAYLOAD_STABLE: assert property (p_bpayload_stable)
    else $error("[AXI CHK] B payload changed while BVALID high and BREADY low");

  // AR payload stability
  property p_arpayload_stable;
    @(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=>
      ($stable(arid)     && $stable(araddr)   && $stable(arlen)  &&
       $stable(arsize)   && $stable(arburst)  && $stable(arlock) &&
       $stable(arcache)  && $stable(arprot)   && $stable(arqos)  &&
       $stable(arregion));
  endproperty
  AST_ARPAYLOAD_STABLE: assert property (p_arpayload_stable)
    else $error("[AXI CHK] AR payload changed while ARVALID high and ARREADY low");

  // R payload stability
  property p_rpayload_stable;
    @(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=>
      ($stable(rid) && $stable(rdata) && $stable(rresp) && $stable(rlast));
  endproperty
  AST_RPAYLOAD_STABLE: assert property (p_rpayload_stable)
    else $error("[AXI CHK] R payload changed while RVALID high and RREADY low");

  // -------------------------------------------------------------------------
  // 3. Burst size must not exceed bus data width
  // -------------------------------------------------------------------------
  property p_aw_burst_size;
    @(posedge aclk) disable iff (!aresetn)
    awvalid |-> (awsize <= MAX_SIZE_ENCODING[2:0]);
  endproperty
  AST_AW_BURST_SIZE: assert property (p_aw_burst_size)
    else $error("[AXI CHK] AWSIZE %0d exceeds max bus size encoding %0d",
                awsize, MAX_SIZE_ENCODING);

  property p_ar_burst_size;
    @(posedge aclk) disable iff (!aresetn)
    arvalid |-> (arsize <= MAX_SIZE_ENCODING[2:0]);
  endproperty
  AST_AR_BURST_SIZE: assert property (p_ar_burst_size)
    else $error("[AXI CHK] ARSIZE %0d exceeds max bus size encoding %0d",
                arsize, MAX_SIZE_ENCODING);

  // -------------------------------------------------------------------------
  // 4. Burst encodings and FIXED burst length
  // -------------------------------------------------------------------------
  property p_aw_burst_encoding;
    @(posedge aclk) disable iff (!aresetn)
    awvalid |-> (awburst != 2'b11);
  endproperty
  AST_AW_BURST_ENCODING: assert property (p_aw_burst_encoding)
    else $error("[AXI CHK] AWBURST uses reserved encoding");

  property p_ar_burst_encoding;
    @(posedge aclk) disable iff (!aresetn)
    arvalid |-> (arburst != 2'b11);
  endproperty
  AST_AR_BURST_ENCODING: assert property (p_ar_burst_encoding)
    else $error("[AXI CHK] ARBURST uses reserved encoding");

  property p_aw_fixed_len;
    @(posedge aclk) disable iff (!aresetn)
    (awvalid && awburst == 2'b00) |-> (awlen <= 8'd15);
  endproperty
  AST_AW_FIXED_LEN: assert property (p_aw_fixed_len)
    else $error("[AXI CHK] FIXED write burst exceeds 16 transfers");

  property p_ar_fixed_len;
    @(posedge aclk) disable iff (!aresetn)
    (arvalid && arburst == 2'b00) |-> (arlen <= 8'd15);
  endproperty
  AST_AR_FIXED_LEN: assert property (p_ar_fixed_len)
    else $error("[AXI CHK] FIXED read burst exceeds 16 transfers");

  // -------------------------------------------------------------------------
  // 5. Bursts must not cross a 4KB boundary
  // -------------------------------------------------------------------------
  property p_aw_4kb_boundary;
    @(posedge aclk) disable iff (!aresetn)
    awvalid |-> !crosses_4kb(awaddr, awlen, awsize, awburst);
  endproperty
  AST_AW_4KB_BOUNDARY: assert property (p_aw_4kb_boundary)
    else $error("[AXI CHK] INCR write burst crosses 4KB boundary: addr=0x%0x len=%0d size=%0d",
                awaddr, awlen, awsize);

  property p_ar_4kb_boundary;
    @(posedge aclk) disable iff (!aresetn)
    arvalid |-> !crosses_4kb(araddr, arlen, arsize, arburst);
  endproperty
  AST_AR_4KB_BOUNDARY: assert property (p_ar_4kb_boundary)
    else $error("[AXI CHK] INCR read burst crosses 4KB boundary: addr=0x%0x len=%0d size=%0d",
                araddr, arlen, arsize);

  // -------------------------------------------------------------------------
  // 6. WRAP burst: length must be 2, 4, 8, or 16 (awlen = 1, 3, 7, 15)
  // -------------------------------------------------------------------------
  property p_aw_wrap_len;
    @(posedge aclk) disable iff (!aresetn)
    (awvalid && (awburst == 2'b10)) |->
      (awlen == WRAP_LEN_2 || awlen == WRAP_LEN_4 ||
       awlen == WRAP_LEN_8 || awlen == WRAP_LEN_16);
  endproperty
  AST_AW_WRAP_LEN: assert property (p_aw_wrap_len)
    else $error("[AXI CHK] WRAP write burst has illegal length awlen=%0d (must be 1/3/7/15)",
                awlen);

  property p_ar_wrap_len;
    @(posedge aclk) disable iff (!aresetn)
    (arvalid && (arburst == 2'b10)) |->
      (arlen == WRAP_LEN_2 || arlen == WRAP_LEN_4 ||
       arlen == WRAP_LEN_8 || arlen == WRAP_LEN_16);
  endproperty
  AST_AR_WRAP_LEN: assert property (p_ar_wrap_len)
    else $error("[AXI CHK] WRAP read burst has illegal length arlen=%0d (must be 1/3/7/15)",
                arlen);

  // -------------------------------------------------------------------------
  // 7. WRAP burst: start address must be aligned to one transfer
  // -------------------------------------------------------------------------

  // Write WRAP alignment
  property p_aw_wrap_align;
    longint unsigned beat_bytes;
    @(posedge aclk) disable iff (!aresetn)
    (awvalid && awburst == 2'b10,
     beat_bytes = transfer_bytes(awsize)) |->
      (($unsigned(awaddr) & (beat_bytes - 1)) == 0);
  endproperty
  AST_AW_WRAP_ALIGN: assert property (p_aw_wrap_align)
    else $error("[AXI CHK] WRAP write burst start address 0x%0x not aligned to wrap size",
                awaddr);

  // Read WRAP alignment
  property p_ar_wrap_align;
    longint unsigned beat_bytes;
    @(posedge aclk) disable iff (!aresetn)
    (arvalid && arburst == 2'b10,
     beat_bytes = transfer_bytes(arsize)) |->
      (($unsigned(araddr) & (beat_bytes - 1)) == 0);
  endproperty
  AST_AR_WRAP_ALIGN: assert property (p_ar_wrap_align)
    else $error("[AXI CHK] WRAP read burst start address 0x%0x not aligned to wrap size",
                araddr);

  // -------------------------------------------------------------------------
  // 8. WLAST tracking: assertion shells consume independent tracker pulses.
  // -------------------------------------------------------------------------

  property p_wlast_on_last_beat;
    @(posedge aclk) disable iff (!aresetn)
    !wlast_on_last_beat_violation_pulse;
  endproperty
  AST_WLAST_ON_LAST_BEAT: assert property (p_wlast_on_last_beat)
    else $error("[AXI CHK] WLAST missing: observed beat %0d, expected beat %0d",
                wlast_on_last_observed_beat,
                wlast_on_last_expected_beat);

  property p_wlast_not_early;
    @(posedge aclk) disable iff (!aresetn)
    !wlast_not_early_violation_pulse;
  endproperty
  AST_WLAST_NOT_EARLY: assert property (p_wlast_not_early)
    else $error("[AXI CHK] WLAST early: observed beat %0d, expected beat %0d",
                wlast_not_early_observed_beat,
                wlast_not_early_expected_beat);

  // -------------------------------------------------------------------------
  // 9. B/R dependency, response ID, and RLAST tracker shells
  // -------------------------------------------------------------------------

  property p_b_after_aw_w;
    @(posedge aclk) disable iff (!aresetn)
    !b_after_aw_w_violation_pulse;
  endproperty
  AST_B_AFTER_AW_W: assert property (p_b_after_aw_w)
    else $error("[AXI CHK] B response for BID 0x%0x preceded write completion",
                b_after_aw_w_observed_id);

  property p_bid_outstanding;
    @(posedge aclk) disable iff (!aresetn)
    !b_id_outstanding_violation_pulse;
  endproperty
  AST_BID_OUTSTANDING: assert property (p_bid_outstanding)
    else $error("[AXI CHK] BID 0x%0x has no outstanding write",
                b_id_outstanding_observed_id);

  property p_r_after_ar;
    @(posedge aclk) disable iff (!aresetn)
    !r_after_ar_violation_pulse;
  endproperty
  AST_R_AFTER_AR: assert property (p_r_after_ar)
    else $error("[AXI CHK] R response for RID 0x%0x preceded AR acceptance",
                r_after_ar_observed_id);

  property p_rid_outstanding;
    @(posedge aclk) disable iff (!aresetn)
    !r_id_outstanding_violation_pulse;
  endproperty
  AST_RID_OUTSTANDING: assert property (p_rid_outstanding)
    else $error("[AXI CHK] RID 0x%0x has no outstanding read",
                r_id_outstanding_observed_id);

  property p_rlast_on_last_beat;
    @(posedge aclk) disable iff (!aresetn)
    !rlast_on_last_beat_violation_pulse;
  endproperty
  AST_RLAST_ON_LAST_BEAT: assert property (p_rlast_on_last_beat)
    else $error("[AXI CHK] RLAST missing for RID 0x%0x: observed beat %0d, expected beat %0d",
                rlast_on_last_observed_id,
                rlast_on_last_observed_beat,
                rlast_on_last_expected_beat);

  property p_rlast_not_early;
    @(posedge aclk) disable iff (!aresetn)
    !rlast_not_early_violation_pulse;
  endproperty
  AST_RLAST_NOT_EARLY: assert property (p_rlast_not_early)
    else $error("[AXI CHK] RLAST early for RID 0x%0x: observed beat %0d, expected beat %0d",
                rlast_not_early_observed_id,
                rlast_not_early_observed_beat,
                rlast_not_early_expected_beat);

  // -------------------------------------------------------------------------
  // 10. Exclusive access: size and length constraints
  //    - Total transfer size <= 128 bytes: (len+1) * (1<<size) <= 128
  //    - Address aligned to total transfer size
  //    - Burst length must be power-of-2: 1, 2, 4, 8, 16
  // -------------------------------------------------------------------------

  // Write exclusive -- total size
  property p_aw_excl_total_size;
    @(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |->
      ((({1'b0, awlen} + 1) << awsize) <= 9'd128);
  endproperty
  AST_AW_EXCL_TOTAL_SIZE: assert property (p_aw_excl_total_size)
    else $error("[AXI CHK] Exclusive write total transfer size > 128 bytes");

  // Write exclusive -- length power-of-2
  property p_aw_excl_len;
    @(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |->
      (awlen == 8'd0  || awlen == 8'd1  || awlen == 8'd3 ||
       awlen == 8'd7  || awlen == 8'd15);
  endproperty
  AST_AW_EXCL_LEN: assert property (p_aw_excl_len)
    else $error("[AXI CHK] Exclusive write burst length %0d not in set 1/2/4/8/16", awlen+1);

  // Write exclusive -- address alignment
  property p_aw_excl_align;
    logic [ADDR_WIDTH-1:0] excl_size;
    @(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock,
     excl_size = ({1'b0, awlen} + 1) << awsize) |->
      ((awaddr & (excl_size - 1)) == '0);
  endproperty
  AST_AW_EXCL_ALIGN: assert property (p_aw_excl_align)
    else $error("[AXI CHK] Exclusive write address 0x%0x not aligned to total transfer size",
                awaddr);

  // Read exclusive -- total size
  property p_ar_excl_total_size;
    @(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |->
      ((({1'b0, arlen} + 1) << arsize) <= 9'd128);
  endproperty
  AST_AR_EXCL_TOTAL_SIZE: assert property (p_ar_excl_total_size)
    else $error("[AXI CHK] Exclusive read total transfer size > 128 bytes");

  // Read exclusive -- length power-of-2
  property p_ar_excl_len;
    @(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |->
      (arlen == 8'd0  || arlen == 8'd1  || arlen == 8'd3 ||
       arlen == 8'd7  || arlen == 8'd15);
  endproperty
  AST_AR_EXCL_LEN: assert property (p_ar_excl_len)
    else $error("[AXI CHK] Exclusive read burst length %0d not in set 1/2/4/8/16", arlen+1);

  // Read exclusive -- address alignment
  property p_ar_excl_align;
    logic [ADDR_WIDTH-1:0] excl_size;
    @(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock,
     excl_size = ({1'b0, arlen} + 1) << arsize) |->
      ((araddr & (excl_size - 1)) == '0);
  endproperty
  AST_AR_EXCL_ALIGN: assert property (p_ar_excl_align)
    else $error("[AXI CHK] Exclusive read address 0x%0x not aligned to total transfer size",
                araddr);

  // -------------------------------------------------------------------------
  // 11. Reset rules: all VALID signals must be low during reset (aresetn==0)
  // -------------------------------------------------------------------------
  property p_reset_awvalid;
    @(posedge aclk)
    !aresetn |-> !awvalid;
  endproperty
  AST_RESET_AWVALID: assert property (p_reset_awvalid)
    else $error("[AXI CHK] AWVALID high during reset");

  property p_reset_wvalid;
    @(posedge aclk)
    !aresetn |-> !wvalid;
  endproperty
  AST_RESET_WVALID: assert property (p_reset_wvalid)
    else $error("[AXI CHK] WVALID high during reset");

  property p_reset_bvalid;
    @(posedge aclk)
    !aresetn |-> !bvalid;
  endproperty
  AST_RESET_BVALID: assert property (p_reset_bvalid)
    else $error("[AXI CHK] BVALID high during reset");

  property p_reset_arvalid;
    @(posedge aclk)
    !aresetn |-> !arvalid;
  endproperty
  AST_RESET_ARVALID: assert property (p_reset_arvalid)
    else $error("[AXI CHK] ARVALID high during reset");

  property p_reset_rvalid;
    @(posedge aclk)
    !aresetn |-> !rvalid;
  endproperty
  AST_RESET_RVALID: assert property (p_reset_rvalid)
    else $error("[AXI CHK] RVALID high during reset");

endmodule

`endif // AXI_PROTOCOL_CHECKER_SV
