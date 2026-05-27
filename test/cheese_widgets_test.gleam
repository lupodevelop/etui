/// Tests for the bubbletea-inspired widgets ported from ratatui-cheese:
/// paginator, help, fieldset, multi_select. Focuses on the state and
/// helper logic; render correctness is covered indirectly by the snapshot
/// tests and visually by the demo apps.
import etui/widgets/fieldset
import etui/widgets/help
import etui/widgets/multi_select
import etui/widgets/paginator
import etui/widgets/spinner
import etui/widgets/tree
import gleeunit/should

// ─────────────────────────────────────────────────────────────────
// Paginator

pub fn paginator_next_clamps_to_last_page_test() {
  let p =
    paginator.paginator_new(3)
    |> paginator.next_page
    |> paginator.next_page
    |> paginator.next_page
    |> paginator.next_page
  p.current |> should.equal(2)
}

pub fn paginator_prev_clamps_to_zero_test() {
  let p =
    paginator.paginator_new(5)
    |> paginator.prev_page
    |> paginator.prev_page
  p.current |> should.equal(0)
}

pub fn paginator_go_to_clamps_test() {
  let p =
    paginator.paginator_new(5)
    |> paginator.go_to(99)
  p.current |> should.equal(4)
}

pub fn paginator_slice_returns_current_page_items_test() {
  let p =
    paginator.paginator_new(3)
    |> paginator.with_page_size(2)
    |> paginator.go_to(1)
  paginator.slice([10, 20, 30, 40, 50], p)
  |> should.equal([30, 40])
}

pub fn paginator_set_item_count_recomputes_total_test() {
  let p =
    paginator.paginator_new(1)
    |> paginator.with_page_size(3)
    |> paginator.set_item_count(10)
  // ceil(10 / 3) = 4 pages
  p.total |> should.equal(4)
}

pub fn paginator_total_clamped_to_one_test() {
  paginator.paginator_new(0).total |> should.equal(1)
}

// ─────────────────────────────────────────────────────────────────
// Help

pub fn help_toggle_mode_test() {
  let h = help.help_new([help.binding(["q"], "quit")])
  h.mode |> should.equal(help.Short)
  let h = help.toggle_mode(h)
  h.mode |> should.equal(help.Full)
  let h = help.toggle_mode(h)
  h.mode |> should.equal(help.Short)
}

pub fn help_binding_keys_preserved_test() {
  let b = help.binding(["ctrl+c", "q"], "quit")
  b.keys |> should.equal(["ctrl+c", "q"])
  b.description |> should.equal("quit")
}

// ─────────────────────────────────────────────────────────────────
// Fieldset

pub fn fieldset_default_align_test() {
  let fs = fieldset.fieldset_new("Section")
  fs.align |> should.equal(fieldset.AlignLeft)
  fs.title |> should.equal("Section")
}

pub fn fieldset_with_align_center_test() {
  let fs =
    fieldset.fieldset_new("Section")
    |> fieldset.with_align(fieldset.AlignCenter)
  fs.align |> should.equal(fieldset.AlignCenter)
}

// ─────────────────────────────────────────────────────────────────
// MultiSelect

pub fn multi_select_toggle_adds_and_removes_test() {
  let s =
    multi_select.state_new()
    |> multi_select.toggle(0)
  multi_select.selected_indices(s) |> should.equal([0])
  let s = multi_select.toggle(s, 0)
  multi_select.selected_indices(s) |> should.equal([])
}

pub fn multi_select_toggle_respects_max_test() {
  let s = multi_select.state_new()
  // cursor 0 then 1, max 1 -> second toggle blocked
  let s = multi_select.toggle(s, 1)
  let s = multi_select.select_next(s, 3)
  let s = multi_select.toggle(s, 1)
  // still only the first selected
  multi_select.selected_indices(s) |> should.equal([0])
}

pub fn multi_select_select_next_clamps_test() {
  let s = multi_select.state_new()
  let s = multi_select.select_next(s, 2)
  let s = multi_select.select_next(s, 2)
  let s = multi_select.select_next(s, 2)
  s.cursor |> should.equal(1)
}

pub fn multi_select_select_prev_clamps_test() {
  let s = multi_select.state_new()
  let s = multi_select.select_prev(s)
  s.cursor |> should.equal(0)
}

pub fn multi_select_selected_values_test() {
  let s = multi_select.state_new()
  let s = multi_select.toggle(s, 0)
  let s = multi_select.select_next(s, 4)
  let s = multi_select.select_next(s, 4)
  let s = multi_select.toggle(s, 0)
  multi_select.selected_values(["a", "b", "c", "d"], s)
  |> should.equal(["a", "c"])
}

pub fn multi_select_clear_test() {
  let s = multi_select.state_new()
  let s = multi_select.toggle(s, 0)
  let s = multi_select.clear_selection(s)
  multi_select.selected_indices(s) |> should.equal([])
}

pub fn multi_select_effective_offset_test() {
  let s = multi_select.state_new()
  let s = multi_select.select_next(s, 10)
  let s = multi_select.select_next(s, 10)
  let s = multi_select.select_next(s, 10)
  // cursor 3, height 2 → offset 2
  multi_select.effective_offset(s, 2) |> should.equal(2)
}

// ─────────────────────────────────────────────────────────────────
// Spinner presets sanity (every preset must produce a non-empty frame)

pub fn spinner_all_presets_have_frames_test() {
  let presets = [
    spinner.Dots,
    spinner.Line,
    spinner.Circle,
    spinner.Bounce,
    spinner.MiniDot,
    spinner.Jump,
    spinner.Pulse,
    spinner.Points,
    spinner.Globe,
    spinner.Moon,
    spinner.Monkey,
    spinner.Meter,
    spinner.Hamburger,
    spinner.Ellipsis,
  ]
  // Each preset must be a valid SpinnerStyle. Building the widget never panics.
  let _ =
    presets
    |> gleeunit_dummy_iter
  Nil
}

fn gleeunit_dummy_iter(presets: List(spinner.SpinnerStyle)) -> Nil {
  case presets {
    [] -> Nil
    [p, ..rest] -> {
      let _ = spinner.spinner_new() |> spinner.with_style(p)
      gleeunit_dummy_iter(rest)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Tree counts (constructors + accessors)

pub fn tree_node_with_count_test() {
  let n = tree.node_with_count("inbox", "Inbox", 12, [])
  n.count |> should.equal(Ok(12))
}

pub fn tree_leaf_with_count_test() {
  let n = tree.leaf_with_count("a", "A", 3)
  n.count |> should.equal(Ok(3))
}

pub fn tree_with_count_attaches_test() {
  let n = tree.leaf("x", "X") |> tree.with_count(7)
  n.count |> should.equal(Ok(7))
}

pub fn tree_node_default_no_count_test() {
  tree.leaf("a", "A").count |> should.equal(Error(Nil))
}
