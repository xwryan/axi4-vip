`ifndef AXI_CHANNEL_RECORDS_SV
`define AXI_CHANNEL_RECORDS_SV

class axi_w_burst_record;
  bit [511:0] data_q[$];
  bit [63:0]  strb_q[$];
  time start_time;
  time end_time;

  function void push(bit [511:0] data, bit [63:0] strb,
                     time sample_time);
    if (data_q.size() == 0)
      start_time = sample_time;
    data_q.push_back(data);
    strb_q.push_back(strb);
    end_time = sample_time;
  endfunction

  function int unsigned size();
    return data_q.size();
  endfunction
endclass

`endif // AXI_CHANNEL_RECORDS_SV
