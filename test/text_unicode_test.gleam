// M2: Unicode-correct cell_width tests.
// Covers real terminal rendering cases: ZWJ, flags, CJK strings,
// combining marks (NFD), fullwidth, mixed content.
// Exit criterion: cell_width matches what a modern terminal displays.

import etui/text
import gleam/list
import gleam/string
import gleeunit/should

// ─── cell_width: CJK strings ───────────────────────────────────────

pub fn cjk_string_two_chars_test() {
  // 你好 = 2 ideographs × 2 cells = 4
  text.cell_width("你好") |> should.equal(4)
}

pub fn cjk_string_single_char_test() {
  text.cell_width("中") |> should.equal(2)
}

pub fn mixed_ascii_cjk_test() {
  // "ab你" = 1+1+2 = 4
  text.cell_width("ab你") |> should.equal(4)
}

pub fn mixed_cjk_ascii_suffix_test() {
  // "你ab" = 2+1+1 = 4
  text.cell_width("你ab") |> should.equal(4)
}

// ─── cell_width: Hangul ────────────────────────────────────────────

pub fn hangul_syllable_test() {
  // 한 = U+D55C (in Hangul Syllables AC00–D7A3) = 2 cells
  text.cell_width("한") |> should.equal(2)
}

pub fn hangul_string_test() {
  // 안녕 = 2 syllables × 2 cells = 4
  text.cell_width("안녕") |> should.equal(4)
}

// ─── cell_width: emoji ─────────────────────────────────────────────

pub fn emoji_smiley_test() {
  // 😀 U+1F600 = 2 cells
  text.cell_width("😀") |> should.equal(2)
}

pub fn emoji_rocket_test() {
  // 🚀 U+1F680 = 2 cells
  text.cell_width("🚀") |> should.equal(2)
}

pub fn emoji_two_chars_test() {
  // "😀😀" = 2+2 = 4
  text.cell_width("😀😀") |> should.equal(4)
}

pub fn emoji_mixed_ascii_test() {
  // "a😀b" = 1+2+1 = 4
  text.cell_width("a😀b") |> should.equal(4)
}

// ─── cell_width: ZWJ sequences ────────────────────────────────────
// ZWJ emoji are ONE grapheme cluster: width = first codepoint (always emoji = 2)

pub fn zwj_family_test() {
  // 👨‍👩‍👧‍👦 = man ZWJ woman ZWJ girl ZWJ boy → 1 grapheme → 2 cells
  text.cell_width("👨‍👩‍👧‍👦") |> should.equal(2)
}

pub fn zwj_couple_test() {
  // 👩‍❤️‍👨 = 1 grapheme → 2 cells
  text.cell_width("👩‍❤️‍👨") |> should.equal(2)
}

pub fn zwj_profession_test() {
  // 👩‍💻 woman technologist = 1 grapheme → 2 cells
  text.cell_width("👩‍💻") |> should.equal(2)
}

// ─── cell_width: flag emoji (regional indicator pairs) ────────────
// Two regional indicators form one grapheme (if Erlang UAX#29 clusters them).
// First codepoint is in range 1F1E6–1F1FF → 2 cells.

pub fn flag_italy_test() {
  // 🇮🇹 = RI(I) + RI(T) → cell_width = 2
  text.cell_width("🇮🇹") |> should.equal(2)
}

pub fn flag_us_test() {
  // 🇺🇸 = 2
  text.cell_width("🇺🇸") |> should.equal(2)
}

// ─── cell_width: combining marks (NFD) ────────────────────────────
// NFD: base char + combining mark → 1 grapheme → width of base char

pub fn combining_acute_e_test() {
  // NFD: U+0065 (e) + U+0301 (combining acute) → grapheme "é" → 1 cell
  let nfd_e_acute = "e\u{0301}"
  text.cell_width(nfd_e_acute) |> should.equal(1)
}

pub fn combining_nfc_e_test() {
  // NFC: U+00E9 precomposed é → 1 cell
  text.cell_width("é") |> should.equal(1)
}

pub fn combining_string_test() {
  // NFD "résumé" → same cell width as NFC (6 cells)
  let nfd = "re\u{0301}sume\u{0301}"
  text.cell_width(nfd) |> should.equal(6)
}

// ─── cell_width: fullwidth forms ──────────────────────────────────

pub fn fullwidth_latin_a_test() {
  // Ａ U+FF21 (Fullwidth Forms FF00–FF60) = 2 cells
  text.cell_width("Ａ") |> should.equal(2)
}

pub fn fullwidth_string_test() {
  // "ＡＢ" = 2+2 = 4
  text.cell_width("ＡＢ") |> should.equal(4)
}

// ─── cell_width: symbols that must be 1-cell ──────────────────────
// Misc Symbols (2600-26FF) and Dingbats (2700-27BF) are Ambiguous/Neutral
// in East Asian Width. Monospace terminals render them as 1 cell.
// This was the bug that caused visual artifacts — verify it stays fixed.

pub fn star_symbol_one_cell_test() {
  // ★ U+2605 (Black Star, Misc Symbols) = 1 cell
  text.cell_width("★") |> should.equal(1)
}

pub fn diamond_symbol_one_cell_test() {
  // ✦ U+2726 (Black Four Pointed Star, Dingbats) = 1 cell
  text.cell_width("✦") |> should.equal(1)
}

pub fn checkmark_one_cell_test() {
  // ✓ U+2713 (Check Mark, Dingbats) = 1 cell
  text.cell_width("✓") |> should.equal(1)
}

pub fn misc_symbols_string_test() {
  // "★✦✓" = 1+1+1 = 3
  text.cell_width("★✦✓") |> should.equal(3)
}

// ─── cell_width: control / zero-width ─────────────────────────────

pub fn zero_width_joiner_test() {
  // ZWJ U+200D alone = 0 cells
  text.cell_width("\u{200D}") |> should.equal(0)
}

pub fn zero_width_space_test() {
  // ZWSP U+200B = 0 cells
  text.cell_width("\u{200B}") |> should.equal(0)
}

// ─── truncate: cell-aware ──────────────────────────────────────────

pub fn truncate_cjk_test() {
  // "你好世界" = 8 cells, truncate to 5 with "…" (1 cell)
  // available=4, "你" takes 2, "好" takes 2 → "你好" (4 cells) + "…" = 5
  text.truncate("你好世界", 5, "…") |> should.equal("你好…")
}

pub fn truncate_cjk_no_partial_wide_test() {
  // "你好" = 4 cells, truncate to 3 with "…" (1 cell)
  // available=2, "你" takes 2 → "你" + "…" = 3
  text.truncate("你好", 3, "…") |> should.equal("你…")
}

pub fn truncate_fits_no_ellipsis_test() {
  // String fits → no ellipsis added
  text.truncate("hi", 10, "…") |> should.equal("hi")
}

pub fn truncate_exact_fit_test() {
  text.truncate("hello", 5, "…") |> should.equal("hello")
}

pub fn truncate_emoji_test() {
  // "😀😀😀" = 6 cells, truncate to 5 with "…"
  // available=4, "😀" takes 2, "😀" takes 2 → "😀😀" (4) + "…" = 5
  text.truncate("😀😀😀", 5, "…") |> should.equal("😀😀…")
}

// ─── pad_right / pad_left: cell-aware ─────────────────────────────

pub fn pad_right_cjk_test() {
  // "你好" = 4 cells, pad to 6 → 2 spaces
  text.pad_right("你好", 6) |> should.equal("你好  ")
}

pub fn pad_left_cjk_test() {
  text.pad_left("你好", 6) |> should.equal("  你好")
}

pub fn pad_right_emoji_test() {
  // "😀" = 2 cells, pad to 5 → 3 spaces
  text.pad_right("😀", 5) |> should.equal("😀   ")
}

pub fn pad_right_already_full_test() {
  text.pad_right("你好", 4) |> should.equal("你好")
}

pub fn pad_right_overflow_test() {
  text.pad_right("你好", 3) |> should.equal("你好")
}

// ─── align: cell-aware ────────────────────────────────────────────

pub fn align_left_cjk_test() {
  text.align("你好", 6, text.Left) |> should.equal("你好  ")
}

pub fn align_right_cjk_test() {
  text.align("你好", 6, text.Right) |> should.equal("  你好")
}

pub fn align_center_cjk_test() {
  // "你好" = 4 cells, width=8 → 2 left + 2 right
  text.align("你好", 8, text.Center) |> should.equal("  你好  ")
}

pub fn align_center_odd_remainder_test() {
  // "你好" = 4, width=7 → 1 left + 2 right (total 3, left=1, right=2)
  text.align("你好", 7, text.Center) |> should.equal(" 你好  ")
}

// ─── wrap: cell-aware ─────────────────────────────────────────────

pub fn wrap_cjk_words_test() {
  // "你好 世界" = "你好"(4) + " " + "世界"(4); max_width=5
  // "你好" fits, adding " 世界" = 9 > 5 → new line
  text.wrap("你好 世界", 5) |> should.equal(["你好", "世界"])
}

pub fn wrap_mixed_cjk_ascii_test() {
  // "ab 你好" max_width=4: "ab"(2) fits; "ab 你好" = 2+1+4=7>4 → "你好" on new line
  text.wrap("ab 你好", 4) |> should.equal(["ab", "你好"])
}

// ─── strip_ansi: extended ─────────────────────────────────────────

pub fn strip_ansi_osc_bel_test() {
  // OSC title sequence terminated by BEL
  let osc = "\u{001B}]0;My Terminal Title\u{0007}"
  text.strip_ansi(osc) |> should.equal("")
}

pub fn strip_ansi_osc_st_test() {
  // OSC terminated by ST (ESC \)
  let osc = "\u{001B}]0;title\u{001B}\\"
  text.strip_ansi(osc) |> should.equal("")
}

pub fn strip_ansi_csi_rgb_test() {
  // Truecolor: \e[38;2;255;0;128m
  let seq = "\u{001B}[38;2;255;0;128mred\u{001B}[0m"
  text.strip_ansi(seq) |> should.equal("red")
}

pub fn strip_ansi_mixed_unicode_test() {
  // ANSI around CJK text
  let styled = "\u{001B}[1m你好\u{001B}[0m"
  text.strip_ansi(styled) |> should.equal("你好")
}

pub fn strip_ansi_cell_width_after_strip_test() {
  // cell_width of stripped string should be correct
  let styled = "\u{001B}[32m😀\u{001B}[0m"
  text.strip_ansi(styled) |> text.cell_width |> should.equal(2)
}

// ─── grapheme counting vs cell counting ───────────────────────────
// These document the distinction: graphemes ≠ cells.

pub fn graphemes_vs_cells_cjk_test() {
  // "你好" = 2 graphemes but 4 cells
  let gs = string.to_graphemes("你好")
  list.length(gs) |> should.equal(2)
  text.cell_width("你好") |> should.equal(4)
}

pub fn graphemes_vs_cells_zwj_test() {
  // ZWJ family = 1 grapheme = 2 cells
  let fam = "👨‍👩‍👧‍👦"
  let gs = string.to_graphemes(fam)
  list.length(gs) |> should.equal(1)
  text.cell_width(fam) |> should.equal(2)
}
