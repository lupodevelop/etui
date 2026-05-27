/// Modal dialog widget: message with Confirm / Cancel buttons.
///
/// Renders a centered popup with a message and two focusable buttons.
/// Drive it with `toggle`, `confirm`, `cancel` and read result via `is_confirmed`.
///
/// ```gleam
/// import etui/widgets/dialog
///
/// let d = dialog.dialog_new("Delete this file?")
/// let state = dialog.state_new()
///
/// // In on_event:
/// let state = case keys.match(k) {
///   keys.Tab    -> dialog.toggle(state)
///   keys.Enter  -> state  // handle below
///   keys.Escape -> dialog.cancel(state)
///   _           -> state
/// }
/// let confirmed = dialog.is_confirmed(state) && key == "enter"
///
/// // In render:
/// dialog.render(buf, screen_area, d, state)
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import etui/widgets/block

// ─────────────────────────────────────────────────────────────────
// Types

/// Dialog configuration.
pub type Dialog {
  Dialog(
    message: String,
    confirm_label: String,
    cancel_label: String,
    /// Dialog box width (0 = auto: max of message width + 4 and 30).
    width: Int,
    /// Total dialog height including border (0 = auto).
    height: Int,
    fg: style.Color,
    bg: style.Color,
    confirm_style: style.Style,
    cancel_style: style.Style,
    /// Style for the focused button.
    focused_style: style.Style,
    border: block.Border,
  )
}

/// Which button is currently focused.
pub type DialogButton {
  Confirm
  Cancel
}

/// Mutable dialog state.
pub type DialogState {
  DialogState(focused: DialogButton)
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// Dialog with default labels ("OK" / "Cancel") and a rounded border.
pub fn dialog_new(message: String) -> Dialog {
  Dialog(
    message: message,
    confirm_label: " OK ",
    cancel_label: " Cancel ",
    width: 0,
    height: 0,
    fg: style.Default,
    bg: style.Default,
    confirm_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.none(),
    ),
    cancel_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.none(),
    ),
    focused_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.reverse(),
    ),
    border: block.Rounded,
  )
}

pub fn state_new() -> DialogState {
  DialogState(focused: Confirm)
}

// ─────────────────────────────────────────────────────────────────
// Builders

pub fn with_labels(d: Dialog, confirm: String, cancel: String) -> Dialog {
  Dialog(..d, confirm_label: confirm, cancel_label: cancel)
}

pub fn with_size(d: Dialog, width: Int, height: Int) -> Dialog {
  Dialog(..d, width: width, height: height)
}

pub fn with_colors(d: Dialog, fg: style.Color, bg: style.Color) -> Dialog {
  Dialog(..d, fg: fg, bg: bg)
}

pub fn with_style(d: Dialog, s: style.Style) -> Dialog {
  Dialog(..d, fg: s.fg, bg: s.bg)
}

pub fn with_focused_style(d: Dialog, s: style.Style) -> Dialog {
  Dialog(..d, focused_style: s)
}

pub fn with_border(d: Dialog, b: block.Border) -> Dialog {
  Dialog(..d, border: b)
}

// ─────────────────────────────────────────────────────────────────
// State operations

/// Toggle focus between Confirm and Cancel.
pub fn toggle(state: DialogState) -> DialogState {
  case state.focused {
    Confirm -> DialogState(focused: Cancel)
    Cancel -> DialogState(focused: Confirm)
  }
}

/// Focus the Confirm button.
pub fn focus_confirm(_state: DialogState) -> DialogState {
  DialogState(focused: Confirm)
}

/// Focus the Cancel button.
pub fn focus_cancel(_state: DialogState) -> DialogState {
  DialogState(focused: Cancel)
}

/// Convenience: focus Cancel (same as pressing Escape conceptually).
pub fn cancel(_state: DialogState) -> DialogState {
  DialogState(focused: Cancel)
}

/// `True` if the Confirm button is focused.
pub fn is_confirmed(state: DialogState) -> Bool {
  state.focused == Confirm
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the dialog centered within `area`.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  d: Dialog,
  state: DialogState,
) -> buffer.Buffer {
  let msg_w = text.cell_width(d.message)
  let btn_w =
    text.cell_width(d.confirm_label) + text.cell_width(d.cancel_label) + 3
  let content_w = case msg_w > btn_w {
    True -> msg_w
    False -> btn_w
  }
  let box_w = case d.width > 0 {
    True -> d.width
    False -> content_w + 4
  }
  let box_h = case d.height > 0 {
    True -> d.height
    False -> 6
  }
  let box_w = case box_w < 20 {
    True -> 20
    False -> box_w
  }
  let box_w = case box_w > area.size.width {
    True -> area.size.width
    False -> box_w
  }
  let box_h = case box_h > area.size.height {
    True -> area.size.height
    False -> box_h
  }

  let x = area.position.x + { area.size.width - box_w } / 2
  let y = area.position.y + { area.size.height - box_h } / 2
  let box_area =
    geometry.Rect(
      position: geometry.Position(x: x, y: y),
      size: geometry.Size(width: box_w, height: box_h),
    )

  let blk =
    block.block_new()
    |> block.with_border(d.border)
    |> block.with_style(d.fg, d.bg)
    |> block.with_bg_fill
  let buf1 = block.render(buf, box_area, blk)
  let inner = block.inner(box_area, blk)

  let msg_x =
    inner.position.x + { inner.size.width - text.cell_width(d.message) } / 2
  let msg_y = inner.position.y + { inner.size.height - 3 } / 2
  let buf2 = case msg_y >= inner.position.y && inner.size.height > 0 {
    False -> buf1
    True ->
      buffer.set_string(
        buf1,
        geometry.Position(x: msg_x, y: msg_y),
        text.truncate(d.message, inner.size.width, "…"),
        d.fg,
        d.bg,
        style.none(),
      )
  }

  let btn_y = inner.position.y + inner.size.height - 1
  case btn_y >= inner.position.y && inner.size.height >= 3 {
    False -> buf2
    True -> render_buttons(buf2, inner, d, state, btn_y)
  }
}

fn render_buttons(
  buf: buffer.Buffer,
  inner: geometry.Rect,
  d: Dialog,
  state: DialogState,
  btn_y: Int,
) -> buffer.Buffer {
  let conf_w = text.cell_width(d.confirm_label)
  let canc_w = text.cell_width(d.cancel_label)
  let total_btn_w = conf_w + 1 + canc_w
  let btn_x = inner.position.x + { inner.size.width - total_btn_w } / 2

  let #(conf_st, canc_st) = case state.focused {
    Confirm -> #(d.focused_style, d.cancel_style)
    Cancel -> #(d.confirm_style, d.focused_style)
  }

  let buf1 =
    buffer.set_string(
      buf,
      geometry.Position(x: btn_x, y: btn_y),
      d.confirm_label,
      conf_st.fg,
      conf_st.bg,
      conf_st.modifier,
    )
  let buf2 =
    buffer.set_string(
      buf1,
      geometry.Position(x: btn_x + conf_w + 1, y: btn_y),
      d.cancel_label,
      canc_st.fg,
      canc_st.bg,
      canc_st.modifier,
    )
  buf2
}
