defmodule DevelopmentWeb.Components.Headless.ChatToolCall do
  @moduledoc """
  Headless **chat_tool_call** — one tool the agent used: what it called, with what, and what came
  back.

  A native `<details>` (no JavaScript): the summary shows the tool `name`, an optional friendlier
  `label` ("Searched the web"), the `status` and the `duration`; expanding it shows the arguments
  and the result. `status` is `pending`, `running`, `success`, `error`, `awaiting_approval` or
  `cancelled` — exposed as `data-status`, spelled out for screen readers, and `aria-busy` while
  running.

  `args` may be a map/list (rendered as pretty JSON with the app's JSON library) or a string;
  `output` works the same, or use the `:result` slot to render a rich result yourself.

      <.chat_tool_call name="web_search" label="Searching the web" status={@status}
        args={%{query: "best waffle cone supplier"}} duration={@ms}>
        <:result><.chat_sources>…</.chat_sources></:result>
      </.chat_tool_call>

  Parts: `trigger`, `icon`, `name`, `label`, `status`, `duration`, `content`, `args`, `result`,
  `heading`.

  Ships **no** colors, sizing or spacing — style via `chelekom-chat-tool-call*`.

  **Documentation:** https://mishka.tools/chelekom/docs/headless/chat_tool_call
  """
  use Phoenix.Component

  @statuses ~w(pending running success error awaiting_approval cancelled)

  @status_text %{
    "pending" => "Pending",
    "running" => "Running",
    "success" => "Done",
    "error" => "Failed",
    "awaiting_approval" => "Waiting for approval",
    "cancelled" => "Cancelled"
  }

  @doc type: :component
  attr :id, :string, default: nil, doc: "DOM id"
  attr :name, :string, required: true, doc: "The tool's name (web_search, read_file, …)"
  attr :label, :string, default: nil, doc: "A human description of the call"
  attr :status, :string, default: "running", values: @statuses, doc: "Lifecycle of the call"

  attr :status_labels, :map,
    default: %{},
    doc: ~s|Override the status text, e.g. %{"success" => "Ok"}|

  attr :duration, :integer, default: nil, doc: "How long it took, in milliseconds"
  attr :args, :any, default: nil, doc: "The arguments (map, list or string)"

  attr :output, :any,
    default: nil,
    doc: "The result (map, list or string); or use the :result slot"

  attr :open, :boolean, default: false, doc: "Start expanded"
  attr :args_label, :string, default: "Arguments", doc: "Heading of the args part"
  attr :result_label, :string, default: "Result", doc: "Heading of the result part"

  attr :class, :any, default: nil, doc: "Extra classes for the root"
  attr :trigger_class, :any, default: nil, doc: ~s|Extra classes for `data-part="trigger"`|
  attr :icon_class, :any, default: nil, doc: ~s|Extra classes for `data-part="icon"`|
  attr :name_class, :any, default: nil, doc: ~s|Extra classes for `data-part="name"`|
  attr :label_class, :any, default: nil, doc: ~s|Extra classes for `data-part="label"`|
  attr :status_class, :any, default: nil, doc: ~s|Extra classes for `data-part="status"`|
  attr :duration_class, :any, default: nil, doc: ~s|Extra classes for `data-part="duration"`|
  attr :content_class, :any, default: nil, doc: ~s|Extra classes for `data-part="content"`|
  attr :args_class, :any, default: nil, doc: ~s|Extra classes for `data-part="args"`|
  attr :result_class, :any, default: nil, doc: ~s|Extra classes for `data-part="result"`|
  attr :heading_class, :any, default: nil, doc: ~s|Extra classes for both `data-part="heading"`|
  attr :rest, :global

  slot :icon, doc: "A glyph for the tool"
  slot :result, doc: "A rich rendering of the result (replaces the `output` attr)"
  slot :inner_block, doc: "Anything else to show when expanded (an approval, a diff)"

  def chat_tool_call(assigns) do
    assigns =
      assigns
      |> assign(
        :status_text,
        Map.get(assigns.status_labels, assigns.status, @status_text[assigns.status])
      )
      |> assign(:args_text, pretty(assigns.args))
      |> assign(:result_text, pretty(assigns.output))

    ~H"""
    <details
      id={@id}
      open={@open}
      aria-busy={to_string(@status == "running")}
      data-part="root"
      data-status={@status}
      data-tool={@name}
      class={["chelekom-chat-tool-call", @class]}
      {@rest}
    >
      <summary data-part="trigger" class={["chelekom-chat-tool-call__trigger", @trigger_class]}>
        <span
          :if={@icon != []}
          data-part="icon"
          aria-hidden="true"
          class={["chelekom-chat-tool-call__icon", @icon_class]}
        >
          {render_slot(@icon)}
        </span>
        <span data-part="name" class={["chelekom-chat-tool-call__name", @name_class]}>{@name}</span>
        <span :if={@label} data-part="label" class={["chelekom-chat-tool-call__label", @label_class]}>
          {@label}
        </span>
        <span
          data-part="status"
          data-status={@status}
          class={["chelekom-chat-tool-call__status", @status_class]}
        >
          {@status_text}
        </span>
        <span
          :if={@duration}
          data-part="duration"
          class={["chelekom-chat-tool-call__duration", @duration_class]}
        >
          {format_duration(@duration)}
        </span>
      </summary>

      <div data-part="content" class={["chelekom-chat-tool-call__content", @content_class]}>
        <div :if={@args_text} data-part="args" class={["chelekom-chat-tool-call__args", @args_class]}>
          <span data-part="heading" class={["chelekom-chat-tool-call__heading", @heading_class]}>
            {@args_label}
          </span>
          <pre><code>{@args_text}</code></pre>
        </div>
        <div
          :if={@result != [] || @result_text}
          data-part="result"
          class={["chelekom-chat-tool-call__result", @result_class]}
        >
          <span data-part="heading" class={["chelekom-chat-tool-call__heading", @heading_class]}>
            {@result_label}
          </span>
          {if @result != [], do: render_slot(@result)}
          <pre :if={@result == [] && @result_text}><code>{@result_text}</code></pre>
        </div>
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  defp pretty(nil), do: nil
  defp pretty(text) when is_binary(text), do: text

  defp pretty(data) do
    # Only Jason takes `pretty:`; a dynamic call keeps apps without Jason warning-free.
    json = Phoenix.json_library()
    if json == Jason, do: json.encode!(data, pretty: true), else: json.encode!(data)
  rescue
    _ -> inspect(data, pretty: true)
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms} ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)} s"
end
