// ChatThread — the scrolling conversation of the headless `chat_thread` component.
//
// A chat viewport has one job the browser does not do for you: stay pinned to the newest message
// while it streams in, and stop the moment the reader scrolls up to look at something older. The
// rules are the ones assistant-ui (MIT) settled on:
//
//   * content grows while we are following the bottom -> jump to the new bottom (instantly, so a
//     streaming answer does not lag behind a smooth-scroll animation)
//   * the reader scrolls UP while the content height is unchanged -> stop following. A scrollTop
//     that drops because content shrank or re-laid-out is not the reader, so it never counts
//   * the reader returns to the bottom (or presses the scroll button) -> follow again
//   * a run starts (`data-running` flips on) -> follow and scroll, the new turn is what matters
//
// Two more things LiveView apps need:
//
//   * content changing ABOVE the reader must not move what they are looking at — older history
//     loaded on top, or (Ash AI's layout) new messages stream_insert-ed `at: 0` into a
//     `flex-col-reverse` list. While not following, the hook anchors the first message in view:
//     it remembers that element's offset and, after any change, scrolls by however far it moved.
//     This does not depend on insertion order or direction, and composes with the browser's own
//     `overflow-anchor` (if the browser already corrected, the element did not move)
//   * `data-on-top` names an event pushed (once per content change) when the reader reaches the
//     top, so the server can stream in the previous page
//
// State is written with `this.js()`, the JS-command engine, so it is sticky: LiveView re-applies
// it after every patch instead of stripping what the server did not render.
//
// Element contract:
//   root                      — the hook; data-auto-scroll, data-running, data-on-top
//                               receives data-at-bottom (sticky) while the viewport is at the end
//   [data-part="viewport"]    — the scroll container
//   [data-part="messages"]    — the content whose size is observed (may be phx-update="stream")
//   [data-part="scroll-button"] — gets `hidden` (sticky) while at the bottom; click scrolls down
//
// Server -> client: push_event("chelekom:chat-thread", %{id: <root id>, scroll: "bottom" | "top",
// behavior: "smooth" | "instant"}).

// Within this many pixels of the end counts as "at the bottom": sub-pixel layouts and zoom levels
// never land exactly on 0.
const BOTTOM_SLACK = 2;
const TOP_SLACK = 24;

export function isAtBottom({ scrollTop, scrollHeight, clientHeight }, slack = BOTTOM_SLACK) {
  return scrollHeight - scrollTop - clientHeight <= slack || scrollHeight <= clientHeight;
}

// A scroll that moved up while the content kept its height is the reader. A height change means the
// offset moved because the content did.
export function isUserScrollUp(previous, current) {
  return previous.scrollTop > current.scrollTop && previous.scrollHeight === current.scrollHeight;
}

export function overflows({ scrollHeight, clientHeight }) {
  return scrollHeight > clientHeight + 1;
}

const ChatThread = {
  mounted() {
    this.viewport = this.el.querySelector('[data-part="viewport"]') || this.el;
    this.messages = this.el.querySelector('[data-part="messages"]') || this.viewport;
    this.follow = this.autoScroll();
    this.running = this.el.hasAttribute("data-running");
    this.topRequested = false;
    this.remember();
    this.firstMessage = this.messages.firstElementChild;
    this.anchor = this.captureAnchor();

    this.onScroll = () => this.handleScroll();
    this.viewport.addEventListener("scroll", this.onScroll, { passive: true });

    // While an answer streams the content height changes nearly every frame, so "scrolled up with
    // an unchanged height" can miss a real reader. An upward gesture is intent on its own.
    this.onIntentUp = (e) => {
      const up =
        (e.type === "wheel" && e.deltaY < 0) ||
        (e.type === "keydown" && ["ArrowUp", "PageUp", "Home"].includes(e.key)) ||
        e.type === "touchmove";
      if (up && overflows(this.metrics())) {
        this.follow = false;
        this.pending = null;
      }
    };
    for (const type of ["wheel", "keydown", "touchmove"]) {
      this.viewport.addEventListener(type, this.onIntentUp, { passive: true });
    }

    this.onButton = (e) => {
      const button = e.target.closest('[data-part="scroll-button"]');
      if (button && this.el.contains(button)) this.scrollToBottom("smooth");
    };
    this.el.addEventListener("click", this.onButton);

    // Height changes (streamed tokens, images loading, a reasoning block expanding) arrive through
    // ResizeObserver; added or removed messages through the MutationObserver, because a message
    // swapped for one of the same height would not resize anything.
    this.ro = new ResizeObserver(() => this.contentChanged());
    this.ro.observe(this.messages);
    this.ro.observe(this.viewport);
    this.mo = new MutationObserver(() => this.contentChanged());
    this.mo.observe(this.messages, { childList: true, subtree: true, characterData: true });

    this.ref = this.handleEvent("chelekom:chat-thread", (payload) => {
      if (!payload || (payload.id && payload.id !== this.el.id)) return;
      const behavior = payload.behavior === "smooth" ? "smooth" : "instant";
      if (payload.scroll === "top") {
        this.follow = false;
        this.viewport.scrollTo({ top: 0, behavior });
      } else if (payload.scroll === "bottom") {
        this.scrollToBottom(behavior);
      }
    });

    this.scrollToBottom("instant");
    this.sync();
  },

  updated() {
    const running = this.el.hasAttribute("data-running");
    // A new run is the reader's own question being answered: follow it even if they had scrolled.
    if (running && !this.running) this.scrollToBottom("smooth");
    this.running = running;
    this.contentChanged();
  },

  destroyed() {
    if (this.viewport) {
      this.viewport.removeEventListener("scroll", this.onScroll);
      for (const type of ["wheel", "keydown", "touchmove"]) {
        this.viewport.removeEventListener(type, this.onIntentUp);
      }
    }
    this.el.removeEventListener("click", this.onButton);
    if (this.ro) this.ro.disconnect();
    if (this.mo) this.mo.disconnect();
    if (this.ref) this.removeHandleEvent(this.ref);
    cancelAnimationFrame(this.frame);
  },

  autoScroll() {
    return this.el.getAttribute("data-auto-scroll") !== "false";
  },

  metrics() {
    const { scrollTop, scrollHeight, clientHeight } = this.viewport;
    return { scrollTop, scrollHeight, clientHeight };
  },

  remember() {
    this.last = this.metrics();
  },

  scrollToBottom(behavior) {
    this.follow = true;
    this.pending = behavior;
    this.viewport.scrollTo({ top: this.viewport.scrollHeight, behavior });
    this.remember();
    this.sync();
  },

  handleScroll() {
    const now = this.metrics();
    const atBottom = isAtBottom(now);

    // A smooth scroll to the bottom passes through many midpoints on its way down; those are not
    // the reader changing their mind.
    const travellingDown = !atBottom && this.last.scrollTop < now.scrollTop && this.pending;

    if (!travellingDown) {
      if (atBottom) {
        if (overflows(now)) this.pending = null;
        if (this.autoScroll()) this.follow = true;
      } else if (isUserScrollUp(this.last, now)) {
        this.pending = null;
        this.follow = false;
      }
    }

    if (now.scrollTop <= TOP_SLACK && this.last.scrollTop > now.scrollTop) this.reachedTop();

    this.last = now;
    this.anchor = this.captureAnchor();
    this.sync();
  },

  // The first message whose bottom edge is below the viewport's top: the one the reader is on.
  captureAnchor() {
    const top = this.viewport.getBoundingClientRect().top;
    for (const el of this.messages.children) {
      const rect = el.getBoundingClientRect();
      if (rect.bottom > top) return { el, offset: rect.top - top };
    }
    return null;
  },

  reachedTop() {
    const event = this.el.getAttribute("data-on-top");
    if (!event || this.topRequested || !overflows(this.metrics())) return;
    this.topRequested = true;
    this.pushEventTo(this.el, event, {});
  },

  // Coalesced to one frame: a streamed answer patches the DOM many times per frame.
  contentChanged() {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.relayout();
    });
  },

  relayout() {
    const now = this.metrics();
    const first = this.messages.firstElementChild;
    // New content arrived: the top can be asked for again (a next page of history).
    if (first !== this.firstMessage || now.scrollHeight !== this.last.scrollHeight) {
      this.topRequested = false;
    }
    this.firstMessage = first;

    if (this.follow && this.autoScroll()) {
      this.viewport.scrollTo({ top: now.scrollHeight, behavior: "instant" });
    } else if (this.pending) {
      this.viewport.scrollTo({ top: now.scrollHeight, behavior: this.pending });
    } else if (this.anchor && this.anchor.el.isConnected) {
      // Keep the message under the reader's eyes where it was, whatever moved above it.
      const top = this.viewport.getBoundingClientRect().top;
      const moved = this.anchor.el.getBoundingClientRect().top - top - this.anchor.offset;
      if (Math.abs(moved) >= 1) this.viewport.scrollTop += moved;
    }

    this.remember();
    this.anchor = this.captureAnchor();
    this.sync();
  },

  sync() {
    const atBottom = isAtBottom(this.metrics());
    const js = this.js();
    if (atBottom) js.setAttribute(this.el, "data-at-bottom", "");
    else js.removeAttribute(this.el, "data-at-bottom");

    this.el.querySelectorAll('[data-part="scroll-button"]').forEach((button) => {
      if (atBottom) js.setAttribute(button, "hidden", "");
      else js.removeAttribute(button, "hidden");
    });
  },
};

export default ChatThread;
