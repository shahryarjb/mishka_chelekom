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
// Element contract:
//   [data-part="text"] — the hook; data-root-id (the id pushes target), data-text, data-smooth
//   root               — receives data-done (sticky) once a push says the stream finished
//
// Text is always written with textContent — never innerHTML — so model output can never inject
// markup. Render markdown on the server once the stream is done.

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

    this.ref = this.handleEvent("chelekom:chat-stream", (payload) => {
      if (!payload || payload.id !== this.rootId) return;
      // New text after a finished stream (a regenerated answer) streams again.
      if (!payload.done && this.doneByUs) this.unmarkDone();
      if (typeof payload.text === "string") this.replace(payload.text);
      if (typeof payload.delta === "string" && payload.delta) this.append(payload.delta);
      if (payload.done) this.finish();
    });
  },

  // A server re-render only reaches us through data-text; apply it only when it really changed,
  // so an unrelated patch never rewinds what the pushes built up.
  updated() {
    const next = this.el.getAttribute("data-text") || "";
    if (next !== this.domText) {
      this.domText = next;
      this.replace(next);
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
