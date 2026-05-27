// Browser (xterm.js) backend FFI for etui.
// Call setup(term) with an xterm.js Terminal instance BEFORE calling main().
// Key normalisation is identical to node_ffi.mjs so keys.match works the same.

import { Ok, Error } from "../../gleam.mjs";
import {
  KeyPress, Resize, Tick,
  MousePress, MouseRelease, MouseScroll,
  MouseLeft, MouseMiddle, MouseRight,
} from "../backend.mjs";

// ─── State ───────────────────────────────────────────────────────

let term = null;
let inputBuffer = [];
let inputResolvers = [];
let resizeQueue = [];
let escapeBuffer = null;
let escapeTimer = null;

// ─── Terminal injection ──────────────────────────────────────────
// Called by the host page before main().

export function setup(xtermTerminal) {
  term = xtermTerminal;
  term.onData(onData);
  term.onResize(({ cols, rows }) => {
    resizeQueue.push([cols, rows]);
    drainResolvers();
  });
}

// ─── Terminal control (no-ops in browser) ────────────────────────

export function enterRaw() {}   // xterm.js is always in "raw" mode

export function exitRaw() {
  if (escapeTimer !== null) {
    clearTimeout(escapeTimer);
    escapeTimer = null;
    escapeBuffer = null;
  }
}

export function writeStdout(s) {
  term?.write(s);
}

export function windowSize() {
  const cols = term?.cols ?? 80;
  const rows = term?.rows ?? 24;
  return new Ok([cols, rows]);
}

// ─── Input handling ──────────────────────────────────────────────
// xterm.js fires onData with the same raw byte sequences as a real terminal.

function onData(chunk) {
  if (escapeBuffer !== null) {
    clearTimeout(escapeTimer);
    escapeTimer = null;
    const combined = escapeBuffer + chunk;
    escapeBuffer = null;
    inputBuffer.push(combined);
  } else if (chunk === "\x1b") {
    escapeBuffer = chunk;
    escapeTimer = setTimeout(() => {
      escapeBuffer = null;
      escapeTimer = null;
      inputBuffer.push("\x1b");
      drainResolvers();
    }, 20);
    return;
  } else {
    inputBuffer.push(chunk);
  }
  drainResolvers();
}

function drainResolvers() {
  while (inputResolvers.length > 0 && (inputBuffer.length > 0 || resizeQueue.length > 0)) {
    inputResolvers.shift()(null);
  }
}

// ─── Poll ─────────────────────────────────────────────────────────

export async function pollInput(timeoutMs) {
  if (resizeQueue.length > 0) {
    const [cols, rows] = resizeQueue.shift();
    return new Ok(new Resize(cols, rows));
  }
  if (inputBuffer.length > 0) {
    return new Ok(parseChunk(inputBuffer.shift()));
  }
  const result = await Promise.race([
    new Promise((resolve) => inputResolvers.push(resolve)),
    new Promise((resolve) => setTimeout(() => resolve("timeout"), timeoutMs)),
  ]);
  if (result === "timeout") return new Ok(new Tick());
  if (resizeQueue.length > 0) {
    const [cols, rows] = resizeQueue.shift();
    return new Ok(new Resize(cols, rows));
  }
  if (inputBuffer.length > 0) {
    return new Ok(parseChunk(inputBuffer.shift()));
  }
  return new Ok(new Tick());
}

// ─── Cleanup ──────────────────────────────────────────────────────

export function registerCleanup(cleanupFn) {
  window.addEventListener("beforeunload", () => {
    try { cleanupFn(); } catch (_) {}
  });
}

// ─── Key normalisation (mirrors erlang.gleam normalise_key) ───────

function normaliseKey(raw) {
  switch (raw) {
    case "\x1b[A": case "\x1bOA": return "up";
    case "\x1b[B": case "\x1bOB": return "down";
    case "\x1b[C": case "\x1bOC": return "right";
    case "\x1b[D": case "\x1bOD": return "left";
    case "\r": case "\n": return "enter";
    case "\x7f": case "\b": return "backspace";
    case "\x1b[3~": return "delete";
    case "\t": return "tab";
    case "\x1b[Z": return "backtab";
    case "\x1b": return "esc";
    case "\x1b[2~": return "insert";
    case "\x1b[5~": return "pageup";
    case "\x1b[6~": return "pagedown";
    case "\x1b[H": case "\x1bOH": case "\x1b[1~": return "home";
    case "\x1b[F": case "\x1bOF": case "\x1b[4~": return "end";
    case "\x1b[11~": case "\x1bOP": return "f1";
    case "\x1b[12~": case "\x1bOQ": return "f2";
    case "\x1b[13~": case "\x1bOR": return "f3";
    case "\x1b[14~": case "\x1bOS": return "f4";
    case "\x1b[15~": return "f5";
    case "\x1b[17~": return "f6";
    case "\x1b[18~": return "f7";
    case "\x1b[19~": return "f8";
    case "\x1b[20~": return "f9";
    case "\x1b[21~": return "f10";
    case "\x1b[23~": return "f11";
    case "\x1b[24~": return "f12";
    case "\x01": return "ctrl+a";
    case "\x02": return "ctrl+b";
    case "\x03": return "ctrl+c";
    case "\x04": return "ctrl+d";
    case "\x05": return "ctrl+e";
    case "\x06": return "ctrl+f";
    case "\x07": return "ctrl+g";
    case "\x0b": return "ctrl+k";
    case "\x0c": return "ctrl+l";
    case "\x0e": return "ctrl+n";
    case "\x0f": return "ctrl+o";
    case "\x10": return "ctrl+p";
    case "\x11": return "ctrl+q";
    case "\x12": return "ctrl+r";
    case "\x13": return "ctrl+s";
    case "\x14": return "ctrl+t";
    case "\x15": return "ctrl+u";
    case "\x16": return "ctrl+v";
    case "\x17": return "ctrl+w";
    case "\x18": return "ctrl+x";
    case "\x19": return "ctrl+y";
    case "\x1a": return "ctrl+z";
    default:
      if (raw.length === 2 && raw[0] === "\x1b") return "alt+" + raw[1];
      return raw;
  }
}

function parseChunk(chunk) {
  if (chunk.startsWith("\x1b[<")) {
    const mouse = parseSgrMouse(chunk.slice(3));
    if (mouse !== null) return mouse;
  }
  return new KeyPress(normaliseKey(chunk));
}

function parseSgrMouse(payload) {
  const isPress = payload.endsWith("M");
  const trimmed = payload.slice(0, -1);
  const parts = trimmed.split(";");
  if (parts.length !== 3) return null;
  const cb = parseInt(parts[0], 10);
  const cx = parseInt(parts[1], 10);
  const cy = parseInt(parts[2], 10);
  if (isNaN(cb) || isNaN(cx) || isNaN(cy)) return null;
  const x = cx - 1;
  const y = cy - 1;
  if (cb === 64) return new MouseScroll(x, y, true);
  if (cb === 65) return new MouseScroll(x, y, false);
  const btn = [new MouseLeft(), new MouseMiddle(), new MouseRight()][cb % 4] ?? new MouseLeft();
  return isPress ? new MousePress(x, y, btn) : new MouseRelease(x, y, btn);
}
