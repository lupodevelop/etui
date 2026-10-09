# Getting Started

## Add dependency

```toml
# gleam.toml
[dependencies]
etui = ">= 2.0.0 and < 3.0.0"
```

## Minimal app

```gleam
import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/geometry.{type Rect}
import etui/widgets/paragraph

pub type Model {
  Model(quit: Bool, width: Int, height: Int)
}

pub fn main() {
  let _ =
    app.run_buffered(
      default.new(),
      Model(quit: False, width: 80, height: 24),
      view,
      update,
      fn(m) { m.quit },
      fn(_) { 16 }, // poll every 16ms (~60fps)
    )
}

fn view(_model: Model, screen: Rect) -> buffer.Buffer {
  buffer.buffer_new(screen)
  |> paragraph.render(screen, paragraph.paragraph_new("Hello, etui!  Press q to quit."))
}

fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.Resize(w, h) -> Model(..model, width: w, height: h)
    backend.KeyPress("q") -> Model(..model, quit: True)
    _ -> model
  }
}
```

## App loop API

```gleam
app.run_buffered(
  backend,       // default.new()
  initial_model,
  view_fn,       // fn(model, Rect) -> Buffer
  update_fn,     // fn(InputEvent, model) -> model
  quit_fn,       // fn(model) -> Bool, return True to exit
  fn(_) { poll_ms }, // poll timeout: fn(state) -> Int, in milliseconds
)
```

The poll timeout is a function of the state, called before each poll. A
constant is `fn(_) { 16 }`. An app that is busy can poll fast and an idle one
slowly:

```gleam
fn(model) { case model.busy { True -> 16  False -> 100 } }
```

### InputEvent

```gleam
backend.KeyPress(key)              // key string: "a", "A", " ", "\r", "ctrl+c", "shift+left"
backend.Resize(w, h)               // terminal was resized
backend.Tick                       // emitted each poll interval (no input)
backend.MousePress(x, y, button)   // optional: use default.new_with_mouse()
backend.MouseRelease(x, y, button)
backend.MouseDrag(x, y, button)    // moved with a button held
backend.MouseMove(x, y)            // moved with no button held
backend.MouseScroll(x, y, up)
backend.Paste(text)                // opt in: default.new_with_options(...)
```

A `case` over `InputEvent` needs a `_ ->` arm: the type gains variants in
minor releases, and did in 2.0.

### App loop variants

| Function | Use when |
| --- | --- |
| `run_buffered` | Default: you return a `Buffer`, diffing is automatic |
| `run_buffered_cursor` | Text fields: also return cursor `Position` |
| `run_animated` | Spinners / marquees: receives `AnimState` each frame |
| `run` | Low-level: you emit `List(RenderOp)` yourself |

Returning the previous `Buffer` unchanged makes that frame free: `buffer.diff`
answers at once for the same term. A frame that emits output is wrapped in
synchronized output (DEC mode 2026), so the terminal does not paint it halfway.

On the **JavaScript** target (Node), these return `Promise(AppResult(_))` instead of `AppResult`.

### Keyboard handling with `keys.match`

`keys.match` parses a raw key string into a typed `Key`. It avoids typos and
handles arrow, function, and Ctrl/Alt keys uniformly. Given a model with a
`selected` index and a `quit` flag:

```gleam
import etui/keys

fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.KeyPress(k) ->
      case keys.match(k) {
        keys.Up        -> Model(..model, selected: model.selected - 1)
        keys.Down      -> Model(..model, selected: model.selected + 1)
        keys.Char("q") -> Model(..model, quit: True)
        keys.Ctrl("c") -> Model(..model, quit: True)
        _              -> model
      }
    _ -> model
  }
}
```

A lone Escape is decided 40 ms after its last byte, so an arrow key split across
two reads is not taken for Escape. An unfinished bracketed paste waits 1 s.
Ctrl+S and Ctrl+Q reach the app: the Erlang backend clears `IXON` on entry and
restores it on exit.

A modified named key — `"shift+left"`, `"ctrl+down"` — is `Unknown` to
`keys.match`, because it is not a character. Use `keys.parse` when you want
the modifier as data:

```gleam
case keys.parse(raw) {
  keys.KeyEvent(keys.Left, keys.Modifiers(shift: True, ..)) -> select_left(model)
  keys.KeyEvent(keys.Left, _) -> move_left(model)
  _ -> model
}
```

## Crash-restore guarantee

All four app loops wrap the event loop in Erlang `try...after` via FFI. If
`view_fn` or `update_fn` raises, the terminal is restored — raw mode off, alt
screen left, cursor back — before the exception propagates.

Closed stdin ends the Erlang backend with an I/O error. The loop stops and the
terminal is restored, as it is for a raised exception.

`erlang:halt`, a `kill -9` or any other end that unwinds nothing runs no Gleam
code at all. An orphan shell process, started when the app entered raw mode,
notices the runtime is gone and restores the terminal itself.

`Ctrl+C` is not a signal in raw mode: `ISIG` is off, so it arrives as the key
`"ctrl+c"` for your `update` to handle. A SIGINT from somewhere else *is* a
signal, and the BEAM keeps it for its own break handler: the app stops
responding and the terminal stays borrowed. Disable the break handler if that
matters to you:

```sh
ERL_FLAGS="+B" gleam run -m your_module     # or ERL_AFLAGS="+Bd", the same thing
```

Both were checked against a real terminal with `dev/pty_cleanup_check.py`.
[Terminal state](terminal-state.md) has the details.

## Manual drive (no app loop)

```gleam
import etui/backend
import etui/backend/erlang
import gleam/list

let b = erlang.new()
case backend.init(b) {
  Error(_) -> Nil
  Ok(state) -> {
    let ops =
      list.append(backend.clear_and_home(), [backend.Write("Hello")])
    let assert Ok(state) = backend.render(b, state, ops)
    let assert Ok(#(_event, state)) = backend.poll(b, state, 16)
    backend.cleanup(b, state)
  }
}
```

`backend.init` enters raw mode and alt screen. `backend.cleanup` restores the terminal.

For new apps, prefer `etui/backend/default` and `app.run_buffered` instead of hand-rolling the loop.
