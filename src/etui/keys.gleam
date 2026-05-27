/// Named key constants and pattern-match helper for keyboard events.
///
/// Instead of comparing raw strings from `backend.KeyPress(key)` everywhere,
/// use these constants for clarity and to avoid typos.
///
/// ```gleam
/// import etui/keys
/// import etui/backend
///
/// fn on_event(ev: backend.InputEvent, state: Model) -> Model {
///   case ev {
///     backend.KeyPress(k) -> case keys.match(k) {
///       keys.Up    -> Model(..state, selected: state.selected - 1)
///       keys.Down  -> Model(..state, selected: state.selected + 1)
///       keys.Enter -> Model(..state, open: True)
///       keys.Char(c) -> handle_char(c, state)
///       _          -> state
///     }
///     _ -> state
///   }
/// }
/// ```
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Key type

pub type Key {
  /// Plain printable character (single grapheme, not a control key).
  Char(String)
  Up
  Down
  Left
  Right
  Enter
  Backspace
  Delete
  Tab
  BackTab
  Home
  End
  PageUp
  PageDown
  Escape
  Insert
  /// F1–F12
  F(Int)
  /// Ctrl+<char>, e.g. Ctrl("c"), Ctrl("d")
  Ctrl(String)
  /// Alt+<char>, e.g. Alt("f")
  Alt(String)
  /// Unknown / unrecognised key string.
  Unknown(String)
}

// ─────────────────────────────────────────────────────────────────
// Match helper

/// Parse a raw key string (from `backend.KeyPress`) into a `Key`.
///
/// Raw strings from the Erlang backend follow these conventions:
/// - Printable ASCII/Unicode: the character itself (e.g. `"a"`, `"A"`, `"€"`)
/// - Arrow keys: `"up"`, `"down"`, `"left"`, `"right"`
/// - Control keys: `"enter"`, `"backspace"`, `"delete"`, `"tab"`, `"backtab"`,
///   `"home"`, `"end"`, `"pageup"`, `"pagedown"`, `"esc"`, `"insert"`
/// - Function keys: `"f1"` … `"f12"`
/// - Ctrl combos: `"ctrl+a"` … `"ctrl+z"`, `"ctrl+["`, etc.
/// - Alt combos:  `"alt+a"` … `"alt+z"`, etc.
pub fn match(raw: String) -> Key {
  case raw {
    "up" -> Up
    "down" -> Down
    "left" -> Left
    "right" -> Right
    "enter" -> Enter
    "backspace" -> Backspace
    "delete" -> Delete
    "tab" -> Tab
    "backtab" -> BackTab
    "home" -> Home
    "end" -> End
    "pageup" -> PageUp
    "pagedown" -> PageDown
    "esc" -> Escape
    "insert" -> Insert
    "f1" -> F(1)
    "f2" -> F(2)
    "f3" -> F(3)
    "f4" -> F(4)
    "f5" -> F(5)
    "f6" -> F(6)
    "f7" -> F(7)
    "f8" -> F(8)
    "f9" -> F(9)
    "f10" -> F(10)
    "f11" -> F(11)
    "f12" -> F(12)
    _ ->
      case string.starts_with(raw, "ctrl+") {
        True -> Ctrl(string.drop_start(raw, 5))
        False ->
          case string.starts_with(raw, "alt+") {
            True -> Alt(string.drop_start(raw, 4))
            False ->
              case string.length(raw) > 0 {
                True -> Char(raw)
                False -> Unknown(raw)
              }
          }
      }
  }
}

// ─────────────────────────────────────────────────────────────────
// Convenience predicates

/// True if key is a printable character (not a control/special key).
pub fn is_char(k: Key) -> Bool {
  case k {
    Char(_) -> True
    _ -> False
  }
}

/// Extract the character string from a `Char` key. Returns `""` for others.
pub fn char_value(k: Key) -> String {
  case k {
    Char(c) -> c
    _ -> ""
  }
}

/// True if the key is a navigation key (arrows, home, end, page up/down).
pub fn is_navigation(k: Key) -> Bool {
  case k {
    Up | Down | Left | Right | Home | End | PageUp | PageDown -> True
    _ -> False
  }
}

/// True if the key is a modifier combo (Ctrl or Alt).
pub fn is_modifier(k: Key) -> Bool {
  case k {
    Ctrl(_) | Alt(_) -> True
    _ -> False
  }
}
