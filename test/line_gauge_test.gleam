/// LineGauge: the one widget with no direct coverage until now.
/// These tests pin the render boundaries (where filled meets unfilled),
/// the label overlay, and the per-portion styling — all pure buffer work,
/// so they run headless on both targets.
import etui/buffer
import etui/geometry
import etui/style
import etui/widgets/line_gauge as lg
import gleam/list
import gleeunit/should

fn indices(n: Int) -> List(Int) {
  case n <= 0 {
    True -> []
    False -> list.append(indices(n - 1), [n - 1])
  }
}

fn row(buf: buffer.Buffer, y: Int) -> List(String) {
  indices(buffer.width(buf))
  |> list.map(fn(x) {
    buffer.get_cell(buf, geometry.Position(x: x, y: y))
    |> buffer.cell_symbol
  })
}

fn symbols(buf: buffer.Buffer, y: Int, from: Int, to: Int) -> List(String) {
  indices(to - from + 1)
  |> list.map(fn(i) {
    buffer.get_cell(buf, geometry.Position(x: from + i, y: y))
    |> buffer.cell_symbol
  })
}

fn rendered(percent: Int) -> buffer.Buffer {
  let area = geometry.rect_new(0, 0, 10, 1)
  let g = lg.line_gauge_new(percent) |> lg.with_line_set(lg.AsciiLine)
  lg.render(buffer.buffer_new(area), area, g)
}

// ─────────────────────────────────────────────────────────────────
// Construction

pub fn new_gauge_defaults_test() {
  let g = lg.line_gauge_new(75)
  g.percent |> should.equal(75)
  g.label |> should.equal("")
  g.line_set |> should.equal(lg.ThinLine)
}

pub fn percent_is_clamped_test() {
  lg.line_gauge_new(150).percent |> should.equal(100)
  lg.line_gauge_new(-10).percent |> should.equal(0)
}

pub fn builders_set_their_field_test() {
  let g =
    lg.line_gauge_new(50)
    |> lg.with_label("50%")
    |> lg.with_line_set(lg.AsciiLine)
    |> lg.with_colors(style.Indexed(1), style.Indexed(2))
    |> lg.with_filled_modifier(style.bold())
  g.label |> should.equal("50%")
  g.line_set |> should.equal(lg.AsciiLine)
  g.fg |> should.equal(style.Indexed(1))
  g.bg |> should.equal(style.Indexed(2))
  g.filled_modifier |> should.equal(style.bold())
}

pub fn with_style_takes_fg_and_bg_only_test() {
  // Modifiers on the Style must not leak into the filled portion; only
  // colours are adopted.
  let s = style.new(style.Rgb(1, 2, 3), style.Rgb(4, 5, 6), style.bold())
  let g = lg.line_gauge_new(10) |> lg.with_style(s)
  g.fg |> should.equal(style.Rgb(1, 2, 3))
  g.bg |> should.equal(style.Rgb(4, 5, 6))
}

// ─────────────────────────────────────────────────────────────────
// Render boundaries

pub fn empty_renders_all_unfilled_test() {
  let buf = rendered(0)
  row(buf, 0)
  |> list.each(fn(s) { s |> should.equal("-") })
}

pub fn full_renders_all_filled_test() {
  let buf = rendered(100)
  row(buf, 0)
  |> list.each(fn(s) { s |> should.equal("=") })
}

pub fn half_splits_at_the_middle_test() {
  let area = geometry.rect_new(0, 0, 10, 1)
  let buf =
    lg.render(
      buffer.buffer_new(area),
      area,
      lg.line_gauge_new(50) |> lg.with_line_set(lg.AsciiLine),
    )
  symbols(buf, 0, 0, 4)
  |> list.each(fn(s) { s |> should.equal("=") })
  symbols(buf, 0, 5, 9)
  |> list.each(fn(s) { s |> should.equal("-") })
}

pub fn fractional_percent_fills_down_test() {
  // 55% of 10 cells is 5.5; integer division fills 5, never 6.
  let area = geometry.rect_new(0, 0, 10, 1)
  let buf =
    lg.render(
      buffer.buffer_new(area),
      area,
      lg.line_gauge_new(55) |> lg.with_line_set(lg.AsciiLine),
    )
  symbols(buf, 0, 0, 4)
  |> list.each(fn(s) { s |> should.equal("=") })
  symbols(buf, 0, 5, 9)
  |> list.each(fn(s) { s |> should.equal("-") })
}

pub fn line_sets_choose_their_characters_test() {
  let area = geometry.rect_new(0, 0, 6, 1)

  let draw = fn(ls: lg.LineSet) {
    lg.render(
      buffer.buffer_new(area),
      area,
      lg.line_gauge_new(100) |> lg.with_line_set(ls),
    )
  }

  draw(lg.DoubleLine)
  |> row(0)
  |> should.equal(["═", "═", "═", "═", "═", "═"])

  draw(lg.ThickLine)
  |> row(0)
  |> should.equal(["━", "━", "━", "━", "━", "━"])
}

// ─────────────────────────────────────────────────────────────────
// Per-portion styling

pub fn unfilled_portion_carries_the_dim_modifier_test() {
  let buf = rendered(50)
  let dim_at = fn(x: Int) {
    buffer.get_cell(buf, geometry.Position(x: x, y: 0))
    |> buffer.cell_modifier
    |> style.has(style.dim())
  }
  // Filled side has none by default.
  dim_at(0) |> should.equal(False)
  dim_at(4) |> should.equal(False)
  // Unfilled side is dimmed.
  dim_at(5) |> should.equal(True)
  dim_at(9) |> should.equal(True)
}

pub fn colors_land_on_both_portions_test() {
  let area = geometry.rect_new(0, 0, 10, 1)
  let buf =
    lg.render(
      buffer.buffer_new(area),
      area,
      lg.line_gauge_new(50)
        |> lg.with_colors(style.Indexed(3), style.Indexed(4)),
    )
  buffer.cell_fg(buffer.get_cell(buf, geometry.Position(x: 0, y: 0)))
  |> should.equal(style.Indexed(3))
  buffer.cell_bg(buffer.get_cell(buf, geometry.Position(x: 9, y: 0)))
  |> should.equal(style.Indexed(4))
}

// ─────────────────────────────────────────────────────────────────
// Label overlay

pub fn label_is_centered_over_the_line_test() {
  let area = geometry.rect_new(0, 0, 10, 1)
  let buf =
    lg.render(
      buffer.buffer_new(area),
      area,
      lg.line_gauge_new(50)
        |> lg.with_line_set(lg.AsciiLine)
        |> lg.with_label("AB"),
    )
  // left_pad = (10 - 2) / 2 = 4, right_pad = 4.
  row(buf, 0)
  |> should.equal(["=", "=", "=", "=", "A", "B", "-", "-", "-", "-"])
}

pub fn wide_label_is_truncated_to_the_width_test() {
  let area = geometry.rect_new(0, 0, 6, 1)
  let buf =
    lg.render(
      buffer.buffer_new(area),
      area,
      lg.line_gauge_new(50) |> lg.with_label("ABCDEFG"),
    )
  row(buf, 0)
  |> should.equal(["A", "B", "C", "D", "E", "F"])
}

// ─────────────────────────────────────────────────────────────────
// Degenerate areas

pub fn zero_width_area_is_a_no_op_test() {
  let area = geometry.rect_new(2, 1, 0, 3)
  let result = lg.render(buffer.buffer_new(area), area, lg.line_gauge_new(80))
  result |> buffer.area |> should.equal(area)
}

pub fn only_the_first_row_is_drawn_test() {
  let area = geometry.rect_new(0, 0, 8, 3)
  let buf =
    lg.render(
      buffer.buffer_new(area),
      area,
      lg.line_gauge_new(100) |> lg.with_line_set(lg.AsciiLine),
    )
  row(buf, 1)
  |> list.each(fn(s) { s |> should.equal(" ") })
  row(buf, 2)
  |> list.each(fn(s) { s |> should.equal(" ") })
}

pub fn render_respects_the_area_origin_test() {
  let area = geometry.rect_new(3, 2, 10, 1)
  let buf =
    lg.render(
      buffer.buffer_new(geometry.rect_new(0, 0, 20, 5)),
      area,
      lg.line_gauge_new(100) |> lg.with_line_set(lg.AsciiLine),
    )
  symbols(buf, 2, 3, 12)
  |> list.each(fn(s) { s |> should.equal("=") })
}
