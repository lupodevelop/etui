/// Generic undo/redo history stack.
///
/// Keep one `UndoStack` in your app model. Call `push` on every state change
/// you want to be undoable. Call `undo`/`redo` in response to key events.
///
/// ```gleam
/// import etui/undo
///
/// // In your model:
/// let history = undo.undo_new("", max_size: 50)
///
/// // On every edit:
/// let history = undo.push(history, new_text)
///
/// // On Ctrl+Z:
/// let history = undo.undo(history)
/// let text = undo.current(history)
///
/// // On Ctrl+Y or Ctrl+Shift+Z:
/// let history = undo.redo(history)
/// ```
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Type

/// Generic undo/redo history.
///
/// - `present`, the current value.
/// - `past`, previous values, most-recent first.
/// - `future`, values undone and available to redo, most-recent first.
/// - `max_size`, maximum entries kept in `past` (0 = unlimited).
pub type UndoStack(a) {
  UndoStack(past: List(a), present: a, future: List(a), max_size: Int)
}

// ─────────────────────────────────────────────────────────────────
// Constructor

/// Create a new stack with an initial `present` value.
/// `max_size` limits how many past entries are retained (0 = unlimited).
pub fn undo_new(initial: a, max_size max_size: Int) -> UndoStack(a) {
  UndoStack(past: [], present: initial, future: [], max_size: max_size)
}

// ─────────────────────────────────────────────────────────────────
// Queries

/// The current value.
pub fn current(stack: UndoStack(a)) -> a {
  stack.present
}

/// `True` if there is at least one past state to undo to.
pub fn can_undo(stack: UndoStack(a)) -> Bool {
  !list.is_empty(stack.past)
}

/// `True` if there is at least one future state to redo to.
pub fn can_redo(stack: UndoStack(a)) -> Bool {
  !list.is_empty(stack.future)
}

/// Number of past entries available to undo.
pub fn undo_depth(stack: UndoStack(a)) -> Int {
  list.length(stack.past)
}

// ─────────────────────────────────────────────────────────────────
// Operations

/// Record `new_value` as the new present, moving the old present into past.
/// Clears the future (redo history) since the branch diverged.
pub fn push(stack: UndoStack(a), new_value: a) -> UndoStack(a) {
  let past = [stack.present, ..stack.past]
  let trimmed = case stack.max_size > 0 && list.length(past) > stack.max_size {
    True -> list.take(past, stack.max_size)
    False -> past
  }
  UndoStack(
    past: trimmed,
    present: new_value,
    future: [],
    max_size: stack.max_size,
  )
}

/// Undo: move present to future, restore the most-recent past as present.
/// No-op if there is nothing to undo.
pub fn undo(stack: UndoStack(a)) -> UndoStack(a) {
  case stack.past {
    [] -> stack
    [prev, ..rest] ->
      UndoStack(
        past: rest,
        present: prev,
        future: [stack.present, ..stack.future],
        max_size: stack.max_size,
      )
  }
}

/// Redo: move present to past, restore the most-recent future as present.
/// No-op if there is nothing to redo.
pub fn redo(stack: UndoStack(a)) -> UndoStack(a) {
  case stack.future {
    [] -> stack
    [next, ..rest] ->
      UndoStack(
        past: [stack.present, ..stack.past],
        present: next,
        future: rest,
        max_size: stack.max_size,
      )
  }
}

/// Reset to initial state, clearing all history.
pub fn reset(stack: UndoStack(a), initial: a) -> UndoStack(a) {
  UndoStack(past: [], present: initial, future: [], max_size: stack.max_size)
}
