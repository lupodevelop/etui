/// GATUI SHOWCASE, interactive widget explorer.
/// Run: gleam run -m etui_showcase
/// TAB=switch  j/k=navigate  ↵=select/submit  TAB/S-TAB=form fields
/// d=dialog  n=info  e=error  r=reset form  q=quit
import etui/anim
import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/geometry.{type Rect, rect_new}
import etui/keys
import etui/span
import etui/style
import etui/widgets/block
import etui/widgets/dialog as dlg_w
import etui/widgets/form
import etui/widgets/gradient_bar
import etui/widgets/hbar
import etui/widgets/list as list_w
import etui/widgets/marquee
import etui/widgets/notification as notif
import etui/widgets/paragraph
import etui/widgets/progress
import etui/widgets/scrollbar
import etui/widgets/spinner
import etui/widgets/statusbar
import etui/widgets/table
import etui/widgets/tabs as tabs_w
import etui/widgets/tree
import gleam/int
import gleam/list
import gleam/string

// ─── Palette ─────────────────────────────────────────────────────

const c_cyan = style.Indexed(51)

const c_dcyan = style.Indexed(37)

const c_green = style.Indexed(82)

const c_amber = style.Indexed(214)

const c_red = style.Indexed(196)

const c_blue = style.Indexed(27)

const c_pink = style.Indexed(213)

const c_violet = style.Indexed(135)

const c_dim = style.Indexed(240)

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

fn grn(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_green)
}

fn grn_b(s: String) -> span.Span {
  grn(s) |> span.span_modifier(style.bold())
}

fn amb(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_amber)
}

fn red_b(s: String) -> span.Span {
  span.span_plain(s)
  |> span.span_fg(c_red)
  |> span.span_modifier(style.bold())
}

fn pk(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_pink)
}

fn vio(s: String) -> span.Span {
  span.span_plain(s) |> span.span_fg(c_violet)
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

// ─── Data ────────────────────────────────────────────────────────

type PkgStatus {
  Stable
  Beta
  Deprecated
}

type Package {
  Package(
    name: String,
    version: String,
    description: String,
    author: String,
    downloads: Int,
    license: String,
    updated: String,
    status: PkgStatus,
  )
}

const packages: List(Package) = [
  Package(
    "gleam_stdlib",
    "0.46.0",
    "Standard library",
    "lpil",
    2_847_291,
    "Apache-2.0",
    "2 days ago",
    Stable,
  ),
  Package(
    "gleam_erlang",
    "0.27.0",
    "Erlang stdlib bindings",
    "lpil",
    1_234_567,
    "Apache-2.0",
    "1 week ago",
    Stable,
  ),
  Package(
    "gleam_otp",
    "0.12.0",
    "OTP actor utilities",
    "lpil",
    987_654,
    "Apache-2.0",
    "3 weeks ago",
    Stable,
  ),
  Package(
    "gleam_json",
    "2.3.0",
    "JSON encode/decode",
    "lpil",
    876_543,
    "Apache-2.0",
    "1 month ago",
    Stable,
  ),
  Package(
    "mist",
    "4.0.2",
    "HTTP/1.1 + HTTP/2 server",
    "rawhat",
    543_210,
    "Apache-2.0",
    "2 days ago",
    Stable,
  ),
  Package(
    "wisp",
    "1.4.0",
    "Web framework",
    "lpil",
    432_109,
    "Apache-2.0",
    "1 week ago",
    Stable,
  ),
  Package(
    "birl",
    "1.7.1",
    "Date + time library",
    "massivefermion",
    321_098,
    "Apache-2.0",
    "2 months ago",
    Stable,
  ),
  Package(
    "simplifile",
    "2.2.0",
    "Cross-platform file I/O",
    "hayleigh-t",
    234_567,
    "MIT",
    "3 weeks ago",
    Stable,
  ),
  Package(
    "gleam_http",
    "3.6.0",
    "HTTP types and client",
    "lpil",
    198_765,
    "Apache-2.0",
    "1 month ago",
    Stable,
  ),
  Package(
    "lustre",
    "4.4.0",
    "Front-end framework",
    "hayleigh-t",
    123_456,
    "MIT",
    "1 week ago",
    Stable,
  ),
  Package(
    "snag",
    "0.3.0",
    "Ergonomic errors",
    "kierangill",
    67_890,
    "MIT",
    "6 months ago",
    Stable,
  ),
  Package(
    "gleam_pgo",
    "1.1.0",
    "PostgreSQL client",
    "lpil",
    87_654,
    "Apache-2.0",
    "3 months ago",
    Stable,
  ),
  Package(
    "glisten",
    "5.0.1",
    "TCP/SSL server",
    "rawhat",
    45_678,
    "Apache-2.0",
    "1 month ago",
    Beta,
  ),
  Package(
    "gleam_crypto",
    "1.4.0",
    "Cryptographic functions",
    "lpil",
    145_678,
    "Apache-2.0",
    "2 months ago",
    Stable,
  ),
]

fn pkg_list_items() -> List(span.Line) {
  list.map(packages, fn(p) {
    let badge = case p.status {
      Stable -> grn(" ● ")
      Beta -> amb(" ◆ ")
      Deprecated -> red_b(" ✖ ")
    }
    let ver = dim(string.pad_end(p.version, 8, " "))
    span.line_new([badge, cy(string.pad_end(p.name, 18, " ")), ver])
  })
}

fn pkg_table_rows() -> List(List(String)) {
  let header = ["PACKAGE", "AUTHOR", "DOWNLOADS", "LICENSE", "UPDATED"]
  let rows =
    list.map(packages, fn(p) {
      [
        p.name,
        p.author,
        int_commas(p.downloads),
        p.license,
        p.updated,
      ]
    })
  [header, ..rows]
}

fn int_commas(n: Int) -> String {
  let s = int.to_string(n)
  let len = string.length(s)
  case len <= 3 {
    True -> s
    False -> int_commas(n / 1000) <> "," <> string.slice(s, len - 3, 3)
  }
}

fn make_tree() -> tree.TreeWidget {
  tree.tree_new([
    tree.node("src", "src/", [
      tree.node("etui", "etui/", [
        tree.node("backend", "backend/", [
          tree.leaf("erlang", "erlang.gleam"),
          tree.leaf("node", "node.gleam"),
        ]),
        tree.node("widgets", "widgets/", [
          tree.leaf("block", "block.gleam"),
          tree.leaf("dialog", "dialog.gleam"),
          tree.leaf("form", "form.gleam"),
          tree.leaf("gauge", "gauge.gleam"),
          tree.leaf("gradient_bar", "gradient_bar.gleam"),
          tree.leaf("hbar", "hbar.gleam"),
          tree.leaf("list", "list.gleam"),
          tree.leaf("marquee", "marquee.gleam"),
          tree.leaf("notification", "notification.gleam"),
          tree.leaf("progress", "progress.gleam"),
          tree.leaf("scrollbar", "scrollbar.gleam"),
          tree.leaf("sparkline", "sparkline.gleam"),
          tree.leaf("spinner", "spinner.gleam"),
          tree.leaf("statusbar", "statusbar.gleam"),
          tree.leaf("table", "table.gleam"),
          tree.leaf("tabs", "tabs.gleam"),
          tree.leaf("tree", "tree.gleam"),
        ]),
        tree.leaf("app", "app.gleam"),
        tree.leaf("buffer", "buffer.gleam"),
        tree.leaf("geometry", "geometry.gleam"),
        tree.leaf("keys", "keys.gleam"),
        tree.leaf("span", "span.gleam"),
        tree.leaf("style", "style.gleam"),
      ]),
    ]),
    tree.node("dev", "dev/", [
      tree.leaf("nexus", "etui_nexus.gleam"),
      tree.leaf("showcase", "etui_showcase.gleam"),
    ]),
    tree.node("test", "test/", [
      tree.leaf("tests", "etui_test.gleam"),
    ]),
    tree.leaf("gleam_toml", "gleam.toml"),
    tree.leaf("readme", "README.md"),
  ])
}

// ─── Model ───────────────────────────────────────────────────────

type Tab {
  TabForm
  TabList
  TabTree
  TabLive
  TabAbout
}

type FormField {
  FieldName
  FieldHost
  FieldTag
}

type ListFocus {
  FocusList
  FocusTable
}

type Model {
  Model(
    tab: Tab,
    form: form.Form(FormField),
    pkg_list_st: list_w.ListState,
    pkg_table_st: table.TableState,
    list_focus: ListFocus,
    tree_widget: tree.TreeWidget,
    tree_st: tree.TreeState,
    dlg_open: Bool,
    dlg_st: dlg_w.DialogState,
    notifs: notif.NotificationQueue,
    width: Int,
    height: Int,
    quit: Bool,
  )
}

fn make_form() -> form.Form(FormField) {
  form.form_new()
  |> form.with_label_width(8)
  |> form.with_focused_colors(c_cyan, style.Indexed(235))
  |> form.add_required(FieldName, "Name", "")
  |> form.add_field(FieldHost, "Host", "prod.example.com", fn(v) {
    case string.contains(v, ".") {
      True -> Ok(Nil)
      False -> Error("must be a valid hostname")
    }
  })
  |> form.add_required(FieldTag, "Tag", "")
}

fn initial_model() -> Model {
  let tw = make_tree()
  let ts =
    tree.state_new()
    |> tree.expand("src", _)
    |> tree.expand("etui", _)
    |> tree.expand("widgets", _)
  Model(
    tab: TabForm,
    form: make_form(),
    pkg_list_st: list_w.state_new(),
    // start at row 1: row 0 is the header
    pkg_table_st: table.select_row(table.state_new(), 1),
    list_focus: FocusList,
    tree_widget: tw,
    tree_st: ts,
    dlg_open: False,
    dlg_st: dlg_w.state_new(),
    notifs: notif.queue_new(max: 4),
    width: 80,
    height: 24,
    quit: False,
  )
}

fn tab_index(t: Tab) -> Int {
  case t {
    TabForm -> 0
    TabList -> 1
    TabTree -> 2
    TabLive -> 3
    TabAbout -> 4
  }
}

fn next_tab(t: Tab) -> Tab {
  case t {
    TabForm -> TabList
    TabList -> TabTree
    TabTree -> TabLive
    TabLive -> TabAbout
    TabAbout -> TabForm
  }
}

fn prev_tab(t: Tab) -> Tab {
  case t {
    TabForm -> TabAbout
    TabList -> TabForm
    TabTree -> TabList
    TabLive -> TabTree
    TabAbout -> TabLive
  }
}

// ─── Shared chrome ───────────────────────────────────────────────

fn draw_tabs(buf: buffer.Buffer, active: Tab, w: Int) -> buffer.Buffer {
  let t =
    tabs_w.tabs_new(["FORM", "LIST", "TREE", "LIVE", "ABOUT"])
    |> tabs_w.with_active(tab_index(active))
    |> tabs_w.with_colors(c_cyan, style.Default)
  let buf = tabs_w.render(buf, rect_new(0, 0, w, 1), t)
  put1(buf, 0, 1, w, [cy(string.repeat("━", w))])
}

fn draw_statusbar(buf: buffer.Buffer, m: Model, frame: Int) -> buffer.Buffer {
  let tab_name = case m.tab {
    TabForm -> "FORM"
    TabList -> "LIST"
    TabTree -> "TREE"
    TabLive -> "LIVE"
    TabAbout -> "ABOUT"
  }
  let live_dot = case frame / 8 % 2 {
    0 -> grn_b("●")
    _ -> grn("●")
  }
  let right_hints = case m.tab {
    TabForm ->
      span.line_new([
        dim("TAB fields  "),
        dim("↵ submit  "),
        dim("r reset  "),
        cy("ESC back"),
        gap(1),
      ])
    TabList ->
      span.line_new([
        dim("jk nav  "),
        dim("hl panel  "),
        dim("TAB switch  "),
        cy("q quit"),
        gap(1),
      ])
    TabTree ->
      span.line_new([
        dim("jk nav  "),
        dim("↵ toggle  "),
        dim("TAB switch  "),
        cy("q quit"),
        gap(1),
      ])
    TabLive | TabAbout ->
      span.line_new([
        dim("TAB switch  "),
        dim("d dialog  "),
        dim("n/e notify  "),
        cy("q quit"),
        gap(1),
      ])
  }
  let sb =
    statusbar.statusbar_new()
    |> statusbar.with_colors(c_dim, style.Indexed(234))
    |> statusbar.with_left([
      span.line_new([gap(1), cy_b("GATUI"), dim(" EXPLORER")]),
    ])
    |> statusbar.with_center([
      span.line_new([live_dot, dim(" " <> tab_name)]),
    ])
    |> statusbar.with_right([right_hints])
  statusbar.render(buf, rect_new(0, m.height - 1, m.width, 1), sb)
}

// ─── FORM tab ────────────────────────────────────────────────────

fn render_form(m: Model) -> buffer.Buffer {
  let screen = rect_new(0, 0, m.width, m.height)
  let buf = buffer.buffer_new(screen)
  let w = m.width
  let h = m.height
  let buf = draw_tabs(buf, TabForm, w)

  let box_w = int.min(54, w - 4)
  let bx = int.max(w / 2 - box_w / 2, 2)
  let by = int.max(h / 2 - 8, 3)

  let blk =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title(" NEW SERVICE ", block.Top)
    |> block.with_colors(c_cyan, style.Default)
  let blk_area = rect_new(bx, by, box_w, 14)
  let inner = block.inner(blk_area, blk)
  let buf = block.render(buf, blk_area, blk)

  let submitted = form.is_submitted(m.form)

  let buf = case submitted {
    True -> {
      let name = form.get_value(m.form, FieldName)
      let host = form.get_value(m.form, FieldHost)
      let tag = form.get_value(m.form, FieldTag)
      let mid_y = inner.position.y + inner.size.height / 2 - 2
      let buf =
        put1(buf, inner.position.x, mid_y, inner.size.width, [
          grn_b("  ✓  DEPLOYED SUCCESSFULLY"),
        ])
      let buf =
        put1(buf, inner.position.x, mid_y + 2, inner.size.width, [
          dim("  name  "),
          cy_b(name),
        ])
      let buf =
        put1(buf, inner.position.x, mid_y + 3, inner.size.width, [
          dim("  host  "),
          cy(host),
        ])
      let buf =
        put1(buf, inner.position.x, mid_y + 4, inner.size.width, [
          dim("  tag   "),
          cy(tag),
        ])
      put1(buf, inner.position.x, mid_y + 6, inner.size.width, [
        dim("  press "),
        cy_r(" r "),
        dim(" to reset"),
      ])
    }
    False -> {
      let form_area =
        rect_new(
          inner.position.x + 1,
          inner.position.y + 1,
          inner.size.width - 2,
          inner.size.height - 4,
        )
      let buf = form.render(buf, form_area, m.form)
      let valid = form.is_valid(m.form)
      let submit_y = inner.position.y + inner.size.height - 2
      put1(buf, inner.position.x, submit_y, inner.size.width, [
        gap(4),
        case valid {
          True -> cy_r("  ↵ DEPLOY  ")
          False -> dim("  ↵ DEPLOY  ")
        },
        gap(3),
        cy_r("  r RESET  "),
      ])
    }
  }

  let buf =
    put1(buf, bx, by + 15, box_w, [
      dim("  TAB / S-TAB"),
      cy(" ─ "),
      dim("move fields    "),
      dim("backspace"),
      cy(" ─ "),
      dim("delete"),
    ])

  buf
}

// ─── LIST tab ────────────────────────────────────────────────────

fn render_list(m: Model) -> buffer.Buffer {
  let screen = rect_new(0, 0, m.width, m.height)
  let buf = buffer.buffer_new(screen)
  let w = m.width
  let h = m.height
  let buf = draw_tabs(buf, TabList, w)

  let list_w_px = w * 2 / 5
  let table_x = list_w_px + 1
  let table_w = w - table_x
  let content_h = h - 4

  // Left panel, package list
  let list_active = m.list_focus == FocusList
  let list_blk =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title(" PACKAGES ", block.Top)
    |> block.with_colors(
      case list_active {
        True -> c_cyan
        False -> c_dim
      },
      style.Default,
    )
  let list_area = rect_new(0, 2, list_w_px, content_h)
  let list_inner = block.inner(list_area, list_blk)
  let buf = block.render(buf, list_area, list_blk)

  let pkg_lw =
    list_w.list_new_styled(pkg_list_items())
    |> list_w.with_highlight_style(style.Style(
      fg: c_cyan,
      bg: style.Indexed(235),
      modifier: style.none(),
    ))
  let buf = list_w.render_stateful(buf, list_inner, pkg_lw, m.pkg_list_st)

  // Scrollbar for list
  let sb =
    scrollbar.scrollbar_new(
      list.length(packages),
      list_inner.size.height,
      list_w.effective_offset(m.pkg_list_st, list_inner.size.height),
    )
    |> scrollbar.with_arrows("", "")
  let buf =
    scrollbar.render_vertical(
      buf,
      rect_new(
        list_inner.position.x + list_inner.size.width,
        list_inner.position.y,
        1,
        list_inner.size.height,
      ),
      sb,
    )

  // Right panel, package detail table
  let table_active = m.list_focus == FocusTable
  let tbl_blk =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title(" DETAILS ", block.Top)
    |> block.with_colors(
      case table_active {
        True -> c_cyan
        False -> c_dim
      },
      style.Default,
    )
  let tbl_area = rect_new(table_x, 2, table_w, content_h)
  let tbl_inner = block.inner(tbl_area, tbl_blk)
  let buf = block.render(buf, tbl_area, tbl_blk)

  let col_w = [14, 10, 10, 10, 10]
  let tbl =
    table.table_new(pkg_table_rows())
    |> table.with_col_widths(col_w)
    |> table.with_header(True)
    |> table.with_highlight_style(style.Style(
      fg: c_cyan,
      bg: style.Indexed(235),
      modifier: style.none(),
    ))
  let buf = table.render_stateful(buf, tbl_inner, tbl, m.pkg_table_st)

  // Focus hint
  put1(buf, 1, h - 2, w - 2, [
    dim("  "),
    cy_r(" h "),
    dim(" list   "),
    cy_r(" l "),
    dim(" table   "),
    dim("j/k navigate"),
  ])
}

// ─── TREE tab ────────────────────────────────────────────────────

fn render_tree(m: Model) -> buffer.Buffer {
  let screen = rect_new(0, 0, m.width, m.height)
  let buf = buffer.buffer_new(screen)
  let w = m.width
  let h = m.height
  let buf = draw_tabs(buf, TabTree, w)

  let tree_w = int.min(42, w - 2)
  let info_x = tree_w + 2
  let info_w = w - info_x - 1
  let content_h = h - 4

  // Tree panel
  let tree_blk =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title(" PROJECT TREE ", block.Top)
    |> block.with_colors(c_cyan, style.Default)
  let tree_area = rect_new(0, 2, tree_w, content_h)
  let tree_inner = block.inner(tree_area, tree_blk)
  let buf = block.render(buf, tree_area, tree_blk)

  let tw =
    m.tree_widget
    |> tree.with_colors(c_dcyan, style.Default)
    |> tree.with_highlight_style(style.Style(
      fg: c_cyan,
      bg: style.Indexed(235),
      modifier: style.none(),
    ))
  let buf = tree.render(buf, tree_inner, tw, m.tree_st)

  // Info panel
  let info_blk =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title(" SELECTION ", block.Top)
    |> block.with_colors(c_dim, style.Default)
  let info_area = rect_new(info_x, 2, info_w, content_h)
  let info_inner = block.inner(info_area, info_blk)
  let buf = block.render(buf, info_area, info_blk)

  let selected_id = case tree.selected(m.tree_st) {
    Ok(id) -> id
    Error(_) -> "(none)"
  }
  let buf =
    put1(
      buf,
      info_inner.position.x,
      info_inner.position.y,
      info_inner.size.width,
      [
        dim("selected"),
      ],
    )
  let buf =
    put1(
      buf,
      info_inner.position.x,
      info_inner.position.y + 1,
      info_inner.size.width,
      [cy_b(selected_id)],
    )

  let buf =
    put1(
      buf,
      info_inner.position.x,
      info_inner.position.y + 3,
      info_inner.size.width,
      [dim("keys")],
    )
  let key_hints = [
    #("↵", "expand/collapse"),
    #("j k", "move selection"),
  ]
  list.index_fold(key_hints, buf, fn(b, kh, i) {
    let #(k, l) = kh
    put1(
      b,
      info_inner.position.x,
      info_inner.position.y + 4 + i,
      info_inner.size.width,
      [cy_r(" " <> k <> " "), dim("  " <> l)],
    )
  })
}

// ─── LIVE tab ────────────────────────────────────────────────────

fn render_live(m: Model, frame: Int) -> buffer.Buffer {
  let screen = rect_new(0, 0, m.width, m.height)
  let buf = buffer.buffer_new(screen)
  let w = m.width
  let h = m.height
  let buf = draw_tabs(buf, TabLive, w)

  let bar_w = int.min(w - 6, 60)
  let lx = 3

  // ── SPINNERS ──────────────────────────────────────────
  let buf = put1(buf, lx, 3, w - 4, [dim_b("SPINNERS")])
  let spin_styles = [
    #(spinner.Dots, "Dots", c_cyan),
    #(spinner.Line, "Line", c_green),
    #(spinner.Circle, "Circle", c_amber),
    #(spinner.Bounce, "Bounce", c_pink),
  ]
  let buf =
    list.index_fold(spin_styles, buf, fn(b, ss, i) {
      let #(style_, label, color) = ss
      let sx = lx + i * 16
      let sp =
        spinner.spinner_new()
        |> spinner.with_style(style_)
        |> spinner.with_label("  " <> label)
        |> spinner.with_colors(color, style.Default)
      spinner.render(b, rect_new(sx, 4, 15, 1), sp, frame)
    })

  // ── PROGRESS BARS ─────────────────────────────────────
  let buf = put1(buf, lx, 6, w - 4, [dim_b("PROGRESS")])

  let pct = frame * 100 / 120 % 101
  let p1 =
    progress.progress_new(pct)
    |> progress.with_label(int.to_string(pct) <> "%")
    |> progress.with_colors(c_cyan, style.Default)
  let buf = progress.render(buf, rect_new(lx, 7, bar_w, 1), p1, frame)

  let p2 =
    progress.progress_indeterminate()
    |> progress.with_colors(c_dcyan, style.Default)
  let buf = progress.render(buf, rect_new(lx, 8, bar_w, 1), p2, frame)

  // ── GRADIENT BARS ─────────────────────────────────────
  let buf = put1(buf, lx, 10, w - 4, [dim_b("GRADIENT BARS")])

  let g1 = gradient_bar.pulse_bar(c_cyan)
  let buf = gradient_bar.render(buf, rect_new(lx, 11, bar_w, 1), g1, frame)

  let g2 = gradient_bar.animated_rainbow_bar()
  let buf = gradient_bar.render(buf, rect_new(lx, 12, bar_w, 1), g2, frame)

  let g3 =
    gradient_bar.gradient_progress_new(
      [c_blue, c_cyan, c_green],
      frame * 100 / 80 % 101,
    )
  let buf = gradient_bar.render(buf, rect_new(lx, 13, bar_w, 1), g3, frame)

  // ── HBAR ──────────────────────────────────────────────
  let buf = put1(buf, lx, 15, w - 4, [dim_b("HBAR")])
  let hb =
    hbar.hbar_new([
      hbar.item("widgets", 28),
      hbar.item("core", 12),
      hbar.item("backend", 4),
      hbar.item("demo", 3),
    ])
    |> hbar.with_show_value(True)
    |> hbar.with_max(50)
    |> hbar.with_label_width(9)
  let buf = hbar.render(buf, rect_new(lx, 16, bar_w, 4), hb, frame)

  // ── MARQUEE ───────────────────────────────────────────
  let buf = put1(buf, lx, h - 4, w - 4, [dim_b("TICKER")])
  let mq =
    marquee.marquee_new(
      "etui  ·  pure gleam  ·  type-safe  ·  animated  ·  no terminal left broken  ·  sparklines  ·  forms  ·  trees  ·  tables  ·  notifications  ·  dialogs  ·",
    )
    |> marquee.with_speed(4)
    |> marquee.with_fg(c_dcyan)
  marquee.render(buf, rect_new(lx, h - 3, w - 6, 1), mq, frame)
}

// ─── ABOUT tab ───────────────────────────────────────────────────

fn render_about(m: Model) -> buffer.Buffer {
  let screen = rect_new(0, 0, m.width, m.height)
  let buf = buffer.buffer_new(screen)
  let w = m.width
  let h = m.height
  let buf = draw_tabs(buf, TabAbout, w)

  let left_w = int.min(38, w / 2)
  let right_x = left_w + 2
  let right_w = w - right_x - 1
  let content_h = h - 4

  // Left: widget list
  let widget_blk =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title(" WIDGETS ", block.Top)
    |> block.with_colors(c_cyan, style.Default)
  let widget_area = rect_new(0, 2, left_w, content_h)
  let widget_inner = block.inner(widget_area, widget_blk)
  let buf = block.render(buf, widget_area, widget_blk)

  let widget_rows = [
    #("block", "border, title, padding"),
    #("buffer", "cell grid + ANSI diff"),
    #("dialog", "confirm / cancel modal"),
    #("form", "multi-field + validation"),
    #("gauge", "filled progress bar"),
    #("gradient_bar", "animated color bars"),
    #("hbar", "horizontal bar chart"),
    #("list", "scrollable item list"),
    #("marquee", "scrolling text ticker"),
    #("notification", "toast overlay queue"),
    #("paragraph", "wrapped styled text"),
    #("progress", "progress / indeterminate"),
    #("scrollbar", "scroll position overlay"),
    #("sparkline", "block-char time-series"),
    #("spinner", "animated loading char"),
    #("statusbar", "L / C / R status strip"),
    #("table", "grid with header + scroll"),
    #("tabs", "tab-bar navigation"),
    #("tree", "expand/collapse tree"),
  ]
  let buf =
    list.index_fold(widget_rows, buf, fn(b, wr, i) {
      let #(name, desc) = wr
      case i < widget_inner.size.height {
        False -> b
        True ->
          put1(
            b,
            widget_inner.position.x,
            widget_inner.position.y + i,
            widget_inner.size.width,
            [
              cy(string.pad_end(name, 14, " ")),
              dim(string.slice(desc, 0, widget_inner.size.width - 15)),
            ],
          )
      }
    })

  // Right: about text + hbar
  let info_blk =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title(" GATUI ", block.Top)
    |> block.with_colors(c_dim, style.Default)
  let info_area = rect_new(right_x, 2, right_w, content_h)
  let info_inner = block.inner(info_area, info_blk)
  let buf = block.render(buf, info_area, info_blk)

  let ix = info_inner.position.x
  let iy = info_inner.position.y
  let iw = info_inner.size.width

  let buf = put1(buf, ix, iy, iw, [pk("The TUI framework for Gleam on BEAM.")])
  let buf =
    put1(buf, ix, iy + 1, iw, [
      dim("Pure Gleam · Type-safe · Crash-safe"),
    ])
  let buf = put1(buf, ix, iy + 3, iw, [dim_b("FEATURES")])
  let features = [
    "Animated event loop (run_animated)",
    "Automatic buffer diff — minimal redraws",
    "Crash-safe: TTY always restored",
    "SIGINT handler — no broken terminal",
    "Mouse support (SGR protocol)",
    "19 built-in widgets",
    "Erlang + Node.js backends",
  ]
  let buf =
    list.index_fold(features, buf, fn(b, feat, i) {
      put1(b, ix, iy + 4 + i, iw, [dim("· "), vio(feat)])
    })

  let buf = put1(buf, ix, iy + 12, iw, [dim_b("FILES")])
  let hb =
    hbar.hbar_new([
      hbar.item("widgets", 19),
      hbar.item("core", 8),
      hbar.item("backends", 3),
      hbar.item("demo", 3),
    ])
    |> hbar.with_show_value(True)
    |> hbar.with_max(25)
    |> hbar.with_label_width(10)
  hbar.render(buf, rect_new(ix, iy + 13, iw, 4), hb, 0)
}

// ─── Overlays ────────────────────────────────────────────────────

fn draw_dialog(buf: buffer.Buffer, m: Model) -> buffer.Buffer {
  case m.dlg_open {
    False -> buf
    True -> {
      let screen = rect_new(0, 0, m.width, m.height)
      let d =
        dlg_w.dialog_new("Quit GATUI EXPLORER?")
        |> dlg_w.with_labels("  QUIT  ", " CANCEL ")
        |> dlg_w.with_border(block.Rounded)
        |> dlg_w.with_colors(c_cyan, style.Default)
        |> dlg_w.with_focused_style(style.Style(
          fg: style.Default,
          bg: style.Indexed(235),
          modifier: style.bold(),
        ))
      dlg_w.render(buf, screen, d, m.dlg_st)
    }
  }
}

fn draw_notifs(buf: buffer.Buffer, m: Model) -> buffer.Buffer {
  let screen = rect_new(0, 0, m.width, m.height)
  notif.render(buf, screen, m.notifs)
}

// ─── Render ──────────────────────────────────────────────────────

fn render(m: Model, screen: Rect, anim_st: anim.AnimState) -> buffer.Buffer {
  let m = Model(..m, width: screen.size.width, height: screen.size.height)
  let frame = anim_st.frame
  let buf = case m.tab {
    TabForm -> render_form(m)
    TabList -> render_list(m)
    TabTree -> render_tree(m)
    TabLive -> render_live(m, frame)
    TabAbout -> render_about(m)
  }
  let buf = draw_statusbar(buf, m, frame)
  let buf = draw_notifs(buf, m)
  draw_dialog(buf, m)
}

// ─── Update ──────────────────────────────────────────────────────

fn update(event: backend.InputEvent, m: Model) -> Model {
  let m = Model(..m, notifs: notif.tick(m.notifs))
  case event {
    backend.Resize(w, h) -> Model(..m, width: w, height: h)
    backend.KeyPress(raw) -> handle_key(keys.match(raw), m)
    _ -> m
  }
}

fn handle_key(k: keys.Key, m: Model) -> Model {
  // Dialog steals all input
  case m.dlg_open {
    True ->
      case k {
        keys.Tab | keys.Left | keys.Right ->
          Model(..m, dlg_st: dlg_w.toggle(m.dlg_st))
        keys.Escape -> Model(..m, dlg_open: False, dlg_st: dlg_w.state_new())
        keys.Enter ->
          case dlg_w.is_confirmed(m.dlg_st) {
            True -> Model(..m, quit: True)
            False -> Model(..m, dlg_open: False, dlg_st: dlg_w.state_new())
          }
        _ -> m
      }
    False ->
      case k {
        // Ctrl+C always quits
        keys.Ctrl("c") -> Model(..m, quit: True)
        // Tab: advance form field when on form tab; otherwise switch tab
        keys.Tab ->
          case m.tab {
            TabForm -> Model(..m, form: form.focus_next(m.form))
            _ -> Model(..m, tab: next_tab(m.tab))
          }
        keys.BackTab ->
          case m.tab {
            TabForm -> Model(..m, form: form.focus_prev(m.form))
            _ -> Model(..m, tab: prev_tab(m.tab))
          }
        // F-keys jump directly to a tab from anywhere
        keys.F(1) -> Model(..m, tab: TabForm)
        keys.F(2) -> Model(..m, tab: TabList)
        keys.F(3) -> Model(..m, tab: TabTree)
        keys.F(4) -> Model(..m, tab: TabLive)
        keys.F(5) -> Model(..m, tab: TabAbout)
        // All other keys are tab-specific
        _ -> handle_tab_key(k, m)
      }
  }
}

fn handle_tab_key(k: keys.Key, m: Model) -> Model {
  case m.tab {
    TabForm -> handle_form(k, m)
    TabList -> handle_list(k, m)
    TabTree -> handle_tree(k, m)
    TabLive | TabAbout -> handle_view(k, m)
  }
}

// Form tab: typing keys reach the form; no single-letter shortcuts conflict
fn handle_form(k: keys.Key, m: Model) -> Model {
  case k {
    keys.Escape -> Model(..m, tab: TabList)
    keys.Backspace -> Model(..m, form: form.backspace(m.form))
    keys.Enter -> {
      let f = form.submit(m.form)
      let m2 = Model(..m, form: f)
      case form.is_submitted(f) {
        True ->
          Model(
            ..m2,
            notifs: notif.push(
              m2.notifs,
              notif.success(
                "Deployed: " <> form.get_value(f, FieldName),
                ttl: 100,
              ),
            ),
          )
        False -> m2
      }
    }
    // r resets form, can't type 'r' in fields, acceptable for a demo
    keys.Char("r") -> Model(..m, form: make_form())
    keys.Char(c) -> Model(..m, form: form.type_char(m.form, c))
    _ -> m
  }
}

fn open_dialog(m: Model) -> Model {
  Model(..m, dlg_open: True, dlg_st: dlg_w.focus_cancel(dlg_w.state_new()))
}

// List tab: j/k always navigate both panels in sync; h/l switch visual focus
fn handle_list(k: keys.Key, m: Model) -> Model {
  let n = list.length(packages)
  case k {
    keys.Char("q") -> Model(..m, quit: True)
    keys.Char("d") -> open_dialog(m)
    keys.Char("n") ->
      Model(
        ..m,
        notifs: notif.push(
          m.notifs,
          notif.info("Package index refreshed", ttl: 80),
        ),
      )
    keys.Char("e") ->
      Model(
        ..m,
        notifs: notif.push(
          m.notifs,
          notif.error("Registry unreachable", ttl: 120),
        ),
      )
    keys.Char("h") | keys.Left -> Model(..m, list_focus: FocusList)
    keys.Char("l") | keys.Right -> Model(..m, list_focus: FocusTable)
    keys.Down | keys.Char("j") ->
      Model(
        ..m,
        pkg_list_st: list_w.select_next(m.pkg_list_st, n),
        // +1 row offset because row 0 is the header
        pkg_table_st: table.select_next_row(m.pkg_table_st, n + 1),
      )
    keys.Up | keys.Char("k") ->
      Model(
        ..m,
        pkg_list_st: list_w.select_prev(m.pkg_list_st),
        pkg_table_st: table.select_prev_row(m.pkg_table_st),
      )
    _ -> m
  }
}

fn handle_tree(k: keys.Key, m: Model) -> Model {
  case k {
    keys.Char("q") -> Model(..m, quit: True)
    keys.Char("d") -> open_dialog(m)
    keys.Char("n") ->
      Model(
        ..m,
        notifs: notif.push(m.notifs, notif.info("Tree refreshed", ttl: 60)),
      )
    keys.Char("e") ->
      Model(
        ..m,
        notifs: notif.push(
          m.notifs,
          notif.error("Watch error: permission denied", ttl: 120),
        ),
      )
    keys.Down | keys.Char("j") ->
      Model(..m, tree_st: tree.select_next(m.tree_st, m.tree_widget))
    keys.Up | keys.Char("k") ->
      Model(..m, tree_st: tree.select_prev(m.tree_st, m.tree_widget))
    keys.Enter | keys.Char(" ") ->
      Model(..m, tree_st: tree.toggle_selected(m.tree_st, m.tree_widget))
    _ -> m
  }
}

fn handle_view(k: keys.Key, m: Model) -> Model {
  case k {
    keys.Char("q") -> Model(..m, quit: True)
    keys.Char("d") -> open_dialog(m)
    keys.Char("n") ->
      Model(
        ..m,
        notifs: notif.push(
          m.notifs,
          notif.info("Service restarted successfully", ttl: 80),
        ),
      )
    keys.Char("e") ->
      Model(
        ..m,
        notifs: notif.push(
          m.notifs,
          notif.error("Connection refused: cdn-origin", ttl: 120),
        ),
      )
    _ -> m
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
