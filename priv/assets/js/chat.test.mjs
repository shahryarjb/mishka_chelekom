// Tests for the pure decisions behind the chat engines (ChatThread, ChatComposer, ChatStream).
// Run with: node --test  (from priv/assets/js/)
//
// These are the rules a chat gets wrong in ways a user notices at once: yanking the reader back to
// the bottom while they read, sending half an IME word, or a stream that lags seconds behind.

import { test } from "node:test";
import assert from "node:assert/strict";
import { isAtBottom, isUserScrollUp, overflows } from "./chat_thread.js";
import { shouldSubmit } from "./chat_composer.js";
import { joinPieces, placeBySeq, revealCount } from "./chat_stream.js";

test("at the bottom within the sub-pixel slack, and whenever nothing overflows", () => {
  assert.equal(isAtBottom({ scrollTop: 600, scrollHeight: 1000, clientHeight: 400 }), true);
  assert.equal(isAtBottom({ scrollTop: 598.5, scrollHeight: 1000, clientHeight: 400 }), true);
  assert.equal(isAtBottom({ scrollTop: 500, scrollHeight: 1000, clientHeight: 400 }), false);
  assert.equal(isAtBottom({ scrollTop: 0, scrollHeight: 300, clientHeight: 400 }), true);
});

test("only an upward move at an unchanged height is the reader scrolling up", () => {
  const before = { scrollTop: 600, scrollHeight: 1000 };
  assert.equal(isUserScrollUp(before, { scrollTop: 450, scrollHeight: 1000 }), true);
  // Content shrank (a block collapsed): the offset moved, the reader did not.
  assert.equal(isUserScrollUp(before, { scrollTop: 450, scrollHeight: 850 }), false);
  assert.equal(isUserScrollUp(before, { scrollTop: 700, scrollHeight: 1000 }), false);
});

test("overflow needs more than a pixel of extra content", () => {
  assert.equal(overflows({ scrollHeight: 401, clientHeight: 400 }), false);
  assert.equal(overflows({ scrollHeight: 420, clientHeight: 400 }), true);
});

const key = (overrides) => ({
  key: "Enter",
  shiftKey: false,
  ctrlKey: false,
  metaKey: false,
  isComposing: false,
  ...overrides,
});

test('"enter" mode: Enter sends, Shift+Enter is a newline', () => {
  assert.equal(shouldSubmit(key({}), "enter"), true);
  assert.equal(shouldSubmit(key({ shiftKey: true }), "enter"), false);
  assert.equal(shouldSubmit(key({ key: "a" }), "enter"), false);
});

test('"ctrl_enter" mode: only Ctrl/Cmd+Enter sends', () => {
  assert.equal(shouldSubmit(key({}), "ctrl_enter"), false);
  assert.equal(shouldSubmit(key({ ctrlKey: true }), "ctrl_enter"), true);
  assert.equal(shouldSubmit(key({ metaKey: true }), "ctrl_enter"), true);
});

test('"none" mode never sends from the keyboard', () => {
  assert.equal(shouldSubmit(key({}), "none"), false);
  assert.equal(shouldSubmit(key({ ctrlKey: true }), "none"), false);
});

test("an IME confirming a candidate with Enter never sends", () => {
  assert.equal(shouldSubmit(key({ isComposing: true }), "enter"), false);
  assert.equal(shouldSubmit(key({ isComposing: true, ctrlKey: true }), "ctrl_enter"), false);
});

test("the stream reveals at least a character and drains any backlog in ~12 frames", () => {
  assert.equal(revealCount(0), 0);
  assert.equal(revealCount(1), 1);
  assert.equal(revealCount(5), 1);
  assert.equal(revealCount(120), 10);
  assert.ok(revealCount(10_000) * 12 >= 10_000);
});

test("sequenced deltas in order append", () => {
  const pieces = [];
  assert.equal(placeBySeq(pieces, 1, "Hel"), "append");
  assert.equal(placeBySeq(pieces, 2, "lo"), "append");
  assert.equal(joinPieces(pieces), "Hello");
});

test("a late delta is placed where it belongs, never dropped", () => {
  const pieces = [];
  placeBySeq(pieces, 2, "should ");
  assert.equal(placeBySeq(pieces, 1, "Pistachio "), "insert");
  assert.equal(placeBySeq(pieces, 3, "lead."), "append");
  assert.equal(joinPieces(pieces), "Pistachio should lead.");
});

test("gaps never stall: Jido's seq counts every runtime event, not only text", () => {
  const pieces = [];
  placeBySeq(pieces, 4, "a");
  placeBySeq(pieces, 9, "b");
  assert.equal(placeBySeq(pieces, 15, "c"), "append");
  assert.equal(joinPieces(pieces), "abc");
});

test("a repeated delta is dropped", () => {
  const pieces = [];
  placeBySeq(pieces, 1, "a");
  assert.equal(placeBySeq(pieces, 1, "a"), "duplicate");
  assert.equal(joinPieces(pieces), "a");
});
