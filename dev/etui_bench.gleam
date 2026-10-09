/// Where the frame time actually goes.
///
/// Run: gleam run -m etui_bench
///      gleam run --target javascript -m etui_bench
///
/// Both targets, because they do not share an implementation underneath: the
/// Erlang side fills buffers through a native module and the JavaScript side
/// through the Gleam fallback, so a change that helps one can do nothing for
/// the other.
///
/// Read it as a budget. A 60 fps app has 16 ms a frame; anything here that
/// costs a meaningful slice of that at a realistic terminal size is worth
/// looking at, and anything that does not is not, however clever the fix.
import etui/anim
import etui/backend
import etui/buffer
import etui/geometry.{type Rect, Fill, Length, Max, Min, Percentage, Position}
import etui/span
import etui/style
import etui/terminal
import etui/text
import etui_showcase
import gleam/float
import gleam/int
import gleam/io
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Clock

@target(erlang)
@external(erlang, "erlang", "monotonic_time")
fn now_native(unit: Micro) -> Int

@target(erlang)
type Micro {
  Microsecond
}

@target(erlang)
fn now_us() -> Int {
  now_native(Microsecond)
}

@target(javascript)
@external(javascript, "./bench_ffi.mjs", "nowMicros")
fn now_us() -> Int

// ─────────────────────────────────────────────────────────────────
// Harness

fn repeat(n: Int, work: fn() -> a) -> a {
  case n <= 1 {
    True -> work()
    False -> {
      let _ = work()
      repeat(n - 1, work)
    }
  }
}

fn bench(name: String, iterations: Int, work: fn() -> a) -> Nil {
  // One pass first so the measurement is not paying for cold code.
  let _ = work()
  let start = now_us()
  let _ = repeat(iterations, work)
  let elapsed = now_us() - start
  let per_op = int.to_float(elapsed) /. int.to_float(iterations)
  io.println(
    pad(name, 40)
    <> pad(int.to_string(iterations) <> "x", 9)
    <> pad(float.to_string(round2(per_op)) <> " us", 14)
    <> budget(per_op),
  )
}

/// What one call costs as a share of a 16 ms frame.
fn budget(per_op_us: Float) -> String {
  let pct = per_op_us /. 16_000.0 *. 100.0
  case pct <. 0.1 {
    True -> ""
    False -> float.to_string(round2(pct)) <> "% of a 60fps frame"
  }
}

fn round2(f: Float) -> Float {
  int.to_float(float.round(f *. 100.0)) /. 100.0
}

fn pad(s: String, n: Int) -> String {
  text.pad_right(s, n)
}

fn heading(title: String) -> Nil {
  io.println("")
  io.println(title)
  io.println(string.repeat("─", 72))
}

// ─────────────────────────────────────────────────────────────────
// Fixtures

fn small() -> Rect {
  geometry.rect_new(0, 0, 80, 24)
}

fn large() -> Rect {
  geometry.rect_new(0, 0, 200, 50)
}

fn filled(area: Rect) -> buffer.Buffer {
  buffer.buffer_new_filled(
    area,
    string.repeat("the quick brown fox ", 20),
    style.new(style.Indexed(7), style.Default, style.none()),
  )
}

fn one_cell_changed(area: Rect) -> #(buffer.Buffer, buffer.Buffer) {
  let before = filled(area)
  let after =
    buffer.set_string(
      before,
      Position(3, 3),
      "X",
      style.new(style.Indexed(1), style.Default, style.none()),
    )
  #(before, after)
}

fn showcase_frame(area: Rect) -> buffer.Buffer {
  let model =
    etui_showcase.update(backend.KeyPress("f2"), etui_showcase.initial_model())
  etui_showcase.render(model, area, anim_state())
}

fn anim_state() -> anim.AnimState {
  anim.anim_new()
}

pub fn main() -> Nil {
  io.println("etui render budget")

  heading("allocating a buffer")
  bench("buffer_new 80x24", 2000, fn() { buffer.buffer_new(small()) })
  bench("buffer_new 200x50", 500, fn() { buffer.buffer_new(large()) })
  bench("buffer_new_filled 80x24", 1000, fn() { filled(small()) })
  bench("buffer_new_filled 200x50", 300, fn() { filled(large()) })

  heading("drawing into it")
  bench("set_string one row 80", 5000, fn() {
    buffer.set_string(
      buffer.buffer_new(small()),
      Position(0, 0),
      string.repeat("x", 80),
      style.new(style.Default, style.Default, style.none()),
    )
  })

  heading("turning it into bytes")
  let small_full = filled(small())
  let large_full = filled(large())
  bench("to_ansi 80x24", 500, fn() { buffer.to_ansi(small_full) })
  bench("to_ansi 200x50", 100, fn() { buffer.to_ansi(large_full) })

  heading("diffing, which is what a steady frame does")
  let #(before_s, after_s) = one_cell_changed(small())
  let #(before_l, after_l) = one_cell_changed(large())
  bench("diff unchanged 80x24", 2000, fn() {
    buffer.diff_to_ansi(small_full, small_full)
  })
  bench("diff unchanged 200x50", 500, fn() {
    buffer.diff_to_ansi(large_full, large_full)
  })
  bench("diff one cell 80x24", 2000, fn() {
    buffer.diff_to_ansi(before_s, after_s)
  })
  bench("diff one cell 200x50", 500, fn() {
    buffer.diff_to_ansi(before_l, after_l)
  })
  bench("diff everything 200x50", 100, fn() {
    buffer.diff_to_ansi(buffer.buffer_new(large()), large_full)
  })

  heading("layout")
  bench("resolve_sizes, 8 constraints", 20_000, fn() {
    geometry.resolve_sizes(200, [
      Length(10),
      Percentage(20),
      Min(5),
      Max(30),
      Fill,
      Fill,
      Min(8),
      Percentage(15),
    ])
  })

  heading("text")
  let paragraph = string.repeat("the quick brown fox jumps over ", 40)
  bench("wrap 1200 chars to 80", 2000, fn() { text.wrap(paragraph, 80) })
  bench("styled wrap 1200 chars to 80", 1000, fn() {
    span.wrap(span.text_plain(paragraph), 80)
  })
  let long_word = string.repeat("a", 50_000)
  bench("styled wrap one 50000-char word to 80", 20, fn() {
    span.wrap(span.text_plain(long_word), 80)
  })

  heading("a whole frame, which is the number that matters")
  let frame_area = geometry.rect_new(0, 0, 120, 40)
  let frame = showcase_frame(frame_area)
  bench("render showcase 120x40", 200, fn() { showcase_frame(frame_area) })
  bench("frame_ops, nothing changed", 1000, fn() {
    terminal.frame_ops(frame, frame, False, terminal.CursorUntouched, True)
  })
  io.println("")
}
