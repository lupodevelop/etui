/// Application event loop. Type-safe, with crash-restore guarantees.
///
/// `run` wraps the entire loop in a `try...after` (via FFI) so that the
/// terminal is always restored, even if the user's render or event
/// function panics. No more broken TTY on crash.
///
/// `run_buffered` is the high-level alternative: the render function returns
/// a `Buffer` instead of a list of `RenderOp`s. The app loop handles diffing
/// automatically, only changed cells are emitted each frame.
///
/// `run_animated` is like `run_buffered` but also passes the current
/// `anim.AnimState` to the render function, auto-ticking every frame.
/// Use it when your UI has spinners, marquees, blinking cursors, or other
/// frame-dependent widgets, no need to store `AnimState` in your model.
import etui/anim
import etui/backend.{type InputEvent, type RenderOp}
import etui/buffer
import etui/cursor
import etui/geometry

@target(javascript)
import gleam/javascript/promise

pub type AppResult(state) {
  Success(final_state: state)
  Error(reason: String)
}

// Erlang try/after: runs cleanup even on panic. Returns thunk's value.
// JS fallback: cleanup registered via backend's register_cleanup_ffi (signal handlers).
@external(erlang, "etui_run_ffi", "with_cleanup")
fn with_cleanup(thunk: fn() -> a, cleanup: fn() -> Nil) -> a {
  let _ = cleanup
  thunk()
}

@target(erlang)
/// Run the app loop.
///
/// Lifecycle:
/// 1. `b.init()`, enter raw mode, alt screen.
/// 2. Loop: `render(state)` → emit ops → `b.poll()` → `on_event()`.
/// 3. Exit when `should_quit(state)` returns `True`.
/// 4. `b.cleanup()`, always runs, even on panic.
///
/// ```gleam
/// app.run(
///   default.new(),
///   Model(count: 0),
///   fn(m) { [Write(int.to_string(m.count))] },
///   fn(ev, m) { case ev { KeyPress("q") -> m KeyPress(_) -> Model(count: m.count + 1) _ -> m } },
///   fn(m) { m.count >= 10 },
///   16,
/// )
/// ```
pub fn run(
  b: backend.Backend(backend_state),
  init_state: state,
  render: fn(state) -> List(RenderOp),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> AppResult(state) {
  case b.init() {
    Ok(bs) ->
      // with_cleanup guarantees b.cleanup(bs) runs on both normal exit
      // and panic. On normal exit the thunk returns Success(state);
      // on panic after runs, terminal is restored, exception re-raises.
      with_cleanup(
        fn() {
          let #(final_state, final_bs) =
            loop(
              b,
              bs,
              init_state,
              render,
              on_event,
              should_quit,
              poll_timeout_ms,
            )
          b.cleanup(final_bs)
          Success(final_state)
        },
        fn() { b.cleanup(bs) },
      )
    _ -> Error("Terminal init failed")
  }
}

@target(erlang)
type LoopStep(s, bst) {
  StepQuit(state: s, bs: bst)
  StepContinue(event: InputEvent, state: s, bs: bst)
}

// Shared core of the erlang app loops: render ops, poll one event, update
// the model, test for quit. A failed render or poll ends the loop. Each loop
// keeps its own frame-building (diff, anim, cursor).
@target(erlang)
fn step(
  b: backend.Backend(backend_state),
  bs: backend_state,
  state: state,
  ops: List(RenderOp),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> LoopStep(state, backend_state) {
  case b.render(bs, ops) {
    Ok(bs2) ->
      case b.poll(bs2, poll_timeout_ms) {
        Ok(#(event, bs3)) -> {
          let next = on_event(event, state)
          case should_quit(next) {
            True -> StepQuit(next, bs3)
            False -> StepContinue(event, next, bs3)
          }
        }
        _ -> StepQuit(state, bs2)
      }
    _ -> StepQuit(state, bs)
  }
}

@target(erlang)
fn loop(
  b: backend.Backend(backend_state),
  bs: backend_state,
  state: state,
  render: fn(state) -> List(RenderOp),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> #(state, backend_state) {
  case
    step(b, bs, state, render(state), on_event, should_quit, poll_timeout_ms)
  {
    StepQuit(s, final_bs) -> #(s, final_bs)
    StepContinue(_event, next, bs3) ->
      loop(b, bs3, next, render, on_event, should_quit, poll_timeout_ms)
  }
}

// ─────────────────────────────────────────────────────────────────
// Buffered app loop (automatic diff rendering)

@target(erlang)
/// High-level app loop. The render function produces a `Buffer`; the loop
/// diffs it against the previous frame and emits only the changed cells.
///
/// First frame: full `to_ansi` (clean slate). Subsequent frames: `diff_to_ansi`.
/// On `Resize`: full re-render at new size.
///
/// ```gleam
/// app.run_buffered(
///   default.new(),
///   Model(count: 0),
///   fn(m, screen) {
///     buffer.buffer_new(screen)
///     |> paragraph.render(screen, paragraph.paragraph_new(int.to_string(m.count)))
///   },
///   fn(ev, m) { case ev { KeyPress("q") -> m _ -> m } },
///   fn(m) { m.quit },
///   16,
/// )
/// ```
pub fn run_buffered(
  b: backend.Backend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> AppResult(state) {
  case b.init() {
    Ok(bs) ->
      with_cleanup(
        fn() {
          // A buffered app draws every cell itself, so the hardware cursor
          // would only sit blinking wherever the last write landed. Hide it
          // for the session and restore it on exit.
          let _ = b.render(bs, [backend.Write(cursor.hide())])
          let #(size, bs2) = case b.next_size(bs) {
            Ok(#(sz, bs1)) -> #(sz, bs1)
            _ -> #(backend.TerminalSize(width: 80, height: 24), bs)
          }
          let screen = geometry.rect_new(0, 0, size.width, size.height)
          let blank = buffer.buffer_new(screen)
          let init_state =
            on_event(backend.Resize(size.width, size.height), init_state)
          let #(final_state, final_bs) =
            loop_buffered(
              b,
              bs2,
              init_state,
              render,
              on_event,
              should_quit,
              poll_timeout_ms,
              blank,
              True,
            )
          let _ = b.render(final_bs, [backend.Write(cursor.show())])
          b.cleanup(final_bs)
          Success(final_state)
        },
        fn() {
          let _ = b.render(bs, [backend.Write(cursor.show())])
          b.cleanup(bs)
        },
      )
    _ -> Error("Terminal init failed")
  }
}

@target(erlang)
fn loop_buffered(
  b: backend.Backend(backend_state),
  bs: backend_state,
  state: state,
  render: fn(state, geometry.Rect) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
  prev_buf: buffer.Buffer,
  first_frame: Bool,
) -> #(state, backend_state) {
  let screen = buffer.area(prev_buf)
  let curr_buf = render(state, screen)
  let ansi = case first_frame {
    True -> buffer.to_ansi(curr_buf)
    False -> buffer.diff_to_ansi(prev_buf, curr_buf)
  }
  let ops = case ansi {
    "" -> []
    _ ->
      case first_frame {
        True -> [
          backend.ClearScreen,
          backend.MoveCursor(0, 0),
          backend.Write(ansi),
        ]
        False -> [backend.Write(ansi)]
      }
  }
  case step(b, bs, state, ops, on_event, should_quit, poll_timeout_ms) {
    StepQuit(s, final_bs) -> #(s, final_bs)
    StepContinue(event, next, bs3) -> {
      let #(new_prev, is_first) = case event {
        backend.Resize(w, h) -> {
          let new_screen = geometry.rect_new(0, 0, w, h)
          #(buffer.buffer_new(new_screen), True)
        }
        _ -> #(curr_buf, False)
      }
      loop_buffered(
        b,
        bs3,
        next,
        render,
        on_event,
        should_quit,
        poll_timeout_ms,
        new_prev,
        is_first,
      )
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Animated buffered app loop (auto-tick AnimState)

@target(erlang)
/// Like `run_buffered` but passes an `anim.AnimState` to the render function,
/// auto-ticked every frame. Use when your UI has spinners, blinking widgets,
/// marquees, or any frame-dependent animation, no manual tick needed.
///
/// ```gleam
/// app.run_animated(
///   default.new(),
///   Model(quit: False),
///   fn(m, screen, anim_state) {
///     let frame = anim_state.frame
///     buffer.buffer_new(screen)
///     |> spinner.render(area, spinner.spinner_new() |> spinner.with_frame(frame))
///   },
///   fn(ev, m) { case ev { backend.KeyPress("q") -> Model(quit: True) _ -> m } },
///   fn(m) { m.quit },
///   16,
/// )
/// ```
pub fn run_animated(
  b: backend.Backend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect, anim.AnimState) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> AppResult(state) {
  case b.init() {
    Ok(bs) ->
      with_cleanup(
        fn() {
          let _ = b.render(bs, [backend.Write(cursor.hide())])
          let #(size, bs2) = case b.next_size(bs) {
            Ok(#(sz, bs1)) -> #(sz, bs1)
            _ -> #(backend.TerminalSize(width: 80, height: 24), bs)
          }
          let screen = geometry.rect_new(0, 0, size.width, size.height)
          let blank = buffer.buffer_new(screen)
          let init_state =
            on_event(backend.Resize(size.width, size.height), init_state)
          let #(final_state, final_bs) =
            loop_animated(
              b,
              bs2,
              init_state,
              render,
              on_event,
              should_quit,
              poll_timeout_ms,
              blank,
              True,
              anim.anim_new(),
            )
          let _ = b.render(final_bs, [backend.Write(cursor.show())])
          b.cleanup(final_bs)
          Success(final_state)
        },
        fn() {
          let _ = b.render(bs, [backend.Write(cursor.show())])
          b.cleanup(bs)
        },
      )
    _ -> Error("Terminal init failed")
  }
}

@target(erlang)
fn loop_animated(
  b: backend.Backend(backend_state),
  bs: backend_state,
  state: state,
  render: fn(state, geometry.Rect, anim.AnimState) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
  prev_buf: buffer.Buffer,
  first_frame: Bool,
  anim_state: anim.AnimState,
) -> #(state, backend_state) {
  let screen = buffer.area(prev_buf)
  let curr_buf = render(state, screen, anim_state)
  let ansi = case first_frame {
    True -> buffer.to_ansi(curr_buf)
    False -> buffer.diff_to_ansi(prev_buf, curr_buf)
  }
  let ops = case ansi {
    "" -> []
    _ ->
      case first_frame {
        True -> [
          backend.ClearScreen,
          backend.MoveCursor(0, 0),
          backend.Write(ansi),
        ]
        False -> [backend.Write(ansi)]
      }
  }
  let next_anim = anim.tick(anim_state)
  case step(b, bs, state, ops, on_event, should_quit, poll_timeout_ms) {
    StepQuit(s, final_bs) -> #(s, final_bs)
    StepContinue(event, next, bs3) -> {
      let #(new_prev, is_first) = case event {
        backend.Resize(w, h) -> {
          let new_screen = geometry.rect_new(0, 0, w, h)
          #(buffer.buffer_new(new_screen), True)
        }
        _ -> #(curr_buf, False)
      }
      loop_animated(
        b,
        bs3,
        next,
        render,
        on_event,
        should_quit,
        poll_timeout_ms,
        new_prev,
        is_first,
        next_anim,
      )
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Buffered loop with hardware cursor positioning

@target(erlang)
/// Like `run_buffered` but the render function also returns an optional cursor
/// position as `Result(geometry.Position, Nil)`.
///
/// - `Ok(pos)`, shows the cursor at `pos` (0-based). Use for text inputs and
///   text areas where the user needs to see the insertion point.
/// - `Error(Nil)`, hides the cursor. Use for read-only views.
///
/// The cursor is hidden automatically on init and restored on exit.
///
/// ```gleam
/// app.run_buffered_cursor(
///   default.new(),
///   Model(text: "", cursor: 0),
///   fn(m, screen) {
///     let buf = buffer.buffer_new(screen) |> input.render(area, w, input_state)
///     let cursor_pos = geometry.Position(x: area.x + input_state.cursor_x + 1, y: area.y)
///     #(buf, Ok(cursor_pos))
///   },
///   on_event,
///   fn(m) { m.quit },
///   16,
/// )
/// ```
pub fn run_buffered_cursor(
  b: backend.Backend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect) ->
    #(buffer.Buffer, Result(geometry.Position, Nil)),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> AppResult(state) {
  case b.init() {
    Ok(bs) ->
      with_cleanup(
        fn() {
          let #(size, bs2) = case b.next_size(bs) {
            Ok(#(sz, bs1)) -> #(sz, bs1)
            _ -> #(backend.TerminalSize(width: 80, height: 24), bs)
          }
          let screen = geometry.rect_new(0, 0, size.width, size.height)
          let blank = buffer.buffer_new(screen)
          // Hide cursor on init; render loop will show it when needed.
          let _ = b.render(bs2, [backend.Write(cursor.hide())])
          let init_state =
            on_event(backend.Resize(size.width, size.height), init_state)
          let #(final_state, final_bs) =
            loop_buffered_cursor(
              b,
              bs2,
              init_state,
              render,
              on_event,
              should_quit,
              poll_timeout_ms,
              blank,
              True,
            )
          // Restore cursor visibility on exit.
          let _ = b.render(final_bs, [backend.Write(cursor.show())])
          b.cleanup(final_bs)
          Success(final_state)
        },
        fn() {
          let _ = b.render(bs, [backend.Write(cursor.show())])
          b.cleanup(bs)
        },
      )
    _ -> Error("Terminal init failed")
  }
}

@target(erlang)
fn loop_buffered_cursor(
  b: backend.Backend(backend_state),
  bs: backend_state,
  state: state,
  render: fn(state, geometry.Rect) ->
    #(buffer.Buffer, Result(geometry.Position, Nil)),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
  prev_buf: buffer.Buffer,
  first_frame: Bool,
) -> #(state, backend_state) {
  let screen = buffer.area(prev_buf)
  let #(curr_buf, cursor_pos) = render(state, screen)
  let ansi = case first_frame {
    True -> buffer.to_ansi(curr_buf)
    False -> buffer.diff_to_ansi(prev_buf, curr_buf)
  }
  let cursor_ansi = case cursor_pos {
    Ok(pos) ->
      cursor.hide() <> cursor.move_to(pos.y + 1, pos.x + 1) <> cursor.show()
    _ -> cursor.hide()
  }
  let ops = case ansi {
    "" -> [backend.Write(cursor_ansi)]
    _ ->
      case first_frame {
        True -> [
          backend.ClearScreen,
          backend.MoveCursor(0, 0),
          backend.Write(ansi <> cursor_ansi),
        ]
        False -> [backend.Write(ansi <> cursor_ansi)]
      }
  }
  case step(b, bs, state, ops, on_event, should_quit, poll_timeout_ms) {
    StepQuit(s, final_bs) -> #(s, final_bs)
    StepContinue(event, next, bs3) -> {
      let #(new_prev, is_first) = case event {
        backend.Resize(w, h) -> {
          let new_screen = geometry.rect_new(0, 0, w, h)
          #(buffer.buffer_new(new_screen), True)
        }
        _ -> #(curr_buf, False)
      }
      loop_buffered_cursor(
        b,
        bs3,
        next,
        render,
        on_event,
        should_quit,
        poll_timeout_ms,
        new_prev,
        is_first,
      )
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// JavaScript async app loops (Node.js target)

@target(javascript)
pub fn run(
  b: backend.AsyncBackend(backend_state),
  init_state: state,
  render: fn(state) -> List(RenderOp),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> promise.Promise(AppResult(state)) {
  case b.init() {
    Ok(bs) ->
      with_cleanup(
        fn() {
          promise.await(
            loop_js(
              b,
              bs,
              init_state,
              render,
              on_event,
              should_quit,
              poll_timeout_ms,
            ),
            fn(r) {
              let #(final_state, final_bs) = r
              b.cleanup(final_bs)
              promise.resolve(Success(final_state))
            },
          )
        },
        fn() { b.cleanup(bs) },
      )
    _ -> promise.resolve(Error("Terminal init failed"))
  }
}

@target(javascript)
fn loop_js(
  b: backend.AsyncBackend(backend_state),
  bs: backend_state,
  state: state,
  render: fn(state) -> List(RenderOp),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> promise.Promise(#(state, backend_state)) {
  case b.render(bs, render(state)) {
    Ok(bs2) ->
      promise.await(b.poll(bs2, poll_timeout_ms), fn(poll_result) {
        case poll_result {
          Ok(#(event, bs3)) -> {
            let next = on_event(event, state)
            case should_quit(next) {
              True -> promise.resolve(#(next, bs3))
              False ->
                loop_js(
                  b,
                  bs3,
                  next,
                  render,
                  on_event,
                  should_quit,
                  poll_timeout_ms,
                )
            }
          }
          _ -> promise.resolve(#(state, bs2))
        }
      })
    _ -> promise.resolve(#(state, bs))
  }
}

@target(javascript)
pub fn run_buffered(
  b: backend.AsyncBackend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> promise.Promise(AppResult(state)) {
  case b.init() {
    Ok(bs) ->
      with_cleanup(
        fn() {
          let #(size, bs2) = case b.next_size(bs) {
            Ok(#(sz, bs1)) -> #(sz, bs1)
            _ -> #(backend.TerminalSize(width: 80, height: 24), bs)
          }
          let screen = geometry.rect_new(0, 0, size.width, size.height)
          let blank = buffer.buffer_new(screen)
          let init_state =
            on_event(backend.Resize(size.width, size.height), init_state)
          promise.await(
            loop_buffered_js(
              b,
              bs2,
              init_state,
              render,
              on_event,
              should_quit,
              poll_timeout_ms,
              blank,
              True,
            ),
            fn(r) {
              let #(final_state, final_bs) = r
              b.cleanup(final_bs)
              promise.resolve(Success(final_state))
            },
          )
        },
        fn() { b.cleanup(bs) },
      )
    _ -> promise.resolve(Error("Terminal init failed"))
  }
}

@target(javascript)
fn loop_buffered_js(
  b: backend.AsyncBackend(backend_state),
  bs: backend_state,
  state: state,
  render: fn(state, geometry.Rect) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
  prev_buf: buffer.Buffer,
  first_frame: Bool,
) -> promise.Promise(#(state, backend_state)) {
  let screen = buffer.area(prev_buf)
  let curr_buf = render(state, screen)
  let ansi = case first_frame {
    True -> buffer.to_ansi(curr_buf)
    False -> buffer.diff_to_ansi(prev_buf, curr_buf)
  }
  let ops = case ansi {
    "" -> []
    _ ->
      case first_frame {
        True -> [
          backend.ClearScreen,
          backend.MoveCursor(0, 0),
          backend.Write(ansi),
        ]
        False -> [backend.Write(ansi)]
      }
  }
  case b.render(bs, ops) {
    Ok(bs2) ->
      promise.await(b.poll(bs2, poll_timeout_ms), fn(poll_result) {
        case poll_result {
          Ok(#(event, bs3)) -> {
            let next = on_event(event, state)
            case should_quit(next) {
              True -> promise.resolve(#(next, bs3))
              False -> {
                let #(new_prev, is_first) = case event {
                  backend.Resize(w, h) -> {
                    let new_screen = geometry.rect_new(0, 0, w, h)
                    #(buffer.buffer_new(new_screen), True)
                  }
                  _ -> #(curr_buf, False)
                }
                loop_buffered_js(
                  b,
                  bs3,
                  next,
                  render,
                  on_event,
                  should_quit,
                  poll_timeout_ms,
                  new_prev,
                  is_first,
                )
              }
            }
          }
          _ -> promise.resolve(#(state, bs2))
        }
      })
    _ -> promise.resolve(#(state, bs))
  }
}

@target(javascript)
pub fn run_animated(
  b: backend.AsyncBackend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect, anim.AnimState) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> promise.Promise(AppResult(state)) {
  case b.init() {
    Ok(bs) ->
      with_cleanup(
        fn() {
          let _ = b.render(bs, [backend.Write(cursor.hide())])
          let #(size, bs2) = case b.next_size(bs) {
            Ok(#(sz, bs1)) -> #(sz, bs1)
            _ -> #(backend.TerminalSize(width: 80, height: 24), bs)
          }
          let screen = geometry.rect_new(0, 0, size.width, size.height)
          let blank = buffer.buffer_new(screen)
          let init_state =
            on_event(backend.Resize(size.width, size.height), init_state)
          promise.await(
            loop_animated_js(
              b,
              bs2,
              init_state,
              render,
              on_event,
              should_quit,
              poll_timeout_ms,
              blank,
              True,
              anim.anim_new(),
            ),
            fn(r) {
              let #(final_state, final_bs) = r
              let _ = b.render(final_bs, [backend.Write(cursor.show())])
              b.cleanup(final_bs)
              promise.resolve(Success(final_state))
            },
          )
        },
        fn() {
          let _ = b.render(bs, [backend.Write(cursor.show())])
          b.cleanup(bs)
        },
      )
    _ -> promise.resolve(Error("Terminal init failed"))
  }
}

@target(javascript)
fn loop_animated_js(
  b: backend.AsyncBackend(backend_state),
  bs: backend_state,
  state: state,
  render: fn(state, geometry.Rect, anim.AnimState) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
  prev_buf: buffer.Buffer,
  first_frame: Bool,
  anim_state: anim.AnimState,
) -> promise.Promise(#(state, backend_state)) {
  let screen = buffer.area(prev_buf)
  let curr_buf = render(state, screen, anim_state)
  let ansi = case first_frame {
    True -> buffer.to_ansi(curr_buf)
    False -> buffer.diff_to_ansi(prev_buf, curr_buf)
  }
  let ops = case ansi {
    "" -> []
    _ ->
      case first_frame {
        True -> [
          backend.ClearScreen,
          backend.MoveCursor(0, 0),
          backend.Write(ansi),
        ]
        False -> [backend.Write(ansi)]
      }
  }
  let next_anim = anim.tick(anim_state)
  case b.render(bs, ops) {
    Ok(bs2) ->
      promise.await(b.poll(bs2, poll_timeout_ms), fn(poll_result) {
        case poll_result {
          Ok(#(event, bs3)) -> {
            let next = on_event(event, state)
            case should_quit(next) {
              True -> promise.resolve(#(next, bs3))
              False -> {
                let #(new_prev, is_first) = case event {
                  backend.Resize(w, h) -> {
                    let new_screen = geometry.rect_new(0, 0, w, h)
                    #(buffer.buffer_new(new_screen), True)
                  }
                  _ -> #(curr_buf, False)
                }
                loop_animated_js(
                  b,
                  bs3,
                  next,
                  render,
                  on_event,
                  should_quit,
                  poll_timeout_ms,
                  new_prev,
                  is_first,
                  next_anim,
                )
              }
            }
          }
          _ -> promise.resolve(#(state, bs2))
        }
      })
    _ -> promise.resolve(#(state, bs))
  }
}

@target(javascript)
pub fn run_buffered_cursor(
  b: backend.AsyncBackend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect) ->
    #(buffer.Buffer, Result(geometry.Position, Nil)),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
) -> promise.Promise(AppResult(state)) {
  case b.init() {
    Ok(bs) ->
      with_cleanup(
        fn() {
          let #(size, bs2) = case b.next_size(bs) {
            Ok(#(sz, bs1)) -> #(sz, bs1)
            _ -> #(backend.TerminalSize(width: 80, height: 24), bs)
          }
          let screen = geometry.rect_new(0, 0, size.width, size.height)
          let blank = buffer.buffer_new(screen)
          let _ = b.render(bs2, [backend.Write(cursor.hide())])
          let init_state =
            on_event(backend.Resize(size.width, size.height), init_state)
          promise.await(
            loop_buffered_cursor_js(
              b,
              bs2,
              init_state,
              render,
              on_event,
              should_quit,
              poll_timeout_ms,
              blank,
              True,
            ),
            fn(r) {
              let #(final_state, final_bs) = r
              let _ = b.render(final_bs, [backend.Write(cursor.show())])
              b.cleanup(final_bs)
              promise.resolve(Success(final_state))
            },
          )
        },
        fn() {
          let _ = b.render(bs, [backend.Write(cursor.show())])
          b.cleanup(bs)
        },
      )
    _ -> promise.resolve(Error("Terminal init failed"))
  }
}

@target(javascript)
fn loop_buffered_cursor_js(
  b: backend.AsyncBackend(backend_state),
  bs: backend_state,
  state: state,
  render: fn(state, geometry.Rect) ->
    #(buffer.Buffer, Result(geometry.Position, Nil)),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: Int,
  prev_buf: buffer.Buffer,
  first_frame: Bool,
) -> promise.Promise(#(state, backend_state)) {
  let screen = buffer.area(prev_buf)
  let #(curr_buf, cursor_pos) = render(state, screen)
  let ansi = case first_frame {
    True -> buffer.to_ansi(curr_buf)
    False -> buffer.diff_to_ansi(prev_buf, curr_buf)
  }
  let cursor_ansi = case cursor_pos {
    Ok(pos) ->
      cursor.hide() <> cursor.move_to(pos.y + 1, pos.x + 1) <> cursor.show()
    _ -> cursor.hide()
  }
  let ops = case ansi {
    "" -> [backend.Write(cursor_ansi)]
    _ ->
      case first_frame {
        True -> [
          backend.ClearScreen,
          backend.MoveCursor(0, 0),
          backend.Write(ansi <> cursor_ansi),
        ]
        False -> [backend.Write(ansi <> cursor_ansi)]
      }
  }
  case b.render(bs, ops) {
    Ok(bs2) ->
      promise.await(b.poll(bs2, poll_timeout_ms), fn(poll_result) {
        case poll_result {
          Ok(#(event, bs3)) -> {
            let next = on_event(event, state)
            case should_quit(next) {
              True -> promise.resolve(#(next, bs3))
              False -> {
                let #(new_prev, is_first) = case event {
                  backend.Resize(w, h) -> {
                    let new_screen = geometry.rect_new(0, 0, w, h)
                    #(buffer.buffer_new(new_screen), True)
                  }
                  _ -> #(curr_buf, False)
                }
                loop_buffered_cursor_js(
                  b,
                  bs3,
                  next,
                  render,
                  on_event,
                  should_quit,
                  poll_timeout_ms,
                  new_prev,
                  is_first,
                )
              }
            }
          }
          _ -> promise.resolve(#(state, bs2))
        }
      })
    _ -> promise.resolve(#(state, bs))
  }
}
