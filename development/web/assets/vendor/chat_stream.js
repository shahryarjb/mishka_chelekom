// ChatStream — streamed text for the headless `chat_stream` component.
//
// Re-rendering a message on every token sends the WHOLE text over the wire each time: a 4 KB
// answer streamed in 400 chunks costs ~800 KB and a diff per chunk. This hook lets the server push
// only the new piece instead:
//
//   push_event(socket, "chelekom:chat-stream", %{id: "answer-1", delta: "Hel"})
//   push_event(socket, "chelekom:chat-stream", %{id: "answer-1", delta: "lo"})
//   push_event(socket, "chelekom:chat-stream", %{id: "answer-1", done: true})
//
// `text` replaces everything (e.g. after a reconnect, or to swap in the final text). The hook lives
// on [data-part="text"], which is `phx-update="ignore"` because the hook owns its content; the
// server can still replace it through `data-text` (a data-* attribute, the one thing LiveView
// merges onto an ignored element), which is also what a reconnect re-renders.
//
// `data-smooth` reveals the buffered text a few characters per frame — faster the more is waiting
// — so bursty model output reads as an even stream rather than jumping a sentence at a time.
//
// Ordered delivery. Deltas may carry `seq` (Jido AI's `ai.llm.delta` does: "order deltas by
// `seq` … delivery order alone is not a durable ordering contract"). The pieces are kept sorted by
// `seq`: the newest appends as usual, a late one is put back where it belongs (the text is laid
// out again), a repeat is dropped. Gaps are fine — Jido's `seq` counts every runtime event, not
// just text, so the numbers are never contiguous — nothing waits for a number that never comes.
//
// Re-render mode. Apps that re-assign the whole accumulated text on every chunk (Ash AI upserts
// the message and broadcasts it) reach the hook through `data-text`. When the new text extends
// what is shown, only the added part is appended — so `smooth` works in this mode too.
//
// Element contract:
//   [data-part="text"] — the hook; data-root-id (the id pushes target), data-text, data-smooth
//   root               — receives data-done (sticky) once a push says the stream finished
//
// Text is always written with textContent — never innerHTML — so model output can never inject
// markup. Render markdown on the server once the stream is done.

// Put a delta into `pieces` (an array of [seq, text], kept sorted). Returns "append" when it is
// the newest piece, "insert" when it landed before others (the text must be laid out again), or
// "duplicate". Pure — exercised by chat.test.mjs.
export function placeBySeq(pieces, seq, delta) {
  let i = pieces.length;
  while (i > 0 && pieces[i - 1][0] > seq) i -= 1;
  if (i > 0 && pieces[i - 1][0] === seq) return "duplicate";
  pieces.splice(i, 0, [seq, delta]);
  return i === pieces.length - 1 ? "append" : "insert";
}

export const joinPieces = (pieces) => pieces.map(([, text]) => text).join("");

// How many characters to reveal this frame for a backlog of `pending`: at least one, and enough
// to drain any backlog in roughly `frames` frames so the text never falls far behind the model.
export function revealCount(pending, frames = 12) {
  if (pending <= 0) return 0;
  return Math.max(1, Math.ceil(pending / frames));
}

const ChatStream = {
  mounted() {
    this.rootId = this.el.getAttribute("data-root-id");
    this.root = document.getElementById(this.rootId);
    this.shown = this.el.getAttribute("data-text") || "";
    this.target = this.shown;
    this.domText = this.shown;
    this.el.textContent = this.shown;
    this.pieces = [];

    this.ref = this.handleEvent("chelekom:chat-stream", (payload) => {
      if (!payload || payload.id !== this.rootId) return;
      // New text after a finished stream (a regenerated answer) streams again.
      if (!payload.done && this.doneByUs) this.unmarkDone();
      if (typeof payload.text === "string") {
        this.pieces = [];
        this.replace(payload.text);
      } else if (typeof payload.delta === "string" && payload.delta) {
        this.delta(payload.delta, payload.seq);
      }
      if (payload.done) this.finish();
    });
  },

  // A server re-render only reaches us through data-text; apply it only when it really changed,
  // so an unrelated patch never rewinds what the pushes built up.
  updated() {
    const next = this.el.getAttribute("data-text") || "";
    if (next !== this.domText) {
      this.domText = next;
      // An extension of what we have is an append (smooth-able); anything else is a replacement.
      if (next.length > this.target.length && next.startsWith(this.target)) {
        this.append(next.slice(this.target.length));
      } else {
        this.replace(next);
      }
    }
  },

  destroyed() {
    if (this.ref) this.removeHandleEvent(this.ref);
    cancelAnimationFrame(this.frame);
  },

  smooth() {
    const value = this.el.getAttribute("data-smooth");
    return value !== null && value !== "false";
  },

  replace(text) {
    this.target = text;
    this.shown = text;
    cancelAnimationFrame(this.frame);
    this.frame = null;
    this.el.textContent = text;
  },

  delta(text, seq) {
    if (!Number.isInteger(seq)) return this.append(text);
    // A text pushed with `text:` (or rendered) before sequenced deltas is their prefix.
    if (this.pieces.length === 0 && this.target) this.pieces.push([-Infinity, this.target]);
    const placed = placeBySeq(this.pieces, seq, text);
    if (placed === "append") this.append(text);
    // Late: the full text changed in the middle. Everything already on screen is laid out again.
    else if (placed === "insert") this.replace(joinPieces(this.pieces));
  },

  append(delta) {
    this.target += delta;
    if (!this.smooth()) {
      this.shown = this.target;
      this.el.append(delta);
      return;
    }
    if (!this.frame) this.frame = requestAnimationFrame(() => this.tick());
  },

  tick() {
    this.frame = null;
    const pending = this.target.length - this.shown.length;
    if (pending <= 0) return;
    const next = this.target.slice(0, this.shown.length + revealCount(pending));
    this.el.append(next.slice(this.shown.length));
    this.shown = next;
    if (this.shown.length < this.target.length) {
      this.frame = requestAnimationFrame(() => this.tick());
    } else if (this.finishing) {
      this.markDone();
    }
  },

  finish() {
    // With smoothing, "done" waits for the reveal to catch up, so the caret disappears only after
    // the last character is on screen.
    if (this.smooth() && this.shown.length < this.target.length) this.finishing = true;
    else this.markDone();
  },

  markDone() {
    this.finishing = false;
    if (!this.root) return;
    this.doneByUs = true;
    this.js().setAttribute(this.root, "data-done", "");
  },

  unmarkDone() {
    this.doneByUs = false;
    this.js().removeAttribute(this.root, "data-done");
  },
};

export default ChatStream;
