/// Drive rendering from your own loop.
///
/// `etui/app` owns the loop for you: you hand it a render function and an
/// event handler and it never gives control back. That is the right shape for
/// most apps and the wrong shape as soon as the terminal is not the only thing
/// your program is doing, because there is nowhere to put the rest. A supervised
/// OTP application, a program already driving a socket, a test that wants to
/// step one frame at a time: all of them need the loop to be theirs.
///
/// A `Terminal` is the piece `app` was hiding. You open it, draw frames when
/// you want to, poll for input when you want to, and close it:
///
/// ```gleam
/// let assert Ok(term) = terminal.new(default.new())
/// let term = case terminal.draw(term, fn(frame) {
///   frame |> terminal.draw_widget(frame.area, my_widget)
/// }) {
///   Ok(t) -> t
///   Error(_) -> term
/// }
/// let assert Ok(#(event, term)) = terminal.poll(term, 16)
/// terminal.restore(term)
/// ```
///
/// Diffing, first-frame handling and resize are still taken care of: `draw`
/// emits only the cells that changed since the last frame, and `poll` notices a
/// resize and arranges for the next `draw` to repaint everything.
///
/// The one thing it does not do is guarantee the terminal is restored if your
/// code panics. `app.run_buffered` and friends wrap the loop in a `try/after`
/// for that; if you drive the terminal yourself, restoring it is yours to
/// arrange.
import etui/backend.{type InputEvent, type RenderOp}
import etui/buffer
import etui/cursor
import etui/geometry.{type Position, type Rect}
import etui/widget
import gleam/int
import gleam/list
import gleam/string

@target(javascript)
import gleam/javascript/promise

// ─────────────────────────────────────────────────────────────────
// Viewport

/// How much of the terminal an app takes over.
///
/// | Viewport | What it uses | What happens to the scrollback |
/// |----------|--------------|--------------------------------|
/// | `Fullscreen` | the whole terminal, on the alternate screen | untouched, and the shell reappears on exit |
/// | `Inline(n)` | the bottom `n` rows of the normal screen | kept, and the app's last frame stays above the prompt |
/// | `Fixed(rect)` | one rect of the normal screen | everything outside the rect is left alone |
///
/// `Inline` is how a build tool or an installer draws a progress area without
/// taking the screen away from you: the rows above it keep scrolling, and what
/// it drew is still on screen after it exits.
pub type Viewport {
  Fullscreen
  Inline(height: Int)
  Fixed(area: Rect)
}

/// The rect a viewport occupies in a terminal of this size.
fn viewport_area(vp: Viewport, size: backend.TerminalSize) -> Rect {
  case vp {
    Fullscreen -> geometry.rect_new(0, 0, size.width, size.height)
    Inline(rows) -> {
      let h = int.clamp(rows, 0, size.height)
      geometry.rect_new(0, size.height - h, size.width, h)
    }
    Fixed(area) ->
      geometry.clamp(area, geometry.rect_new(0, 0, size.width, size.height))
  }
}

/// Only a full-screen app may clear the terminal. Anywhere else that would
/// wipe scrollback the app does not own, so a repaint writes its own cells
/// and touches nothing outside them.
fn may_clear(vp: Viewport) -> Bool {
  case vp {
    Fullscreen -> True
    _ -> False
  }
}

/// Ops that make room for the viewport before the first frame.
///
/// An inline viewport prints its own height in newlines, which scrolls
/// whatever was on screen up and leaves the bottom rows blank for the app.
/// Without it the first frame would draw over the last lines of output.
///
/// Public alongside `close_viewport`; see there.
pub fn open_viewport(vp: Viewport) -> List(RenderOp) {
  case vp {
    Fullscreen -> [backend.EnterAltScreen]
    // The backends enter the alternate screen when they initialise, which is
    // exactly what these two must not have.
    Inline(rows) -> [
      backend.ExitAltScreen,
      backend.Write(string.repeat("\n", int.max(0, rows))),
    ]
    Fixed(_) -> [backend.ExitAltScreen]
  }
}

/// Ops that hand the terminal back, once the app is done.
///
/// Public for the same reason as `frame_ops`: what a viewport does on the way
/// out is worth being able to check without a terminal to do it to, and for an
/// inline app it is the visible difference from a full-screen one.
pub fn close_viewport(vp: Viewport, area: Rect) -> List(RenderOp) {
  case vp {
    Fullscreen -> [backend.Write(cursor.show())]
    // Leave the cursor under the last frame so the shell prompt continues
    // after it rather than over it.
    _ -> [
      backend.MoveCursor(0, geometry.bottom(area) - 1),
      backend.Write("\r\n" <> cursor.show()),
    ]
  }
}

// ─────────────────────────────────────────────────────────────────
// Frame

/// Where the hardware cursor should be after a frame is drawn.
pub type Cursor {
  /// Leave the cursor wherever it was. The default, and what a full-screen
  /// app wants: it hides the cursor once at start-up and never thinks about
  /// it again.
  CursorUntouched
  /// Hide the cursor for this frame.
  CursorHidden
  /// Show the cursor at a 0-based cell position. Text inputs want this so the
  /// insertion point is where the terminal actually blinks.
  CursorShown(Position)
}

/// One frame under construction: the area it covers, the cells drawn into it
/// so far, and where the cursor should end up.
pub type Frame {
  Frame(area: Rect, buffer: buffer.Buffer, cursor: Cursor)
}

/// Draw a widget into part of the frame.
pub fn draw_widget(frame: Frame, area: Rect, w: widget.Widget) -> Frame {
  Frame(..frame, buffer: w(frame.buffer, area))
}

/// Replace the frame's buffer, for code that renders by returning a buffer
/// rather than by applying widgets.
pub fn with_buffer(frame: Frame, buf: buffer.Buffer) -> Frame {
  Frame(..frame, buffer: buf)
}

/// Put the cursor at `pos` when this frame is drawn.
pub fn set_cursor(frame: Frame, pos: Position) -> Frame {
  Frame(..frame, cursor: CursorShown(pos))
}

/// Hide the cursor when this frame is drawn.
pub fn hide_cursor(frame: Frame) -> Frame {
  Frame(..frame, cursor: CursorHidden)
}

// ─────────────────────────────────────────────────────────────────
// Frame assembly, shared by both targets and by etui/app

/// The render ops that take the terminal from `prev` to `curr`.
///
/// A first frame, at start-up or after a resize, repaints everything: what the
/// terminal is showing is unknown, so there is nothing to diff against. Every
/// frame after that emits only the cells that changed.
///
/// A frame that emits anything is wrapped in synchronized output, so the
/// terminal shows the old frame until the whole new one has arrived.
///
/// Public because it is worth being able to check what a frame will emit
/// without a terminal to emit it into, which is how the diffing and cursor
/// rules are tested. `draw` is what an app calls.
pub fn frame_ops(
  prev: buffer.Buffer,
  curr: buffer.Buffer,
  first_frame: Bool,
  cur: Cursor,
  clear_first: Bool,
) -> List(RenderOp) {
  let ansi = case first_frame {
    True -> buffer.to_ansi(curr)
    False -> buffer.diff_to_ansi(prev, curr)
  }
  let cursor_ansi = case cur {
    CursorUntouched -> ""
    CursorHidden -> cursor.hide()
    CursorShown(pos) ->
      cursor.hide() <> cursor.move_to(pos.y + 1, pos.x + 1) <> cursor.show()
  }
  let ops = case ansi, cursor_ansi {
    "", "" -> []
    "", only_cursor -> [backend.Write(only_cursor)]
    _, _ ->
      case first_frame && clear_first {
        True -> [
          backend.ClearScreen,
          backend.MoveCursor(0, 0),
          backend.Write(ansi <> cursor_ansi),
        ]
        False -> [backend.Write(ansi <> cursor_ansi)]
      }
  }
  // Nothing to say, nothing sent: an idle poll must not cost two escape
  // sequences. A first frame's clear is part of the frame and goes inside.
  case ops {
    [] -> []
    _ ->
      list.flatten([
        [backend.BeginSynchronizedOutput],
        ops,
        [backend.EndSynchronizedOutput],
      ])
  }
}

fn blank(area: Rect) -> buffer.Buffer {
  buffer.buffer_new(area)
}

// ─────────────────────────────────────────────────────────────────
// Erlang

@target(erlang)
/// An open terminal: the backend, its state, and what was last drawn.
pub opaque type Terminal(backend_state) {
  Terminal(
    backend: backend.Backend(backend_state),
    state: backend_state,
    /// How much of the screen this app took over.
    viewport: Viewport,
    /// What the terminal is currently showing, to diff the next frame against.
    previous: buffer.Buffer,
    /// Set at start-up and after a resize: the next frame repaints in full.
    repaint: Bool,
  )
}

@target(erlang)
/// Open a terminal that takes over the whole screen.
pub fn new(
  b: backend.Backend(backend_state),
) -> Result(Terminal(backend_state), backend.Error) {
  new_with_viewport(b, Fullscreen)
}

@target(erlang)
/// Open a terminal that uses only part of the screen.
///
/// ```gleam
/// // A five-row progress area under whatever the shell has already printed
/// let assert Ok(term) = terminal.new_with_viewport(default.new(), terminal.Inline(5))
/// ```
pub fn new_with_viewport(
  b: backend.Backend(backend_state),
  vp: Viewport,
) -> Result(Terminal(backend_state), backend.Error) {
  case b.init() {
    Ok(bs) -> {
      let #(size, bs2) = case b.next_size(bs) {
        Ok(#(sz, bs1)) -> #(sz, bs1)
        _ -> #(backend.TerminalSize(width: 80, height: 24), bs)
      }
      let area = viewport_area(vp, size)
      // One write, not two: opening the viewport and hiding the cursor are the
      // same moment as far as the terminal is concerned.
      let opening =
        list.append(open_viewport(vp), [backend.Write(cursor.hide())])
      let opened = case b.render(bs2, opening) {
        Ok(bs3) -> bs3
        _ -> bs2
      }
      Ok(Terminal(
        backend: b,
        state: opened,
        viewport: vp,
        previous: blank(area),
        repaint: True,
      ))
    }
    Error(e) -> Error(e)
  }
}

@target(erlang)
/// The area a frame will be given, which is the viewport rather than always
/// the whole screen.
pub fn area(term: Terminal(backend_state)) -> Rect {
  buffer.area(term.previous)
}

@target(erlang)
/// The viewport this terminal was opened with.
pub fn viewport(term: Terminal(backend_state)) -> Viewport {
  term.viewport
}

@target(erlang)
/// Draw one frame. `build` is handed an empty frame the size of the screen and
/// returns it filled in.
pub fn draw(
  term: Terminal(backend_state),
  build: fn(Frame) -> Frame,
) -> Result(Terminal(backend_state), backend.Error) {
  case draw_with(term, fn(frame) { #(build(frame), Nil) }) {
    Ok(#(next, Nil)) -> Ok(next)
    Error(e) -> Error(e)
  }
}

@target(erlang)
/// Draw one frame and carry a value back out of it.
///
/// A frame closure works out things the rest of your program wants: the rects
/// the layout produced, so a click can be matched against them, or the state a
/// list settled on once it knew how tall it was. Without a way out those die
/// inside the closure and have to be computed a second time.
///
/// ```gleam
/// let assert Ok(#(term, panes)) =
///   terminal.draw_with(term, fn(frame) {
///     let panes = geometry.split_h(frame.area, [Fill, Fill])
///     #(draw_panes(frame, panes), panes)
///   })
/// // `panes` is now available for hit-testing the next mouse event
/// ```
pub fn draw_with(
  term: Terminal(backend_state),
  build: fn(Frame) -> #(Frame, a),
) -> Result(#(Terminal(backend_state), a), backend.Error) {
  let screen = area(term)
  let #(frame, carried) =
    build(Frame(
      area: screen,
      buffer: buffer.buffer_new(screen),
      cursor: CursorUntouched,
    ))
  let ops =
    frame_ops(
      term.previous,
      frame.buffer,
      term.repaint,
      frame.cursor,
      may_clear(term.viewport),
    )
  case term.backend.render(term.state, ops) {
    Ok(bs) ->
      Ok(#(
        Terminal(..term, state: bs, previous: frame.buffer, repaint: False),
        carried,
      ))
    Error(e) -> Error(e)
  }
}

@target(erlang)
/// Wait up to `timeout_ms` for an event.
///
/// A resize is reported like any other event, and also resets the terminal's
/// idea of what is on screen, so the next `draw` repaints at the new size.
pub fn poll(
  term: Terminal(backend_state),
  timeout_ms: Int,
) -> Result(#(InputEvent, Terminal(backend_state)), backend.Error) {
  case term.backend.poll(term.state, timeout_ms) {
    Ok(#(event, bs)) -> Ok(#(event, absorb(Terminal(..term, state: bs), event)))
    Error(e) -> Error(e)
  }
}

@target(erlang)
/// Leave the alternate screen, restore the cursor and hand the terminal back.
pub fn restore(term: Terminal(backend_state)) -> Nil {
  let _ =
    term.backend.render(term.state, close_viewport(term.viewport, area(term)))
  term.backend.cleanup(term.state)
}

// ─────────────────────────────────────────────────────────────────
// JavaScript
//
// Same shape; only `poll` differs, because the Node and browser backends read
// input asynchronously.

@target(javascript)
pub opaque type Terminal(backend_state) {
  Terminal(
    backend: backend.AsyncBackend(backend_state),
    state: backend_state,
    viewport: Viewport,
    previous: buffer.Buffer,
    repaint: Bool,
  )
}

@target(javascript)
/// Open a terminal that takes over the whole screen.
pub fn new(
  b: backend.AsyncBackend(backend_state),
) -> Result(Terminal(backend_state), backend.Error) {
  new_with_viewport(b, Fullscreen)
}

@target(javascript)
/// Open a terminal that uses only part of the screen.
///
/// ```gleam
/// // A five-row progress area under whatever the shell has already printed
/// let assert Ok(term) = terminal.new_with_viewport(default.new(), terminal.Inline(5))
/// ```
pub fn new_with_viewport(
  b: backend.AsyncBackend(backend_state),
  vp: Viewport,
) -> Result(Terminal(backend_state), backend.Error) {
  case b.init() {
    Ok(bs) -> {
      let #(size, bs2) = case b.next_size(bs) {
        Ok(#(sz, bs1)) -> #(sz, bs1)
        _ -> #(backend.TerminalSize(width: 80, height: 24), bs)
      }
      let area = viewport_area(vp, size)
      // One write, not two: opening the viewport and hiding the cursor are the
      // same moment as far as the terminal is concerned.
      let opening =
        list.append(open_viewport(vp), [backend.Write(cursor.hide())])
      let opened = case b.render(bs2, opening) {
        Ok(bs3) -> bs3
        _ -> bs2
      }
      Ok(Terminal(
        backend: b,
        state: opened,
        viewport: vp,
        previous: blank(area),
        repaint: True,
      ))
    }
    Error(e) -> Error(e)
  }
}

@target(javascript)
pub fn area(term: Terminal(backend_state)) -> Rect {
  buffer.area(term.previous)
}

@target(javascript)
pub fn viewport(term: Terminal(backend_state)) -> Viewport {
  term.viewport
}

@target(javascript)
pub fn draw(
  term: Terminal(backend_state),
  build: fn(Frame) -> Frame,
) -> Result(Terminal(backend_state), backend.Error) {
  case draw_with(term, fn(frame) { #(build(frame), Nil) }) {
    Ok(#(next, Nil)) -> Ok(next)
    Error(e) -> Error(e)
  }
}

@target(javascript)
/// Draw one frame and carry a value back out of it. See the Erlang docs.
pub fn draw_with(
  term: Terminal(backend_state),
  build: fn(Frame) -> #(Frame, a),
) -> Result(#(Terminal(backend_state), a), backend.Error) {
  let screen = area(term)
  let #(frame, carried) =
    build(Frame(
      area: screen,
      buffer: buffer.buffer_new(screen),
      cursor: CursorUntouched,
    ))
  let ops =
    frame_ops(
      term.previous,
      frame.buffer,
      term.repaint,
      frame.cursor,
      may_clear(term.viewport),
    )
  case term.backend.render(term.state, ops) {
    Ok(bs) ->
      Ok(#(
        Terminal(..term, state: bs, previous: frame.buffer, repaint: False),
        carried,
      ))
    Error(e) -> Error(e)
  }
}

@target(javascript)
pub fn poll(
  term: Terminal(backend_state),
  timeout_ms: Int,
) -> promise.Promise(
  Result(#(InputEvent, Terminal(backend_state)), backend.Error),
) {
  promise.map(term.backend.poll(term.state, timeout_ms), fn(result) {
    case result {
      Ok(#(event, bs)) ->
        Ok(#(event, absorb(Terminal(..term, state: bs), event)))
      Error(e) -> Error(e)
    }
  })
}

@target(javascript)
pub fn restore(term: Terminal(backend_state)) -> Nil {
  let _ =
    term.backend.render(term.state, close_viewport(term.viewport, area(term)))
  term.backend.cleanup(term.state)
}

// A resize invalidates everything we knew about the screen.
fn absorb(
  term: Terminal(backend_state),
  event: InputEvent,
) -> Terminal(backend_state) {
  case event {
    backend.Resize(w, h) ->
      Terminal(
        ..term,
        previous: blank(viewport_area(
          term.viewport,
          backend.TerminalSize(width: w, height: h),
        )),
        repaint: True,
      )
    _ -> term
  }
}
