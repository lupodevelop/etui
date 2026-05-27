/// Text input widget with cursor tracking and editing operations.
///
/// State (`InputState`) is kept external so it persists across renders.
/// Use `insert_char`, `backspace`, `move_cursor_left/right` in your `update`
/// function to mutate state in response to `KeyPress` events.
///
/// Example:
/// ```gleam
/// let state = input.insert_char(widget, state, "a")
/// input.render(buf, area, widget, state)
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

/// Validator: Ok(Nil) = valid, Error(String) = message to show.
pub type Validator =
  fn(String) -> Result(Nil, String)

/// Input widget configuration.
pub type InputWidget {
  InputWidget(
    max_length: Int,
    placeholder: String,
    fg: style.Color,
    bg: style.Color,
    /// Optional validation function; run via `validate/2`.
    validator: Validator,
    error_fg: style.Color,
    /// Prefix shown before the value (e.g. "> ", "$ "). Counts toward width.
    prompt: String,
    /// When `True`, render each value cell as `mask` instead of the real char.
    password: Bool,
    /// Mask character used in password mode. Default `"*"`.
    mask: String,
  )
}

/// Mutable editing state: current value and cursor column (in cells).
pub type InputState {
  InputState(value: String, cursor: Int)
}

// ─────────────────────────────────────────────────────────────────
// Widget config constructors

/// New input widget with placeholder text. Default max length: 256 cells.
pub fn input_new(placeholder: String) -> InputWidget {
  InputWidget(
    max_length: 256,
    placeholder: placeholder,
    fg: style.Default,
    bg: style.Default,
    validator: fn(_) { Ok(Nil) },
    error_fg: style.Indexed(1),
    prompt: "",
    password: False,
    mask: "*",
  )
}

/// Set a prefix shown before the value (e.g. `"> "`).
pub fn with_prompt(i: InputWidget, prompt: String) -> InputWidget {
  InputWidget(..i, prompt: prompt)
}

/// Render each value cell as the mask character. Use for password fields.
pub fn with_password(i: InputWidget, password: Bool) -> InputWidget {
  InputWidget(..i, password: password)
}

/// Mask character used when `password` is True. Default `"*"`.
pub fn with_mask(i: InputWidget, mask: String) -> InputWidget {
  InputWidget(..i, mask: mask)
}

/// Set a validation function. Call `validate/2` to run it.
pub fn with_validator(i: InputWidget, v: Validator) -> InputWidget {
  InputWidget(..i, validator: v)
}

/// Set the color used to display validation errors.
pub fn with_error_color(i: InputWidget, fg: style.Color) -> InputWidget {
  InputWidget(..i, error_fg: fg)
}

/// Run the validator on `value`. Returns Ok(Nil) or Error(message).
pub fn validate(i: InputWidget, value: String) -> Result(Nil, String) {
  i.validator(value)
}

/// Maximum value width in cells (wide characters count as 2).
pub fn with_max_length(i: InputWidget, len: Int) -> InputWidget {
  InputWidget(..i, max_length: len)
}

pub fn with_colors(
  i: InputWidget,
  fg: style.Color,
  bg: style.Color,
) -> InputWidget {
  InputWidget(..i, fg: fg, bg: bg)
}

pub fn with_style(i: InputWidget, s: style.Style) -> InputWidget {
  InputWidget(..i, fg: s.fg, bg: s.bg)
}

// ─────────────────────────────────────────────────────────────────
// State constructors

/// Initial state: empty value, cursor at 0.
pub fn state_new() -> InputState {
  InputState(value: "", cursor: 0)
}

/// State pre-populated with a string; cursor placed at the end.
pub fn state_from_string(s: String) -> InputState {
  InputState(value: s, cursor: text.cell_width(s))
}

// ─────────────────────────────────────────────────────────────────
// Editing operations (operate on state only)

/// Insert character at cursor. Respects widget max_length.
pub fn insert_char(
  widget: InputWidget,
  state: InputState,
  ch: String,
) -> InputState {
  case text.cell_width(state.value) >= widget.max_length {
    True -> state
    False -> {
      let before = text.truncate(state.value, state.cursor, "")
      let after = string.drop_start(state.value, string.length(before))
      InputState(
        value: before <> ch <> after,
        cursor: state.cursor + text.cell_width(ch),
      )
    }
  }
}

/// Delete the character immediately before the cursor (backspace semantics).
pub fn backspace(state: InputState) -> InputState {
  case state.cursor <= 0 {
    True -> state
    False -> {
      let before = text.truncate(state.value, state.cursor - 1, "")
      let graphemes_at_cursor =
        string.length(text.truncate(state.value, state.cursor, ""))
      let after = string.drop_start(state.value, graphemes_at_cursor)
      InputState(value: before <> after, cursor: text.cell_width(before))
    }
  }
}

/// Move cursor one cell left, clamped to 0.
pub fn move_cursor_left(state: InputState) -> InputState {
  case state.cursor <= 0 {
    True -> state
    False -> {
      let new_cursor =
        text.cell_width(text.truncate(state.value, state.cursor - 1, ""))
      InputState(..state, cursor: new_cursor)
    }
  }
}

/// Move cursor one cell right, clamped to end of value.
pub fn move_cursor_right(state: InputState) -> InputState {
  case state.cursor >= text.cell_width(state.value) {
    True -> state
    False -> {
      let step = grapheme_width_at(state.value, state.cursor)
      InputState(..state, cursor: state.cursor + step)
    }
  }
}

/// Move cursor to beginning of value.
pub fn move_to_start(state: InputState) -> InputState {
  InputState(..state, cursor: 0)
}

/// Move cursor to end of value.
pub fn move_to_end(state: InputState) -> InputState {
  InputState(..state, cursor: text.cell_width(state.value))
}

/// Delete from cursor to end of value.
pub fn delete_to_end(state: InputState) -> InputState {
  let before = text.truncate(state.value, state.cursor, "")
  InputState(..state, value: before)
}

/// Reset value and cursor to empty.
pub fn clear_state(_state: InputState) -> InputState {
  InputState(value: "", cursor: 0)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the input field. Shows `state.value` (bold) or placeholder when empty.
/// Text is truncated to fit `area.size.width` (minus one cell reserved for the
/// trailing cursor). When `password` is True the value is masked.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  widget: InputWidget,
  state: InputState,
) -> buffer.Buffer {
  case area.size.width <= 0 {
    True -> buf
    False -> {
      let has_value = state.value != ""
      let value_display = case widget.password && has_value {
        True -> string.repeat(widget.mask, text.cell_width(state.value))
        False -> state.value
      }
      let display_text = case has_value {
        True -> widget.prompt <> value_display
        False -> widget.prompt <> widget.placeholder
      }
      let truncated = text.truncate(display_text, area.size.width - 1, "")
      let padded = text.pad_right(truncated, area.size.width)
      let modifier = case has_value {
        True -> style.bold()
        False -> style.none()
      }
      buffer.set_string(
        buf,
        area.position,
        padded,
        widget.fg,
        widget.bg,
        modifier,
      )
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

fn grapheme_width_at(s: String, cell_pos: Int) -> Int {
  let prefix = text.truncate(s, cell_pos, "")
  let rest = string.drop_start(s, string.length(prefix))
  case string.to_graphemes(rest) {
    [g, ..] -> text.cell_width(g)
    [] -> 1
  }
}
