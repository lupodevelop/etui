@target(erlang)
/// The code and the numbers in docs/migrating-to-2.0.md.
///
/// A migration guide is read by people who cannot yet tell a mistake in it
/// from a mistake in their own code, so every snippet in that document is
/// also here, compiled on every run, and every "2.0.0" figure in its tables
/// is asserted here rather than remembered.
///
/// The "1.0.1" column of those tables cannot be checked from this repository:
/// it is what the old code did. It was measured by running the same probe
/// against a worktree at the v1.0.1 tag, which the guide says how to redo.
import etui/app
import etui/backend
import etui/buffer
import etui/geometry.{
  type Rect, Fill, FillWeighted, FlexBetween, FlexStart, Horizontal, Length, Max,
  Min, Percentage, Position, Ratio, Size,
}
import etui/keys
import etui/span
import etui/style
import etui/text
import gleam/list
import gleeunit/should

fn area() -> Rect {
  geometry.rect_new(0, 0, 20, 3)
}

// ─────────────────────────────────────────────────────────────────
// "What the compiler will stop on" — the after-snippets, compiled

pub fn a_style_is_built_with_new_test() {
  let s = style.new(style.Indexed(1), style.Default, style.bold())

  s.fg |> should.equal(style.Indexed(1))
  // The two fields the record gained, at their "changes nothing" values.
  style.is_none(s.sub_modifier) |> should.equal(True)
  s.underline_color |> should.equal(style.Default)
  // Which is exactly what the old three-field constructor meant.
  s
  |> should.equal(style.Style(
    fg: style.Indexed(1),
    bg: style.Default,
    modifier: style.bold(),
    sub_modifier: style.none(),
    underline_color: style.Default,
  ))
}

pub fn the_buffer_write_functions_take_a_style_test() {
  let fg = style.Indexed(2)
  let bg = style.Default
  let modifier = style.bold()
  let pos = Position(0, 0)

  let buf =
    buffer.buffer_new(area())
    |> buffer.set_string(pos, "hello", style.new(fg, bg, modifier))
    |> buffer.set_string_linked(
      Position(0, 1),
      "docs",
      style.new(fg, bg, modifier),
      "https://gleam.run",
    )
  let filled =
    buffer.buffer_new_filled(area(), " ", style.new(fg, bg, modifier))
  let cont = buffer.continuation_cell(style.new(fg, bg, modifier))

  buffer.cell_symbol(buffer.get_cell(buf, pos)) |> should.equal("h")
  buffer.cell_fg(buffer.get_cell(filled, pos)) |> should.equal(fg)
  buffer.is_continuation(cont) |> should.equal(True)
}

pub fn a_cell_and_a_span_hold_a_style_test() {
  let fg = style.Indexed(4)
  let bg = style.Default
  let m = style.italic()

  let cell =
    buffer.Cell(
      content: buffer.Content("x", 1),
      style: style.new(fg, bg, m),
      link: "",
    )
  let sp = span.Span(content: "hi", style: style.new(fg, bg, m), link: "")

  // Field access moves one level in; the accessors did not change.
  cell.style.fg |> should.equal(fg)
  buffer.cell_fg(cell) |> should.equal(fg)
  buffer.cell_bg(cell) |> should.equal(bg)
  buffer.cell_modifier(cell) |> should.equal(m)
  buffer.cell_symbol(cell) |> should.equal("x")
  buffer.cell_link(cell) |> should.equal("")
  // And the two the guide calls new.
  buffer.cell_style(cell) |> should.equal(style.new(fg, bg, m))
  buffer.cell_underline_color(cell) |> should.equal(style.Default)
  sp.style.modifier |> should.equal(m)
}

/// The guide says a cell holds a resolved style, and that two cells which
/// look the same compare equal. Both halves, since the second is the reason
/// for the first.
pub fn a_cell_holds_a_resolved_style_test() {
  let long =
    style.new(
      style.Default,
      style.Default,
      style.add(style.bold(), style.italic()),
    )
    |> style.remove_modifier(style.bold())
  let short = style.new(style.Default, style.Default, style.italic())

  let one =
    buffer.buffer_new(area()) |> buffer.set_string(Position(0, 0), "ab", long)
  let two =
    buffer.buffer_new(area()) |> buffer.set_string(Position(0, 0), "ab", short)

  style.is_none(
    buffer.cell_style(buffer.get_cell(one, Position(0, 0))).sub_modifier,
  )
  |> should.equal(True)
  buffer.diff(one, two) |> should.equal([])
}

pub fn split_with_replaces_split_flex_test() {
  let constraints = [Length(6), Length(6), Length(6)]
  geometry.split_with(Horizontal, area(), constraints, FlexBetween, 2)
  |> list.length
  |> should.equal(3)
}

@target(erlang)
pub fn the_poll_timeout_is_a_function_test() {
  let quiet =
    backend.Backend(
      init: fn() { Ok(Nil) },
      render: fn(s, _ops) { Ok(s) },
      poll: fn(s, _timeout) { Ok(#(backend.Tick, s)) },
      next_size: fn(s) { Ok(#(backend.TerminalSize(80, 24), s)) },
      cleanup: fn(_s) { Nil },
    )
  let result =
    app.run_buffered(
      quiet,
      0,
      fn(_, screen) { buffer.buffer_new(screen) },
      fn(_, m) { m },
      fn(_) { True },
      fn(_) { 16 },
    )
  case result {
    app.Success(_) -> Nil
    _ -> panic as "loop did not succeed"
  }
}

// ─────────────────────────────────────────────────────────────────
// "What still compiles and now behaves differently"
//
// The 2.0.0 column of every table in the guide.

fn sizes(constraints: List(geometry.Constraint)) -> List(Int) {
  geometry.resolve_sizes(100, constraints)
}

pub fn the_layout_table_is_what_the_guide_says_test() {
  // Rows where 2.0 differs from 1.0.1.
  sizes([Min(60), Min(60)]) |> should.equal([50, 50])
  sizes([Min(80), Min(80)]) |> should.equal([50, 50])
  sizes([Min(50), Max(20)]) |> should.equal([80, 20])
  sizes([Min(30), Max(40), Fill]) |> should.equal([34, 33, 33])

  // Rows the guide lists as unchanged.
  sizes([Min(60), Fill]) |> should.equal([60, 40])
  sizes([Min(20), Fill]) |> should.equal([50, 50])
  sizes([Min(60), Fill, Fill]) |> should.equal([60, 20, 20])
  sizes([Max(20), Min(50), Fill]) |> should.equal([20, 50, 30])
  sizes([Max(10), Fill]) |> should.equal([10, 90])
  sizes([Length(10), Fill, Fill]) |> should.equal([10, 45, 45])
  sizes([Percentage(30), Fill]) |> should.equal([30, 70])
  sizes([Ratio(1, 3), Fill]) |> should.equal([33, 67])

  // And the one the guide warns about: a ceiling is not a claim.
  sizes([Max(30), Max(30)]) |> should.equal([30, 30])
}

pub fn fill_is_fill_weighted_one_test() {
  sizes([FillWeighted(1), FillWeighted(2)])
  |> should.equal(sizes([Fill, FillWeighted(2)]))
}

fn lefts(flex: geometry.Flex, spacing: Int) -> List(Int) {
  let row = geometry.Rect(Position(0, 0), Size(width: 40, height: 1))
  geometry.split_with(
    Horizontal,
    row,
    [Length(6), Length(6), Length(6)],
    flex,
    spacing,
  )
  |> list.map(fn(r) { r.position.x })
}

pub fn spacing_composes_with_flex_test() {
  // The guide's table: FlexBetween reaches the right edge, spacing or not.
  lefts(FlexBetween, 0) |> should.equal([0, 17, 34])
  lefts(FlexBetween, 2) |> should.equal([0, 17, 34])
  // 34 + 6 is 40, the full width.
  lefts(FlexStart, 2) |> should.equal([0, 8, 16])
}

pub fn keys_match_refuses_a_multi_grapheme_key_test() {
  keys.match("shift+left") |> should.equal(keys.Unknown("shift+left"))
  keys.match("ctrl+c") |> should.equal(keys.Ctrl("c"))
  keys.match("a") |> should.equal(keys.Char("a"))
}

/// The `keys.parse` example from the guide, as code that runs.
pub fn keys_parse_gives_the_modifier_as_data_test() {
  let handle = fn(raw) {
    case keys.parse(raw) {
      keys.KeyEvent(keys.Left, keys.Modifiers(shift: True, ..)) -> "select"
      keys.KeyEvent(keys.Left, _) -> "move"
      _ -> "ignore"
    }
  }

  handle("shift+left") |> should.equal("select")
  handle("left") |> should.equal("move")
  handle("q") |> should.equal("ignore")
}

pub fn wrap_normalises_tabs_and_line_endings_test() {
  text.wrap("a\tb", 20) |> should.equal(["a       b"])
  text.wrap("a\r\nb", 20) |> should.equal(["a", "b"])
}

pub fn every_target_enables_the_same_mouse_modes_test() {
  backend.op_to_ansi(backend.EnableMouse)
  |> should.equal("\u{001B}[?1002h\u{001B}[?1006h")
  // Disabling still clears 1000, which nothing enables any more.
  backend.op_to_ansi(backend.DisableMouse)
  |> fn(seq) { seq }
  |> should.equal(
    "\u{001B}[?1007l\u{001B}[?1015l\u{001B}[?1006l\u{001B}[?1005l\u{001B}[?1003l\u{001B}[?1002l\u{001B}[?1000l",
  )
}

// ─────────────────────────────────────────────────────────────────
// "Worth adopting" — the pieces the guide points at exist and work

pub fn the_new_pieces_the_guide_names_exist_test() {
  span.span_styled("teh", style.underline_style())
  |> span.span_underline_color(style.Rgb(220, 60, 60))
  |> fn(sp) { sp.style.underline_color }
  |> should.equal(style.Rgb(220, 60, 60))

  backend.restore_sequence()
  |> fn(s) { s != "" }
  |> should.equal(True)
}
