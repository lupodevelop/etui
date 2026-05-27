/// GLEAMFALL TUI mock, phosphor-green retro NASA NEO tracker.
///
/// Run: gleam run -m etui_gleamfall
/// Screens: Boot → KeyPrompt → Loading → NeoListView ↔ Detail
///          NeoListView → SearchPrompt (/) → NeoListView
///          NeoListView → ChartsView (c) → NeoListView
/// Keys: j/k navigate; ↵ detail; / search; h haz; s sort; c charts; x reset; q quit.
import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/geometry.{rect_new}
import etui/keys
import etui/span
import etui/style
import etui/widgets/gauge
import etui/widgets/input as input_widget
import etui/widgets/list as list_widget
import etui/widgets/paragraph
import etui/widgets/scrollbar
import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ─── Color palette ────────────────────────────────────────────────

const c_phos = style.Indexed(46)

const c_dphos = style.Indexed(34)

const c_pink = style.Indexed(213)

const c_spink = style.Indexed(218)

const c_dim = style.Indexed(240)

// ─── Span helpers ─────────────────────────────────────────────────

fn phos(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_phos)
}

fn phos_b(s: String) -> span.Span {
  phos(s) |> span.span_modifier(style.bold())
}

fn phos_r(s: String) -> span.Span {
  phos(s) |> span.span_modifier(style.reverse())
}

fn dphos(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_dphos)
}

fn pk(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_pink)
}

fn pk_b(s: String) -> span.Span {
  pk(s) |> span.span_modifier(style.bold())
}

fn pk_r(s: String) -> span.Span {
  pk(s) |> span.span_modifier(style.reverse())
}

fn spk(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_spink)
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

fn hint(key: String, label: String) -> List(span.Span) {
  [phos_r(" " <> key <> " "), dim(" " <> label)]
}

fn hint_pk(key: String, label: String) -> List(span.Span) {
  [pk_r(" " <> key <> " "), dim(" " <> label)]
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

// ─── Fake NEO data ────────────────────────────────────────────────

pub type Neo {
  Neo(
    name: String,
    magnitude: Float,
    diameter_km: Float,
    velocity_kms: Float,
    is_hazardous: Bool,
    is_sentry: Bool,
    approach_date: String,
    miss_dist_ld: Float,
  )
}

const fake_neos: List(Neo) = [
  Neo("(2024 YR4)", 26.7, 0.057, 17.3, True, True, "2024-01-01", 0.06),
  Neo("(2003 QQ47)", 20.5, 1.2, 22.1, True, False, "2024-01-01", 3.2),
  Neo("(2024 BX1)", 29.3, 0.009, 8.6, False, False, "2024-01-02", 0.001),
  Neo("433 Eros", 11.2, 16.8, 24.4, False, False, "2024-01-02", 44.0),
  Neo("(2024 PT5)", 27.1, 0.011, 0.5, False, False, "2024-01-03", 0.003),
  Neo("(2025 AA1)", 24.8, 0.085, 31.2, True, False, "2024-01-03", 15.8),
  Neo("(2023 DW)", 25.1, 0.049, 15.7, False, True, "2024-01-04", 1.2),
  Neo("(2024 MK)", 23.9, 0.18, 19.5, True, False, "2024-01-04", 8.4),
  Neo("(2019 OK)", 22.8, 0.26, 24.0, True, False, "2024-01-05", 0.62),
  Neo("(2021 UA1)", 28.4, 0.002, 0.2, False, False, "2024-01-05", 0.0002),
  Neo("(2020 SW)", 26.9, 0.004, 7.9, False, False, "2024-01-06", 0.013),
  Neo("(2022 AP7)", 17.9, 1.1, 30.6, True, True, "2024-01-06", 70.0),
  Neo("(2023 TL4)", 25.5, 0.031, 11.3, False, False, "2024-01-06", 2.1),
  Neo("(2024 GJ2)", 24.2, 0.13, 20.8, True, False, "2024-01-07", 5.3),
  Neo("(2018 LV3)", 23.4, 0.17, 16.5, False, False, "2024-01-07", 12.7),
]

// ─── Filter & Sort ────────────────────────────────────────────────

pub type SortKey {
  SortName
  SortMagnitude
  SortDiameter
  SortVelocity
}

pub type Filter {
  Filter(hazard_only: Bool, sort_by: SortKey, search: String)
}

fn apply_filter(neos: List(Neo), f: Filter) -> List(Neo) {
  neos
  |> list.filter(fn(n) {
    case f.hazard_only {
      True -> n.is_hazardous
      False -> True
    }
  })
  |> list.filter(fn(n) {
    case f.search {
      "" -> True
      q -> string.contains(string.lowercase(n.name), string.lowercase(q))
    }
  })
  |> sort_neos(f.sort_by)
}

fn sort_neos(neos: List(Neo), by: SortKey) -> List(Neo) {
  case by {
    SortName -> list.sort(neos, fn(a, b) { string.compare(a.name, b.name) })
    SortMagnitude ->
      list.sort(neos, fn(a, b) { float.compare(a.magnitude, b.magnitude) })
    SortDiameter ->
      list.sort(neos, fn(a, b) { float.compare(b.diameter_km, a.diameter_km) })
    SortVelocity ->
      list.sort(neos, fn(a, b) { float.compare(b.velocity_kms, a.velocity_kms) })
  }
}

fn cycle_sort(s: SortKey) -> SortKey {
  case s {
    SortName -> SortMagnitude
    SortMagnitude -> SortDiameter
    SortDiameter -> SortVelocity
    SortVelocity -> SortName
  }
}

fn sort_label(s: SortKey) -> String {
  case s {
    SortName -> "NAME"
    SortMagnitude -> "MAG"
    SortDiameter -> "SIZE"
    SortVelocity -> "VEL"
  }
}

// ─── Model ────────────────────────────────────────────────────────

pub type Screen {
  Boot
  KeyPrompt(api_input: input_widget.InputState)
  Loading(progress: Int)
  NeoListView(cursor: Int, offset: Int)
  SearchPrompt(buffer: String, back_cursor: Int, back_offset: Int)
  ChartsView(back_cursor: Int, back_offset: Int)
  Detail(neo: Neo, back_cursor: Int, back_offset: Int)
}

pub type Model {
  Model(screen: Screen, filter: Filter, width: Int, height: Int, quit: Bool)
}

fn initial_model() -> Model {
  Model(
    screen: Boot,
    filter: Filter(hazard_only: False, sort_by: SortName, search: ""),
    width: 80,
    height: 24,
    quit: False,
  )
}

// ─── Boot screen ─────────────────────────────────────────────────

const banner_lines: List(String) = [
  " ██████  ██      ███████  █████  ███    ███ ███████  █████  ██      ██",
  "██       ██      ██      ██   ██ ████  ████ ██      ██   ██ ██      ██",
  "██   ███ ██      █████   ███████ ██ ████ ██ █████   ███████ ██      ██",
  "██    ██ ██      ██      ██   ██ ██  ██  ██ ██      ██   ██ ██      ██",
  " ██████  ███████ ███████ ██   ██ ██      ██ ██      ██   ██ ███████ ███████",
]

const boot_checks: List(String) = [
  "POWER-ON SELF-TEST",
  "LOAD ASTROMETRIC LIBRARY",
  "ESTABLISH NASA NEoWs LINK",
  "INITIALIZE TERMLINK INTERFACE",
  "MOUNT VAULT-TEC SUBSYSTEM",
]

fn render_boot(model: Model) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let content_h =
    list.length(banner_lines) + 3 + 1 + list.length(boot_checks) + 3
  let top_y = int.max(model.height / 2 - content_h / 2, 1)
  let indent = int.max(model.width / 2 - 36, 2)
  let content_w = model.width - indent * 2

  let banner_lines_ =
    list.map(banner_lines, fn(line) { span.line_new([phos_b(line)]) })
  let buf =
    paragraph.render_styled(
      buf,
      rect_new(indent, top_y, content_w, list.length(banner_lines)),
      banner_lines_,
    )

  let info_y = top_y + list.length(banner_lines) + 1
  let buf =
    put1(buf, indent, info_y, content_w, [
      phos_b("ROBCO INDUSTRIES (TM) TERMLINK PROTOCOL"),
    ])
  let buf =
    put1(buf, indent, info_y + 1, content_w, [
      dphos("NEAR-EARTH OBJECT TRACKING SUBSYSTEM v0.1.0"),
    ])
  let buf =
    put1(buf, indent, info_y + 2, content_w, [
      dim("-- COPYRIGHT 2026 GLEAMFALL (MOCK) --"),
    ])

  let checks_y = info_y + 4
  let check_lines =
    list.map(boot_checks, fn(label) {
      let dotted = string.pad_end(label, 38, ".")
      span.line_new([
        dim("> "),
        phos(dotted),
        phos(" ["),
        phos_b("OK"),
        phos("]"),
      ])
    })
  let buf =
    paragraph.render_styled(
      buf,
      rect_new(indent, checks_y, content_w, list.length(boot_checks)),
      check_lines,
    )

  let prompt_y = checks_y + list.length(boot_checks) + 2
  put1(buf, indent, prompt_y, content_w, [
    pk_b("> PRESS ANY KEY TO PROCEED "),
    pk_r(" ▌ "),
  ])
}

// ─── KeyPrompt screen ─────────────────────────────────────────────

fn render_key_prompt(
  model: Model,
  inp: input_widget.InputState,
) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let frame_w = int.min(60, model.width - 4)
  let cx = int.max(model.width / 2 - frame_w / 2, 2)
  let cy = int.max(model.height / 2 - 5, 1)

  let title_pad = int.max(frame_w - 4 - 20, 0)
  let top = "═══ ENTER NASA API KEY " <> string.repeat("═", title_pad) <> "═"
  let bottom = string.repeat("═", frame_w)

  let buf = put1(buf, cx, cy, frame_w, [phos_b(top)])

  let #(key_text, key_span) = case inp.value {
    "" -> #(string.pad_end("(start typing...)", frame_w - 12, " "), fn(s) {
      dim(s)
    })
    v -> #(
      string.pad_end(string.repeat("•", string.length(v)), frame_w - 12, " "),
      fn(s) { pk(s) },
    )
  }
  let buf =
    put1(buf, cx + 4, cy + 2, frame_w - 4, [
      dim("KEY ▸ "),
      key_span(key_text),
      pk_r(" "),
    ])

  let hints =
    list.flatten([
      hint("ENTER", "CONFIRM"),
      [gap(3)],
      hint("ESC", "DEMO KEY"),
      [gap(3)],
      hint("^C", "QUIT"),
    ])
  let buf = put1(buf, cx + 4, cy + 4, frame_w - 4, hints)
  let buf = put1(buf, cx, cy + 6, frame_w, [phos(bottom)])
  put1(buf, cx + 4, cy + 7, frame_w - 4, [
    dim("✎ KEY WILL BE SAVED TO "),
    dphos("./.env"),
    dim(" (NASA_API_KEY=...)"),
  ])
}

// ─── Loading screen ───────────────────────────────────────────────

const loading_steps: List(String) = [
  "INITIALIZING...",
  "QUERYING api.nasa.gov...",
  "PARSING ORBITAL DATA...",
  "SORTING BY APPROACH DATE...",
  "READY.",
]

fn render_loading(model: Model, progress: Int) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let frame_w = int.min(64, model.width - 4)
  let cx = int.max(model.width / 2 - frame_w / 2, 2)
  let cy = int.max(model.height / 2 - 4, 1)

  let pad = int.max(frame_w - 21, 0)
  let top = "═══ LOADING NEO FEED " <> string.repeat("═", pad)
  let bottom = string.repeat("═", frame_w)

  let buf = put1(buf, cx, cy, frame_w, [pk_b(top)])
  let buf =
    put1(buf, cx + 4, cy + 2, frame_w - 4, [
      pk_b("⠿  "),
      phos_b("FETCHING NEAR-EARTH OBJECTS"),
    ])
  let buf =
    put1(buf, cx + 4, cy + 3, frame_w - 4, [
      dim("   range  "),
      dphos("2024-01-01 → 2024-01-07"),
    ])

  let g =
    gauge.gauge_new(progress)
    |> gauge.with_label(int.to_string(progress) <> "%")
    |> gauge.with_colors(c_pink, style.Default)
  let buf = gauge.render(buf, rect_new(cx + 4, cy + 5, frame_w - 8, 1), g)

  let n_steps = list.length(loading_steps)
  let step_idx = int.min(progress * n_steps / 101, n_steps - 1)
  let step_label = case list.drop(loading_steps, step_idx) {
    [s, ..] -> s
    [] -> "READY."
  }
  let buf = put1(buf, cx + 4, cy + 6, frame_w - 4, [dim(step_label)])
  put1(buf, cx, cy + 8, frame_w, [pk(bottom)])
}

// ─── NeoListView screen ───────────────────────────────────────────

fn neo_row(neo: Neo, selected: Bool, max_dia: Float) -> span.Line {
  let cursor_s = case selected {
    True -> pk_b("▌▌ ")
    False -> span.span_plain("   ")
  }
  let glyph_s = case neo.is_hazardous, neo.is_sentry {
    True, _ -> pk_b("☢")
    False, True -> spk("◎")
    False, False -> dim("·")
  }
  let name_field = string.pad_end(neo.name, 26, " ")
  let name_s = case selected {
    True -> pk_r(name_field)
    False -> phos(name_field)
  }
  span.line_new([
    cursor_s,
    glyph_s,
    gap(2),
    name_s,
    gap(2),
    dphos(string.pad_end(float_1(neo.magnitude), 5, " ")),
    gap(2),
    pk(diameter_bar(neo.diameter_km, max_dia, 10)),
    gap(2),
    dphos(string.pad_end(diameter_label(neo.diameter_km), 8, " ")),
    gap(2),
    dphos(float_2(neo.velocity_kms)),
  ])
}

fn build_filter_spans(f: Filter, visible: Int, total: Int) -> List(span.Span) {
  let haz_part = case f.hazard_only {
    False -> []
    True -> [pk_b("[HAZ]"), gap(1)]
  }
  let search_part = case f.search {
    "" -> []
    q -> [pk("[/" <> q <> "]"), gap(1)]
  }
  let sort_part = [dim("[sort:"), spk(sort_label(f.sort_by)), dim("]")]
  let count_part = case visible == total {
    True -> []
    False -> [
      gap(1),
      dim("("),
      pk(int.to_string(visible)),
      dim("/"),
      dim(int.to_string(total)),
      dim(")"),
    ]
  }
  list.flatten([haz_part, search_part, sort_part, count_part])
}

fn render_neo_list(model: Model, cursor: Int, offset: Int) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let all_neos = fake_neos
  let visible_neos = apply_filter(all_neos, model.filter)
  let total_all = list.length(all_neos)
  let total_vis = list.length(visible_neos)
  let hazardous = list.length(list.filter(all_neos, fn(n) { n.is_hazardous }))
  let sentries = list.length(list.filter(all_neos, fn(n) { n.is_sentry }))
  let max_dia = compute_max_dia(visible_neos)
  let w = model.width - 4

  let buf =
    put1(buf, 2, 1, w, [
      phos_b("GLEAMFALL"),
      dim(" :: "),
      dphos("NEO TRACKING"),
      gap(4),
      dim("2024-01-01 → 2024-01-07"),
    ])
  let buf = put1(buf, 2, 2, w, [phos(string.repeat("═", w))])

  let filter_spans = build_filter_spans(model.filter, total_vis, total_all)
  let buf =
    put1(
      buf,
      2,
      3,
      w,
      list.flatten([
        [
          dim("TRACKED "),
          phos_b(int.to_string(total_all)),
          dim("    ☢ "),
          case hazardous {
            0 -> dim("0")
            n -> pk_b(int.to_string(n))
          },
          dim("   ◎ "),
          case sentries {
            0 -> dim("0")
            n -> spk(int.to_string(n))
          },
          gap(3),
        ],
        filter_spans,
      ]),
    )

  let header_cols = [
    gap(4),
    dim_b("ST  "),
    dim_b(string.pad_end("NAME", 28, " ")),
    dim_b(string.pad_end("MAG", 7, " ")),
    dim_b(string.pad_end("REL.SIZE", 12, " ")),
    dim_b(string.pad_end("DIAMETER", 10, " ")),
    dim_b("V(km/s)"),
  ]
  let buf = put1(buf, 2, 4, w, header_cols)
  let buf = put1(buf, 2, 5, w, [dim(string.repeat("─", w))])

  let row_count = int.max(model.height - 9, 3)
  let buf = case total_vis {
    0 -> {
      let msg_y = model.height / 2 - 1
      let msg_x = int.max(model.width / 2 - 18, 2)
      let buf =
        put1(buf, msg_x, msg_y, 38, [pk("· NO RESULTS — CHANGE FILTERS ·")])
      put1(
        buf,
        msg_x,
        msg_y + 2,
        36,
        list.flatten([
          hint("x", "CLEAR FILTERS"),
          [gap(2)],
          hint("h", "TOGGLE HAZ"),
        ]),
      )
    }
    _ -> {
      let visible = visible_neos |> list.drop(offset) |> list.take(row_count)
      let row_lines =
        list.index_map(visible, fn(neo, i) {
          neo_row(neo, offset + i == cursor, max_dia)
        })
      paragraph.render_styled(buf, rect_new(2, 6, w - 1, row_count), row_lines)
    }
  }

  let sb =
    scrollbar.scrollbar_new(total_vis, row_count, offset)
    |> scrollbar.with_arrows("", "")
  let buf =
    scrollbar.render_vertical(
      buf,
      rect_new(model.width - 2, 6, 1, row_count),
      sb,
    )

  let buf = put1(buf, 2, model.height - 2, w, [dim(string.repeat("─", w))])
  let cursor_display = case total_vis {
    0 -> "0/0"
    _ -> int.to_string(cursor + 1) <> "/" <> int.to_string(total_vis)
  }
  let footer =
    list.flatten([
      hint("↑↓", "MOVE"),
      [gap(2)],
      hint("↵", "DETAIL"),
      [gap(2)],
      hint("/", "FIND"),
      [gap(2)],
      hint_pk("h", "HAZ"),
      [gap(2)],
      hint_pk("s", "SORT:" <> sort_label(model.filter.sort_by)),
      [gap(2)],
      hint_pk("c", "CHARTS"),
      [gap(2)],
      hint("x", "RESET"),
      [gap(2)],
      hint("q", "QUIT"),
      [gap(2)],
      [dim(cursor_display)],
    ])
  put1(buf, 2, model.height - 1, w, footer)
}

// ─── SearchPrompt screen ──────────────────────────────────────────

fn render_search(model: Model, search_buf: String) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let frame_w = int.min(60, model.width - 4)
  let cx = int.max(model.width / 2 - frame_w / 2, 2)
  let cy = int.max(model.height / 2 - 4, 1)

  let title_pad = int.max(frame_w - 4 - 16, 0)
  let top = "═══ FILTER BY NAME " <> string.repeat("═", title_pad) <> "═"
  let bottom = string.repeat("═", frame_w)

  let buf = put1(buf, cx, cy, frame_w, [pk_b(top)])
  let input_pad =
    string.repeat(" ", int.max(frame_w - 12 - string.length(search_buf), 0))
  let buf =
    put1(buf, cx + 4, cy + 2, frame_w - 4, [
      dim("MATCH ▸ "),
      pk(search_buf),
      pk_r(" "),
      dim(input_pad),
    ])
  let buf =
    put1(
      buf,
      cx + 4,
      cy + 4,
      frame_w - 4,
      list.flatten([
        hint("ENTER", "APPLY"),
        [gap(3)],
        hint("ESC", "CANCEL"),
        [gap(3)],
        hint("⌫", "DELETE"),
      ]),
    )
  let buf = put1(buf, cx, cy + 6, frame_w, [pk(bottom)])
  put1(buf, cx + 4, cy + 7, frame_w - 4, [
    dim("substring match · case-insensitive · 2024-01-01 → 2024-01-07"),
  ])
}

// ─── ChartsView screen ────────────────────────────────────────────

type DayBucket {
  DayBucket(date: String, count: Int, hazardous: Int, max_miss_ld: Float)
}

const chart_dates: List(String) = [
  "2024-01-01",
  "2024-01-02",
  "2024-01-03",
  "2024-01-04",
  "2024-01-05",
  "2024-01-06",
  "2024-01-07",
]

fn bucket_by_day(neos: List(Neo)) -> List(DayBucket) {
  list.map(chart_dates, fn(date) {
    let day_neos = list.filter(neos, fn(n) { n.approach_date == date })
    let count = list.length(day_neos)
    let haz = list.length(list.filter(day_neos, fn(n) { n.is_hazardous }))
    let max_ld =
      list.fold(day_neos, 0.0, fn(acc, n) {
        case n.miss_dist_ld >. acc {
          True -> n.miss_dist_ld
          False -> acc
        }
      })
    DayBucket(date: date, count: count, hazardous: haz, max_miss_ld: max_ld)
  })
}

fn short_date(iso: String) -> String {
  case string.split(iso, "-") {
    [_, mm, dd] -> mm <> "/" <> dd
    _ -> iso
  }
}

fn render_distance_scatter(
  neos: List(Neo),
  chart_w: Int,
) -> List(List(span.Span)) {
  let buckets = bucket_by_day(neos)
  let max_ld =
    list.fold(buckets, 0.0, fn(acc, b) {
      case b.max_miss_ld >. acc {
        True -> b.max_miss_ld
        False -> acc
      }
    })
  let bar_w = int.max(chart_w - 16, 10)
  list.map(buckets, fn(b) {
    let scale = case max_ld >. 0.0 {
      True -> int.to_float(bar_w) /. max_ld
      False -> 1.0
    }
    let bar_len = int.clamp(float_round(b.max_miss_ld *. scale), 0, bar_w)
    let bar_chars = string.repeat("█", bar_len)
    let pad_chars = string.repeat(" ", int.max(bar_w - bar_len, 0))
    let bar_span = case b.hazardous > 0 {
      True -> pk(bar_chars)
      False -> phos(bar_chars)
    }
    let haz_tag = case b.hazardous {
      0 -> [gap(2), dim("   ")]
      n -> [gap(2), pk_b("☢" <> int.to_string(n))]
    }
    let count_s = string.pad_start("(" <> int.to_string(b.count) <> ")", 4, " ")
    let ld_s = case b.count {
      0 -> string.pad_end("─", 8, " ")
      _ -> string.pad_end(float_1(b.max_miss_ld) <> " LD", 8, " ")
    }
    list.flatten([
      [
        dphos(short_date(b.date)),
        gap(2),
        bar_span,
        span.span_plain(pad_chars),
        gap(1),
        dim(count_s),
        gap(2),
        dphos(ld_s),
      ],
      haz_tag,
    ])
  })
}

fn render_size_histogram(
  neos: List(Neo),
  chart_w: Int,
) -> List(List(span.Span)) {
  let bins = [
    #("< 50 m", fn(d: Float) { d <. 0.05 }),
    #("50 – 200 m", fn(d) { d >=. 0.05 && d <. 0.2 }),
    #("200 m – 1 km", fn(d) { d >=. 0.2 && d <. 1.0 }),
    #("1 – 5 km", fn(d) { d >=. 1.0 && d <. 5.0 }),
    #("> 5 km", fn(d) { d >=. 5.0 }),
  ]
  let counts =
    list.map(bins, fn(b) {
      let #(label, pred) = b
      #(label, list.length(list.filter(neos, fn(n) { pred(n.diameter_km) })))
    })
  let max_count =
    list.fold(counts, 0, fn(acc, c) {
      case c.1 > acc {
        True -> c.1
        False -> acc
      }
    })
  let bar_w = int.max(chart_w - 22, 8)
  list.map(counts, fn(c) {
    let #(label, count) = c
    let filled = case max_count {
      0 -> 0
      m -> count * bar_w / m
    }
    let bar_s = string.repeat("█", filled)
    let empty_s = string.repeat("░", int.max(bar_w - filled, 0))
    let pad_label = string.pad_end(label, 16, " ")
    let count_str = "(" <> int.to_string(count) <> ")"
    case count {
      0 -> [dim(pad_label), gap(2), dim(empty_s), gap(2), dim(count_str)]
      _ -> [
        dphos(pad_label),
        gap(2),
        pk(bar_s),
        dim(empty_s),
        gap(2),
        dim(count_str),
      ]
    }
  })
}

fn render_charts(model: Model) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let neos = apply_filter(fake_neos, model.filter)
  let inner_w = model.width - 4
  let chart_w = int.max(inner_w - 6, 24)

  let buf =
    put1(buf, 2, 1, inner_w, [
      phos_b("GLEAMFALL"),
      dim(" :: "),
      dphos("DATA VISUALIZATION"),
      gap(4),
      dim("2024-01-01 → 2024-01-07"),
    ])
  let buf = put1(buf, 2, 2, inner_w, [phos(string.repeat("═", inner_w))])

  let buf =
    put1(buf, 2, 3, inner_w, [
      dphos("─── CLOSEST APPROACH PER DAY  "),
      dim("(bar = max miss distance in LD)"),
    ])
  let buf =
    put1(buf, 4, 4, inner_w - 2, [
      dim("longer bar = farther  "),
      pk("pink"),
      dim(" = day with ☢ NEO"),
    ])

  let scatter_lines = render_distance_scatter(neos, chart_w)
  let scatter_h = list.length(scatter_lines)
  let buf =
    paragraph.render_styled(
      buf,
      rect_new(4, 5, inner_w - 2, scatter_h),
      list.map(scatter_lines, fn(line) { span.line_new(line) }),
    )

  let hist_y = 5 + scatter_h + 1
  let buf =
    put1(buf, 2, hist_y, inner_w, [
      dphos("─── SIZE DISTRIBUTION  "),
      dim("(NEO count per diameter bin)"),
    ])
  let hist_lines = render_size_histogram(neos, chart_w)
  let hist_h = list.length(hist_lines)
  let buf =
    paragraph.render_styled(
      buf,
      rect_new(4, hist_y + 1, inner_w - 2, hist_h),
      list.map(hist_lines, fn(line) { span.line_new(line) }),
    )

  let buf =
    put1(buf, 2, model.height - 2, inner_w, [
      dim(string.repeat("─", inner_w)),
    ])
  let footer =
    list.flatten([
      hint("b/ESC/c", "BACK"),
      [gap(3)],
      hint("q", "QUIT"),
    ])
  put1(buf, 2, model.height - 1, inner_w, footer)
}

// ─── Detail screen ────────────────────────────────────────────────

fn render_detail(model: Model, neo: Neo) -> buffer.Buffer {
  let screen = rect_new(0, 0, model.width, model.height)
  let buf = buffer.buffer_new(screen)
  let frame_w = int.min(68, model.width - 4)
  let cx = int.max(model.width / 2 - frame_w / 2, 2)
  let cy = int.max(model.height / 2 - 8, 1)

  let title_pad = int.max(frame_w - 30, 0)
  let top =
    "╔══ NEAR-EARTH OBJECT DETAIL " <> string.repeat("═", title_pad) <> "╗"
  let side_l = "║  "
  let bottom = "╚" <> string.repeat("═", frame_w - 2) <> "╝"

  let buf = put1(buf, cx, cy, frame_w, [phos_b(top)])
  let buf =
    put1(buf, cx, cy + 2, frame_w, [
      phos(side_l),
      pk_b(string.pad_end(neo.name, frame_w - 6, " ")),
      phos("  ║"),
    ])

  let status_text = case neo.is_hazardous, neo.is_sentry {
    True, True -> [pk_b("☢ HAZARDOUS"), gap(2), spk("◎ SENTRY WATCH")]
    True, False -> [pk_b("☢ HAZARDOUS")]
    False, True -> [spk("◎ SENTRY WATCH")]
    False, False -> [dphos("· SAFE")]
  }
  let status_field_w = frame_w - 18
  let buf =
    put1(buf, cx, cy + 3, frame_w, [
      phos(side_l),
      dim_b("STATUS      "),
      ..list.append(status_text, [
        span.span_plain(string.repeat(
          " ",
          int.max(status_field_w - neo_status_width(neo), 0),
        )),
        phos("  ║"),
      ])
    ])

  let data_rows = [
    #("MAGNITUDE   ", float_1(neo.magnitude), ""),
    #("DIAMETER    ", diameter_label(neo.diameter_km), ""),
    #("VELOCITY    ", float_2(neo.velocity_kms), " km/s"),
    #("APPROACH    ", neo.approach_date, ""),
    #("MISS DIST   ", float_2(neo.miss_dist_ld), " LD"),
  ]
  let buf =
    list.index_fold(data_rows, buf, fn(b, row, i) {
      let #(label, value, suffix) = row
      let pad =
        int.max(
          frame_w - 6 - 12 - string.length(value) - string.length(suffix),
          0,
        )
      put1(b, cx, cy + 5 + i, frame_w, [
        phos(side_l),
        dim_b(label),
        phos_b(value),
        dphos(suffix),
        gap(pad),
        phos("  ║"),
      ])
    })

  let buf =
    put1(buf, cx, cy + 11, frame_w, [
      phos(side_l <> string.repeat(" ", frame_w - 4) <> "║"),
    ])
  let buf = put1(buf, cx, cy + 12, frame_w, [phos(bottom)])

  let buf =
    put1(buf, cx, cy + 14, frame_w, [
      dim("MOCK — real detail would query "),
      dphos("api.nasa.gov/neo/{id}"),
    ])
  let back_hints =
    list.flatten([hint("←/h/ESC", "BACK TO LIST"), [gap(2)], hint("q", "QUIT")])
  put1(buf, cx, cy + 15, frame_w, back_hints)
}

fn neo_status_width(neo: Neo) -> Int {
  case neo.is_hazardous, neo.is_sentry {
    True, True -> 27
    True, False -> 11
    False, True -> 14
    False, False -> 6
  }
}

// ─── Rendering dispatcher ─────────────────────────────────────────

fn render(model: Model) -> List(backend.RenderOp) {
  let buf = case model.screen {
    Boot -> render_boot(model)
    KeyPrompt(inp) -> render_key_prompt(model, inp)
    Loading(pct) -> render_loading(model, pct)
    NeoListView(cursor, off) -> render_neo_list(model, cursor, off)
    SearchPrompt(search_buf, _, _) -> render_search(model, search_buf)
    ChartsView(_, _) -> render_charts(model)
    Detail(neo, _, _) -> render_detail(model, neo)
  }
  let screen = rect_new(0, 0, model.width, model.height)
  [
    backend.ClearScreen,
    backend.MoveCursor(0, 0),
    backend.Write(buf_to_ansi(buf, screen)),
  ]
}

// ─── Update ───────────────────────────────────────────────────────

fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.Resize(w, h) -> Model(..model, width: w, height: h)
    _ ->
      case model.screen {
        Boot ->
          case event {
            backend.KeyPress(_) ->
              Model(..model, screen: KeyPrompt(input_widget.state_new()))
            _ -> model
          }

        KeyPrompt(inp) ->
          case event {
            backend.KeyPress(k) ->
              case keys.match(k) {
                keys.Char("q") -> Model(..model, quit: True)
                keys.Enter | keys.Escape -> Model(..model, screen: Loading(0))
                keys.Backspace | keys.Delete ->
                  Model(..model, screen: KeyPrompt(input_widget.backspace(inp)))
                keys.Char(c) ->
                  Model(
                    ..model,
                    screen: KeyPrompt(input_widget.insert_char(
                      input_widget.input_new("API KEY"),
                      inp,
                      c,
                    )),
                  )
                _ -> model
              }
            _ -> model
          }

        Loading(pct) ->
          case event {
            backend.KeyPress("q") -> Model(..model, quit: True)
            backend.KeyPress(_) -> Model(..model, screen: NeoListView(0, 0))
            backend.Tick ->
              case pct >= 100 {
                True -> Model(..model, screen: NeoListView(0, 0))
                False -> Model(..model, screen: Loading(int.min(pct + 5, 100)))
              }
            _ -> model
          }

        NeoListView(cursor, off) -> {
          let visible = apply_filter(fake_neos, model.filter)
          let total = list.length(visible)
          let row_count = int.max(model.height - 9, 3)
          let adj = fn(c) {
            list_widget.effective_offset(
              list_widget.ListState(selected: c, offset: off),
              row_count,
            )
          }
          case event {
            backend.KeyPress(k) ->
              case keys.match(k) {
                keys.Char("q") -> Model(..model, quit: True)
                keys.Down | keys.Char("j") -> {
                  let c = int.min(cursor + 1, int.max(total - 1, 0))
                  Model(..model, screen: NeoListView(c, adj(c)))
                }
                keys.Up | keys.Char("k") -> {
                  let c = int.max(cursor - 1, 0)
                  Model(..model, screen: NeoListView(c, adj(c)))
                }
                keys.Enter -> {
                  case list.drop(visible, cursor) {
                    [neo, ..] ->
                      Model(..model, screen: Detail(neo, cursor, off))
                    [] -> model
                  }
                }
                keys.Char("/") ->
                  Model(
                    ..model,
                    screen: SearchPrompt(model.filter.search, cursor, off),
                  )
                keys.Char("h") -> {
                  let nf =
                    Filter(
                      ..model.filter,
                      hazard_only: !model.filter.hazard_only,
                    )
                  Model(..model, filter: nf, screen: NeoListView(0, 0))
                }
                keys.Char("s") -> {
                  let nf =
                    Filter(
                      ..model.filter,
                      sort_by: cycle_sort(model.filter.sort_by),
                    )
                  Model(..model, filter: nf, screen: NeoListView(0, 0))
                }
                keys.Char("c") ->
                  Model(..model, screen: ChartsView(cursor, off))
                keys.Char("x") -> {
                  let reset =
                    Filter(hazard_only: False, sort_by: SortName, search: "")
                  Model(..model, filter: reset, screen: NeoListView(0, 0))
                }
                _ -> model
              }
            backend.MouseScroll(_, _, True) -> {
              let c = int.max(cursor - 1, 0)
              Model(..model, screen: NeoListView(c, adj(c)))
            }
            backend.MouseScroll(_, _, False) -> {
              let c = int.min(cursor + 1, int.max(total - 1, 0))
              Model(..model, screen: NeoListView(c, adj(c)))
            }
            backend.MousePress(_, y, backend.MouseLeft) -> {
              let row_y = y - 6
              case row_y >= 0 && row_y < row_count {
                True -> {
                  let c = int.clamp(off + row_y, 0, int.max(total - 1, 0))
                  Model(..model, screen: NeoListView(c, adj(c)))
                }
                False -> model
              }
            }
            _ -> model
          }
        }

        SearchPrompt(search_buf, back_c, back_o) ->
          case event {
            backend.KeyPress(k) ->
              case keys.match(k) {
                keys.Char("q") -> Model(..model, quit: True)
                keys.Enter -> {
                  let nf =
                    Filter(..model.filter, search: string.trim(search_buf))
                  Model(..model, filter: nf, screen: NeoListView(0, 0))
                }
                keys.Escape ->
                  Model(..model, screen: NeoListView(back_c, back_o))
                keys.Backspace | keys.Delete -> {
                  let new_buf = case string.length(search_buf) {
                    0 -> ""
                    n -> string.slice(search_buf, 0, n - 1)
                  }
                  Model(..model, screen: SearchPrompt(new_buf, back_c, back_o))
                }
                keys.Char(c) ->
                  Model(
                    ..model,
                    screen: SearchPrompt(search_buf <> c, back_c, back_o),
                  )
                _ -> model
              }
            _ -> model
          }

        ChartsView(back_c, back_o) ->
          case event {
            backend.KeyPress(k) ->
              case keys.match(k) {
                keys.Char("q") -> Model(..model, quit: True)
                keys.Escape | keys.Char("b") | keys.Char("c") ->
                  Model(..model, screen: NeoListView(back_c, back_o))
                _ -> model
              }
            _ -> model
          }

        Detail(_, back_c, back_o) ->
          case event {
            backend.KeyPress(k) ->
              case keys.match(k) {
                keys.Char("q") -> Model(..model, quit: True)
                keys.Left | keys.Char("h") | keys.Escape ->
                  Model(..model, screen: NeoListView(back_c, back_o))
                _ -> model
              }
            _ -> model
          }
      }
  }
}

// ─── ANSI helpers ─────────────────────────────────────────────────

fn buf_to_ansi(buf: buffer.Buffer, area: geometry.Rect) -> String {
  rows_to_ansi(
    buf,
    area.position.x,
    area.position.y,
    area.size.width,
    area.size.height,
    0,
    "",
  )
}

fn rows_to_ansi(
  buf: buffer.Buffer,
  x0: Int,
  y0: Int,
  w: Int,
  h: Int,
  row: Int,
  acc: String,
) -> String {
  case row >= h {
    True -> acc <> style.ansi_reset()
    False ->
      rows_to_ansi(
        buf,
        x0,
        y0,
        w,
        h,
        row + 1,
        acc
          <> move_cursor_seq(x0, y0 + row)
          <> row_to_ansi(buf, x0, y0 + row, w, 0, ""),
      )
  }
}

fn row_to_ansi(
  buf: buffer.Buffer,
  x0: Int,
  y: Int,
  w: Int,
  col: Int,
  acc: String,
) -> String {
  case col >= w {
    True -> acc
    False -> {
      let pos = geometry.Position(x: x0 + col, y: y)
      let cell = buffer.get_cell(buf, pos)
      let s = case buffer.is_continuation(cell) {
        True -> ""
        False -> {
          let fg_seq = style.ansi_fg(buffer.cell_fg(cell))
          let bg_seq = style.ansi_bg(buffer.cell_bg(cell))
          let mod_seq = style.ansi_modifier(buffer.cell_modifier(cell))
          case fg_seq != "" || bg_seq != "" || mod_seq != "" {
            True ->
              fg_seq
              <> bg_seq
              <> mod_seq
              <> buffer.cell_symbol(cell)
              <> style.ansi_reset()
            False -> buffer.cell_symbol(cell)
          }
        }
      }
      row_to_ansi(buf, x0, y, w, col + 1, acc <> s)
    }
  }
}

fn move_cursor_seq(x: Int, y: Int) -> String {
  "\u{001B}[" <> int.to_string(y + 1) <> ";" <> int.to_string(x + 1) <> "H"
}

// ─── Float & size formatting ──────────────────────────────────────

fn float_1(f: Float) -> String {
  let w = float_floor(f)
  let frac = float_round({ f -. int.to_float(w) } *. 10.0)
  int.to_string(w) <> "." <> int.to_string(frac)
}

fn float_2(f: Float) -> String {
  let w = float_floor(f)
  let frac = float_round({ f -. int.to_float(w) } *. 100.0)
  int.to_string(w)
  <> "."
  <> case frac < 10 {
    True -> "0" <> int.to_string(frac)
    False -> int.to_string(frac)
  }
}

fn diameter_bar(d_km: Float, max_km: Float, width: Int) -> String {
  let filled = case max_km >. 0.0 {
    True ->
      int.clamp(float_round(d_km /. max_km *. int.to_float(width)), 0, width)
    False -> 0
  }
  string.repeat("█", filled) <> string.repeat("░", int.max(width - filled, 0))
}

fn diameter_label(d_km: Float) -> String {
  case d_km <. 1.0 {
    True -> float_0(d_km *. 1000.0) <> "m"
    False -> float_1(d_km) <> "km"
  }
}

fn float_0(f: Float) -> String {
  int.to_string(float_round(f))
}

fn compute_max_dia(neos: List(Neo)) -> Float {
  list.fold(neos, 0.0, fn(acc, n) {
    case n.diameter_km >. acc {
      True -> n.diameter_km
      False -> acc
    }
  })
}

fn float_floor(f: Float) -> Int {
  float.truncate(float.floor(f))
}

fn float_round(f: Float) -> Int {
  float.round(f)
}

// ─── Entry point ──────────────────────────────────────────────────

pub fn main() -> Nil {
  let model = initial_model()
  let b = default.new()
  let _ = app.run(b, model, render, update, fn(m) { m.quit }, 50)
  Nil
}
