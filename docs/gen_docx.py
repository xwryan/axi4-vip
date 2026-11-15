#!/usr/bin/env python3
# Minimal .docx writer (no python-docx / pandoc / libreoffice needed).
# Builds AXI VIP architecture and usage document.

import argparse
import os
import stat
import zipfile
from xml.sax.saxutils import escape as xml_escape

DEFAULT_OUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "AXI_VIP_Architecture_and_Usage.docx")

parser = argparse.ArgumentParser(description="Generate the AXI VIP usage DOCX")
parser.add_argument("--output", default=DEFAULT_OUT_PATH,
                    help="output DOCX path (default: docs/AXI_VIP_Architecture_and_Usage.docx)")
OUT_PATH = os.path.abspath(parser.parse_args().output)

# ---------------------------------------------------------------------------
# Fixed package files
# ---------------------------------------------------------------------------
CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>
"""

RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"""

DOC_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
"""

STYLES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Calibri" w:eastAsia="SimSun" w:hAnsi="Calibri" w:cs="Calibri"/>
        <w:sz w:val="22"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:after="120"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:jc w:val="center"/><w:spacing w:before="240" w:after="240"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="48"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:before="360" w:after="120"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="1F4E79"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:before="240" w:after="100"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="2E74B5"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:before="180" w:after="80"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="22"/><w:color w:val="2E74B5"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Code">
    <w:name w:val="Code"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:after="0"/>
      <w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>
      <w:ind w:left="240"/>
    </w:pPr>
    <w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/><w:sz w:val="18"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Bullet">
    <w:name w:val="Bullet"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:ind w:left="360"/></w:pPr>
  </w:style>
</w:styles>
"""


# ---------------------------------------------------------------------------
# Body builders
# ---------------------------------------------------------------------------

def run(text, bold=False):
    rpr = "<w:rPr><w:b/></w:rPr>" if bold else ""
    return f'<w:r>{rpr}<w:t xml:space="preserve">{xml_escape(text)}</w:t></w:r>'


def para(text, style="Normal", bold=False):
    return f'<w:p><w:pPr><w:pStyle w:val="{style}"/></w:pPr>{run(text, bold=bold)}</w:p>'


def title(text): return para(text, style="Title", bold=True)
def h1(text):    return para(text, style="Heading1")
def h2(text):    return para(text, style="Heading2")
def h3(text):    return para(text, style="Heading3")


def bullet(text):
    return (
        '<w:p><w:pPr><w:pStyle w:val="Bullet"/>'
        '</w:pPr>'
        + run("• " + text) +
        '</w:p>'
    )


def code_block(text):
    out = []
    for ln in text.split("\n"):
        out.append(
            '<w:p><w:pPr><w:pStyle w:val="Code"/></w:pPr>'
            '<w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>'
            '<w:sz w:val="18"/></w:rPr>'
            f'<w:t xml:space="preserve">{xml_escape(ln)}</w:t></w:r></w:p>'
        )
    return "".join(out)


def table(rows, col_widths=None):
    if col_widths is None:
        col_widths = [3000] * len(rows[0])
    parts = ['<w:tbl>']
    parts.append(
        '<w:tblPr>'
        '<w:tblW w:w="9000" w:type="dxa"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="808080"/>'
        '<w:left w:val="single" w:sz="4" w:color="808080"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="808080"/>'
        '<w:right w:val="single" w:sz="4" w:color="808080"/>'
        '<w:insideH w:val="single" w:sz="4" w:color="808080"/>'
        '<w:insideV w:val="single" w:sz="4" w:color="808080"/>'
        '</w:tblBorders>'
        '</w:tblPr>'
    )
    parts.append('<w:tblGrid>')
    for w in col_widths:
        parts.append(f'<w:gridCol w:w="{w}"/>')
    parts.append('</w:tblGrid>')

    for ri, row in enumerate(rows):
        parts.append('<w:tr>')
        for ci, cell in enumerate(row):
            shade = '<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>' if ri == 0 else ''
            parts.append(
                f'<w:tc><w:tcPr><w:tcW w:w="{col_widths[ci]}" w:type="dxa"/>{shade}</w:tcPr>'
                f'<w:p>{run(cell, bold=(ri == 0))}</w:p></w:tc>'
            )
        parts.append('</w:tr>')
    parts.append('</w:tbl><w:p/>')
    return "".join(parts)


# ---------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------

b = []

b.append(title("AXI4 UVM VIP 架构与使用说明"))
b.append(para("版本: 1.1     项目: axi_work     文档日期: 2026-08-19", bold=True))

# ---- 1 ----
b.append(h1("1. 项目概述"))
b.append(para(
    "本项目是一套基于 UVM 1.2 的 AXI4 / AXI4-Lite 验证 IP (VIP)，提供完整的 Master / Slave Agent、"
    "SVA 协议检查器、功能覆盖率、参考模型数据校验、错误注入、性能监控与可配置反压/带宽限制能力，"
    "可在 VCS、Xcelium、Questa 三种仿真器下开箱运行。"))

b.append(h2("1.1 核心特性"))
for f in [
    "Master Agent：五通道并发驱动，支持全部 AXI4 burst 类型 (FIXED / INCR / WRAP) 与窄传输、非对齐访问",
    "独立 endpoint 反压：Master 配置 B/R READY，Slave 配置 AW/W/AR READY",
    "协议检查器：非侵入式 SVA Assertion，默认由 tb_top 显式实例化",
    "Scoreboard：基于独立 expected_mem 的单接口 memory-like 读写一致性校验",
    "覆盖率：txn_type / burst_type / burst_size / burst_len / resp / 未对齐 / 窄传输 / outstanding 等多维 cross",
    "错误注入：resp error / data corruption / timeout 三类独立序列",
    "性能监控：Read / Write 独立的吞吐率、时延均值/最大值、Gbps 带宽统计",
    "带宽限制：滑窗 (window_cycles / max_bytes_per_window) 主动限流",
    "反压策略：NONE / FIXED_DELAY / RANDOM / BURST / INTERMITTENT / CUSTOM 六种模式",
]:
    b.append(bullet(f))

# ---- 2 ----
b.append(h1("2. 目录结构"))
b.append(code_block(
"""axi_work/
├── Makefile                 -- 编译/仿真入口（VCS / Xcelium / Questa）
├── rtl/
│   └── axi_if.sv            -- AXI 接口 + clocking block + modport
├── src/                     -- UVM 核心组件
│   ├── axi_types.sv         -- 枚举类型
│   ├── axi_pkg.sv           -- 顶层 package，按依赖顺序 `include
│   ├── axi_config.sv        -- 集中配置对象
│   ├── axi_bp_config.sv     -- 反压策略配置
│   ├── axi_seq_item.sv      -- 事务项 (随机约束 + beat 计算)
│   ├── axi_ref_model.sv     -- 字节粒度参考内存 + exclusive 支持
│   ├── axi_bp_generator.sv  -- 反压 ready 生成器
│   ├── axi_bw_limiter.sv    -- 滑窗带宽限制器
│   ├── axi_master_*.sv      -- Master agent / driver / monitor / sequencer
│   ├── axi_slave_*.sv       -- Slave  agent / driver / monitor / sequencer
│   ├── axi_scoreboard.sv    -- 读写一致性校验
│   ├── axi_coverage.sv      -- 功能覆盖率
│   ├── axi_perf_monitor.sv  -- 性能监控 (分方向 BW)
│   └── axi_env.sv           -- 环境顶层
├── seq_lib/                 -- 通用激励序列
├── error_inject/            -- 错误注入序列
├── checker/                 -- SVA 协议检查器 + bind 文件
├── test/                    -- 测试用例库 + tb_top
└── docs/                    -- 文档"""))
b.append(para("Current make print-sources order: rtl/axi_if.sv src/axi_types.sv src/axi_pkg.sv checker/axi_protocol_checker.sv test/tb_top.sv"))

# ---- 3 ----
b.append(h1("3. 整体架构"))
b.append(para("下图展示主要 UVM 组件以及它们之间的配置与分析数据流。"))
b.append(code_block(
"""                        +-----------------------------+
                        |          tb_top             |
                        |  clk / rst / axi_if (DUT bus)|
                        | explicit checker instance  |
                        +--------------+--------------+
                                       |
                                       v   (set vif via uvm_config_db)
                        +--------------+--------------+
                        |       axi_base_test         |
                        |  创建 cfg / configure_test  |
                        +--------------+--------------+
                                       |
                                       v
                        +--------------+--------------+
                        |           axi_env           |
                        |  ref_mem (共享)             |
                        |  master_agent / slave_agent |
                        |  scoreboard / coverage      |
                        |  perf_monitor               |
                        +----+----------------+-------+
                             |                |
                             v                v
            +----------------+---+  +---------+-----------+
            |  master_agent      |  |  slave_agent        |
            |  +  sequencer      |  |  + slave_driver     |
            |  +  master_driver  |  |    (写 ref_mem,     |
            |  +  master_monitor |  |     读 ref_mem 出   |
            +--------------------+  |     rdata)          |
                             |      |  + slave_monitor    |
                             |      +---------+-----------+
                             +-------+--------+
                                     v
                             +-------+--------+
                             |   axi_if (RTL) |<-- SVA checker instance
                             +----------------+"""))
b.append(para("The checker is explicitly instantiated in test/tb_top.sv and connected to the same axi_if. has_protocol_check is configuration/topology intent and does not instantiate the SystemVerilog module. External integrations may explicitly instantiate the checker or provide their own bind, but must not use both."))

b.append(h2("3.1 关键数据流"))
for f in [
    "激励：test → sequence → sequencer → master_driver → axi_if",
    "被动采样：axi_if → 选定 endpoint monitor → scoreboard / coverage / perf_monitor",
    "双 endpoint 时 analysis source 优先采用 Master monitor；Master 关闭时采用 Slave monitor",
    "Slave driver 使用 env.ref_mem 生成响应；scoreboard 使用独立 expected_mem 构造期望值",
    "Scoreboard 从 write_commit / read_request / complete 三路 analysis 事件校验读回数据",
]:
    b.append(bullet(f))

# ---- 4 ----
b.append(h1("4. 关键组件详解"))

b.append(h2("4.1 axi_if (rtl/axi_if.sv)"))
for f in [
    "shipped path 仅支持 axi_if 默认 specialization：DATA_WIDTH=64 / ADDR_WIDTH=32 / ID_WIDTH=4 / USER_WIDTH=0",
    "USER nets 只在 interface generate block 中存在，当前 clocking/modport/transaction/driver/monitor 均不处理 USER",
    "clocking block：master_cb / slave_cb / monitor_cb (input #1step / output #1)",
    "modport：master_mp / slave_mp / monitor_mp",
    "reset_master_signals / reset_slave_signals 任务用于 driver run_phase 起始复位",
]:
    b.append(bullet(f))
b.append(para("The shipped out-of-box VIP path supports only axi_if's default specialization: DATA_WIDTH=64, ADDR_WIDTH=32, ID_WIDTH=4, USER_WIDTH=0."))
b.append(para("USER signals are not driven or monitored by the VIP."))
b.append(para("Non-default widths or USER support require parameterizing the virtual-interface/type chain and implementing USER transaction and channel support."))

b.append(h3("4.1.1 Public net 与 role-private proxy ownership"))
b.append(para(
    "axi_if 的 39 根非 USER 公共信号是 resolved net。DUT、monitor 与 checker 只连接或采样公共信号；"
    "VIP driver 先 claim 对应角色，再通过 master_* 或 slave_* private proxy 驱动。"))
for f in [
    "DUT port 只能连接 awvalid/awready 等 public axi_if signal，不能连接 role-private proxy",
    "Active VIP driver 在 run_phase 自动 claim；passive/disabled role 保持 high impedance，不会遮蔽 DUT output",
    "自定义组件可通过 axi_if.master_mp/slave_mp 调用对应 claim/release task，再驱动既有 master_cb/slave_cb clockvar",
    "外部 endpoint 优先用 module port 建模；class fixture 必须显式 claim role，只写匹配的 master_* / slave_* proxy，有限驱动结束后 release",
    "Monitor、checker、DUT 与 fixture handshake observation 始终读取 public resolved net",
    "禁止 class 对 public AXI net 做 procedural assignment；两个同方向 producer 误接时 public net 解析为 X，应作为 integration error 处理",
]:
    b.append(bullet(f))
b.append(code_block(
"""master_agent -> axi_if public nets -> DUT slave port
slave_agent  <- axi_if public nets <- DUT master port"""))
b.append(table([
    ["VIP role", "VIP-produced public signals", "Signals sampled from DUT/peer"],
    ["Master", "AW payload/awvalid, W payload/wvalid, bready, AR payload/arvalid, rready", "awready, wready, B payload/bvalid, arready, R payload/rvalid"],
    ["Slave", "awready, wready, B payload/bvalid, arready, R payload/rvalid", "AW payload/awvalid, W payload/wvalid, bready, AR payload/arvalid, rready"],
], col_widths=[1400, 3800, 3800]))
b.append(para(
    "一个 physical AXI link 只使用一个 axi_if 与一个 axi_env，不能在同一 axi_if 上配置两个 Master driver。"
    "多个 Master port 必须创建多个 env/interface pair；共享地址空间时在 env 之上增加 system-level predictor/reference model。"))

b.append(h2("4.2 axi_config (集中配置)"))
b.append(para("axi_config 保存总线公共属性，并持有相互独立的 master_cfg / slave_cfg。由 axi_base_test 创建并通过 uvm_config_db 广播；配置 endpoint 前必须先调用 resolve_agent_configs()。"))
b.append(table([
    ["字段", "类型 / 默认", "含义"],
    ["mode", "axi_mode_e (AXI4)", "AXI4 或 AXI4_LITE"],
    ["data/addr/id/user_width", "int (64/32/4/0)", "shipped flow 固定默认值；字段本身不会参数化 virtual axi_if"],
    ["has_scoreboard", "bit (1)", "是否实例化 scoreboard"],
    ["has_coverage",   "bit (0)", "是否开启功能覆盖率"],
    ["has_protocol_check", "bit (1)", "协议检查配置意图；checker 仍须在 top 实例化"],
    ["master_cfg.enabled/is_active", "bit/UVM enum (1/ACTIVE)", "独立创建 Master monitor/driver/sequencer"],
    ["master_cfg.max_outstanding_rd/wr", "int (16/16)", "Master 读写 outstanding 上限，必须非零"],
    ["master_cfg.enable_bw_limit", "bit (0)", "Master 请求带宽限制开关"],
    ["master_cfg.max_bytes_per_window", "int (1024)", "Master 窗口字节上限"],
    ["master_cfg.bw_window_cycles", "int (100)", "Master 带宽窗口周期"],
    ["master_cfg.b/r_bp_cfg", "axi_bp_config", "Master 独立 B/R READY 反压"],
    ["slave_cfg.enabled/is_active", "bit/UVM enum (1/ACTIVE)", "独立创建 Slave monitor/driver/sequencer"],
    ["slave_cfg.resp_delay_min/max", "int (0/10)", "Slave 响应延迟范围"],
    ["slave_cfg.enable_err_inject", "bit (0)", "Slave 错误注入开关"],
    ["slave_cfg.aw/w/ar_bp_cfg", "axi_bp_config", "Slave 独立 AW/W/AR READY 反压"],
    ["vif", "virtual axi_if", "虚接口句柄 (由 tb_top 注入)"],
], col_widths=[2200, 2200, 4600]))
b.append(para("legacy role 与公共 endpoint 字段不会在 resolve_agent_configs() 之后再次映射；新代码应直接使用 master_cfg / slave_cfg。"))

b.append(h2("4.3 axi_seq_item"))
for f in [
    "字段：addr / id / txn_type / burst_len / burst_type / burst_size / lock / cache / prot / qos / region / data[] / wstrb[] / resp[] / rdata[]",
    "时间戳：addr_phase_time / data_start_time / data_end_time / resp_time (由 monitor 填充)",
    "错误注入：inject_err / err_type / err_beat",
    "约束：4KB 不跨界、WRAP 对齐、exclusive 长度 ≤ 128 字节、AXI4-Lite 限制等",
    "工具方法：calc_beat_addr / pack_beat_data / pack_beat_wstrb / get_latency / get_total_bytes",
]:
    b.append(bullet(f))

b.append(h2("4.4 Master / Slave Driver"))
for f in [
    "master_driver 使用 mailbox 解耦 fetch_items 与 AW/W/AR 三个并发发送任务",
    "B/R 通道通过 axi_bp_generator 生成 ready，支持六种模式",
    "带宽限制：fetch_items 在发出事务前等待 bw_limiter 放行；bw_tick_loop 每 cycle 驱动窗口",
    "slave_driver 维护 pending_aw_q，在 wlast 时调用 ref_mem.burst_write() 将写数据落库",
    "slave_driver R 通道按 beat 从 ref_mem.read() 取期望数据并按 byte lane 正确摆位",
    "slave_driver 支持 exclusive (读→写 EXOKAY/OKAY) 与错误注入 (resp/data corrupt/timeout)",
]:
    b.append(bullet(f))

b.append(h2("4.5 Master Monitor"))
for f in [
    "五通道并发采样：monitor_aw / w / b / ar / r_channel",
    "按 ID 匹配读写数据 (wr_addr_q / rd_addr_q)，以兼容 outstanding 与乱序回读",
    "按 beat_addr 与 bus_bytes 正确提取 narrow / unaligned 的有效字节车道",
    "完成时戳记 addr_phase_time / data_start_time / data_end_time / resp_time 并广播到 analysis_port",
    "维护 cur_outstanding_rd / cur_outstanding_wr，供 base test 的 wait_for_idle() 判定总线空闲",
]:
    b.append(bullet(f))

b.append(h2("4.6 Scoreboard"))
for f in [
    "write_commit 把完整写事务更新到 scoreboard 自己的 expected_mem",
    "read_request 在 AR 时从 expected_mem 快照期望读数据，complete 按 ID 匹配响应",
    "按 header、resp/rdata 长度与逐字节数据比较，累计 match_count / mismatch_count",
    "仅适用于单接口 memory-like 语义；真实 DUT 与跨 env 地址空间应使用系统级 predictor/reference model",
    "report_phase 输出总结，mismatch_count > 0 即视为 FAIL",
]:
    b.append(bullet(f))

b.append(h2("4.7 Coverage"))
for f in [
    "axi_txn_cg：txn_type / burst_type / burst_size / burst_len / resp / lock / addr_range / narrow / unaligned",
    "Cross：type×burst、type×size、type×len、burst×len",
    "axi_outstanding_cg：outstanding_rd / outstanding_wr 分桶 + cross",
]:
    b.append(bullet(f))

b.append(h2("4.8 Performance Monitor"))
for f in [
    "Read / Write 分向计数：total_txn、total_bytes、sum_latency、max_latency",
    "Read / Write 分向时间窗：first_rd_time/last_rd_time、first_wr_time/last_wr_time",
    "Gbps 带宽公式：bytes * 8000 / duration_ps",
    "print_stats(name) 支持 mid-simulation 打印；report_phase 打印最终 summary",
]:
    b.append(bullet(f))

b.append(h2("4.9 Backpressure (axi_bp_generator)"))
b.append(table([
    ["模式", "行为"],
    ["BP_NONE", "ready 常 1"],
    ["BP_FIXED_DELAY", "等 fixed_delay cycles 后再拉高一次"],
    ["BP_RANDOM", "random_ready_pct% 概率拉高"],
    ["BP_BURST", "accept N cycles，block M cycles，交替"],
    ["BP_INTERMITTENT", "on_window / off_window 周期性开关"],
    ["BP_CUSTOM", "预留钩子 (默认直通)"],
], col_widths=[2500, 6500]))

b.append(h2("4.10 Bandwidth Limiter (axi_bw_limiter)"))
for f in [
    "在 master_driver 的 fetch_items 前端过滤",
    "滑窗：每 window_cycles cycle 清零 byte_counter",
    "record_sent(N) 累积已下发字节；超过 max_bytes_per_window 即 throttle 等待下一窗口",
    "tick() 每 cycle 调用一次 (由 bw_tick_loop 驱动)",
]:
    b.append(bullet(f))

b.append(h2("4.11 Protocol Checker"))
for f in [
    "checker/axi_protocol_checker.sv：WLAST beat 计数、4KB 跨界、WRAP 合法长度、resp 合法值等 SVA",
    "默认 Makefile 流程由 tb_top 显式实例化 checker；checker_bind.sv 仅供支持 bind-to-interface 的自定义集成选择，不能与显式实例重复使用",
]:
    b.append(bullet(f))

b.append(h2("4.12 Reference Model (ref_mem)"))
for f in [
    "associative array 存储字节：bit [7:0] mem[bit [63:0]]",
    "burst_write / burst_read / write / read 支持 wstrb",
    "exclusive_read / exclusive_write 实现 LOCK/EXOKAY 模型",
    "backdoor_read / backdoor_write 便于测试预置初值",
]:
    b.append(bullet(f))

# ---- 5 ----
b.append(h1("5. 测试用例"))
b.append(table([
    ["测试名称", "作用"],
    ["axi_smoke_test", "冒烟：single_rw → burst → random_stress 三阶段自检"],
    ["axi_rw_test", "集成读写一致性：N 次 write 后全部读回并经 scoreboard 比对"],
    ["axi_mass_rw_test", "大批量读写 (默认 1000)，用于回归稳定性与内存占用评估"],
    ["axi_perf_test", "基础性能监控：write+read 对，演示 perf_monitor 报告"],
    ["axi_perf_stats_test", "多段统计：reset/print_stats/report，验证分段性能统计"],
    ["axi_bw_limit_test", "启用 bw_limiter，校准窗口内带宽限制是否精确"],
    ["axi_bp_test", "五通道反压组合：FIXED_DELAY / RANDOM / BURST / INTERMITTENT"],
    ["axi_high_traffic_test", "持续混合流量；默认 20000 transaction / 32 outstanding / burst 16"],
], col_widths=[2800, 6200]))

# ---- 6 ----
b.append(h1("6. 序列库 (seq_lib)"))
b.append(table([
    ["序列", "作用"],
    ["axi_base_seq", "所有序列基类，提供 do_write / do_read 便捷 API"],
    ["axi_single_rw_seq", "单拍 W/R"],
    ["axi_burst_seq", "多拍 INCR burst"],
    ["axi_wrap_burst_seq", "WRAP burst (长度 2/4/8/16)"],
    ["axi_narrow_seq", "窄传输 (burst_size < bus_bytes)"],
    ["axi_unaligned_seq", "非对齐起始地址"],
    ["axi_b2b_seq", "背靠背连续传输"],
    ["axi_outstanding_seq", "多 outstanding 并发"],
    ["axi_exclusive_seq", "LOCK 独占访问 (EXOKAY)"],
    ["axi_random_stress_seq", "随机混合压力"],
], col_widths=[2800, 6200]))

# ---- 7 ----
b.append(h1("7. 错误注入 (error_inject)"))
b.append(table([
    ["组件", "作用"],
    ["axi_err_seq_item", "扩展 axi_seq_item，带 inject_err / err_type / err_beat"],
    ["axi_err_resp_seq", "注入 SLVERR / DECERR 响应"],
    ["axi_err_data_corrupt_seq", "在指定 beat 翻转数据字节 (XOR 0xFF)"],
    ["axi_err_timeout_seq", "在指定 beat 注入 1000 cycle 超时"],
], col_widths=[2800, 6200]))
b.append(para("启用方式：先调用 cfg.resolve_agent_configs()，再设置 cfg.slave_cfg.enable_err_inject = 1；sequence item 还需设置 inject_err / err_type / err_beat。"))

# ---- 8 ----
b.append(h1("8. 使用说明"))

b.append(h2("8.1 环境要求"))
for f in [
    "SystemVerilog 仿真器：VCS / Xcelium / Questa",
    "UVM 版本：1.2 及以上",
    "仿真时标：1ns/1ps (tb_top 内设置)",
    "时钟：tb_top 默认 800 MHz (1.25 ns 周期)",
    "复位：拉低 10 cycle，在 negedge aclk 松开",
]:
    b.append(bullet(f))

b.append(h2("8.2 快速开始"))
b.append(code_block(
"""# 固定 seed 的 VCS smoke test
make run TOOL=vcs TEST=axi_smoke_test SEED=1

# 永久 16 项回归
make regress TOOL=vcs

# 高流量显式参数：20000 transaction / 32 outstanding / burst 16
make run TOOL=vcs TEST=axi_high_traffic_test SEED=1402 RUN_ARGS='+AXI_TRAFFIC_TXNS=20000 +AXI_TRAFFIC_OUTSTANDING=32 +AXI_TRAFFIC_BURST_MAX=16'

# 独立 SVA checker rule 回归
make checker-regress TOOL=vcs

# 其它支持的单测仿真器
make run TOOL=xcelium TEST=axi_smoke_test SEED=1
make run TOOL=questa  TEST=axi_smoke_test SEED=1"""))
b.append(para("高流量三个 plusarg 仅接受 ASCII 十进制数字；TXNS>=4，OUTSTANDING>=2，BURST_MAX 仅可为 1/4/8/16。重复、空值、非数字或 uint32 overflow 均 UVM_FATAL。永久矩阵使用默认 20000/32/16。"))

b.append(h2("8.3 Makefile 变量"))
b.append(table([
    ["变量", "默认值", "含义"],
    ["TOOL", "vcs",            "仿真器 (vcs/xcelium/questa)"],
    ["TOP",  "tb_top",         "顶层模块名"],
    ["TEST", "axi_smoke_test", "+UVM_TESTNAME 对应的测试类"],
    ["SEED", "random",         "随机种子 (random 或整数)"],
    ["RUN_ARGS", "空",          "原样追加到 vcs/xcelium/questa 的 RUN 命令"],
], col_widths=[1800, 2400, 4800]))

b.append(h2("8.4 编写新测试"))
b.append(code_block(
"""// test/my_test.sv
class my_test extends axi_base_test;
  `uvm_component_utils(my_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    super.configure_test();
    cfg.resolve_agent_configs();
    cfg.data_width = 64;
    cfg.has_coverage = 1;
    cfg.slave_cfg.enable_err_inject = 0;
    cfg.master_cfg.enable_bw_limit = 1;
    cfg.master_cfg.max_bytes_per_window = 2048;
    cfg.master_cfg.bw_window_cycles = 200;
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_burst_seq seq;
    phase.raise_objection(this);
    seq = axi_burst_seq::type_id::create("seq");
    void'(seq.randomize());
    seq.start(env.master_agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass"""))
b.append(h3("8.4.1 注册测试"))
b.append(para("将新测试 `include 到 src/axi_pkg.sv 的最后 (test/ 段)。"))

b.append(h2("8.5 编写新序列"))
b.append(code_block(
"""class my_seq extends axi_base_seq;
  `uvm_object_utils(my_seq)
  function new(string name = "my_seq"); super.new(name); endfunction

  virtual task body();
    bit [7:0]    wr_data[];
    axi_seq_item rsp;

    wr_data = new[8];
    foreach (wr_data[i]) wr_data[i] = i;

    do_write(.addr(64'h1000), .data(wr_data),
             .burst_len(0), .burst_size(3), .burst_type(AXI_INCR));

    do_read(.addr(64'h1000), .burst_len(0), .burst_size(3),
            .burst_type(AXI_INCR), .rsp(rsp));
  endtask
endclass"""))

b.append(h2("8.6 启用反压"))
b.append(code_block(
"""cfg.resolve_agent_configs();

// Master 独立控制 B/R READY
cfg.master_cfg.per_channel_bp_enable = 1;
cfg.master_cfg.b_bp_cfg.mode = BP_RANDOM;
cfg.master_cfg.b_bp_cfg.random_ready_pct = 50;
cfg.master_cfg.r_bp_cfg.mode = BP_FIXED_DELAY;
cfg.master_cfg.r_bp_cfg.fixed_delay = 3;

// Slave 独立控制 AW/W/AR READY
cfg.slave_cfg.per_channel_bp_enable = 1;
cfg.slave_cfg.aw_bp_cfg.mode = BP_FIXED_DELAY;
cfg.slave_cfg.aw_bp_cfg.fixed_delay = 3;
cfg.slave_cfg.w_bp_cfg.mode = BP_BURST;
cfg.slave_cfg.w_bp_cfg.burst_accept_cycles = 8;
cfg.slave_cfg.w_bp_cfg.burst_block_cycles = 4;
cfg.slave_cfg.ar_bp_cfg.mode = BP_INTERMITTENT;
cfg.slave_cfg.ar_bp_cfg.on_window = 20;
cfg.slave_cfg.ar_bp_cfg.off_window = 5;"""))

b.append(h2("8.7 启用带宽限制"))
b.append(code_block(
"""cfg.resolve_agent_configs();
cfg.master_cfg.enable_bw_limit = 1;
cfg.master_cfg.max_bytes_per_window = 1024;  // 窗口内最多 1 KB
cfg.master_cfg.bw_window_cycles = 100;       // 每 100 cycle 为一窗口
// 800 MHz clock × 1024 B / (100 cycle × 1.25 ns) ≈ 8.192 Gbps 上限"""))

b.append(h2("8.8 启用错误注入"))
b.append(code_block(
"""cfg.resolve_agent_configs();
cfg.slave_cfg.enable_err_inject = 1;
// 在 sequence 中：
item.inject_err = 1;
item.err_type   = ERR_RESP;      // ERR_RESP / ERR_DATA_CORRUPT / ERR_TIMEOUT
item.err_beat   = 2;"""))

b.append(h2("8.9 多端口 / 多环境规则"))
b.append(para("一个物理 AXI 接口严格对应一个 axi_env、一个独立 axi_config 和一个 virtual axi_if。两个 Master 端口与一个 Slave 端口应创建 m0_env、m1_env、s0_env，并分别把 cfg scoped set 到三个 env；不得让多个 env 共享同一物理接口。"))
b.append(code_block(
"""m0_cfg.vif = m0_vif; m0_cfg.resolve_agent_configs();
m1_cfg.vif = m1_vif; m1_cfg.resolve_agent_configs();
s0_cfg.vif = s0_vif; s0_cfg.resolve_agent_configs();
uvm_config_db #(axi_config)::set(this, "m0_env", "cfg", m0_cfg);
uvm_config_db #(axi_config)::set(this, "m1_env", "cfg", m1_cfg);
uvm_config_db #(axi_config)::set(this, "s0_env", "cfg", s0_cfg);"""))
b.append(para("built-in scoreboard 只处理单 env 的 memory-like 事务，不做跨 env 比对。多个 Master 共享地址空间时，应在 env 之上增加 system-level predictor/reference model。"))

b.append(h2("8.10 查看性能报告"))
b.append(para("运行结束后 UVM report_phase 打印："))
b.append(code_block(
"""UVM_INFO ... [PERF] ======================================================
UVM_INFO ... [PERF]            AXI Performance Monitor Report
UVM_INFO ... [PERF] ======================================================
UVM_INFO ... [PERF]   Simulation window : 12500 -- 187500  (elapsed=175000)
UVM_INFO ... [PERF] ------------------------------------------------------
UVM_INFO ... [PERF]   READ  transactions : 200
UVM_INFO ... [PERF]   READ  total bytes  : 12800
UVM_INFO ... [PERF]   READ  avg latency  : 42.50
UVM_INFO ... [PERF]   READ  max latency  : 95
UVM_INFO ... [PERF]   READ  throughput   : 0.0731 B/tu
UVM_INFO ... [PERF]   READ  bandwidth    : 5.846 Gbps
UVM_INFO ... [PERF] ------------------------------------------------------
UVM_INFO ... [PERF]   WRITE transactions : 200
...
UVM_INFO ... [PERF] ======================================================"""))

# ---- 9 ----
b.append(h1("9. 常见问题 (FAQ)"))
faqs = [
    ("Q: 如何切换 AXI4-Lite 模式？",
     "A: cfg.mode = AXI4_LITE。axi_seq_item 的 lite_mode_c 约束会自动把 burst_len 固定为 0、burst_size 固定为 bus_bytes、禁用 lock。"),
    ("Q: VCS 报 bind-to-interface 不支持怎么办？",
     "A: Makefile 的所有 tool 流程都沿用 tb_top 中显式实例化的 axi_protocol_checker，不把 checker/axi_checker_bind.sv 加入同一次编译。"),
    ("Q: Scoreboard 的适用边界是什么？",
     "A: 它从 monitor 的 write_commit/read_request/complete 更新独立 expected_mem，适合单接口 memory-like 语义；真实 DUT 副作用、bridge/interconnect 或跨 env 共享地址空间需外部 predictor/reference model。"),
    ("Q: wait_for_idle 超时如何定位？",
     "A: 打开 UVM_HIGH 日志查看 MON / SLV_DRV 的 AR/AW/B/R 事件；常见原因：slave 反压过严、bw_limiter 窗口设太小、outstanding 队列未匹配 ID。"),
    ("Q: 如何收集覆盖率数据库？",
     "A: cfg.has_coverage = 1；VCS 下编译加 -cm line+cond+fsm+tgl 选项即可。"),
]
for q, a in faqs:
    b.append(para(q, bold=True))
    b.append(para(a))

# ---- 10 ----
b.append(h1("10. 扩展点 (Roadmap)"))
for f in [
    "AXI5 / ACE 扩展：新增 snoop channel 与协议检查",
    "寄存器模型 (uvm_reg)：对接具体 DUT 时挂载 reg_block",
    "多时钟域 / CDC：将 axi_if 扩展为带 gen_clk 的参数化接口",
    "覆盖率驱动：coverage_driven_seq 按剩余 bin 自动回填",
    "真实 DUT 集成：把 slave_agent 替换为 passive + 接真 DUT",
]:
    b.append(bullet(f))

# ---- Appendix ----
b.append(h1("附录 A：axi_pkg.sv include 顺序"))
b.append(code_block(
"""axi_types (外部 package，被 axi_pkg 导入)
├─ axi_bp_config
├─ axi_master_config / axi_slave_config
├─ axi_config         (依赖上述 endpoint config)
├─ axi_seq_item       (依赖 axi_config)
├─ axi_ref_model
├─ axi_bp_generator
├─ axi_bw_limiter
├─ master: sequencer → monitor → driver → agent
├─ slave : sequencer → monitor → driver → agent
├─ axi_scoreboard
├─ axi_coverage
├─ axi_perf_monitor
└─ axi_env
seq_lib/   : base_seq → single_rw / burst / b2b / narrow / unaligned
             / exclusive / wrap / outstanding / random_stress
error_inject/ : err_seq_item → err_resp / err_timeout / err_data_corrupt
test/      : base_test → topology / config_validation / response_lifecycle
             → smoke / rw / perf / bp / mass_rw / perf_stats / bw_limit
             → outstanding_limit / high_traffic"""))

b.append(h1("附录 B：VCS 编译命令"))
b.append(code_block(
"""vcs -full64 -sverilog -ntb_opts uvm-1.2 \\
    +incdir+src +incdir+seq_lib +incdir+error_inject +incdir+test \\
    -timescale=1ns/1ps -debug_access+all \\
    rtl/axi_if.sv \\
    src/axi_types.sv src/axi_pkg.sv \\
    checker/axi_protocol_checker.sv \\
    test/tb_top.sv \\
    -o simv
./simv +UVM_TESTNAME=axi_smoke_test +ntb_random_seed=1"""))

# ---------------------------------------------------------------------------
document_body = "".join(b)
DOCUMENT = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\n'
    '<w:body>\n' + document_body +
    '<w:sectPr>'
    '<w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="720" w:footer="720" w:gutter="0"/>'
    '</w:sectPr>'
    '</w:body>\n</w:document>\n'
)

def write_deterministic_member(archive, name, content):
    info = zipfile.ZipInfo(name, date_time=(2026, 8, 19, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | 0o644) << 16
    archive.writestr(info, content)


with zipfile.ZipFile(OUT_PATH, "w") as z:
    write_deterministic_member(z, "[Content_Types].xml", CONTENT_TYPES)
    write_deterministic_member(z, "_rels/.rels", RELS)
    write_deterministic_member(z, "word/document.xml", DOCUMENT)
    write_deterministic_member(z, "word/_rels/document.xml.rels", DOC_RELS)
    write_deterministic_member(z, "word/styles.xml", STYLES)

print(f"Wrote {OUT_PATH} ({os.path.getsize(OUT_PATH)} bytes)")
