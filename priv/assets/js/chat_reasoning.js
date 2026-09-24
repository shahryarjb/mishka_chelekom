// ChatReasoning — the open/closed behaviour of the headless `chat_reasoning` component.
//
// A model's reasoning is interesting while it happens and noise afterwards, so the disclosure
// (a native <details>) follows the run:
//
//   status "streaming" -> opens, so the reader watches the thinking arrive
//   status "done"      -> closes, leaving the one-line "Thought for 4 seconds" summary
//
// …unless the reader has toggled it themselves. Once they open or close it, their choice wins
// for the rest of this block's life: auto-collapsing a trace someone is reading is the bug this
// hook exists to avoid.
//
// `open` is written with `this.js()` so it is sticky: the server never renders it after the first
// paint, and LiveView re-applies the sticky value after each patch instead of stripping it.
//
// Element contract:
//   root (<details>) — the hook; data-status ("streaming" | "done")

const ChatReasoning = {
  mounted() {
    this.status = this.el.getAttribute("data-status");
    this.userChoice = null;

    // Only a toggle that follows the reader's own click (Enter/Space on a summary also click) is
    // theirs. `toggle` alone cannot tell: a patch that strips `open` and the sticky re-apply that
    // restores it fires one too, and must not freeze the block in place.
    this.onClick = (e) => {
      const summary = e.target.closest("summary");
      if (summary && summary.parentElement === this.el) this.userToggling = true;
    };
    this.onToggle = () => {
      if (!this.userToggling) return;
      this.userToggling = false;
      this.userChoice = this.el.open;
      this.apply(this.el.open);
    };
    this.el.addEventListener("click", this.onClick);
    this.el.addEventListener("toggle", this.onToggle);

    // First paint: open while thinking; a finished block keeps whatever the server rendered.
    this.apply(this.status === "streaming" || this.el.open);
  },

  updated() {
    const status = this.el.getAttribute("data-status");
    if (status !== this.status) {
      this.status = status;
      if (this.userChoice === null) this.apply(status === "streaming");
    }
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    this.el.removeEventListener("toggle", this.onToggle);
  },

  apply(open) {
    const js = this.js();
    if (open) js.setAttribute(this.el, "open", "");
    else js.removeAttribute(this.el, "open");
  },
};

export default ChatReasoning;
