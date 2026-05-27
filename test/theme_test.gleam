/// Tests for the theme system: built-in palettes and style helpers.
import etui/style
import etui/theme
import gleeunit/should

// ─────────────────────────────────────────────────────────────────
// RGB already supported in style

pub fn rgb_fg_emits_truecolor_sequence_test() {
  style.ansi_fg(style.Rgb(255, 128, 0))
  |> should.equal("\u{001B}[38;2;255;128;0m")
}

pub fn rgb_bg_emits_truecolor_sequence_test() {
  style.ansi_bg(style.Rgb(0, 0, 128))
  |> should.equal("\u{001B}[48;2;0;0;128m")
}

pub fn rgb_zero_is_black_test() {
  style.ansi_fg(style.Rgb(0, 0, 0))
  |> should.equal("\u{001B}[38;2;0;0;0m")
}

pub fn rgb_max_is_white_test() {
  style.ansi_fg(style.Rgb(255, 255, 255))
  |> should.equal("\u{001B}[38;2;255;255;255m")
}

// ─────────────────────────────────────────────────────────────────
// Theme type construction

pub fn dark_theme_has_indexed_colors_test() {
  let t = theme.dark()
  // selection_bg uses Indexed(4) — blue
  t.selection_bg |> should.equal(style.Indexed(4))
}

pub fn light_theme_has_indexed_colors_test() {
  let t = theme.light()
  t.accent |> should.equal(style.Indexed(4))
}

// ─────────────────────────────────────────────────────────────────
// Built-in RGB themes — spot check key slots

pub fn dracula_bg_is_correct_test() {
  theme.dracula().bg |> should.equal(style.Rgb(40, 42, 54))
}

pub fn dracula_accent_is_purple_test() {
  theme.dracula().accent |> should.equal(style.Rgb(189, 147, 249))
}

pub fn nord_bg_test() {
  theme.nord().bg |> should.equal(style.Rgb(46, 52, 64))
}

pub fn nord_error_test() {
  theme.nord().error |> should.equal(style.Rgb(191, 97, 106))
}

pub fn catppuccin_mocha_bg_test() {
  theme.catppuccin_mocha().bg |> should.equal(style.Rgb(30, 30, 46))
}

pub fn catppuccin_latte_bg_is_light_test() {
  // Latte bg is bright — high RGB values
  let c = theme.catppuccin_latte().bg
  let is_light = case c {
    style.Rgb(r, g, b) -> r > 200 && g > 200 && b > 200
    _ -> False
  }
  is_light |> should.equal(True)
}

pub fn monokai_success_is_green_test() {
  theme.monokai().success |> should.equal(style.Rgb(166, 226, 46))
}

pub fn gruvbox_dark_bg_test() {
  theme.gruvbox_dark().bg |> should.equal(style.Rgb(29, 32, 33))
}

pub fn tokyo_night_accent_test() {
  theme.tokyo_night().accent |> should.equal(style.Rgb(187, 154, 247))
}

pub fn solarized_dark_bg_test() {
  theme.solarized_dark().bg |> should.equal(style.Rgb(0, 43, 54))
}

// ─────────────────────────────────────────────────────────────────
// Style helpers

pub fn normal_style_uses_fg_and_bg_test() {
  let t = theme.dracula()
  let s = theme.normal(t)
  s.fg |> should.equal(t.fg)
  s.bg |> should.equal(t.bg)
  style.is_none(s.modifier) |> should.equal(True)
}

pub fn selection_style_uses_selection_slots_test() {
  let t = theme.nord()
  let s = theme.selection(t)
  s.fg |> should.equal(t.selection_fg)
  s.bg |> should.equal(t.selection_bg)
}

pub fn error_style_is_bold_test() {
  let t = theme.dracula()
  let s = theme.error_style(t)
  s.fg |> should.equal(t.error)
  style.has(s.modifier, style.bold()) |> should.equal(True)
}

pub fn statusbar_style_uses_statusbar_slots_test() {
  let t = theme.tokyo_night()
  let s = theme.statusbar_style(t)
  s.fg |> should.equal(t.statusbar_fg)
  s.bg |> should.equal(t.statusbar_bg)
}

pub fn muted_style_uses_muted_fg_test() {
  let t = theme.gruvbox_dark()
  let s = theme.muted_style(t)
  s.fg |> should.equal(t.muted)
  s.bg |> should.equal(t.bg)
}

// ─────────────────────────────────────────────────────────────────
// Customisation helpers

pub fn with_accent_overrides_accent_only_test() {
  let base = theme.nord()
  let custom = theme.with_accent(base, style.Rgb(255, 165, 0))
  custom.accent |> should.equal(style.Rgb(255, 165, 0))
  // Other slots unchanged
  custom.bg |> should.equal(base.bg)
  custom.fg |> should.equal(base.fg)
}

pub fn with_selection_overrides_both_slots_test() {
  let base = theme.dracula()
  let custom =
    theme.with_selection(base, style.Rgb(100, 0, 100), style.Rgb(255, 255, 255))
  custom.selection_bg |> should.equal(style.Rgb(100, 0, 100))
  custom.selection_fg |> should.equal(style.Rgb(255, 255, 255))
  custom.bg |> should.equal(base.bg)
}

pub fn with_statusbar_overrides_statusbar_slots_test() {
  let base = theme.monokai()
  let custom =
    theme.with_statusbar(base, style.Rgb(0, 0, 0), style.Rgb(200, 200, 200))
  custom.statusbar_bg |> should.equal(style.Rgb(0, 0, 0))
  custom.statusbar_fg |> should.equal(style.Rgb(200, 200, 200))
}

pub fn with_base_overrides_bg_and_fg_test() {
  let base = theme.solarized_dark()
  let custom =
    theme.with_base(base, style.Rgb(0, 0, 0), style.Rgb(255, 255, 255))
  custom.bg |> should.equal(style.Rgb(0, 0, 0))
  custom.fg |> should.equal(style.Rgb(255, 255, 255))
  custom.accent |> should.equal(base.accent)
}

pub fn record_update_syntax_works_test() {
  let t = theme.Theme(..theme.nord(), accent: style.Rgb(255, 165, 0))
  t.accent |> should.equal(style.Rgb(255, 165, 0))
  t.bg |> should.equal(theme.nord().bg)
}
