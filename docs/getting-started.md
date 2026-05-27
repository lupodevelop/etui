# Getting Started

## Add dependency

```toml
# gleam.toml
[dependencies]
etui = ">= 1.0.0 and < 2.0.0"
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
      16, // poll every 16ms (~60fps)
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
  poll_ms,       // event poll interval in milliseconds
)
```

### InputEvent

```gleam
backend.KeyPress(key)              // key string: "a", "A", " ", "\r", etc.
backend.Resize(w, h)               // terminal was resized
backend.Tick                       // emitted each poll interval (no input)
backend.MousePress(x, y, button)   // optional: use default.new_with_mouse()
backend.MouseRelease(x, y, button)
backend.MouseScroll(x, y, up)
```

### App loop variants

| Function | Use when |
| --- | --- |
| `run_buffered` | Default: you return a `Buffer`, diffing is automatic |
| `run_buffered_cursor` | Text fields: also return cursor `Position` |
| `run_animated` | Spinners / marquees: receives `AnimState` each frame |
| `run` | Low-level: you emit `List(RenderOp)` yourself |

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

## Crash-restore guarantee

`app.run` wraps the event loop in Erlang `try...after` via FFI. If `view_fn` or `update_fn` raises, the terminal is restored (raw mode off, alt screen exit) before the exception propagates.

On the Erlang target, `gleam run` inherits the BEAM default for `Ctrl+C`: by default it opens the BREAK handler instead of terminating the process immediately. Etui restores the terminal on normal exits, exceptions, and supported abort paths, but if you want `Ctrl+C` to terminate the session directly, start the runtime with `ERL_AFLAGS="+Bd"`, for example:

```sh
ERL_AFLAGS="+Bd" gleam run -m your_module
```

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
