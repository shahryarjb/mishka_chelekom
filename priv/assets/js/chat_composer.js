// ChatComposer — the message box of the headless `chat_composer` component.
//
// The keyboard contract is assistant-ui's (MIT):
//
//   submit mode "enter"      Enter sends, Shift+Enter inserts a newline (the default)
//   submit mode "ctrl_enter" Ctrl/Cmd+Enter sends, Enter inserts a newline
//   submit mode "none"       only the send button sends
//
//   * never while an IME is composing (Japanese/Chinese/Korean input confirms a candidate with
//     Enter — sending there would post half a word)
//   * never while a run is in progress (`data-running`): the answer is not finished yet
//   * never an empty message — the send button is `disabled` while the box is blank
//   * Escape, while running, pushes `data-on-cancel` (the same event the stop button sends)
//
// The textarea grows with its content between `data-min-rows` and `data-max-rows`, then scrolls.
// After a send it is cleared: LiveView deliberately never overwrites the value of a focused input,
// so the server resetting it would not reach the box the user is typing in.
//
// Element contract:
//   root (form)             — the hook; data-submit-mode, data-running, data-on-cancel,
//                             data-clear-on-submit; receives data-empty (sticky) while blank
//   [data-part="input"]     — the textarea; data-min-rows, data-max-rows
//   [data-part="send"]      — submit button; receives `disabled` (sticky) while blank or running
//   [data-part="cancel"]    — stop button (a plain phx-click on the server's event)

export function shouldSubmit({ key, shiftKey, ctrlKey, metaKey, isComposing }, mode) {
  if (key !== "Enter" || isComposing) return false;
  if (mode === "ctrl_enter") return ctrlKey || metaKey;
  if (mode === "enter") return !shiftKey && !ctrlKey && !metaKey;
  return false;
}

const rows = (el, attr, fallback) => {
  const value = Number(el.getAttribute(attr));
  return Number.isFinite(value) && value > 0 ? value : fallback;
};

const ChatComposer = {
  mounted() {
    this.input = this.el.querySelector('[data-part="input"]');
    if (!this.input) return;

    this.onKeyDown = (e) => this.keydown(e);
    this.onInput = () => this.refresh();
    this.onSubmit = (e) => this.submitted(e);
    this.input.addEventListener("keydown", this.onKeyDown);
    this.input.addEventListener("input", this.onInput);
    this.el.addEventListener("submit", this.onSubmit);

    if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => this.fit());
    this.refresh();
  },

  updated() {
    this.input = this.el.querySelector('[data-part="input"]');
    this.refresh();
  },

  destroyed() {
    if (!this.input) return;
    this.input.removeEventListener("keydown", this.onKeyDown);
    this.input.removeEventListener("input", this.onInput);
    this.el.removeEventListener("submit", this.onSubmit);
  },

  running() {
    return this.el.hasAttribute("data-running");
  },

  blank() {
    return this.input.value.trim() === "";
  },

  keydown(e) {
    if (e.key === "Escape" && !e.isComposing && this.running()) {
      const cancel = this.el.getAttribute("data-on-cancel");
      if (cancel) {
        e.preventDefault();
        this.pushEventTo(this.el, cancel, {});
      }
      return;
    }

    const mode = this.el.getAttribute("data-submit-mode") || "enter";
    if (!shouldSubmit(e, mode)) return;

    // Enter was ours to handle: never let it insert a newline, even when we decline to send.
    e.preventDefault();
    if (this.running() || this.blank() || this.input.disabled) return;
    this.el.requestSubmit();
  },

  submitted(e) {
    if (this.blank() || this.running()) {
      e.preventDefault();
      e.stopImmediatePropagation();
      return;
    }
    if (this.el.getAttribute("data-clear-on-submit") === "false") return;
    // LiveView serialises the form while this same submit event dispatches, so clearing on the
    // next task cannot lose the message being sent.
    setTimeout(() => {
      this.input.value = "";
      this.refresh();
      this.input.focus({ preventScroll: true });
    }, 0);
  },

  refresh() {
    const js = this.js();
    const blank = this.blank();
    if (blank) js.setAttribute(this.el, "data-empty", "");
    else js.removeAttribute(this.el, "data-empty");

    // The server disables send too (blank value, running, disabled); this must agree with it, or
    // the sticky removal would re-enable the button mid-run.
    const off = blank || this.running() || this.el.hasAttribute("data-disabled");
    this.el.querySelectorAll('[data-part="send"]').forEach((send) => {
      if (off) js.setAttribute(send, "disabled", "");
      else js.removeAttribute(send, "disabled");
    });
    this.fit();
  },

  // Collapse first so scrollHeight reports the content, not the height we last set. scrollHeight
  // includes padding but never borders, so both box-sizing modes are converted explicitly.
  fit() {
    const el = this.input;
    const style = getComputedStyle(el);
    const px = (name) => parseFloat(style[name]) || 0;
    const line = px("lineHeight") || px("fontSize") * 1.4 || 20;
    const padding = px("paddingTop") + px("paddingBottom");
    const border = px("borderTopWidth") + px("borderBottomWidth");
    const borderBox = style.boxSizing === "border-box";
    const extra = borderBox ? padding + border : 0;

    const min = rows(el, "data-min-rows", 1) * line + extra;
    const max = rows(el, "data-max-rows", 8) * line + extra;

    el.style.height = "auto";
    const wanted = borderBox ? el.scrollHeight + border : el.scrollHeight - padding;
    const height = Math.min(Math.max(wanted, min), max);
    // Sticky, like every other attribute this hook writes: a patch would otherwise strip the
    // inline height the server never rendered and collapse the box mid-sentence.
    this.js().setAttribute(
      el,
      "style",
      `height: ${height}px; overflow-y: ${wanted > max + 1 ? "auto" : "hidden"};`,
    );
  },
};

export default ChatComposer;
