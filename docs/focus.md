# Focus Management

`etui/focus` gives you a `FocusRing`: an ordered set of named widget slots
where exactly one slot is active at a time.

## Basic usage

```gleam
import etui/focus

// Define slots in tab order
let ring = focus.focus_new(["sidebar", "editor", "statusbar"])

// In update:
let ring = case event {
  KeyPress("tab")     -> focus.focus_next(ring)
  KeyPress("backtab") -> focus.focus_prev(ring)
  _ -> ring
}

// In render, route events only to the focused slot:
let in_sidebar = focus.is_focused(ring, "sidebar")
let in_editor = focus.is_focused(ring, "editor")
```

## API

```gleam
// Constructors
focus.focus_new(ids: List(String)) -> FocusRing  // first slot starts focused

// Queries
focus.focused(ring)                    // Result(String, Nil), current slot ID
focus.is_focused(ring, "id")           // Bool
focus.current_index(ring)              // Int, 0-based
focus.size(ring)                       // Int, slot count

// Navigation
focus.focus_next(ring)                 // advance (wraps)
focus.focus_prev(ring)                 // retreat (wraps)
focus.focus_id(ring, "editor")         // jump to a specific slot
focus.focus_index(ring, 2)             // jump to an index (clamped)
```

## Pattern: conditional border style

```gleam
let border_style = fn(id) {
  case focus.is_focused(ring, id) {
    True  -> block.with_style(style.Rgb(100, 200, 255), style.Default)
    False -> block.with_style(style.Default, style.Default)
  }
}

let sidebar_block =
  block.block_new()
  |> block.with_border(block.Single)
  |> border_style("sidebar")
```

## Pattern: full multi-panel app

```gleam
import etui/keys

type Model {
  Model(ring: FocusRing, list_state: ListState, input_state: InputState, item_count: Int)
}

// input_widget is a module-level constant or a value from your model
const input_widget = input.input_new("")

fn update(event: backend.InputEvent, m: Model) -> Model {
  case event {
    backend.KeyPress("tab") -> Model(..m, ring: focus.focus_next(m.ring))
    _ ->
      case focus.focused(m.ring) {
        Ok("list") ->
          case event {
            backend.KeyPress("j") -> Model(..m, list_state: list.select_next(m.list_state, m.item_count))
            backend.KeyPress("k") -> Model(..m, list_state: list.select_prev(m.list_state))
            _ -> m
          }
        Ok("input") ->
          case event {
            backend.KeyPress("backspace") -> Model(..m, input_state: input.backspace(m.input_state))
            backend.KeyPress(k) ->
              case keys.match(k) {
                keys.Char(c) -> Model(..m, input_state: input.insert_char(input_widget, m.input_state, c))
                _ -> m
              }
            _ -> m
          }
        _ -> m
      }
  }
}
```

Focus wraps around at both ends. An empty ring is inert: every query returns
`Error(Nil)` or `False`.
