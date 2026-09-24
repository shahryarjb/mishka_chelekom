// ChatActionBar — the copy action of the headless `chat_action_bar` component.
//
// Every other action (regenerate, edit, feedback) is a plain phx-click the server answers; copying
// is the one the server cannot do, because the clipboard lives in the browser. The text comes
// from `data-copy-text`, or — so a long answer is not duplicated into an attribute — from the
// element named by `data-copy-from` (its rendered text, so markdown the server turned into HTML
// copies as the words the reader sees).
//
// After a copy the button gets `data-copied` for `data-copied-duration` ms (the "Copied ✓" state a
// skin shows) and the visually hidden status part announces it to screen readers. Both are sticky
// JS-command attributes, so a patch arriving mid-feedback does not cut it short.
//
// Element contract:
//   root                      — the hook; data-copy-text | data-copy-from, data-copied-duration
//   [data-part="copy"]        — the copy button; receives data-copied (sticky) for the duration
//   [data-part="copy-status"] — polite live region; receives the copied label as text
//   data-copied-label         — on root; what the status announces (default "Copied")

export async function writeClipboard(text) {
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text);
    return;
  }
  // Plain-http development servers have no async clipboard; the legacy path still works there.
  const area = document.createElement("textarea");
  area.value = text;
  area.setAttribute("readonly", "");
  area.style.position = "fixed";
  area.style.opacity = "0";
  document.body.appendChild(area);
  area.select();
  try {
    document.execCommand("copy");
  } finally {
    area.remove();
  }
}

const ChatActionBar = {
  mounted() {
    this.onClick = (e) => {
      const button = e.target.closest('[data-part="copy"]');
      if (button && this.el.contains(button)) this.copy(button);
    };
    this.el.addEventListener("click", this.onClick);
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    clearTimeout(this.timer);
  },

  text() {
    const from = this.el.getAttribute("data-copy-from");
    if (from) {
      const source = document.getElementById(from);
      return source ? source.innerText.trim() : "";
    }
    return this.el.getAttribute("data-copy-text") || "";
  },

  async copy(button) {
    const text = this.text();
    if (!text) return;
    try {
      await writeClipboard(text);
    } catch (_e) {
      return;
    }

    const js = this.js();
    const status = this.el.querySelector('[data-part="copy-status"]');
    js.setAttribute(button, "data-copied", "");
    js.setAttribute(this.el, "data-copied", "");
    if (status) status.textContent = this.el.getAttribute("data-copied-label") || "Copied";

    const duration = Number(this.el.getAttribute("data-copied-duration")) || 2000;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      js.removeAttribute(button, "data-copied");
      js.removeAttribute(this.el, "data-copied");
      if (status) status.textContent = "";
    }, duration);
  },
};

export default ChatActionBar;
