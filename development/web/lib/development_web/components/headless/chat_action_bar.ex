defmodule DevelopmentWeb.Components.Headless.ChatActionBar do
  @moduledoc """
  Headless **chat_action_bar** — what can be done with a message: copy, regenerate, edit, rate.

  Copying needs the browser's clipboard, so it is built in: pass the text as `copy`, or — to avoid
  duplicating a long answer into an attribute — the id of the element holding it as `copy_from`
  (its rendered text is copied). After a copy the button carries `data-copied` for
  `copied_duration` ms and a polite live region says `copied_label`.

  Every other action is an `:action` slot: a button with a label that sends a LiveView event.
  `pressed` makes it a toggle (`aria-pressed`) — thumbs up/down feedback:

      <.chat_action_bar id="m-2-actions" copy_from="m-2-content" autohide="not_last">
        <:copy_icon><.icon name="hero-clipboard" /></:copy_icon>
        <:action label="Regenerate" on_click="regenerate" value="m-2">↻</:action>
        <:action label="Good answer" on_click="rate" value="up" pressed={@rating == :up}>👍</:action>
      </.chat_action_bar>

  `autohide` hides the bar until the message is hovered or focused: `always`, `not_last` (the
  newest message keeps its actions visible — pair with `chat_message`'s `last`), or `never`. The
  rule lives in the headless stylesheet and uses `visibility`, so nothing shifts on hover and the
  buttons stay reachable by keyboard focus.

  Parts: `copy`, `copy-status`, `action`.

  Ships **no** colors, sizing or spacing — style via `chelekom-chat-action-bar*`.

  **Documentation:** https://mishka.tools/chelekom/docs/headless/chat_action_bar
  """
  use Phoenix.Component

  @doc type: :component
  attr :id, :string, default: nil, doc: "Unique id — required when copying (carries the hook)"
  attr :copy, :string, default: nil, doc: "Text the copy button copies"

  attr :copy_from, :string,
    default: nil,
    doc: "Id of the element whose text the copy button copies"

  attr :copy_label, :string, default: "Copy", doc: "Accessible name of the copy button"
  attr :copied_label, :string, default: "Copied", doc: "Announced after a copy"
  attr :copied_duration, :integer, default: 2000, doc: "How long data-copied stays, in ms"

  attr :autohide, :string,
    default: "never",
    values: ~w(never always not_last),
    doc: "Hide until the message is hovered or focused"

  attr :label, :string, default: "Message actions", doc: "Accessible name of the group"
  attr :target, :any, default: nil, doc: "phx-target for every action"

  attr :class, :any, default: nil, doc: "Extra classes for the root"
  attr :copy_class, :any, default: nil, doc: ~s|Extra classes for `data-part="copy"`|

  attr :copy_status_class, :any,
    default: nil,
    doc: ~s|Extra classes for `data-part="copy-status"`|

  attr :action_class, :any, default: nil, doc: ~s|Extra classes for every `data-part="action"`|
  attr :rest, :global

  slot :copy_icon, doc: "Content of the copy button (defaults to `copy_label`)"

  slot :action, doc: "A button sending a LiveView event" do
    attr :label, :string, required: true, doc: "Accessible name (and the text when empty)"
    attr :on_click, :string, doc: "LiveView event to push"
    attr :value, :any, doc: "Sent as phx-value-value"
    attr :pressed, :boolean, doc: "Makes it a toggle button (aria-pressed)"
    attr :disabled, :boolean
    attr :name, :string, doc: "Exposed as data-action, for styling one action"
    attr :class, :any, doc: "Extra classes for this action"
  end

  def chat_action_bar(assigns) do
    assigns =
      assign(assigns, :copyable, assigns.id != nil and (assigns.copy || assigns.copy_from) != nil)

    ~H"""
    <div
      id={@id}
      phx-hook={@copyable && "ChatActionBar"}
      role="group"
      aria-label={@label}
      data-part="root"
      data-autohide={@autohide}
      data-copy-text={@copy}
      data-copy-from={@copy_from}
      data-copied-label={@copied_label}
      data-copied-duration={@copied_duration}
      class={["chelekom-chat-action-bar", @class]}
      {@rest}
    >
      <button
        :if={@copyable}
        type="button"
        aria-label={@copy_label}
        data-part="copy"
        class={["chelekom-chat-action-bar__copy", @copy_class]}
      >
        {if @copy_icon != [], do: render_slot(@copy_icon), else: @copy_label}
      </button>
      <span
        :if={@copyable}
        role="status"
        aria-live="polite"
        data-part="copy-status"
        class={["chelekom-sr-only", "chelekom-chat-action-bar__copy-status", @copy_status_class]}
      ></span>

      <button
        :for={action <- @action}
        type="button"
        aria-label={action.label}
        aria-pressed={Map.has_key?(action, :pressed) && to_string(action[:pressed] == true)}
        disabled={action[:disabled]}
        phx-click={action[:on_click]}
        phx-value-value={action[:value]}
        phx-target={@target}
        data-part="action"
        data-action={action[:name]}
        data-pressed={action[:pressed] == true}
        class={["chelekom-chat-action-bar__action", @action_class, action[:class]]}
      >
        {if action.inner_block, do: render_slot(action), else: action.label}
      </button>
    </div>
    """
  end
end
