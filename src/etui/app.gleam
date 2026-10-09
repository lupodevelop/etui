/// Application event loops.
///
/// These own the loop for you: hand one a render function and an event
/// handler and it runs until `should_quit` says otherwise, restoring the
/// terminal on the way out even if your code panics.
///
/// | Loop | Render function returns |
/// |------|--------------------------|
/// | `run` | a list of `RenderOp`, for drawing without a buffer |
/// | `run_buffered` | a `Buffer`, diffed against the last frame |
/// | `run_animated` | a `Buffer`, and is given a ticking `anim.AnimState` |
/// | `run_buffered_cursor` | a `Buffer` and where the hardware cursor belongs |
///
/// The three buffered loops are thin wrappers over `etui/terminal`. If you
/// need the loop to be yours, because the terminal is not the only thing your
/// program is doing, use that module directly.
import etui/anim
import etui/backend.{type InputEvent, type RenderOp}
import etui/buffer
import etui/geometry
import etui/terminal.{type Frame, type Terminal}

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

// Every buffered loop sends this before its first frame, so a model can size
// itself from the real terminal rather than from a guess.
fn initial_resize(screen: geometry.Rect) -> InputEvent {
  backend.Resize(screen.size.width, screen.size.height)
}

// How the three buffered loops differ: only in the frame they build.
fn buffered_frame(frame: Frame, rendered: buffer.Buffer) -> Frame {
  terminal.with_buffer(frame, rendered)
}

fn cursor_frame(
  frame: Frame,
  rendered: #(buffer.Buffer, Result(geometry.Position, Nil)),
) -> Frame {
  let #(buf, pos) = rendered
  let placed = terminal.with_buffer(frame, buf)
  case pos {
    Ok(p) -> terminal.set_cursor(placed, p)
    _ -> terminal.hide_cursor(placed)
  }
}

// ─────────────────────────────────────────────────────────────────
// Erlang: raw render-op loop

@target(erlang)
/// Run the app loop over raw render ops.
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
///   fn(_) { 16 },
/// )
/// ```
pub fn run(
  b: backend.Backend(backend_state),
  init_state: state,
  render: fn(state) -> List(RenderOp),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
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
fn loop(
  b: backend.Backend(backend_state),
  bs: backend_state,
  state: state,
  render: fn(state) -> List(RenderOp),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
) -> #(state, backend_state) {
  case b.render(bs, render(state)) {
    Ok(bs2) ->
      case b.poll(bs2, poll_timeout_ms(state)) {
        Ok(#(event, bs3)) -> {
          let next = on_event(event, state)
          case should_quit(next) {
            True -> #(next, bs3)
            False ->
              loop(b, bs3, next, render, on_event, should_quit, poll_timeout_ms)
          }
        }
        _ -> #(state, bs2)
      }
    _ -> #(state, bs)
  }
}

// ─────────────────────────────────────────────────────────────────
// Erlang: buffered loops
//
// One driver behind all three. Diffing, first-frame repaint, resize and
// cursor placement all live in etui/terminal now.

@target(erlang)
fn drive(
  b: backend.Backend(backend_state),
  init_state: state,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
  build: fn(Frame, state, anim.AnimState) -> Frame,
) -> AppResult(state) {
  case terminal.new(b) {
    Ok(term) ->
      with_cleanup(
        fn() {
          let started =
            on_event(initial_resize(terminal.area(term)), init_state)
          let #(final_state, final_term) =
            drive_loop(
              term,
              started,
              on_event,
              should_quit,
              poll_timeout_ms,
              build,
              anim.anim_new(),
            )
          terminal.restore(final_term)
          Success(final_state)
        },
        fn() { terminal.restore(term) },
      )
    _ -> Error("Terminal init failed")
  }
}

@target(erlang)
fn drive_loop(
  term: Terminal(backend_state),
  state: state,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
  build: fn(Frame, state, anim.AnimState) -> Frame,
  anim_state: anim.AnimState,
) -> #(state, Terminal(backend_state)) {
  // `Error` on its own would resolve to AppResult's constructor here, which
  // shadows the built-in one, so these match on Ok and fall through.
  case terminal.draw(term, fn(frame) { build(frame, state, anim_state) }) {
    Ok(drawn) ->
      case terminal.poll(drawn, poll_timeout_ms(state)) {
        Ok(#(event, polled)) -> {
          let next = on_event(event, state)
          case should_quit(next) {
            True -> #(next, polled)
            False ->
              drive_loop(
                polled,
                next,
                on_event,
                should_quit,
                poll_timeout_ms,
                build,
                anim.tick(anim_state),
              )
          }
        }
        _ -> #(state, drawn)
      }
    _ -> #(state, term)
  }
}

@target(erlang)
/// High-level app loop. The render function produces a `Buffer`; the loop
/// diffs it against the previous frame and emits only the changed cells.
///
/// First frame: full repaint. Subsequent frames: diff. On `Resize`: full
/// repaint at the new size.
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
///   fn(_) { 16 },
/// )
/// ```
pub fn run_buffered(
  b: backend.Backend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
) -> AppResult(state) {
  drive(b, init_state, on_event, should_quit, poll_timeout_ms, fn(f, s, _anim) {
    buffered_frame(f, render(s, f.area))
  })
}

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
///     buffer.buffer_new(screen)
///     |> spinner.render(area, spinner.spinner_new() |> spinner.with_frame(anim_state.frame))
///   },
///   fn(ev, m) { case ev { backend.KeyPress("q") -> Model(quit: True) _ -> m } },
///   fn(m) { m.quit },
///   fn(_) { 16 },
/// )
/// ```
pub fn run_animated(
  b: backend.Backend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect, anim.AnimState) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
) -> AppResult(state) {
  drive(
    b,
    init_state,
    on_event,
    should_quit,
    poll_timeout_ms,
    fn(f, s, anim_st) { buffered_frame(f, render(s, f.area, anim_st)) },
  )
}

@target(erlang)
/// Like `run_buffered` but the render function also returns where the hardware
/// cursor belongs, as `Result(geometry.Position, Nil)`.
///
/// - `Ok(pos)` shows the cursor at `pos` (0-based). Use for text inputs and
///   text areas where the user needs to see the insertion point.
/// - `Error(Nil)` hides it. Use for read-only views.
pub fn run_buffered_cursor(
  b: backend.Backend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect) ->
    #(buffer.Buffer, Result(geometry.Position, Nil)),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
) -> AppResult(state) {
  drive(b, init_state, on_event, should_quit, poll_timeout_ms, fn(f, s, _anim) {
    cursor_frame(f, render(s, f.area))
  })
}

// ─────────────────────────────────────────────────────────────────
// JavaScript
//
// The same four loops. Only polling differs: the Node and browser backends
// read input asynchronously, so each loop is a promise chain.

@target(javascript)
pub fn run(
  b: backend.AsyncBackend(backend_state),
  init_state: state,
  render: fn(state) -> List(RenderOp),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
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
  poll_timeout_ms: fn(state) -> Int,
) -> promise.Promise(#(state, backend_state)) {
  case b.render(bs, render(state)) {
    Ok(bs2) ->
      promise.await(b.poll(bs2, poll_timeout_ms(state)), fn(poll_result) {
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
fn drive_js(
  b: backend.AsyncBackend(backend_state),
  init_state: state,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
  build: fn(Frame, state, anim.AnimState) -> Frame,
) -> promise.Promise(AppResult(state)) {
  case terminal.new(b) {
    Ok(term) ->
      with_cleanup(
        fn() {
          let started =
            on_event(initial_resize(terminal.area(term)), init_state)
          promise.await(
            drive_loop_js(
              term,
              started,
              on_event,
              should_quit,
              poll_timeout_ms,
              build,
              anim.anim_new(),
            ),
            fn(r) {
              let #(final_state, final_term) = r
              terminal.restore(final_term)
              promise.resolve(Success(final_state))
            },
          )
        },
        fn() { terminal.restore(term) },
      )
    _ -> promise.resolve(Error("Terminal init failed"))
  }
}

@target(javascript)
fn drive_loop_js(
  term: Terminal(backend_state),
  state: state,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
  build: fn(Frame, state, anim.AnimState) -> Frame,
  anim_state: anim.AnimState,
) -> promise.Promise(#(state, Terminal(backend_state))) {
  case terminal.draw(term, fn(frame) { build(frame, state, anim_state) }) {
    Ok(drawn) ->
      promise.await(terminal.poll(drawn, poll_timeout_ms(state)), fn(result) {
        case result {
          Ok(#(event, polled)) -> {
            let next = on_event(event, state)
            case should_quit(next) {
              True -> promise.resolve(#(next, polled))
              False ->
                drive_loop_js(
                  polled,
                  next,
                  on_event,
                  should_quit,
                  poll_timeout_ms,
                  build,
                  anim.tick(anim_state),
                )
            }
          }
          _ -> promise.resolve(#(state, drawn))
        }
      })
    _ -> promise.resolve(#(state, term))
  }
}

@target(javascript)
pub fn run_buffered(
  b: backend.AsyncBackend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
) -> promise.Promise(AppResult(state)) {
  drive_js(
    b,
    init_state,
    on_event,
    should_quit,
    poll_timeout_ms,
    fn(f, s, _anim) { buffered_frame(f, render(s, f.area)) },
  )
}

@target(javascript)
pub fn run_animated(
  b: backend.AsyncBackend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect, anim.AnimState) -> buffer.Buffer,
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
) -> promise.Promise(AppResult(state)) {
  drive_js(
    b,
    init_state,
    on_event,
    should_quit,
    poll_timeout_ms,
    fn(f, s, anim_st) { buffered_frame(f, render(s, f.area, anim_st)) },
  )
}

@target(javascript)
pub fn run_buffered_cursor(
  b: backend.AsyncBackend(backend_state),
  init_state: state,
  render: fn(state, geometry.Rect) ->
    #(buffer.Buffer, Result(geometry.Position, Nil)),
  on_event: fn(InputEvent, state) -> state,
  should_quit: fn(state) -> Bool,
  poll_timeout_ms: fn(state) -> Int,
) -> promise.Promise(AppResult(state)) {
  drive_js(
    b,
    init_state,
    on_event,
    should_quit,
    poll_timeout_ms,
    fn(f, s, _anim) { cursor_frame(f, render(s, f.area)) },
  )
}
