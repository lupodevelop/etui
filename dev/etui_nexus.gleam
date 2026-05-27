/// GATUI NEXUS, infrastructure operations dashboard.
///
/// Run:  gleam run -m etui_nexus
/// Tabs: TAB=next  j/k ↑↓=navigate  ↵=detail  ESC/h/←=back  q=quit
import etui/anim
import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/geometry.{type Rect, rect_new}
import etui/span
import etui/style
import etui/widgets/gauge
import etui/widgets/list as list_widget
import etui/widgets/paragraph
import etui/widgets/scrollbar
import etui/widgets/sparkline
import etui/widgets/tabs as tabs_widget
import gleam/int
import gleam/list
import gleam/string

// ─── Palette ─────────────────────────────────────────────────────

const c_cyan = style.Indexed(51)

const c_dcyan = style.Indexed(37)

const c_cyan2 = style.Indexed(45)

const c_cyan3 = style.Indexed(39)

const c_blue = style.Indexed(27)

const c_amber = style.Indexed(214)

const c_red = style.Indexed(196)

const c_pink = style.Indexed(213)

const c_green = style.Indexed(82)

const c_dim = style.Indexed(240)

const c_white = style.Indexed(255)

// ─── Span helpers ────────────────────────────────────────────────

fn cy(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_cyan)
}

fn cy_b(s: String) -> span.Span {
  cy(s) |> span.span_modifier(style.bold())
}

fn cy_r(s: String) -> span.Span {
  cy(s) |> span.span_modifier(style.reverse())
}

fn dcy(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_dcyan)
}

fn amb(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_amber)
}

fn amb_b(s: String) -> span.Span {
  amb(s) |> span.span_modifier(style.bold())
}

fn red_b(s: String) -> span.Span {
  span.span_plain(s)
  |> span.span_fg(c_red)
  |> span.span_modifier(style.bold())
}

fn pk(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_pink)
}

fn pk_b(s: String) -> span.Span {
  pk(s) |> span.span_modifier(style.bold())
}

fn grn(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_green)
}

fn grn_b(s: String) -> span.Span {
  grn(s) |> span.span_modifier(style.bold())
}

fn wht_b(s: String) -> span.Span {
  span.span_plain(s)
  |> span.span_fg(c_white)
  |> span.span_modifier(style.bold())
}

fn dim(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_dim)
}

fn dim_b(s: String) -> span.Span {
  dim(s) |> span.span_modifier(style.bold())
}

fn gap(n: Int) -> span.Span {
  span.span_plain(string.repeat(" ", n))
}

fn put1(
  buf: buffer.Buffer,
  x: Int,
  y: Int,
  w: Int,
  spans: List(span.Span),
) -> buffer.Buffer {
  paragraph.render_styled(buf, rect_new(x, y, w, 1), [span.line_new(spans)])
}

fn hint(key: String, label: String) -> List(span.Span) {
  [cy_r(" " <> key <> " "), dim(" " <> label)]
}

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}

// ─── Data ────────────────────────────────────────────────────────

type ServiceStatus {
  Up
  Down
  Warn
}

type Service {
  Service(
    name: String,
    host: String,
    status: ServiceStatus,
    cpu_pct: Int,
    mem_pct: Int,
    uptime: String,
    version: String,
    info: String,
  )
}

type LogLevel {
  LInfo
  LWarn
  LError
  LDebug
}

type LogEntry {
  LogEntry(time: String, level: LogLevel, service: String, message: String)
}

const services: List(Service) = [
  Service(
    "api-gateway",
    "gw01.prod",
    Up,
    23,
    41,
    "47d 3h",
    "nginx/2.8.1",
    "Reverse proxy, 12k req/s, 6 upstreams active",
  ),
  Service(
    "auth-service",
    "auth01.prod",
    Up,
    8,
    29,
    "12d 6h",
    "auth/3.1.0",
    "JWT issuer + OIDC provider, 3k active sessions",
  ),
  Service(
    "user-db",
    "pg01.prod",
    Up,
    67,
    78,
    "180d 2h",
    "postgres/16.1",
    "Primary Postgres, 2.1M rows, 8 connections",
  ),
  Service(
    "cache",
    "redis01.prod",
    Warn,
    2,
    89,
    "3d 14h",
    "redis/7.2",
    "LRU cache — memory at 89% of limit, eviction elevated",
  ),
  Service(
    "worker-queue",
    "rmq01.prod",
    Up,
    12,
    33,
    "22d 9h",
    "rabbitmq/3.12",
    "3 queues, 41 consumers, 120 msg/s throughput",
  ),
  Service(
    "ml-inference",
    "gpu01.prod",
    Up,
    91,
    62,
    "5d 11h",
    "triton/1.4.2",
    "3 models loaded: bert-v2, clip, embed-v1",
  ),
  Service(
    "cdn-origin",
    "cdn01.prod",
    Down,
    0,
    0,
    "—",
    "cdn/1.0.9",
    "OFFLINE since 14:32 UTC — upstream unreachable",
  ),
  Service(
    "monitor",
    "mon01.prod",
    Up,
    4,
    18,
    "90d 0h",
    "prom/2.3.0",
    "Prometheus + Grafana, 8/8 targets healthy",
  ),
]

const log_entries: List(LogEntry) = [
  LogEntry(
    "14:32:01",
    LError,
    "cdn-origin",
    "Connection reset: upstream unreachable",
  ),
  LogEntry(
    "14:32:05",
    LError,
    "cdn-origin",
    "Health check failed (3/3) — marking DOWN",
  ),
  LogEntry("14:32:05", LWarn, "api-gateway", "Upstream cdn-origin marked DOWN"),
  LogEntry(
    "14:31:44",
    LInfo,
    "auth-service",
    "Token refresh: user=521a3b expires=+1h",
  ),
  LogEntry(
    "14:31:39",
    LInfo,
    "worker-queue",
    "Job enqueued: email_send id=8fc9d1",
  ),
  LogEntry(
    "14:31:22",
    LInfo,
    "user-db",
    "Checkpoint complete — 4821 buffers written",
  ),
  LogEntry("14:30:58", LWarn, "cache", "Used memory 89% of maxmemory"),
  LogEntry("14:30:41", LInfo, "ml-inference", "Model bert-v2 loaded: 1.2 GB"),
  LogEntry(
    "14:30:30",
    LDebug,
    "auth-service",
    "OIDC discovery endpoint refreshed",
  ),
  LogEntry(
    "14:30:11",
    LInfo,
    "api-gateway",
    "Config reload: 0 errors, 12 upstreams",
  ),
  LogEntry("14:29:55", LInfo, "monitor", "Scrape cycle OK: 8/8 targets healthy"),
  LogEntry("14:29:33", LInfo, "user-db", "VACUUM: 12000 dead rows removed"),
  LogEntry(
    "14:29:01",
    LError,
    "cdn-origin",
    "SSL handshake timeout: peer=203.x.x.x",
  ),
  LogEntry("14:28:47", LInfo, "worker-queue", "Consumer ack: job=8fb1 t=42ms"),
  LogEntry(
    "14:28:22",
    LInfo,
    "auth-service",
    "Login ok: user=d3f1a ip=10.0.1.4",
  ),
  LogEntry("14:27:59", LWarn, "cache", "Eviction rate elevated: 120 keys/s"),
  LogEntry(
    "14:27:33",
    LInfo,
    "api-gateway",
    "Upstream ml-inference marked healthy",
  ),
  LogEntry("14:27:01", LDebug, "monitor", "Alert rule eval: 0 rules firing"),
  LogEntry("14:26:45", LInfo, "user-db", "New connection from auth-service"),
]

const req_data: List(Int) = [
  120, 145, 132, 167, 155, 180, 172, 195, 188, 210, 198, 225, 215, 198, 220, 242,
  235, 218, 200, 212,
]

const lat_data: List(Int) = [
  8, 9, 7, 12, 10, 8, 11, 14, 12, 9, 8, 10, 13, 11, 9, 8, 10, 12, 9, 7,
]

const err_data: List(Int) = [
  0, 0, 1, 0, 0, 2, 1, 0, 0, 0, 3, 1, 0, 0, 5, 3, 1, 0, 0, 0,
]

// ─── Model ───────────────────────────────────────────────────────

type Tab {
  TabServices
  TabEvents
  TabMetrics
  TabAbout
}

type Screen {
  Boot
  Dashboard(tab: Tab, svc_cursor: Int, svc_offset: Int, log_offset: Int)
  Detail(svc: Service, back_cursor: Int, back_offset: Int)
}

type Model {
  Model(screen: Screen, width: Int, height: Int, quit: Bool)
}

fn initial_model() -> Model {
  Model(screen: Boot, width: 80, height: 24, quit: False)
}

// ─── Helpers ─────────────────────────────────────────────────────

fn tab_index(tab: Tab) -> Int {
  case tab {
    TabServices -> 0
    TabEvents -> 1
    TabMetrics -> 2
    TabAbout -> 3
  }
}

fn next_tab(tab: Tab) -> Tab {
  case tab {
    TabServices -> TabEvents
    TabEvents -> TabMetrics
    TabMetrics -> TabAbout
    TabAbout -> TabServices
  }
}

fn color_for_pct(pct: Int) -> style.Color {
  case pct >= 85 {
    True -> c_red
    False ->
      case pct >= 60 {
        True -> c_amber
        False -> c_green
      }
  }
}

fn mini_bar(pct: Int, color: style.Color) -> span.Span {
  let width = 7
  let filled = case pct {
    0 -> 0
    100 -> width
    _ -> int.max(pct * width / 100, 1)
  }
  let bar = string.repeat("█", filled) <> string.repeat("░", width - filled)
  span.span_plain(bar) |> span.span_fg(color)
}

fn rotate_data(data: List(Int), offset: Int) -> List(Int) {
  let len = list.length(data)
  case len {
    0 -> []
    _ -> {
      let off = offset % len
      list.append(list.drop(data, off), list.take(data, off))
    }
  }
}

fn last_value(data: List(Int)) -> Int {
  list.fold(data, 0, fn(_, v) { v })
}

fn svc_status_chars(s: ServiceStatus) -> Int {
  case s {
    Up -> 8
    Down -> 9
    Warn -> 10
  }
}

fn fake_clock(frame: Int) -> String {
  let total_secs = frame * 80 / 1000
  let secs = total_secs % 60
  let mins = { 32 + total_secs / 60 } % 60
  "14:" <> pad2(mins) <> ":" <> pad2(secs)
}

fn spin_char(frame: Int) -> String {
  let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  case list.drop(frames, frame % list.length(frames)) {
    [s, ..] -> s
    [] -> "·"
  }
}

// Animated status badge: UP static, WARN pulses, DOWN blinks
fn status_badge(s: ServiceStatus, frame: Int) -> span.Span {
  case s {
    Up -> grn_b("● UP   ")
    Warn ->
      case frame / 8 % 2 {
        0 -> amb_b("▲ WARN ")
        _ -> amb("▲ WARN ")
      }
    Down ->
      case frame / 12 % 2 {
        0 -> red_b("✖ DOWN ")
        _ -> span.span_plain("✖ DOWN ") |> span.span_fg(c_red)
      }
  }
}

// Pulsing cursor for selected list rows
fn list_cursor(selected: Bool, frame: Int) -> span.Span {
  case selected {
    False -> span.span_plain("   ")
    True ->
      case frame / 5 % 2 {
        0 -> cy_b("▌▌ ")
        _ -> cy("▌▌ ")
      }
  }
}

// ─── Shared layout ───────────────────────────────────────────────

fn draw_tab_bar(buf: buffer.Buffer, active: Tab, w: Int) -> buffer.Buffer {
  let t =
    tabs_widget.tabs_new(["SERVICES", "EVENTS", "METRICS", "ABOUT"])
    |> tabs_widget.with_active(tab_index(active))
    |> tabs_widget.with_colors(c_cyan, style.Default)
  let buf = tabs_widget.render(buf, rect_new(0, 0, w, 1), t)
  put1(buf, 0, 1, w, [cy(string.repeat("━", w))])
}

fn draw_footer(
  buf: buffer.Buffer,
  w: Int,
  h: Int,
  hints: List(span.Span),
) -> buffer.Buffer {
  let buf = put1(buf, 0, h - 2, w, [dim(string.repeat("─", w))])
  put1(buf, 1, h - 1, w - 2, hints)
}

// ─── Boot screen ─────────────────────────────────────────────────

const boot_banner: List(String) = [
  "  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗  ",
  "  ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝  ",
  "  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗  ",
  "  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║  ",
  "  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║  ",
  "  ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝  ",
]

const load_messages: List(String) = [
  "CONNECTING TO MONITORING SUBSYSTEM...",
  "LOADING INFRASTRUCTURE REGISTRY...",
  "SYNCING METRICS PIPELINE...",
  "ATTACHING EVENT LOG STREAM...",
  "FINALIZING INTERFACES...",
  "SYSTEM READY",
]

// Banner fully typed at frame ~24, loading starts then.
// Loading completes at frame 24 + 35 = 59 (~4.7s total boot).
const banner_done_at = 24

const load_frames = 35

fn render_boot(model: Model, anim_st: anim.AnimState) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let w = model.width
  let h = model.height
  let frame = anim_st.frame
  let banner_h = list.length(boot_banner)
  let total_h = banner_h + 7
  let top_y = int.max(h / 2 - total_h / 2, 1)
  let indent = int.max(w / 2 - 24, 1)
  let cw = w - indent * 2

  // Phase 1: Banner types in, 4 graphemes per frame, line i starts at frame i*2
  let buf =
    list.index_fold(boot_banner, buf, fn(b, line, i) {
      let line_frame = int.max(frame - i * 2, 0)
      let n = int.min(line_frame * 4, string.length(line))
      case n {
        0 -> b
        _ -> {
          let tail_len = int.min(4, n)
          let head = string.slice(line, 0, n - tail_len)
          let tail = string.slice(line, n - tail_len, tail_len)
          put1(b, indent, top_y + i, cw, [dcy(head), cy_b(tail)])
        }
      }
    })

  // Subtitle appears when banner is complete
  let sub_y = top_y + banner_h + 1
  let buf = case frame >= banner_done_at {
    False -> buf
    True ->
      put1(buf, indent, sub_y, cw, [
        dcy("INFRASTRUCTURE MONITOR"),
        gap(4),
        dim("v1.0.0 — etui demo"),
      ])
  }

  // Phase 2: Loading gauge fills up
  let load_start = banner_done_at
  let progress = case frame < load_start {
    True -> 0
    False -> int.min({ frame - load_start } * 100 / load_frames, 100)
  }
  let all_done = frame >= load_start + load_frames

  let gauge_y = sub_y + 2
  let gauge_w = int.min(cw - 4, 50)
  let gauge_x = indent + 2

  let buf = case frame >= load_start {
    False -> buf
    True -> {
      // Spinner + message
      let n_msg = list.length(load_messages)
      let msg_idx = int.min(progress * n_msg / 101, n_msg - 1)
      let msg = case list.drop(load_messages, msg_idx) {
        [s, ..] -> s
        [] -> "SYSTEM READY"
      }
      let buf =
        put1(buf, gauge_x, gauge_y, gauge_w + 2, [
          case all_done {
            True -> grn_b("✓")
            False -> amb_b(spin_char(frame))
          },
          gap(2),
          case all_done {
            True -> grn(msg)
            False -> dim(msg)
          },
        ])

      // Gauge bar
      let gauge_color = case progress {
        p if p < 40 -> c_cyan
        p if p < 70 -> c_cyan2
        _ -> c_green
      }
      let g =
        gauge.gauge_new(progress)
        |> gauge.with_label(int.to_string(progress) <> "%")
        |> gauge.with_colors(gauge_color, style.Default)
      gauge.render(buf, rect_new(gauge_x, gauge_y + 1, gauge_w, 1), g)
    }
  }

  // Phase 3: Prompt, blinks when ready
  let prompt_y = gauge_y + 3
  case all_done {
    False -> buf
    True ->
      put1(buf, indent, prompt_y, cw, [
        cy_b("> PRESS ANY KEY TO START  "),
        case frame / 6 % 2 {
          0 -> cy_r(" ▌ ")
          _ -> cy(" ▌ ")
        },
      ])
  }
}

// ─── Services tab ────────────────────────────────────────────────

fn svc_name_span(svc: Service, selected: Bool, frame: Int) -> span.Span {
  let f = string.pad_end(svc.name, 18, " ")
  case svc.status {
    Up ->
      case selected {
        True ->
          case frame / 5 % 2 {
            0 -> wht_b(f)
            _ -> cy_b(f)
          }
        False -> cy(f)
      }
    Down ->
      case selected {
        True -> red_b(f)
        False -> span.span_plain(f) |> span.span_fg(c_red)
      }
    Warn ->
      case selected {
        True ->
          case frame / 7 % 2 {
            0 -> amb_b(f)
            _ -> wht_b(f)
          }
        False -> amb(f)
      }
  }
}

fn render_services(
  model: Model,
  cursor: Int,
  offset: Int,
  frame: Int,
) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let w = model.width
  let h = model.height
  let row_count = int.max(h - 8, 3)
  let total = list.length(services)
  let n_up = list.length(list.filter(services, fn(s) { s.status == Up }))
  let n_down = list.length(list.filter(services, fn(s) { s.status == Down }))
  let n_warn = list.length(list.filter(services, fn(s) { s.status == Warn }))

  let buf = draw_tab_bar(buf, TabServices, w)

  // Title + right health badge (pulses red when DOWN services exist)
  let health_str =
    "● "
    <> int.to_string(n_up)
    <> "  ✖ "
    <> int.to_string(n_down)
    <> "  ▲ "
    <> int.to_string(n_warn)
  let health_w = string.length(health_str)
  let down_color = case n_down > 0 && frame / 8 % 2 == 0 {
    True -> c_red
    False -> c_dim
  }
  let buf =
    put1(buf, 2, 2, w - health_w - 4, [
      cy_b("SERVICES"),
      gap(3),
      dim(int.to_string(total) <> " services"),
    ])
  let buf =
    put1(buf, w - health_w - 2, 2, health_w + 2, [
      grn_b("● "),
      grn_b(int.to_string(n_up)),
      span.span_plain("  ✖ ") |> span.span_fg(down_color),
      span.span_plain(int.to_string(n_down))
        |> span.span_fg(down_color)
        |> span.span_modifier(style.bold()),
      dim("  ▲ "),
      amb_b(int.to_string(n_warn)),
    ])
  let buf = put1(buf, 0, 3, w, [dim(string.repeat("─", w))])

  // Column headers
  let buf =
    put1(buf, 1, 4, w - 2, [
      span.span_plain("   "),
      dim_b("STATUS "),
      gap(1),
      dim_b(string.pad_end("NAME", 18, " ")),
      gap(1),
      dim_b(string.pad_end("HOST", 14, " ")),
      gap(1),
      dim_b("CPU    "),
      gap(1),
      dim_b("MEM    "),
      gap(1),
      dim_b("UPTIME"),
    ])
  let buf = put1(buf, 0, 5, w, [dim(string.repeat("─", w))])

  // Rows
  let visible = services |> list.drop(offset) |> list.take(row_count)
  let row_lines =
    list.index_map(visible, fn(svc, i) {
      let selected = offset + i == cursor
      span.line_new([
        list_cursor(selected, frame),
        status_badge(svc.status, frame),
        gap(1),
        svc_name_span(svc, selected, frame),
        gap(1),
        dim(string.pad_end(svc.host, 14, " ")),
        gap(1),
        mini_bar(svc.cpu_pct, color_for_pct(svc.cpu_pct)),
        gap(1),
        mini_bar(svc.mem_pct, color_for_pct(svc.mem_pct)),
        gap(1),
        case svc.status {
          Down -> dim("  —    ")
          _ -> dcy(string.pad_end(svc.uptime, 7, " "))
        },
      ])
    })
  let buf =
    paragraph.render_styled(buf, rect_new(1, 6, w - 3, row_count), row_lines)

  let sb =
    scrollbar.scrollbar_new(total, row_count, offset)
    |> scrollbar.with_arrows("", "")
  let buf = scrollbar.render_vertical(buf, rect_new(w - 1, 6, 1, row_count), sb)

  let footer =
    list.flatten([
      hint("↑↓ jk", "MOVE"),
      [gap(2)],
      hint("↵", "DETAIL"),
      [gap(2)],
      hint("TAB", "SWITCH"),
      [gap(2)],
      hint("q", "QUIT"),
      [gap(3)],
      [dim(int.to_string(cursor + 1) <> "/" <> int.to_string(total))],
    ])
  draw_footer(buf, w, h, footer)
}

// ─── Events tab ──────────────────────────────────────────────────

fn render_events(model: Model, log_offset: Int, frame: Int) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let w = model.width
  let h = model.height
  let total = list.length(log_entries)
  let n_err = list.length(list.filter(log_entries, fn(e) { e.level == LError }))
  let n_warn = list.length(list.filter(log_entries, fn(e) { e.level == LWarn }))

  let buf = draw_tab_bar(buf, TabEvents, w)

  // Animated LIVE badge (● pulses green ↔ dim)
  let live_dot = case frame / 6 % 2 {
    0 -> grn_b("●")
    _ -> grn("○")
  }
  let buf =
    put1(buf, 2, 2, w - 14, [
      cy_b("EVENTS"),
      gap(3),
      dim(int.to_string(total) <> " entries"),
    ])
  let buf = put1(buf, w - 10, 2, 10, [live_dot, grn(" LIVE  ")])
  let buf = put1(buf, 0, 3, w, [dim(string.repeat("─", w))])

  // Alert bar: pulses when errors present
  let buf = case n_err > 0 {
    False -> buf
    True -> {
      let alert_bright = frame / 10 % 2 == 0
      let err_col = case alert_bright {
        True -> c_red
        False -> c_dim
      }
      put1(buf, 2, 4, w - 4, [
        span.span_plain("✖ " <> int.to_string(n_err) <> " error")
          |> span.span_fg(err_col)
          |> span.span_modifier(style.bold()),
        case n_err == 1 {
          True -> dim("")
          False -> dim("s")
        },
        case n_warn > 0 {
          True ->
            amb(
              "    ▲ "
              <> int.to_string(n_warn)
              <> " warning"
              <> case n_warn == 1 {
                True -> ""
                False -> "s"
              },
            )
          False -> span.span_plain("")
        },
      ])
    }
  }

  let col_y = case n_err > 0 {
    True -> 5
    False -> 4
  }
  let data_start = col_y + 2
  let row_count = int.max(h - data_start - 2, 3)

  let buf =
    put1(buf, 1, col_y, w - 2, [
      dim_b("TIME    "),
      gap(1),
      dim_b(" LEVEL  "),
      gap(1),
      dim_b(string.pad_end("SERVICE", 17, " ")),
      dim_b("MESSAGE"),
    ])
  let buf = put1(buf, 0, col_y + 1, w, [dim(string.repeat("─", w))])

  let visible = log_entries |> list.drop(log_offset) |> list.take(row_count)
  let rows =
    list.map(visible, fn(entry) {
      let time_s = case entry.level {
        LError -> {
          // Error timestamps pulse
          case frame / 8 % 2 {
            0 -> span.span_plain(entry.time) |> span.span_fg(c_red)
            _ ->
              span.span_plain(entry.time)
              |> span.span_fg(c_red)
              |> span.span_modifier(style.bold())
          }
        }
        LWarn -> amb(entry.time)
        _ -> dim(entry.time)
      }
      span.line_new([
        time_s,
        gap(1),
        case entry.level {
          LInfo -> grn(" INFO ")
          LWarn -> amb(" WARN ")
          LError -> red_b(" ERR  ")
          LDebug -> dim(" DBG  ")
        },
        gap(1),
        dcy(string.pad_end(entry.service, 17, " ")),
        case entry.level {
          LError -> span.span_plain(entry.message) |> span.span_fg(c_red)
          LWarn -> amb(entry.message)
          _ -> dim(entry.message)
        },
      ])
    })
  let buf =
    paragraph.render_styled(
      buf,
      rect_new(1, data_start, w - 3, row_count),
      rows,
    )

  let sb =
    scrollbar.scrollbar_new(total, row_count, log_offset)
    |> scrollbar.with_arrows("", "")
  let buf =
    scrollbar.render_vertical(
      buf,
      rect_new(w - 1, data_start, 1, row_count),
      sb,
    )

  let footer =
    list.flatten([
      hint("↑↓ jk", "SCROLL"),
      [gap(2)],
      hint("TAB", "SWITCH"),
      [gap(2)],
      hint("q", "QUIT"),
    ])
  draw_footer(buf, w, h, footer)
}

// ─── Metrics tab ─────────────────────────────────────────────────

fn render_metrics(model: Model, anim_st: anim.AnimState) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let w = model.width
  let h = model.height
  let frame = anim_st.frame
  let data_off = frame / 5
  let clock = fake_clock(frame)

  let buf = draw_tab_bar(buf, TabMetrics, w)

  // Ticking clock in header
  let buf =
    put1(buf, 2, 2, w - 14, [
      cy_b("METRICS"),
      gap(3),
      dim("20s window"),
    ])
  let buf =
    put1(buf, w - 12, 2, 12, [
      case frame / 6 % 2 {
        0 -> grn_b("●")
        _ -> grn("●")
      },
      grn(" "),
      dim(clock),
    ])
  let buf = put1(buf, 0, 3, w, [dim(string.repeat("─", w))])

  let chart_w = int.max(w - 16, 20)
  let val_x = chart_w + 3
  let val_w = int.max(w - chart_w - 5, 8)

  // REQ/S, animated gradient cyan → teal → blue
  let req = rotate_data(req_data, data_off)
  let cur_req = last_value(req)
  let buf =
    put1(buf, 2, 4, w - 4, [
      cy_b("REQ/S"),
      gap(2),
      dim("req per second · "),
      dcy("peak 242"),
    ])
  let buf =
    sparkline.render(
      buf,
      rect_new(2, 5, chart_w, 4),
      sparkline.sparkline_new(req)
        |> sparkline.with_fill(
          sparkline.SparkAnimated([c_blue, c_dcyan, c_cyan, c_cyan2]),
        ),
      frame,
    )
  let buf =
    put1(buf, val_x, 6, val_w, [cy_b(int.to_string(cur_req)), dim(" r/s")])

  // P95 LATENCY, animated gradient dark → cyan
  let lat = rotate_data(lat_data, data_off)
  let cur_lat = last_value(lat)
  let buf =
    put1(buf, 2, 10, w - 4, [
      cy_b("P95 ms"),
      gap(2),
      dim("response latency · "),
      dcy("peak 14ms"),
    ])
  let buf =
    sparkline.render(
      buf,
      rect_new(2, 11, chart_w, 4),
      sparkline.sparkline_new(lat)
        |> sparkline.with_fill(
          sparkline.SparkAnimated([c_dcyan, c_cyan3, c_cyan]),
        ),
      frame,
    )
  let lat_color = case cur_lat >= 12 {
    True -> c_amber
    False -> c_dcyan
  }
  let buf =
    put1(buf, val_x, 12, val_w, [
      span.span_plain(int.to_string(cur_lat)) |> span.span_fg(lat_color),
      dim(" ms"),
    ])

  // ERRORS/S, animated rainbow (very dramatic)
  let err = rotate_data(err_data, data_off)
  let cur_err = last_value(err)
  let buf =
    put1(buf, 2, 16, w - 4, [
      cy_b("ERRORS"),
      gap(2),
      dim("errors per second · "),
      case cur_err {
        0 -> grn("all clear")
        _ -> red_b("active!")
      },
    ])
  let buf =
    sparkline.render(
      buf,
      rect_new(2, 17, chart_w, 4),
      sparkline.sparkline_new(err)
        |> sparkline.with_fill(sparkline.SparkAnimatedRainbow),
      frame,
    )
  let buf =
    put1(buf, val_x, 18, val_w, [
      case cur_err {
        0 -> grn_b("0")
        n -> red_b(int.to_string(n))
      },
      dim(" e/s"),
    ])

  let footer =
    list.flatten([
      hint("TAB", "SWITCH"),
      [gap(2)],
      hint("q", "QUIT"),
      [gap(4)],
      [dim("gradients animate in real time")],
    ])
  draw_footer(buf, w, h, footer)
}

// ─── About tab ───────────────────────────────────────────────────

fn render_about(model: Model, frame: Int) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let w = model.width
  let h = model.height
  let indent = int.max(w / 2 - 28, 2)
  let cw = w - indent * 2

  let buf = draw_tab_bar(buf, TabAbout, w)
  let buf =
    put1(buf, 2, 2, w - 4, [
      cy_b("ABOUT"),
      gap(3),
      dim("etui — TUI framework for Gleam"),
    ])
  let buf = put1(buf, 0, 3, w, [dim(string.repeat("─", w))])

  let buf =
    put1(buf, indent, 5, cw, [
      cy_b("GATUI"),
      gap(3),
      case frame / 8 % 2 {
        0 -> pk_b("The TUI framework for Gleam on BEAM")
        _ -> pk("The TUI framework for Gleam on BEAM")
      },
    ])
  let buf =
    put1(buf, indent, 6, cw, [
      dcy("Pure Gleam · Type-safe · No terminal left broken"),
    ])
  let buf = put1(buf, indent, 7, cw, [dim(string.repeat("─", int.min(cw, 52)))])

  let features = [
    #("run_animated", "event loop with auto-managed AnimState"),
    #("sparkline", "block-char charts — animated gradient or rainbow fill"),
    #("gauge", "progress bar, custom color, label overlay"),
    #("tabs", "tab bar with active highlight and color control"),
    #("span + line", "rich inline styled text, color + modifier per span"),
    #("buffer + diff", "dense cell grid, minimal ANSI patches per frame"),
    #("scrollbar", "scroll indicator overlay, configurable arrows"),
    #("paragraph", "word-wrap, alignment, styled line rendering"),
  ]
  let buf = put1(buf, indent, 9, cw, [dim_b("WIDGETS IN USE")])
  let buf =
    list.index_fold(features, buf, fn(b, f, i) {
      let #(name, desc) = f
      put1(b, indent, 10 + i, cw, [
        cy_b(string.pad_end(name, 14, " ")),
        dim(desc),
      ])
    })

  let key_hints = [
    #("↑↓  j k", "navigate lists"),
    #("↵", "open service detail"),
    #("TAB", "cycle tabs"),
    #("q", "quit"),
  ]
  let buf = put1(buf, indent, 20, cw, [dim_b("KEYS")])
  let buf =
    list.index_fold(key_hints, buf, fn(b, kh, i) {
      let #(key, label) = kh
      put1(b, indent, 21 + i, cw, [
        cy_r(" " <> key <> " "),
        gap(2),
        dim(label),
      ])
    })

  let footer =
    list.flatten([hint("TAB", "SWITCH"), [gap(2)], hint("q", "QUIT")])
  draw_footer(buf, w, h, footer)
}

// ─── Detail screen ───────────────────────────────────────────────

fn render_detail(model: Model, svc: Service, frame: Int) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let w = model.width
  let h = model.height
  let frame_w = int.min(64, w - 4)
  let cx = int.max(w / 2 - frame_w / 2, 2)
  let cy_ = int.max(h / 2 - 10, 1)
  let inner_w = frame_w - 6

  // Box drawing
  let top =
    "╔══ SERVICE DETAIL " <> string.repeat("═", int.max(frame_w - 20, 0)) <> "╗"
  let mid = "╠" <> string.repeat("═", frame_w - 2) <> "╣"
  let bottom = "╚" <> string.repeat("═", frame_w - 2) <> "╝"
  let side = "║  "
  let side_r = "  ║"
  let blank = side <> string.repeat(" ", frame_w - 4) <> "║"

  // Box color pulses for WARN/DOWN
  let box_col = case svc.status {
    Up -> c_cyan
    Down ->
      case frame / 8 % 2 {
        0 -> c_red
        _ -> c_dim
      }
    Warn ->
      case frame / 10 % 2 {
        0 -> c_amber
        _ -> c_dim
      }
  }
  let bx = fn(s: String) { span.span_plain(s) |> span.span_fg(box_col) }

  let buf = put1(buf, cx, cy_, frame_w, [bx(top)])

  // Service name, colored by status
  let name_col = case svc.status {
    Up -> wht_b(string.pad_end(svc.name, inner_w, " "))
    Down -> red_b(string.pad_end(svc.name, inner_w, " "))
    Warn -> amb_b(string.pad_end(svc.name, inner_w, " "))
  }
  let buf = put1(buf, cx, cy_ + 1, frame_w, [bx(side), name_col, bx(side_r)])
  let buf =
    put1(buf, cx, cy_ + 2, frame_w, [
      bx(side),
      dim(string.pad_end(svc.version, inner_w, " ")),
      bx(side_r),
    ])

  // Status row with animated badge
  let buf = put1(buf, cx, cy_ + 3, frame_w, [bx(mid)])
  let status_s = status_badge(svc.status, frame)
  let buf =
    put1(buf, cx, cy_ + 4, frame_w, [
      bx(side),
      dim_b(string.pad_end("STATUS", 10, " ")),
      status_s,
      span.span_plain(string.repeat(
        " ",
        int.max(inner_w - 10 - svc_status_chars(svc.status), 0),
      )),
      bx(side_r),
    ])

  // Data fields
  let data_rows = [
    #("HOST", svc.host),
    #("UPTIME", svc.uptime),
    #("INFO", svc.info),
  ]
  let buf =
    list.index_fold(data_rows, buf, fn(b, dr, i) {
      let #(label, value) = dr
      let val_w = int.min(string.length(value), inner_w - 10)
      let pad = int.max(inner_w - 10 - val_w, 0)
      put1(b, cx, cy_ + 5 + i, frame_w, [
        bx(side),
        dim_b(string.pad_end(label, 10, " ")),
        cy_b(string.slice(value, 0, val_w)),
        span.span_plain(string.repeat(" ", pad)),
        bx(side_r),
      ])
    })

  // Resource gauges
  let buf = put1(buf, cx, cy_ + 8, frame_w, [bx(mid)])
  let gauge_w = frame_w - 8

  let buf = put1(buf, cx, cy_ + 9, frame_w, [bx(blank)])
  let cpu_g =
    gauge.gauge_new(svc.cpu_pct)
    |> gauge.with_label("CPU  " <> int.to_string(svc.cpu_pct) <> "%")
    |> gauge.with_colors(color_for_pct(svc.cpu_pct), style.Default)
  let buf = gauge.render(buf, rect_new(cx + 4, cy_ + 9, gauge_w, 1), cpu_g)

  let buf = put1(buf, cx, cy_ + 10, frame_w, [bx(blank)])
  let mem_g =
    gauge.gauge_new(svc.mem_pct)
    |> gauge.with_label("MEM  " <> int.to_string(svc.mem_pct) <> "%")
    |> gauge.with_colors(color_for_pct(svc.mem_pct), style.Default)
  let buf = gauge.render(buf, rect_new(cx + 4, cy_ + 10, gauge_w, 1), mem_g)

  let buf = put1(buf, cx, cy_ + 11, frame_w, [bx(blank)])
  let buf = put1(buf, cx, cy_ + 12, frame_w, [bx(bottom)])

  let back_hints =
    list.flatten([hint("← h ESC", "BACK"), [gap(2)], hint("q", "QUIT")])
  put1(buf, cx, cy_ + 13, frame_w, back_hints)
}

// ─── Render dispatcher ───────────────────────────────────────────

fn render(
  model: Model,
  screen: Rect,
  anim_st: anim.AnimState,
) -> buffer.Buffer {
  let model =
    Model(..model, width: screen.size.width, height: screen.size.height)
  let frame = anim_st.frame
  case model.screen {
    Boot -> render_boot(model, anim_st)
    Dashboard(tab, c, o, lo) ->
      case tab {
        TabServices -> render_services(model, c, o, frame)
        TabEvents -> render_events(model, lo, frame)
        TabMetrics -> render_metrics(model, anim_st)
        TabAbout -> render_about(model, frame)
      }
    Detail(svc, _, _) -> render_detail(model, svc, frame)
  }
}

// ─── Update ──────────────────────────────────────────────────────

fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.Resize(w, h) -> Model(..model, width: w, height: h)
    _ ->
      case model.screen {
        Boot ->
          case event {
            backend.KeyPress(_) ->
              Model(..model, screen: Dashboard(TabServices, 0, 0, 0))
            _ -> model
          }

        Dashboard(tab, c, o, lo) -> {
          let row_count = int.max(model.height - 8, 3)
          let total_svcs = list.length(services)
          let total_logs = list.length(log_entries)
          case event {
            backend.KeyPress("q") -> Model(..model, quit: True)
            backend.KeyPress("tab") ->
              Model(..model, screen: Dashboard(next_tab(tab), c, o, lo))
            backend.KeyPress("j") | backend.KeyPress("down") ->
              case tab {
                TabServices -> {
                  let nc = int.min(c + 1, int.max(total_svcs - 1, 0))
                  Model(
                    ..model,
                    screen: Dashboard(
                      tab,
                      nc,
                      list_widget.effective_offset(
                        list_widget.ListState(selected: nc, offset: o),
                        row_count,
                      ),
                      lo,
                    ),
                  )
                }
                TabEvents -> {
                  let nlo = int.min(lo + 1, int.max(total_logs - row_count, 0))
                  Model(..model, screen: Dashboard(tab, c, o, nlo))
                }
                _ -> model
              }
            backend.KeyPress("k") | backend.KeyPress("up") ->
              case tab {
                TabServices -> {
                  let nc = int.max(c - 1, 0)
                  Model(
                    ..model,
                    screen: Dashboard(
                      tab,
                      nc,
                      list_widget.effective_offset(
                        list_widget.ListState(selected: nc, offset: o),
                        row_count,
                      ),
                      lo,
                    ),
                  )
                }
                TabEvents -> {
                  let nlo = int.max(lo - 1, 0)
                  Model(..model, screen: Dashboard(tab, c, o, nlo))
                }
                _ -> model
              }
            backend.KeyPress("enter") ->
              case tab {
                TabServices ->
                  case list.drop(services, c) {
                    [svc, ..] -> Model(..model, screen: Detail(svc, c, o))
                    [] -> model
                  }
                _ -> model
              }
            _ -> model
          }
        }

        Detail(_, back_c, back_o) ->
          case event {
            backend.KeyPress("q") -> Model(..model, quit: True)
            backend.KeyPress("h")
            | backend.KeyPress("esc")
            | backend.KeyPress("left") ->
              Model(..model, screen: Dashboard(TabServices, back_c, back_o, 0))
            _ -> model
          }
      }
  }
}

// ─── Entry point ─────────────────────────────────────────────────

pub fn main() -> Nil {
  let _ =
    app.run_animated(
      default.new(),
      initial_model(),
      render,
      update,
      fn(m) { m.quit },
      80,
    )
  Nil
}
