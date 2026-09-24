defmodule DevelopmentWeb.Components.Headless.ChatThread do
  @moduledoc """
  Headless **chat_thread** — the scrolling conversation of an AI chat.

  It does the one thing a chat viewport needs JavaScript for: stay pinned to the newest message
  while an answer streams in, and let go the moment the reader scrolls up to read something older.
  Scrolling back to the end (or pressing the scroll button) follows again, and a new run
  (`running` turning on) always brings the reader to the answer. The rules follow assistant-ui's
  stick-to-bottom logic: a scroll only counts as the reader's when the content height did not
  change, so a collapsing block or a re-layout never unpins you.

  Loading older history is supported too: `on_top` is pushed when the reader reaches the top, and
  messages inserted *above* keep the one under the reader's eyes where it was.

  The messages live in a `role="log"` region with `aria-busy` while a run is in progress, so a
  screen reader announces the finished answer once rather than every streamed token.

  Works with plain lists and with LiveView streams (`stream`), in which case each child needs a
  DOM id — `chat_message` takes one:

      <.chat_thread id="thread" stream running={@running} class="h-[70vh]">
        <.chat_message :for={{dom_id, msg} <- @streams.messages} id={dom_id} role={msg.role}>
          {msg.text}
        </.chat_message>
        <:empty>Ask me anything.</:empty>
        <:footer><.chat_composer id="composer" on_submit="send" running={@running} /></:footer>
      </.chat_thread>

  Scroll it from the server with
  `push_event(socket, "chelekom:chat-thread", %{id: "thread", scroll: "bottom"})`.

  The `empty` part shows only while `messages` has no children (a `:has()` rule in the headless
  stylesheet), so it needs no assign and works with streams.

  Parts: `viewport`, `messages`, `empty`, `scroll-button`, `footer`.

  Ships **no** colors, sizing or spacing — give the root a height and style via
  `chelekom-chat-thread*`.

  **Documentation:** https://mishka.tools/chelekom/docs/headless/chat_thread
  """
  use Phoenix.Component

  @doc type: :component
  attr :id, :string, required: true, doc: "Unique id (carries the ChatThread hook)"

  attr :running, :boolean,
    default: false,
    doc: "A run is in progress: marks the log busy, and scrolls to the answer when it starts"

  attr :auto_scroll, :boolean,
    default: true,
    doc: "Follow new content while the reader is at the bottom"

  attr :stream, :boolean,
    default: false,
    doc: ~s|The children are a LiveView stream (sets `phx-update="stream"` on `messages`)|

  attr :on_top, :string,
    default: nil,
    doc: "LiveView event pushed when the reader scrolls to the top (load older messages)"

  attr :label, :string, default: "Conversation", doc: "Accessible name of the message log"

  attr :scroll_label, :string,
    default: "Scroll to latest",
    doc: "Accessible name of the scroll button"

  attr :class, :any, default: nil, doc: "Extra classes for the root"
  attr :viewport_class, :any, default: nil, doc: ~s|Extra classes for `data-part="viewport"`|
  attr :messages_class, :any, default: nil, doc: ~s|Extra classes for `data-part="messages"`|
  attr :empty_class, :any, default: nil, doc: ~s|Extra classes for `data-part="empty"`|

  attr :scroll_button_class, :any,
    default: nil,
    doc: ~s|Extra classes for `data-part="scroll-button"`|

  attr :footer_class, :any, default: nil, doc: ~s|Extra classes for `data-part="footer"`|
  attr :rest, :global

  slot :inner_block, doc: "The messages (usually `chat_message` components)"
  slot :empty, doc: "Shown while there are no messages (a welcome, suggestions)"
  slot :scroll_button, doc: "Content of the scroll-to-latest button (defaults to `scroll_label`)"
  slot :footer, doc: "Pinned below the viewport — the composer"

  def chat_thread(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="ChatThread"
      data-part="root"
      data-running={@running}
      data-auto-scroll={to_string(@auto_scroll)}
      data-on-top={@on_top}
      class={["chelekom-chat-thread", @class]}
      {@rest}
    >
      <div
        data-part="viewport"
        role="region"
        aria-label={@label}
        tabindex="0"
        class={["chelekom-chat-thread__viewport", @viewport_class]}
      >
        <div
          :if={@empty != []}
          data-part="empty"
          class={["chelekom-chat-thread__empty", @empty_class]}
        >
          {render_slot(@empty)}
        </div>
        <div
          id={"#{@id}-messages"}
          data-part="messages"
          role="log"
          aria-label={@label}
          aria-live="polite"
          aria-relevant="additions"
          aria-busy={to_string(@running)}
          phx-update={@stream && "stream"}
          class={["chelekom-chat-thread__messages", @messages_class]}
        >
          {render_slot(@inner_block)}
        </div>
      </div>

      <button
        type="button"
        data-part="scroll-button"
        aria-label={@scroll_label}
        hidden
        class={["chelekom-chat-thread__scroll-button", @scroll_button_class]}
      >
        {if @scroll_button != [], do: render_slot(@scroll_button), else: @scroll_label}
      </button>

      <div
        :if={@footer != []}
        data-part="footer"
        class={["chelekom-chat-thread__footer", @footer_class]}
      >
        {render_slot(@footer)}
      </div>
    </div>
    """
  end
end
