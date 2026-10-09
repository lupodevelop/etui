/// Breaking a word that is wider than the row.
///
/// Two things used to be wrong with it. A grapheme wider than the row fitted
/// nowhere, so the wrapper put the same word back and never returned. And each
/// row measured and re-joined the whole rest of the word, which is quadratic.
import etui/span.{type Line}
import etui/text
import gleam/list
import gleam/string
import gleeunit/should

fn rows(s: String, width: Int) -> List(String) {
  span.wrap_line(span.line_plain(s), width)
  |> list.map(fn(l: Line) {
    string.concat(list.map(l.spans, fn(sp) { sp.content }))
  })
}

pub fn a_grapheme_wider_than_the_row_gets_a_row_of_its_own_test() {
  rows("a中b", 1) |> should.equal(["a", "中", "b"])
  rows("中中", 1) |> should.equal(["中", "中"])
}

pub fn a_joined_sequence_is_never_split_test() {
  let family = "👨\u{200D}👩\u{200D}👧"
  let flag = "\u{1F1EF}\u{1F1F5}"
  rows("x" <> family <> flag, 2) |> should.equal(["x", family, flag])
}

pub fn only_a_single_wide_grapheme_may_exceed_the_width_test() {
  let src = "ab 中文字漢字 supercalifragilistic 中"
  list.each([1, 2, 3, 4, 5, 6, 7], fn(width) {
    list.each(rows(src, width), fn(r) {
      case text.cell_width(r) > width {
        True -> string.length(r) |> should.equal(1)
        False -> Nil
      }
    })
  })
}

pub fn no_text_is_lost_or_invented_test() {
  let src = "ab 中文字漢字 supercalifragilistic 中"
  let squash = fn(s) { string.replace(s, " ", "") }
  list.each([1, 2, 3, 4, 5, 6, 7, 40], fn(width) {
    rows(src, width)
    |> string.concat
    |> squash
    |> should.equal(squash(src))
  })
}

pub fn a_zero_width_grapheme_stays_on_its_row_test() {
  rows("ab 中\u{200B}中", 2) |> should.equal(["ab", "中\u{200B}", "中"])
}

pub fn the_first_piece_fills_the_row_it_starts_on_test() {
  rows("ab cdefghijklmnop", 5)
  |> should.equal(["ab cd", "efghi", "jklmn", "op"])
}

pub fn words_after_a_broken_one_share_its_last_row_test() {
  rows("abcdefgh ij", 5) |> should.equal(["abcde", "fgh", "ij"])
}

pub fn a_very_long_word_is_cut_into_full_rows_test() {
  let word = string.repeat("a", 50_000)
  let out = rows(word, 80)
  list.length(out) |> should.equal(625)
  list.all(out, fn(r) { text.cell_width(r) == 80 }) |> should.equal(True)
  string.concat(out) |> should.equal(word)
}

pub fn a_zero_width_line_is_empty_test() {
  rows("abc", 0) |> should.equal([])
}
