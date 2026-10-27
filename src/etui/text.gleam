/// TUI-aware text handling. Cell-width semantics for terminals.
///
/// All `width` values are in **terminal cells**, not graphemes or codepoints:
///   - ASCII printable: 1 cell
///   - CJK / Hangul / Hiragana / Katakana / Fullwidth: 2 cells
///   - Emoji (including ZWJ sequences): 2 cells by default
///   - Supported VS16 sequences: 2 cells; VS15 on BMP emoji: 1 cell
///   - Combining marks, ZWJ, variation selectors, zero-width formatters: 0 cells
///   - Misc Symbols U+2600–26FF and Dingbats U+2700–27BF: 1 cell, except the
///     East Asian Wide ones (⚡ ✅ ❌ ⭐ ...), which are 2.
///
/// Grapheme segmentation delegates to Erlang's native Unicode (UAX #29).
/// This correctly clusters ZWJ sequences, flag pairs, and combining marks.
///
/// **Limitation:** emoji whose width depends on terminal/font (e.g. keycap
/// sequences, skin-tone modifiers) are approximated as 2 cells. Behaviour
/// may differ on terminals that render them as narrow.
import gleam/int
import gleam/list
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Cell width

/// Split a string into grapheme clusters (UAX #29, via Erlang Unicode).
///
/// Each element is one user-perceived character: a base letter, a ZWJ
/// sequence, a flag pair, an emoji with modifiers, etc.
///
/// ```gleam
/// graphemes("café") // ["c", "a", "f", "é"]
/// graphemes("👨‍👩‍👧‍👦") // ["👨‍👩‍👧‍👦"], one cluster
/// ```
@external(erlang, "etui_text_ffi", "graphemes")
pub fn graphemes(s: String) -> List(String) {
  string.to_graphemes(s)
}

/// Cell width of a string (sum of grapheme widths).
pub fn cell_width(s: String) -> Int {
  s
  |> graphemes
  |> list.fold(0, fn(acc, g) { acc + grapheme_cell_width(g) })
}

/// Cell width of a single grapheme cluster.
/// The base determines width, except for a supported emoji variation sequence:
/// VS16 requests two cells; VS15 requests one for bases below U+1F000.
/// Supplementary emoji retain their base width with VS15. This is a terminal
/// width policy; actual glyph presentation depends on the terminal and font.
/// Selectors must immediately follow a base listed in Unicode 16.0's emoji
/// variation sequences. Combining marks and the rest of a ZWJ cluster add no
/// cells of their own.
pub fn grapheme_cell_width(g: String) -> Int {
  case string.to_utf_codepoints(g) {
    [] -> 0
    [cp] -> codepoint_cell_width(string.utf_codepoint_to_int(cp))
    [cp, next, ..] -> {
      let base = string.utf_codepoint_to_int(cp)
      let selector = string.utf_codepoint_to_int(next)
      case selector {
        0xFE0F | 0xFE0E ->
          case emoji_variation_base(base) {
            True if selector == 0xFE0F -> 2
            True if base < 0x1F000 -> 1
            _ -> codepoint_cell_width(base)
          }
        _ -> codepoint_cell_width(base)
      }
    }
  }
}

// Bases from Unicode 16.0 emoji-variation-sequences.txt (2024-05-01).
// https://www.unicode.org/Public/16.0.0/ucd/emoji/emoji-variation-sequences.txt
// Unicode data license: https://www.unicode.org/license.txt
// Merge consecutive bases into ranges when regenerating this table.
fn emoji_variation_base(cp: Int) -> Bool {
  case cp {
    0x0023 -> True
    0x002A -> True
    n if n >= 0x0030 && n <= 0x0039 -> True
    0x00A9 -> True
    0x00AE -> True
    0x203C -> True
    0x2049 -> True
    0x2122 -> True
    0x2139 -> True
    n if n >= 0x2194 && n <= 0x2199 -> True
    n if n >= 0x21A9 && n <= 0x21AA -> True
    n if n >= 0x231A && n <= 0x231B -> True
    0x2328 -> True
    0x23CF -> True
    n if n >= 0x23E9 && n <= 0x23F3 -> True
    n if n >= 0x23F8 && n <= 0x23FA -> True
    0x24C2 -> True
    n if n >= 0x25AA && n <= 0x25AB -> True
    0x25B6 -> True
    0x25C0 -> True
    n if n >= 0x25FB && n <= 0x25FE -> True
    n if n >= 0x2600 && n <= 0x2604 -> True
    0x260E -> True
    0x2611 -> True
    n if n >= 0x2614 && n <= 0x2615 -> True
    0x2618 -> True
    0x261D -> True
    0x2620 -> True
    n if n >= 0x2622 && n <= 0x2623 -> True
    0x2626 -> True
    0x262A -> True
    n if n >= 0x262E && n <= 0x262F -> True
    n if n >= 0x2638 && n <= 0x263A -> True
    0x2640 -> True
    0x2642 -> True
    n if n >= 0x2648 && n <= 0x2653 -> True
    n if n >= 0x265F && n <= 0x2660 -> True
    0x2663 -> True
    n if n >= 0x2665 && n <= 0x2666 -> True
    0x2668 -> True
    0x267B -> True
    n if n >= 0x267E && n <= 0x267F -> True
    n if n >= 0x2692 && n <= 0x2697 -> True
    0x2699 -> True
    n if n >= 0x269B && n <= 0x269C -> True
    n if n >= 0x26A0 && n <= 0x26A1 -> True
    0x26A7 -> True
    n if n >= 0x26AA && n <= 0x26AB -> True
    n if n >= 0x26B0 && n <= 0x26B1 -> True
    n if n >= 0x26BD && n <= 0x26BE -> True
    n if n >= 0x26C4 && n <= 0x26C5 -> True
    0x26C8 -> True
    n if n >= 0x26CE && n <= 0x26CF -> True
    0x26D1 -> True
    n if n >= 0x26D3 && n <= 0x26D4 -> True
    n if n >= 0x26E9 && n <= 0x26EA -> True
    n if n >= 0x26F0 && n <= 0x26F5 -> True
    n if n >= 0x26F7 && n <= 0x26FA -> True
    0x26FD -> True
    0x2702 -> True
    0x2705 -> True
    n if n >= 0x2708 && n <= 0x270D -> True
    0x270F -> True
    0x2712 -> True
    0x2714 -> True
    0x2716 -> True
    0x271D -> True
    0x2721 -> True
    0x2728 -> True
    n if n >= 0x2733 && n <= 0x2734 -> True
    0x2744 -> True
    0x2747 -> True
    0x274C -> True
    0x274E -> True
    n if n >= 0x2753 && n <= 0x2755 -> True
    0x2757 -> True
    n if n >= 0x2763 && n <= 0x2764 -> True
    n if n >= 0x2795 && n <= 0x2797 -> True
    0x27A1 -> True
    0x27B0 -> True
    0x27BF -> True
    n if n >= 0x2934 && n <= 0x2935 -> True
    n if n >= 0x2B05 && n <= 0x2B07 -> True
    n if n >= 0x2B1B && n <= 0x2B1C -> True
    0x2B50 -> True
    0x2B55 -> True
    0x3030 -> True
    0x303D -> True
    0x3297 -> True
    0x3299 -> True
    0x1F004 -> True
    n if n >= 0x1F170 && n <= 0x1F171 -> True
    n if n >= 0x1F17E && n <= 0x1F17F -> True
    0x1F202 -> True
    0x1F21A -> True
    0x1F22F -> True
    0x1F237 -> True
    n if n >= 0x1F30D && n <= 0x1F30F -> True
    0x1F315 -> True
    0x1F31C -> True
    0x1F321 -> True
    n if n >= 0x1F324 && n <= 0x1F32C -> True
    0x1F336 -> True
    0x1F378 -> True
    0x1F37D -> True
    0x1F393 -> True
    n if n >= 0x1F396 && n <= 0x1F397 -> True
    n if n >= 0x1F399 && n <= 0x1F39B -> True
    n if n >= 0x1F39E && n <= 0x1F39F -> True
    0x1F3A7 -> True
    n if n >= 0x1F3AC && n <= 0x1F3AE -> True
    0x1F3C2 -> True
    0x1F3C4 -> True
    0x1F3C6 -> True
    n if n >= 0x1F3CA && n <= 0x1F3CE -> True
    n if n >= 0x1F3D4 && n <= 0x1F3E0 -> True
    0x1F3ED -> True
    0x1F3F3 -> True
    0x1F3F5 -> True
    0x1F3F7 -> True
    0x1F408 -> True
    0x1F415 -> True
    0x1F41F -> True
    0x1F426 -> True
    0x1F43F -> True
    n if n >= 0x1F441 && n <= 0x1F442 -> True
    n if n >= 0x1F446 && n <= 0x1F449 -> True
    n if n >= 0x1F44D && n <= 0x1F44E -> True
    0x1F453 -> True
    0x1F46A -> True
    0x1F47D -> True
    0x1F4A3 -> True
    0x1F4B0 -> True
    0x1F4B3 -> True
    0x1F4BB -> True
    0x1F4BF -> True
    0x1F4CB -> True
    0x1F4DA -> True
    0x1F4DF -> True
    n if n >= 0x1F4E4 && n <= 0x1F4E6 -> True
    n if n >= 0x1F4EA && n <= 0x1F4ED -> True
    0x1F4F7 -> True
    n if n >= 0x1F4F9 && n <= 0x1F4FB -> True
    0x1F4FD -> True
    0x1F508 -> True
    0x1F50D -> True
    n if n >= 0x1F512 && n <= 0x1F513 -> True
    n if n >= 0x1F549 && n <= 0x1F54A -> True
    n if n >= 0x1F550 && n <= 0x1F567 -> True
    n if n >= 0x1F56F && n <= 0x1F570 -> True
    n if n >= 0x1F573 && n <= 0x1F579 -> True
    0x1F587 -> True
    n if n >= 0x1F58A && n <= 0x1F58D -> True
    0x1F590 -> True
    0x1F5A5 -> True
    0x1F5A8 -> True
    n if n >= 0x1F5B1 && n <= 0x1F5B2 -> True
    0x1F5BC -> True
    n if n >= 0x1F5C2 && n <= 0x1F5C4 -> True
    n if n >= 0x1F5D1 && n <= 0x1F5D3 -> True
    n if n >= 0x1F5DC && n <= 0x1F5DE -> True
    0x1F5E1 -> True
    0x1F5E3 -> True
    0x1F5E8 -> True
    0x1F5EF -> True
    0x1F5F3 -> True
    0x1F5FA -> True
    0x1F610 -> True
    0x1F687 -> True
    0x1F68D -> True
    0x1F691 -> True
    0x1F694 -> True
    0x1F698 -> True
    0x1F6AD -> True
    0x1F6B2 -> True
    n if n >= 0x1F6B9 && n <= 0x1F6BA -> True
    0x1F6BC -> True
    0x1F6CB -> True
    n if n >= 0x1F6CD && n <= 0x1F6CF -> True
    n if n >= 0x1F6E0 && n <= 0x1F6E5 -> True
    0x1F6E9 -> True
    0x1F6F0 -> True
    0x1F6F3 -> True
    _ -> False
  }
}

/// Cell width of a single Unicode codepoint.
/// Returns 0 for control / combining / zero-width, 2 for wide (CJK / emoji /
/// fullwidth), 1 otherwise.
pub fn codepoint_cell_width(cp: Int) -> Int {
  case cp {
    // C0 controls + DEL
    n if n < 0x20 -> 0
    0x7F -> 0
    // Combining diacritical marks
    n if n >= 0x0300 && n <= 0x036F -> 0
    // Hangul Jamo medial vowels + final consonants (combining)
    n if n >= 0x1160 && n <= 0x11FF -> 0
    // Variation selectors
    n if n >= 0xFE00 && n <= 0xFE0F -> 0
    n if n >= 0xE0100 && n <= 0xE01EF -> 0
    // Zero-width formatters: ZWSP, ZWNJ, ZWJ, BOM
    0x200B | 0x200C | 0x200D | 0xFEFF -> 0

    // ── Wide (East Asian Wide / Fullwidth) ─────────────────────────
    // Hangul Jamo initial consonants
    n if n >= 0x1100 && n <= 0x115F -> 2
    // CJK Radicals + Symbols + Punctuation
    n if n >= 0x2E80 && n <= 0x303E -> 2
    // Hiragana, Katakana, Bopomofo, Hangul Compat, CJK Strokes, etc.
    n if n >= 0x3041 && n <= 0x33FF -> 2
    // CJK Extension A
    n if n >= 0x3400 && n <= 0x4DBF -> 2
    // CJK Unified Ideographs
    n if n >= 0x4E00 && n <= 0x9FFF -> 2
    // Yi Syllables/Radicals
    n if n >= 0xA000 && n <= 0xA4CF -> 2
    // Hangul Syllables
    n if n >= 0xAC00 && n <= 0xD7A3 -> 2
    // CJK Compatibility Ideographs
    n if n >= 0xF900 && n <= 0xFAFF -> 2
    // CJK Compatibility Forms
    n if n >= 0xFE30 && n <= 0xFE4F -> 2
    // Fullwidth Forms (NOT halfwidth section 0xFF61–0xFFDC which is width 1)
    n if n >= 0xFF00 && n <= 0xFF60 -> 2
    // Fullwidth Signs
    n if n >= 0xFFE0 && n <= 0xFFE6 -> 2

    // ── Emoji ──────────────────────────────────────────────────────
    // Misc Symbols (0x2600..0x26FF) and Dingbats (0x2700..0x27BF) are not
    // ranges here: most of them (✦ ★ ◆ ☆) are one cell, and treating the block
    // as wide made buffer positions drift past the cursor. `symbol_width`
    // below picks out the wide ones.
    // Regional Indicator Symbols (flags pair into 2 cells)
    n if n >= 0x1F1E6 && n <= 0x1F1FF -> 2
    // Misc Symbols and Pictographs
    n if n >= 0x1F300 && n <= 0x1F5FF -> 2
    // Emoticons
    n if n >= 0x1F600 && n <= 0x1F64F -> 2
    // Transport and Map Symbols
    n if n >= 0x1F680 && n <= 0x1F6FF -> 2
    // Alchemical Symbols
    n if n >= 0x1F700 && n <= 0x1F77F -> 2
    // Geometric Shapes Extended
    n if n >= 0x1F780 && n <= 0x1F7FF -> 2
    // Supplemental Arrows-C
    n if n >= 0x1F800 && n <= 0x1F8FF -> 2
    // Supplemental Symbols and Pictographs
    n if n >= 0x1F900 && n <= 0x1F9FF -> 2
    // Symbols and Pictographs Extended-A
    n if n >= 0x1FA00 && n <= 0x1FAFF -> 2

    // CJK Extensions B, C, D, E, F, G
    n if n >= 0x20000 && n <= 0x2FFFD -> 2
    n if n >= 0x30000 && n <= 0x3FFFD -> 2

    n -> symbol_width(n)
  }
}

/// Width of the East Asian Wide symbols that no block above covers.
///
/// Misc Symbols and Dingbats mix characters that are one cell (✦ ★ ◆ ☆,
/// Ambiguous) with ones every terminal draws in two (⚡ ✅ ❌ ⭐), so the block
/// cannot decide. The East Asian Width property does, one code point at a
/// time, and a terminal's own `wcwidth` follows it. These are its Wide (W)
/// runs below U+1F300 that lie outside the CJK ranges above. Regenerate them
/// from EastAsianWidth.txt rather than editing by hand.
fn symbol_width(cp: Int) -> Int {
  case cp {
    n if n >= 0x2329 && n <= 0x232A -> 2
    n if n >= 0x231A && n <= 0x231B -> 2
    n if n >= 0x23E9 && n <= 0x23EC -> 2
    n if n >= 0x25FD && n <= 0x25FE -> 2
    n if n >= 0x2614 && n <= 0x2615 -> 2
    n if n >= 0x2648 && n <= 0x2653 -> 2
    n if n >= 0x26AA && n <= 0x26AB -> 2
    n if n >= 0x26BD && n <= 0x26BE -> 2
    n if n >= 0x26C4 && n <= 0x26C5 -> 2
    n if n >= 0x26F2 && n <= 0x26F3 -> 2
    n if n >= 0x270A && n <= 0x270B -> 2
    n if n >= 0x2753 && n <= 0x2755 -> 2
    n if n >= 0x2795 && n <= 0x2797 -> 2
    n if n >= 0x2B1B && n <= 0x2B1C -> 2
    0x23F0
    | 0x23F3
    | 0x267F
    | 0x2693
    | 0x26A1
    | 0x26CE
    | 0x26D4
    | 0x26EA
    | 0x26F5
    | 0x26FA
    | 0x26FD
    | 0x2705
    | 0x2728
    | 0x274C
    | 0x274E
    | 0x2757
    | 0x27B0
    | 0x27BF
    | 0x2B50
    | 0x2B55 -> 2

    // Mahjong, playing cards, and the enclosed squares and ideographs.
    0x1F004 | 0x1F0CF | 0x1F18E -> 2
    n if n >= 0x1F191 && n <= 0x1F19A -> 2
    n if n >= 0x1F200 && n <= 0x1F202 -> 2
    n if n >= 0x1F210 && n <= 0x1F23B -> 2
    n if n >= 0x1F240 && n <= 0x1F248 -> 2
    n if n >= 0x1F250 && n <= 0x1F251 -> 2
    n if n >= 0x1F260 && n <= 0x1F265 -> 2

    _ -> 1
  }
}

// ─────────────────────────────────────────────────────────────────
// Text operations (cell-aware)

pub type Alignment {
  Left
  Center
  Right
}

/// Truncate to max_width cells. Appends ellipsis only if truncation occurs.
/// The ellipsis itself counts toward the budget.
pub fn truncate(s: String, max_width: Int, ellipsis: String) -> String {
  case max_width {
    w if w <= 0 -> ""
    _ -> {
      let s_width = cell_width(s)
      case s_width <= max_width {
        True -> s
        False -> {
          let ellipsis_width = cell_width(ellipsis)
          let available = int.max(0, max_width - ellipsis_width)
          let gs = graphemes(s)
          take_prefix(gs, available, 0, "") <> ellipsis
        }
      }
    }
  }
}

fn take_prefix(
  graphemes: List(String),
  available: Int,
  width: Int,
  acc: String,
) -> String {
  case graphemes {
    [] -> acc
    [g, ..rest] -> {
      let g_width = grapheme_cell_width(g)
      case width + g_width <= available {
        True -> take_prefix(rest, available, width + g_width, acc <> g)
        False -> acc
      }
    }
  }
}

/// Return `s` without its first `n` graphemes.
///
/// Not spelled `string.drop_start`: on the JavaScript target that function
/// measures the dropped prefix in UTF-8 bytes and then slices the string with
/// that count, while `String.slice` counts UTF-16 units. The two agree on
/// ASCII and disagree everywhere else — box drawing, CJK, emoji — where the
/// index lands short of or past the end and the wrong remainder comes back
/// (observed with gleam_stdlib 1.0.0). Graphemes in, graphemes out, on every
/// target.
pub fn drop_graphemes(s: String, n: Int) -> String {
  case n <= 0 {
    True -> s
    False ->
      s
      |> graphemes
      |> list.drop(n)
      |> string.concat
  }
}

/// Word-wrap to max_width cells.
///
/// Line endings are normalised first: `\r\n` and lone `\r` both become `\n`.
/// A raw `\r` left in the output would occupy zero cells and desynchronise
/// every position after it.
///
/// Tabs are expanded to spaces at 8-column tab stops before wrapping, so a
/// tab never reaches the buffer (control characters are dropped there).
///
/// Returns a list of lines, each at most `max_width` cells wide.
pub fn wrap(s: String, max_width: Int) -> List(String) {
  case max_width {
    w if w <= 0 -> []
    _ ->
      s
      |> normalise_newlines
      |> expand_tabs(8)
      |> string.split("\n")
      |> list.flat_map(fn(para) { wrap_para(para, max_width) })
  }
}

/// Normalise `\r\n` and lone `\r` to `\n`.
///
/// No `string.contains(s, "\r")` fast path: `\r\n` is a single grapheme
/// cluster, so `contains` reports False for a `\r` that is followed by `\n`,
/// which is exactly the case this needs to catch.
pub fn normalise_newlines(s: String) -> String {
  s
  |> string.replace("\r\n", "\n")
  |> string.replace("\r", "\n")
}

/// Expand tab characters to spaces, advancing to the next multiple of
/// `tab_width` cells. Newlines reset the column counter.
///
/// ```gleam
/// text.expand_tabs("a\tb", 4)  // "a   b"
/// ```
pub fn expand_tabs(s: String, tab_width: Int) -> String {
  case string.contains(s, "\t") {
    False -> s
    True -> expand_tabs_loop(graphemes(s), int.max(1, tab_width), 0, [])
  }
}

// Pieces accumulate newest-first and are joined once. Appending to the string
// on every grapheme would copy the whole accumulator each time, which is
// O(n^2) in the length of the line.
fn expand_tabs_loop(
  gs: List(String),
  tab_width: Int,
  col: Int,
  rev_acc: List(String),
) -> String {
  case gs {
    [] -> string.concat(list.reverse(rev_acc))
    ["\t", ..rest] -> {
      let pad = tab_width - col % tab_width
      expand_tabs_loop(rest, tab_width, col + pad, [
        string.repeat(" ", pad),
        ..rev_acc
      ])
    }
    ["\n", ..rest] -> expand_tabs_loop(rest, tab_width, 0, ["\n", ..rev_acc])
    [g, ..rest] ->
      expand_tabs_loop(rest, tab_width, col + grapheme_cell_width(g), [
        g,
        ..rev_acc
      ])
  }
}

fn wrap_para(s: String, max_width: Int) -> List(String) {
  // An empty paragraph produces one blank line (not zero lines).
  case s {
    "" -> [""]
    _ -> wrap_para_words(s, max_width)
  }
}

fn wrap_para_words(s: String, max_width: Int) -> List(String) {
  // The line being built is kept as its words, newest first, next to its
  // width. Both matter: measuring the joined line on every word walks its
  // graphemes again and again, and rebuilding it with <> copies it again and
  // again, so a long line cost time quadratic in its own length. Each word is
  // now measured once and each line joined once.
  let #(rev_lines, rev_current, _) =
    list.fold(string.split(s, " "), #([], [], 0), fn(acc, word) {
      let #(lines, current, width) = acc
      let word_width = cell_width(word)
      let gap = case current {
        [] -> 0
        _ -> 1
      }
      case width + gap + word_width <= max_width {
        True -> #(lines, [word, ..current], width + gap + word_width)
        False -> {
          let closed = case current {
            [] -> lines
            _ -> [join_words(current), ..lines]
          }
          case word_width <= max_width {
            True -> #(closed, [word], word_width)
            False -> {
              // Wider than the whole line: break it, and carry the last piece
              // on as the start of the next line.
              case list.reverse(hard_break_word(word, max_width)) {
                [] -> #(closed, [], 0)
                [last, ..rest_rev] -> #(
                  list.append(rest_rev, closed),
                  [last],
                  cell_width(last),
                )
              }
            }
          }
        }
      }
    })
  let all_rev = case rev_current {
    [] -> rev_lines
    _ -> [join_words(rev_current), ..rev_lines]
  }
  list.reverse(all_rev)
}

fn join_words(rev_words: List(String)) -> String {
  string.join(list.reverse(rev_words), " ")
}

// Split a single token into chunks of at most max_width cells.
// Always produces at least one chunk even if a single grapheme is wider than max_width.
//
// Both the chunk list and the current chunk accumulate newest-first and are
// reversed once, so a long token (a CJK paragraph is one token, it has no
// spaces) costs O(n) rather than O(n^2) in list appends and string copies.
fn hard_break_word(s: String, max_width: Int) -> List(String) {
  hard_break_acc(graphemes(s), max_width, 0, [], [])
}

fn hard_break_acc(
  gs: List(String),
  max_width: Int,
  curr_w: Int,
  rev_curr: List(String),
  rev_acc: List(String),
) -> List(String) {
  case gs {
    [] ->
      case rev_curr {
        [] -> list.reverse(rev_acc)
        _ -> list.reverse([join_rev(rev_curr), ..rev_acc])
      }
    [g, ..rest] -> {
      let gw = grapheme_cell_width(g)
      // Flush when adding g would exceed max_width (but always accept the first grapheme).
      case curr_w > 0 && curr_w + gw > max_width {
        True ->
          hard_break_acc(rest, max_width, gw, [g], [
            join_rev(rev_curr),
            ..rev_acc
          ])
        False ->
          hard_break_acc(rest, max_width, curr_w + gw, [g, ..rev_curr], rev_acc)
      }
    }
  }
}

fn join_rev(rev_pieces: List(String)) -> String {
  string.concat(list.reverse(rev_pieces))
}

/// Pad right with spaces to reach `width` cells. Cell-aware.
pub fn pad_right(s: String, width: Int) -> String {
  let cw = cell_width(s)
  case cw >= width {
    True -> s
    False -> s <> string.repeat(" ", width - cw)
  }
}

/// Pad left with spaces to reach `width` cells. Cell-aware.
pub fn pad_left(s: String, width: Int) -> String {
  let cw = cell_width(s)
  case cw >= width {
    True -> s
    False -> string.repeat(" ", width - cw) <> s
  }
}

/// Align left/center/right within `width` cells. Cell-aware.
pub fn align(s: String, width: Int, alignment: Alignment) -> String {
  case alignment {
    Left -> pad_right(s, width)
    Right -> pad_left(s, width)
    Center -> {
      let cw = cell_width(s)
      case cw >= width {
        True -> s
        False -> {
          let total = width - cw
          let left = total / 2
          let right = total - left
          string.repeat(" ", left) <> s <> string.repeat(" ", right)
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// ANSI stripping

/// Strip ANSI escape sequences. Handles CSI (`\e[…<final>`) and OSC
/// (`\e]…ST`/`\e]…BEL`) sequences.
pub fn strip_ansi(s: String) -> String {
  strip_loop(graphemes(s), "", Plain)
}

type StripState {
  Plain
  EscSeen
  CsiBody
  OscBody
  OscEscSeen
}

fn strip_loop(gs: List(String), acc: String, state: StripState) -> String {
  case gs {
    [] -> acc
    [g, ..rest] -> {
      let #(new_acc, new_state) = case state, g {
        Plain, "\u{001B}" -> #(acc, EscSeen)
        Plain, _ -> #(acc <> g, Plain)
        EscSeen, "[" -> #(acc, CsiBody)
        EscSeen, "]" -> #(acc, OscBody)
        // Other ESC <char> two-byte sequences (charset switch, etc.), drop both
        EscSeen, _ -> #(acc, Plain)
        // CSI body terminates on any byte in 0x40..0x7E (final byte)
        CsiBody, c -> {
          case is_csi_final(c) {
            True -> #(acc, Plain)
            False -> #(acc, CsiBody)
          }
        }
        // OSC body terminates on BEL (0x07) or ST (ESC \\)
        OscBody, "\u{0007}" -> #(acc, Plain)
        OscBody, "\u{001B}" -> #(acc, OscEscSeen)
        OscBody, _ -> #(acc, OscBody)
        OscEscSeen, "\\" -> #(acc, Plain)
        OscEscSeen, _ -> #(acc, OscBody)
      }
      strip_loop(rest, new_acc, new_state)
    }
  }
}

fn is_csi_final(g: String) -> Bool {
  case string.to_utf_codepoints(g) {
    [cp, ..] -> {
      let n = string.utf_codepoint_to_int(cp)
      n >= 0x40 && n <= 0x7E
    }
    [] -> False
  }
}
