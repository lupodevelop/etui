/// Focus ring, cycle keyboard focus between named widget slots.
///
/// Keep a `FocusRing` in your app model. Route keyboard events to whichever
/// widget `is_focused`. Advance with Tab / Shift-Tab.
///
/// ```gleam
/// import etui/focus
///
/// let ring = focus.focus_new(["sidebar", "main", "statusbar"])
///
/// // In update:
/// let ring = case event {
///   KeyPress("tab")     -> focus.focus_next(ring)
///   KeyPress("backtab") -> focus.focus_prev(ring)   // Shift-Tab
///   _ -> ring
/// }
///
/// // In render:
/// let sidebar_active = focus.is_focused(ring, "sidebar")
/// ```
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

/// Ordered ring of focus slot IDs. Exactly one slot is active at a time.
pub type FocusRing {
  FocusRing(ids: List(String), current: Int)
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// Create a focus ring from a list of slot IDs.
/// The first slot starts focused. Empty list creates an inert ring.
pub fn focus_new(ids: List(String)) -> FocusRing {
  FocusRing(ids: ids, current: 0)
}

// ─────────────────────────────────────────────────────────────────
// Queries

/// ID of the currently focused slot, or `None` if the ring is empty.
pub fn focused(ring: FocusRing) -> Result(String, Nil) {
  get_at(ring.ids, ring.current)
}

/// `True` if `id` is the currently focused slot.
pub fn is_focused(ring: FocusRing, id: String) -> Bool {
  case focused(ring) {
    Ok(current_id) -> current_id == id
    Error(_) -> False
  }
}

/// 0-based index of the currently focused slot.
pub fn current_index(ring: FocusRing) -> Int {
  ring.current
}

/// Total number of slots in the ring.
pub fn size(ring: FocusRing) -> Int {
  list.length(ring.ids)
}

// ─────────────────────────────────────────────────────────────────
// Navigation

/// Move focus to the next slot (wraps around).
pub fn focus_next(ring: FocusRing) -> FocusRing {
  let n = list.length(ring.ids)
  case n {
    0 -> ring
    _ ->
      FocusRing(
        ..ring,
        current: { ring.current + 1 } |> int.modulo(n) |> unwrap_zero,
      )
  }
}

/// Move focus to the previous slot (wraps around).
pub fn focus_prev(ring: FocusRing) -> FocusRing {
  let n = list.length(ring.ids)
  case n {
    0 -> ring
    _ ->
      FocusRing(
        ..ring,
        current: { ring.current + n - 1 } |> int.modulo(n) |> unwrap_zero,
      )
  }
}

/// Move focus to the slot with the given `id`. No-op if `id` not found.
pub fn focus_id(ring: FocusRing, id: String) -> FocusRing {
  case index_of(ring.ids, id, 0) {
    Ok(i) -> FocusRing(..ring, current: i)
    Error(_) -> ring
  }
}

/// Move focus to the slot at the given index (clamped to valid range).
pub fn focus_index(ring: FocusRing, idx: Int) -> FocusRing {
  let n = list.length(ring.ids)
  case n {
    0 -> ring
    _ -> FocusRing(..ring, current: int.clamp(idx, 0, n - 1))
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

fn get_at(lst: List(String), idx: Int) -> Result(String, Nil) {
  case idx {
    i if i < 0 -> Error(Nil)
    0 ->
      case lst {
        [h, ..] -> Ok(h)
        [] -> Error(Nil)
      }
    _ ->
      case lst {
        [] -> Error(Nil)
        [_, ..rest] -> get_at(rest, idx - 1)
      }
  }
}

fn index_of(lst: List(String), target: String, acc: Int) -> Result(Int, Nil) {
  case lst {
    [] -> Error(Nil)
    [h, ..rest] ->
      case h == target {
        True -> Ok(acc)
        False -> index_of(rest, target, acc + 1)
      }
  }
}

fn unwrap_zero(r: Result(Int, Nil)) -> Int {
  case r {
    Ok(n) -> n
    Error(_) -> 0
  }
}
