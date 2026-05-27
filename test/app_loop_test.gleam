@target(erlang)
/// Drives every erlang app loop (`run`, `run_buffered`, `run_animated`,
/// `run_buffered_cursor`) end to end against a scripted mock backend.
/// This is the safety net for the shared `step` core in `etui/app`.
import etui/app
import etui/backend
import etui/buffer
import etui/geometry.{Fill, Horizontal, Length, Percentage, rect_new, split}
import etui/style
import etui/widgets/block
import etui/widgets/gauge
import etui/widgets/list as glist
import etui/widgets/table
import gleam/list
import gleeunit/should

// ─────────────────────────────────────────────────────────────────
// Mock backend: poll replays a fixed event script, one event per frame.

@target(erlang)
type MockState {
  MockState(events: List(backend.InputEvent))
}

@target(erlang)
fn mock_backend(
  events: List(backend.InputEvent),
) -> backend.Backend(MockState) {
  backend.Backend(
    init: fn() { Ok(MockState(events: events)) },
    render: fn(s, _ops) { Ok(s) },
    poll: fn(s, _timeout) {
      case s.events {
        [ev, ..rest] -> Ok(#(ev, MockState(events: rest)))
        // Script exhausted: a poll failure ends the loop (StepQuit path).
        [] -> Error(backend.Interrupted)
      }
    },
    next_size: fn(s) { Ok(#(backend.TerminalSize(80, 24), s)) },
    cleanup: fn(_s) { Nil },
  )
}

// ─────────────────────────────────────────────────────────────────
// Test model: counts non-quit key presses, quits on "q".

@target(erlang)
type Counter {
  Counter(count: Int, quit: Bool)
}

@target(erlang)
fn count_update(ev: backend.InputEvent, m: Counter) -> Counter {
  case ev {
    backend.KeyPress("q") -> Counter(..m, quit: True)
    backend.KeyPress(_) -> Counter(..m, count: m.count + 1)
    _ -> m
  }
}

@target(erlang)
fn count_quit(m: Counter) -> Bool {
  m.quit
}

// ─────────────────────────────────────────────────────────────────
// Tests: each entry point drives the script to the quit condition.

@target(erlang)
pub fn run_drives_to_quit_test() {
  let result =
    app.run(
      mock_backend([backend.KeyPress("x"), backend.KeyPress("q")]),
      Counter(count: 0, quit: False),
      fn(_m) { [] },
      count_update,
      count_quit,
      16,
    )
  result |> should.equal(app.Success(Counter(count: 1, quit: True)))
}

@target(erlang)
pub fn run_buffered_drives_to_quit_test() {
  let result =
    app.run_buffered(
      mock_backend([
        backend.KeyPress("a"),
        backend.KeyPress("b"),
        backend.KeyPress("q"),
      ]),
      Counter(count: 0, quit: False),
      fn(_m, screen) { buffer.buffer_new(screen) },
      count_update,
      count_quit,
      16,
    )
  result |> should.equal(app.Success(Counter(count: 2, quit: True)))
}

@target(erlang)
pub fn run_animated_drives_to_quit_test() {
  let result =
    app.run_animated(
      mock_backend([backend.KeyPress("q")]),
      Counter(count: 0, quit: False),
      fn(_m, screen, _anim) { buffer.buffer_new(screen) },
      count_update,
      count_quit,
      16,
    )
  result |> should.equal(app.Success(Counter(count: 0, quit: True)))
}

@target(erlang)
pub fn run_buffered_cursor_drives_to_quit_test() {
  let result =
    app.run_buffered_cursor(
      mock_backend([backend.KeyPress("z"), backend.KeyPress("q")]),
      Counter(count: 0, quit: False),
      fn(_m, screen) { #(buffer.buffer_new(screen), Error(Nil)) },
      count_update,
      count_quit,
      16,
    )
  result |> should.equal(app.Success(Counter(count: 1, quit: True)))
}

// A script with no quit event: poll runs dry, the loop ends with the
// state reached so far. Exercises `step`'s poll-failure StepQuit branch.
@target(erlang)
pub fn run_buffered_poll_failure_ends_loop_test() {
  let result =
    app.run_buffered(
      mock_backend([backend.KeyPress("a")]),
      Counter(count: 0, quit: False),
      fn(_m, screen) { buffer.buffer_new(screen) },
      count_update,
      count_quit,
      16,
    )
  result |> should.equal(app.Success(Counter(count: 1, quit: False)))
}

// Doc snippets in `docs/` must keep compiling (layout, widgets, style).
@target(erlang)
pub fn doc_snippets_compile_test() {
  let area = rect_new(0, 0, 80, 24)
  let buf = buffer.buffer_new(area)
  let cols = split(Horizontal, area, [Length(20), Percentage(50), Fill])
  cols |> list.length |> should.equal(3)

  style.Style(
    fg: style.Rgb(255, 128, 0),
    bg: style.Indexed(0),
    modifier: style.bold(),
  )
  |> fn(s) { s.fg }
  |> should.equal(style.Rgb(255, 128, 0))

  let blk = block.block_new() |> block.with_border(block.Rounded)
  let _ = block.render(buf, area, blk)
  let _ =
    glist.render_stateful(buf, area, glist.list_new(["a"]), glist.state_new())
  let _ =
    table.render_stateful(
      buf,
      area,
      table.table_new([["x"]]),
      table.state_new(),
    )
  let _ = gauge.render(buf, area, gauge.gauge_new(50))
}
