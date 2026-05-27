# étui Code Snippets

This document contains copy-pasteable code blocks to help you build interfaces with **étui**. 

Since `.gleam` files cannot contain top-level floating variables (a `let` binding must live within a function block), these snippets are grouped as Markdown recipes. You can copy the code directly into your application's `view` or `update` loops.

---

## 1. Splitting Layouts

Use `geometry.split` to divide an area into multiple smaller areas (chunks). This is the building block of multi-pane terminal user interfaces.

```gleam
import etui/geometry.{Fill, Horizontal, Length, Percentage, Vertical}

// Horizontal split: Sidebar (30%) and Main content (remaining space)
let chunks = geometry.split(Horizontal, screen_area, [Percentage(30), Fill])
let sidebar_area = case chunks {
  [l, ..] -> l
  _ -> screen_area
}
let main_area = case chunks {
  [_, r, ..] -> r
  _ -> screen_area
}

// Vertical split: Header (fixed 3 lines), Body (fill), Footer (fixed 1 line)
let rows = geometry.split(Vertical, main_area, [Length(3), Fill, Length(1)])
let #(header_area, body_area, footer_area) = case rows {
  [h, b, f, ..] -> #(h, b, f)
  _ -> #(main_area, main_area, main_area)
}
```

---

## 2. Text Input Widget (With Cursor Support)

To build a text input field, use `app.run_buffered_cursor` instead of `run_buffered`. This tells the application loop to track and show the hardware cursor at the correct position.

### Application State & Model
```gleam
import etui/geometry
import etui/widgets/input

pub type Model {
  Model(
    input_state: input.InputState,
    quit: Bool,
  )
}
```

### Update function
```gleam
import etui/backend

pub fn update(event: backend.InputEvent, model: Model) -> Model {
  let widget = input.input_new("Type here...")
  
  case event {
    backend.KeyPress("q") -> Model(..model, quit: True)
    
    // Handle typing characters
    backend.TextInput(ch) -> {
      let next_state = input.insert_char(widget, model.input_state, ch)
      Model(..model, input_state: next_state)
    }
    
    // Handle editing keys
    backend.KeyPress("Backspace") -> {
      let next_state = input.backspace(model.input_state)
      Model(..model, input_state: next_state)
    }
    backend.KeyPress("Left") -> {
      let next_state = input.move_cursor_left(model.input_state)
      Model(..model, input_state: next_state)
    }
    backend.KeyPress("Right") -> {
      let next_state = input.move_cursor_right(model.input_state)
      Model(..model, input_state: next_state)
    }
    _ -> model
  }
}
```

### View function (rendering text and placing cursor)
```gleam
import etui/buffer
import etui/geometry

pub fn view(model: Model, screen: geometry.Rect) -> #(buffer.Buffer, Result(geometry.Position, Nil)) {
  let area = geometry.Rect(
    position: geometry.Position(x: 2, y: 2),
    size: geometry.Size(width: 30, height: 1)
  )
  
  let widget = input.input_new("Type here...")
    |> input.with_prompt("> ")
    
  let buf = buffer.buffer_new(screen)
    |> input.render(area, widget, model.input_state)
    
  // Place the terminal cursor at the end of the text input
  let cursor_pos = geometry.Position(
    x: area.position.x + model.input_state.cursor + 2, // Account for prompt length
    y: area.position.y,
  )
  
  #(buf, Ok(cursor_pos))
}
```

---

## 3. Stateful Scrollable List

Use `widgets/list` for vertical lists of selectable options. The list automatically manages internal scroll offsets if items overflow the height of the rendering area.

### Application State & Model
```gleam
import etui/widgets/list as glist

pub type Model {
  Model(
    items: List(String),
    list_state: glist.ListState,
    quit: Bool,
  )
}
```

### Update function
```gleam
import etui/backend
import gleam/list

pub fn update(event: backend.InputEvent, model: Model) -> Model {
  let count = list.length(model.items)
  
  case event {
    backend.KeyPress("q") -> Model(..model, quit: True)
    
    // Navigate list items
    backend.KeyPress("Up") -> {
      let next_state = glist.select_prev(model.list_state)
      Model(..model, list_state: next_state)
    }
    backend.KeyPress("Down") -> {
      let next_state = glist.select_next(model.list_state, count)
      Model(..model, list_state: next_state)
    }
    _ -> model
  }
}
```

### View function
```gleam
import etui/buffer
import etui/geometry
import etui/widgets/list as glist

pub fn view(model: Model, screen: geometry.Rect) -> buffer.Buffer {
  let area = geometry.Rect(
    position: geometry.Position(x: 2, y: 2),
    size: geometry.Size(width: 40, height: 10)
  )
  
  let widget = glist.list_new(model.items)
  
  buffer.buffer_new(screen)
  |> glist.render_stateful(area, widget, model.list_state)
}
```

---

## 4. Horizontal Tab Bar

Tabs let users switch between different sub-views easily. They automatically highlight the selected option and handle horizontal layout dividers.

### Application State & Model
```gleam
import etui/widgets/tabs

pub type Model {
  Model(
    tabs: tabs.Tabs,
    quit: Bool,
  )
}
```

### Update function
```gleam
import etui/backend

pub fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.KeyPress("q") -> Model(..model, quit: True)
    
    // Cycle tabs
    backend.KeyPress("Tab") -> Model(..model, tabs: tabs.next_tab(model.tabs))
    backend.KeyPress("Right") -> Model(..model, tabs: tabs.next_tab(model.tabs))
    backend.KeyPress("Left") -> Model(..model, tabs: tabs.prev_tab(model.tabs))
    _ -> model
  }
}
```

### View function
```gleam
import etui/buffer
import etui/geometry
import etui/widgets/tabs

pub fn view(model: Model, screen: geometry.Rect) -> buffer.Buffer {
  let area = geometry.Rect(
    position: geometry.Position(x: 0, y: 0),
    size: geometry.Size(width: screen.size.width, height: 1)
  )
  
  buffer.buffer_new(screen)
  |> tabs.render(area, model.tabs)
}
```

---

## 5. Modal Centered Dialog

Centered dialog boxes are helpful for overlaying confirmation modal flows (like "OK/Cancel" prompts) on top of the existing screen.

### Application State & Model
```gleam
import etui/widgets/dialog

pub type Model {
  Model(
    dialog_state: dialog.DialogState,
    show_dialog: Bool,
    quit: Bool,
  )
}
```

### Update function
```gleam
import etui/backend
import etui/widgets/dialog

pub fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.KeyPress("q") -> Model(..model, quit: True)
    
    // Dialog interaction
    backend.KeyPress("Tab") -> {
      let next_state = dialog.toggle(model.dialog_state)
      Model(..model, dialog_state: next_state)
    }
    backend.KeyPress("Enter") -> {
      let is_ok = dialog.is_confirmed(model.dialog_state)
      case is_ok {
        True -> // User selected OK
          Model(..model, show_dialog: False, quit: True)
        False -> // User selected Cancel
          Model(..model, show_dialog: False)
      }
    }
    backend.KeyPress("Escape") -> {
      Model(..model, show_dialog: False)
    }
    _ -> model
  }
}
```

### View function
```gleam
import etui/buffer
import etui/geometry
import etui/widgets/dialog

pub fn view(model: Model, screen: geometry.Rect) -> buffer.Buffer {
  let buf = buffer.buffer_new(screen)
  
  // Render main screen first...
  
  // Overlay dialog on top if active
  case model.show_dialog {
    True -> {
      let modal = dialog.dialog_new("Are you sure you want to quit?")
        |> dialog.with_labels("Yes, Quit", "Stay")
        
      dialog.render(buf, screen, modal, model.dialog_state)
    }
    False -> buf
  }
}
```

---

## 6. Panel Border with Title and Text Paragraph

A classic layout pattern is a structured border (Block) containing styled text inside it.

```gleam
import etui/buffer
import etui/geometry
import etui/widgets/block
import etui/widgets/paragraph

pub fn view(_model: Model, screen: geometry.Rect) -> buffer.Buffer {
  let panel_area = geometry.Rect(
    position: geometry.Position(x: 5, y: 3),
    size: geometry.Size(width: 40, height: 10)
  )
  
  // Define a block with a rounded border and title
  let blk = block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title("About étui", block.Top)
    |> block.with_bg_fill
    
  // Define a text paragraph inside the block
  let para = paragraph.paragraph_new("étui is a modern, reactive, type-safe terminal user interface library for Gleam terminal applications.")
  
  buffer.buffer_new(screen)
  // 1. Render the block border on the layout area
  |> block.render(panel_area, blk)
  // 2. Render paragraph in the inner content area (adjusted for border offsets)
  |> paragraph.render(block.inner(panel_area, blk), para)
}
```
