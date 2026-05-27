/// Multi-field form widget with focus management and validation.
///
/// Each field has a label, an input value, and an optional validator.
/// Tab/Shift-Tab move focus between fields; Enter submits if all valid.
///
/// ```gleam
/// import etui/widgets/form
///
/// type MyField { Name | Email | Age }
///
/// let f =
///   form.form_new()
///   |> form.add_field(Name, "Name", "", fn(v) {
///     case v { "" -> Error("required") _ -> Ok(Nil) }
///   })
///   |> form.add_field(Email, "Email", "", fn(v) {
///     case string.contains(v, "@") {
///       True -> Ok(Nil)
///       False -> Error("invalid email")
///     }
///   })
///
/// // In on_event:
/// let f = case key {
///   "tab"   -> form.focus_next(f)
///   "s-tab" -> form.focus_prev(f)
///   "enter" -> f  // check form.is_valid(f) / form.submit(f)
///   ch      -> form.type_char(f, ch)
/// }
///
/// // In render:
/// form.render(buf, area, f)
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/list
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

/// Validator: Ok(Nil) if valid, Error(String) with message if not.
pub type Validator =
  fn(String) -> Result(Nil, String)

/// A single form field.
pub type Field(id) {
  Field(
    id: id,
    label: String,
    value: String,
    validator: Validator,
    error: String,
    /// Number of graphemes / cells allowed (0 = unlimited within display width).
    max_length: Int,
  )
}

/// Form state: ordered list of fields plus focus index.
pub type Form(id) {
  Form(
    fields: List(Field(id)),
    focused: Int,
    submitted: Bool,
    label_width: Int,
    fg: style.Color,
    bg: style.Color,
    focused_fg: style.Color,
    focused_bg: style.Color,
    error_fg: style.Color,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// Empty form with default styles.
pub fn form_new() -> Form(id) {
  Form(
    fields: [],
    focused: 0,
    submitted: False,
    label_width: 0,
    fg: style.Default,
    bg: style.Default,
    focused_fg: style.Default,
    focused_bg: style.Indexed(4),
    error_fg: style.Indexed(1),
  )
}

/// Append a field with a validator.
pub fn add_field(
  f: Form(id),
  id: id,
  label: String,
  default_value: String,
  validator: Validator,
) -> Form(id) {
  let field =
    Field(
      id: id,
      label: label,
      value: default_value,
      validator: validator,
      error: "",
      max_length: 0,
    )
  Form(..f, fields: list.append(f.fields, [field]))
}

/// Append a required text field (non-empty validator).
pub fn add_required(
  f: Form(id),
  id: id,
  label: String,
  default_value: String,
) -> Form(id) {
  add_field(f, id, label, default_value, fn(v) {
    case v {
      "" -> Error("required")
      _ -> Ok(Nil)
    }
  })
}

/// Append an optional field (always valid).
pub fn add_optional(
  f: Form(id),
  id: id,
  label: String,
  default_value: String,
) -> Form(id) {
  add_field(f, id, label, default_value, fn(_) { Ok(Nil) })
}

/// Set max grapheme length for the most-recently added field.
pub fn with_field_max_length(f: Form(id), max: Int) -> Form(id) {
  let fields =
    list.index_map(f.fields, fn(field, i) {
      case i == list.length(f.fields) - 1 {
        True -> Field(..field, max_length: max)
        False -> field
      }
    })
  Form(..f, fields: fields)
}

/// Override label column width (auto-computed from labels if 0).
pub fn with_label_width(f: Form(id), w: Int) -> Form(id) {
  Form(..f, label_width: w)
}

/// Set base foreground/background.
pub fn with_colors(f: Form(id), fg: style.Color, bg: style.Color) -> Form(id) {
  Form(..f, fg: fg, bg: bg)
}

/// Set focused field highlight colors.
pub fn with_focused_colors(
  f: Form(id),
  fg: style.Color,
  bg: style.Color,
) -> Form(id) {
  Form(..f, focused_fg: fg, focused_bg: bg)
}

/// Set validation error text color.
pub fn with_error_color(f: Form(id), fg: style.Color) -> Form(id) {
  Form(..f, error_fg: fg)
}

// ─────────────────────────────────────────────────────────────────
// Focus

/// Move focus to the next field (wraps around).
pub fn focus_next(f: Form(id)) -> Form(id) {
  let n = list.length(f.fields)
  case n {
    0 -> f
    _ -> Form(..f, focused: { f.focused + 1 } % n)
  }
}

/// Move focus to the previous field (wraps around).
pub fn focus_prev(f: Form(id)) -> Form(id) {
  let n = list.length(f.fields)
  case n {
    0 -> f
    _ ->
      Form(..f, focused: {
        let prev = f.focused - 1
        case prev < 0 {
          True -> n - 1
          False -> prev
        }
      })
  }
}

/// Move focus to a specific field by index.
pub fn focus_index(f: Form(id), idx: Int) -> Form(id) {
  let n = list.length(f.fields)
  case idx >= 0 && idx < n {
    True -> Form(..f, focused: idx)
    False -> f
  }
}

// ─────────────────────────────────────────────────────────────────
// Editing

/// Type a character into the currently focused field.
pub fn type_char(f: Form(id), ch: String) -> Form(id) {
  update_focused(f, fn(field) {
    case
      field.max_length > 0 && text.cell_width(field.value) >= field.max_length
    {
      True -> field
      False -> Field(..field, value: field.value <> ch, error: "")
    }
  })
}

/// Backspace on the currently focused field.
pub fn backspace(f: Form(id)) -> Form(id) {
  update_focused(f, fn(field) {
    case field.value {
      "" -> field
      v -> {
        let graphemes = text.graphemes(v)
        let dropped = list.take(graphemes, list.length(graphemes) - 1)
        Field(..field, value: string.concat(dropped), error: "")
      }
    }
  })
}

/// Clear the currently focused field's value.
pub fn clear_focused(f: Form(id)) -> Form(id) {
  update_focused(f, fn(field) { Field(..field, value: "", error: "") })
}

/// Set a field's value by id.
pub fn set_value(f: Form(id), id: id, value: String) -> Form(id) {
  let fields =
    list.map(f.fields, fn(field) {
      case field.id == id {
        True -> Field(..field, value: value, error: "")
        False -> field
      }
    })
  Form(..f, fields: fields)
}

// ─────────────────────────────────────────────────────────────────
// Validation & submission

/// Validate all fields. Returns form with error messages populated.
pub fn validate(f: Form(id)) -> Form(id) {
  let fields =
    list.map(f.fields, fn(field) {
      case field.validator(field.value) {
        Ok(_) -> Field(..field, error: "")
        Error(msg) -> Field(..field, error: msg)
      }
    })
  Form(..f, fields: fields)
}

/// True if all fields are valid (no errors after validation).
pub fn is_valid(f: Form(id)) -> Bool {
  list.all(f.fields, fn(field) {
    case field.validator(field.value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

/// Validate then mark as submitted if valid. Returns the form.
pub fn submit(f: Form(id)) -> Form(id) {
  let validated = validate(f)
  case is_valid(validated) {
    True -> Form(..validated, submitted: True)
    False -> validated
  }
}

/// True if the form was successfully submitted.
pub fn is_submitted(f: Form(id)) -> Bool {
  f.submitted
}

/// Reset all fields to empty, clear errors and submitted flag.
pub fn reset(f: Form(id)) -> Form(id) {
  let fields =
    list.map(f.fields, fn(field) { Field(..field, value: "", error: "") })
  Form(..f, fields: fields, focused: 0, submitted: False)
}

/// Get a field's current value by id. Returns "" if not found.
pub fn get_value(f: Form(id), id: id) -> String {
  case list.find(f.fields, fn(field) { field.id == id }) {
    Ok(field) -> field.value
    Error(_) -> ""
  }
}

/// Get all field values as `#(id, value)` pairs.
pub fn values(f: Form(id)) -> List(#(id, String)) {
  list.map(f.fields, fn(field) { #(field.id, field.value) })
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render all fields as label + value rows. Each field takes 2 rows
/// (value row + optional error row). Focused field is highlighted.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  f: Form(id),
) -> buffer.Buffer {
  case
    area.size.width <= 0 || area.size.height <= 0 || list.is_empty(f.fields)
  {
    True -> buf
    False -> {
      let lw = case f.label_width {
        0 -> compute_label_width(f.fields)
        w -> w
      }
      render_fields(buf, area, f.fields, f, lw, 0, 0)
    }
  }
}

fn render_fields(
  buf: buffer.Buffer,
  area: geometry.Rect,
  fields: List(Field(id)),
  f: Form(id),
  lw: Int,
  field_idx: Int,
  row: Int,
) -> buffer.Buffer {
  let row_height = 2
  case fields {
    [] -> buf
    [field, ..rest] -> {
      let y = area.position.y + row
      let fits = y < area.position.y + area.size.height
      let buf2 = case fits {
        False -> buf
        True -> render_field_row(buf, area, field, f, lw, field_idx, y)
      }
      render_fields(buf2, area, rest, f, lw, field_idx + 1, row + row_height)
    }
  }
}

fn render_field_row(
  buf: buffer.Buffer,
  area: geometry.Rect,
  field: Field(id),
  f: Form(id),
  lw: Int,
  field_idx: Int,
  y: Int,
) -> buffer.Buffer {
  let is_focused = field_idx == f.focused
  let label_text = text.pad_right(text.truncate(field.label, lw, ""), lw) <> " "
  let value_x = area.position.x + lw + 1
  let value_w = area.size.width - lw - 1
  let value_w = case value_w < 0 {
    True -> 0
    False -> value_w
  }

  let #(val_fg, val_bg) = case is_focused {
    True -> #(f.focused_fg, f.focused_bg)
    False -> #(f.fg, f.bg)
  }

  let label_modifier = case is_focused {
    True -> style.bold()
    False -> style.none()
  }

  let buf1 = case lw > 0 {
    False -> buf
    True ->
      buffer.set_string(
        buf,
        geometry.Position(x: area.position.x, y: y),
        label_text,
        f.fg,
        f.bg,
        label_modifier,
      )
  }

  let padded_value =
    text.pad_right(text.truncate(field.value, value_w, ""), value_w)
  let buf2 = case value_w > 0 {
    False -> buf1
    True ->
      buffer.set_string(
        buf1,
        geometry.Position(x: value_x, y: y),
        padded_value,
        val_fg,
        val_bg,
        style.none(),
      )
  }

  let error_y = y + 1
  case
    field.error != ""
    && error_y < area.position.y + area.size.height
    && value_w > 0
  {
    False -> buf2
    True ->
      buffer.set_string(
        buf2,
        geometry.Position(x: value_x, y: error_y),
        text.truncate("  " <> field.error, value_w, ""),
        f.error_fg,
        f.bg,
        style.none(),
      )
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

fn update_focused(
  f: Form(id),
  updater: fn(Field(id)) -> Field(id),
) -> Form(id) {
  let fields =
    list.index_map(f.fields, fn(field, i) {
      case i == f.focused {
        True -> updater(field)
        False -> field
      }
    })
  Form(..f, fields: fields)
}

fn compute_label_width(fields: List(Field(id))) -> Int {
  list.fold(fields, 0, fn(acc, field) {
    let w = text.cell_width(field.label)
    case w > acc {
      True -> w
      False -> acc
    }
  })
}
