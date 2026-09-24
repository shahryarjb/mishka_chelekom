defmodule DevelopmentWeb.Showcase.ChatLabLive do
  @moduledoc """
  `/showcase/chat/lab` — the chat components fed the way real Elixir AI stacks feed a LiveView.

  Pick a source and ask something. The producer (see `DevelopmentWeb.Showcase.ChatLabSources`) is
  a stand-in, but the LiveView side below is what an app writes for each library, and the two
  rendering styles both run through the same components:

    * **Ash AI — re-render.** Every chunk is a PubSub broadcast of the whole message;
      `stream_insert(:messages, message, at: 0)` into a `flex-col-reverse` list (Ash's generated
      layout). The text reaches `chat_stream` as `text=`, which appends only what is new.
    * **Jido AI — deltas with `seq`.** Signals arrive in `handle_info/2`; content deltas are
      pushed to `chat_stream` with their `seq`, so out-of-order delivery is reordered in the
      browser. Thinking deltas fill `chat_reasoning`, tool signals drive `chat_tool_call`.
    * **ReqLLM — deltas.** A task consumes the stream and forwards `StreamChunk`s.

  The wire counter shows what each style costs: re-render sends the whole text per chunk.
  """
  use DevelopmentWeb, :live_view

  import DevelopmentWeb.Components.Headless.ChatComposer
  import DevelopmentWeb.Components.Headless.ChatMessage
  import DevelopmentWeb.Components.Headless.ChatReasoning
  import DevelopmentWeb.Components.Headless.ChatStream
  import DevelopmentWeb.Components.Headless.ChatSuggestions
  import DevelopmentWeb.Components.Headless.ChatThread
  import DevelopmentWeb.Components.Headless.ChatToolCall
  import DevelopmentWeb.Components.Headless.ChatTypingIndicator

  alias DevelopmentWeb.Showcase.ChatLabSources, as: Sources

  @sources [
    {"ash_ai", "Ash AI — PubSub re-render"},
    {"jido", "Jido AI — signals, deltas with seq"},
    {"req_llm", "ReqLLM — stream chunks"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(sources: @sources, opts: default_opts())
     |> reset()}
  end

  defp default_opts,
    do: %{source: "ash_ai", speed: "normal", chunking: :token, shuffle: true, fail: false}

  defp reset(socket) do
    if socket.assigns[:task], do: Process.exit(socket.assigns.task, :kill)
    conversation = "lab-#{System.unique_integer([:positive])}"

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Development.PubSub, "chat:messages:#{conversation}")

    socket
    |> assign(
      conversation: conversation,
      messages: %{},
      counter: 0,
      run: nil,
      task: nil,
      events: 0,
      wire: 0
    )
    |> stream(:messages, [], reset: true)
  end

  # ── controls ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("configure", params, socket) do
    opts = %{
      source: params["source"] || socket.assigns.opts.source,
      speed: params["speed"] || "normal",
      chunking: if(params["chunking"] == "burst", do: :burst, else: :token),
      shuffle: params["shuffle"] == "true",
      fail: params["fail"] == "true"
    }

    socket = assign(socket, opts: opts)

    if opts.source != socket.assigns.opts.source,
      do: {:noreply, reset(socket)},
      else: {:noreply, socket}
  end

  def handle_event("send", %{"message" => text}, socket), do: {:noreply, ask(socket, text)}
  def handle_event("suggest", %{"prompt" => prompt}, socket), do: {:noreply, ask(socket, prompt)}

  def handle_event("stop", _params, %{assigns: %{run: %{id: id}}} = socket) do
    if socket.assigns.task, do: Process.exit(socket.assigns.task, :kill)

    {:noreply,
     socket
     |> push_event("chelekom:chat-stream", %{id: stream_id(id), done: true})
     |> update_message(id, &%{&1 | status: "complete", reasoning: done(&1.reasoning)})
     |> assign(run: nil, task: nil)}
  end

  def handle_event("stop", _params, socket), do: {:noreply, socket}

  defp ask(socket, text) do
    text = String.trim(text)

    if text == "" or socket.assigns.run do
      socket
    else
      {socket, user_id} = next_id(socket)
      {socket, id} = next_id(socket)
      source = socket.assigns.opts.source

      user = %{message(user_id, "user") | status: "complete", text: text}
      mode = if source == "ash_ai", do: :rerender, else: :delta
      reply = %{message(id, "assistant") | mode: mode}

      socket = socket |> put_message(user) |> put_message(reply)
      {:ok, task} = start_source(socket, source, id)
      assign(socket, run: %{id: id, source: source, ref: id, text: %{}}, task: task)
    end
  end

  defp start_source(socket, "ash_ai", id),
    do:
      Sources.ash_ai(
        "chat:messages:#{socket.assigns.conversation}",
        %{id: id, source: :agent},
        socket.assigns.opts
      )

  defp start_source(socket, "jido", id), do: Sources.jido(self(), id, socket.assigns.opts)
  defp start_source(socket, "req_llm", id), do: Sources.req_llm(self(), id, socket.assigns.opts)

  # ── Ash AI: the whole message, re-broadcast on every upsert ──────────────

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "chat:messages:" <> _, payload: msg}, socket) do
    status = ash_status(msg)

    socket =
      socket
      |> count(byte_size(msg[:text] || ""))
      |> update_message(msg.id, fn m ->
        %{m | status: status, text: msg.text || "", tools: ash_tools(msg), error: msg[:error]}
      end)

    {:noreply,
     if(status in ~w(complete error), do: assign(socket, run: nil, task: nil), else: socket)}
  end

  # ── Jido AI: signals (a real %Jido.Signal{} matches the same clause) ─────

  def handle_info(%{type: "ai." <> _ = type, data: %{call_id: id} = data}, socket) do
    {:noreply, socket |> count(byte_size(to_string(data[:delta] || ""))) |> jido(type, id, data)}
  end

  # ── ReqLLM: StreamChunks forwarded by the consuming task ─────────────────

  def handle_info({:req_llm, id, chunk}, socket) do
    socket = count(socket, if(is_map(chunk), do: byte_size(chunk[:text] || ""), else: 0))
    {:noreply, req_llm(socket, id, chunk)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp jido(socket, "ai.llm.delta", id, %{chunk_type: :thinking, delta: delta}),
    do: update_message(socket, id, &think(&1, delta))

  defp jido(socket, "ai.llm.delta", id, %{chunk_type: :content, delta: delta, seq: seq}) do
    socket
    |> update_message(id, &%{&1 | status: "streaming", reasoning: done(&1.reasoning)})
    |> push_event("chelekom:chat-stream", %{id: stream_id(id), delta: delta, seq: seq})
    |> collect(seq, delta)
  end

  defp jido(socket, "ai.tool.started", id, data),
    do:
      update_message(socket, id, fn m ->
        tool = %{name: data.tool_name, args: data.arguments, status: "running", output: nil}
        %{m | tools: m.tools ++ [tool], reasoning: done(m.reasoning)}
      end)

  defp jido(socket, "ai.tool.result", id, %{result: result}),
    do:
      update_message(socket, id, fn m ->
        {status, output} =
          case result do
            {:ok, value} -> {"success", value}
            {:error, reason} -> {"error", reason}
          end

        %{m | tools: Enum.map(m.tools, &%{&1 | status: status, output: output})}
      end)

  defp jido(socket, "ai.request.completed", id, _data), do: finish(socket, id)

  defp jido(socket, "ai.request.failed", id, %{error: error}),
    do:
      socket
      |> update_message(id, &%{&1 | status: "error", error: error, reasoning: done(&1.reasoning)})
      |> assign(run: nil, task: nil)

  defp jido(socket, _type, _id, _data), do: socket

  defp req_llm(socket, id, %{type: :thinking, text: text}),
    do: update_message(socket, id, &think(&1, text))

  defp req_llm(socket, id, %{type: :tool_call} = chunk),
    do:
      update_message(socket, id, fn m ->
        tool = %{name: chunk.name, args: chunk.arguments, status: "success", output: nil}
        %{m | tools: m.tools ++ [tool], reasoning: done(m.reasoning)}
      end)

  defp req_llm(socket, id, %{type: :content, text: text}) do
    socket
    |> update_message(id, &%{&1 | status: "streaming", reasoning: done(&1.reasoning)})
    |> push_event("chelekom:chat-stream", %{id: stream_id(id), delta: text})
  end

  defp req_llm(socket, id, :done), do: finish(socket, id)

  defp req_llm(socket, id, {:error, reason}),
    do:
      socket
      |> update_message(
        id,
        &%{&1 | status: "error", error: reason, reasoning: done(&1.reasoning)}
      )
      |> assign(run: nil, task: nil)

  defp ash_status(%{error: error}) when is_binary(error), do: "error"
  defp ash_status(%{complete: true}), do: "complete"
  defp ash_status(%{text: text}) when text in [nil, ""], do: "pending"
  defp ash_status(_msg), do: "streaming"

  # A tool call is done once a result with its id is on the row.
  defp ash_tools(msg) do
    results = Map.new(msg[:tool_results] || [], &{&1.tool_call_id, &1})

    Enum.map(msg[:tool_calls] || [], fn call ->
      result = results[call.id]

      %{
        name: call.name,
        args: call.arguments,
        status: if(result, do: "success", else: "running"),
        output: result && result.content
      }
    end)
  end

  defp finish(socket, id) do
    socket
    |> push_event("chelekom:chat-stream", %{id: stream_id(id), done: true})
    |> update_message(id, &%{&1 | status: "complete", reasoning: done(&1.reasoning)})
    |> assign(run: nil, task: nil)
  end

  # The server's own copy of a delta-streamed answer, assembled in seq order.
  defp collect(%{assigns: %{run: run}} = socket, seq, delta) when is_map(run),
    do: assign(socket, run: %{run | text: Map.put(run.text, seq, delta)})

  defp collect(socket, _seq, _delta), do: socket

  defp think(message, delta) do
    reasoning = message.reasoning || %{status: "streaming", text: ""}
    %{message | reasoning: %{reasoning | text: reasoning.text <> delta}}
  end

  defp done(nil), do: nil
  defp done(reasoning), do: %{reasoning | status: "done"}

  defp count(socket, bytes),
    do: assign(socket, events: socket.assigns.events + 1, wire: socket.assigns.wire + bytes)

  # ── message store ────────────────────────────────────────────────────────

  defp message(id, role),
    do: %{
      id: id,
      role: role,
      status: "pending",
      mode: :rerender,
      text: "",
      reasoning: nil,
      tools: [],
      error: nil
    }

  defp next_id(socket) do
    counter = socket.assigns.counter + 1
    {assign(socket, counter: counter), "#{socket.assigns.conversation}-#{counter}"}
  end

  # Ash's layout: newest first in the DOM, flex-col-reverse shows it last. The others append.
  defp put_message(socket, message) do
    at = if socket.assigns.opts.source == "ash_ai", do: 0, else: -1

    socket
    |> assign(messages: Map.put(socket.assigns.messages, message.id, message))
    |> stream_insert(:messages, message, at: at)
  end

  defp update_message(socket, id, fun) do
    case socket.assigns.messages[id] do
      nil -> socket
      message -> put_message(socket, fun.(message))
    end
  end

  defp stream_id(id), do: "#{id}-stream"

  # ── render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen flex-col bg-white text-neutral-950 dark:bg-neutral-950 dark:text-white">
      <header class="flex flex-wrap items-center gap-3 border-b border-neutral-200 px-4 py-3 text-sm dark:border-neutral-800">
        <.link navigate={~p"/showcase/chat"} class="text-xs text-neutral-500 hover:underline">
          ← chat demo
        </.link>
        <span class="font-medium">Chat lab</span>
        <form id="lab-config" phx-change="configure" class="flex flex-wrap items-center gap-3 text-xs">
          <select
            name="source"
            aria-label="Source"
            class="rounded border border-neutral-300 bg-transparent px-2 py-1 dark:border-neutral-700"
          >
            <option :for={{value, label} <- @sources} value={value} selected={value == @opts.source}>
              {label}
            </option>
          </select>
          <select
            name="speed"
            aria-label="Speed"
            class="rounded border border-neutral-300 bg-transparent px-2 py-1 dark:border-neutral-700"
          >
            <option :for={speed <- ~w(slow normal fast)} value={speed} selected={speed == @opts.speed}>
              {speed}
            </option>
          </select>
          <select
            name="chunking"
            aria-label="Chunking"
            class="rounded border border-neutral-300 bg-transparent px-2 py-1 dark:border-neutral-700"
          >
            <option value="token" selected={@opts.chunking == :token}>a word per chunk</option>
            <option value="burst" selected={@opts.chunking == :burst}>bursts of 5 words</option>
          </select>
          <label class="flex items-center gap-1">
            <input type="hidden" name="shuffle" value="false" />
            <input type="checkbox" name="shuffle" value="true" checked={@opts.shuffle} />
            out-of-order (Jido)
          </label>
          <label class="flex items-center gap-1">
            <input type="hidden" name="fail" value="false" />
            <input type="checkbox" name="fail" value="true" checked={@opts.fail} /> fail
          </label>
        </form>
        <span id="lab-stats" class="ml-auto text-xs tabular-nums text-neutral-500">
          events <strong>{@events}</strong> · text over the wire <strong>{@wire}</strong> bytes
        </span>
      </header>

      <.chat_thread
        id="lab"
        stream
        running={@run != nil}
        class="min-h-0 flex-1"
        viewport_class="px-4"
        messages_class={[
          "mx-auto flex max-w-2xl gap-6 py-6",
          if(@opts.source == "ash_ai", do: "flex-col-reverse", else: "flex-col")
        ]}
        empty_class="mx-auto flex max-w-2xl flex-col items-center gap-4 py-24 text-center"
        scroll_button_class="absolute bottom-28 left-1/2 -translate-x-1/2 rounded-full border border-neutral-200 bg-white px-3 py-1 text-xs shadow-sm dark:border-neutral-700 dark:bg-neutral-900"
        footer_class="mx-auto w-full max-w-2xl px-4 pb-4"
      >
        <.chat_message
          :for={{dom_id, msg} <- @streams.messages}
          id={dom_id}
          role={msg.role}
          status={msg.status}
          class="flex data-[role=user]:justify-end"
          body_class="flex min-w-0 max-w-full flex-col gap-2"
          content_class="text-sm leading-relaxed [[data-role=user]_&]:rounded-2xl [[data-role=user]_&]:bg-neutral-100 [[data-role=user]_&]:px-4 [[data-role=user]_&]:py-2 dark:[[data-role=user]_&]:bg-neutral-800"
          error_class="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-300"
          show_caret={false}
        >
          <%= if msg.role == "user" do %>
            {msg.text}
          <% else %>
            <div class="mb-2 flex flex-col gap-2">
              <.chat_reasoning
                :if={msg.reasoning}
                id={"#{msg.id}-reasoning"}
                status={msg.reasoning.status}
                class="text-sm"
                trigger_class="cursor-pointer select-none text-neutral-500"
                label_class="data-[status=streaming]:animate-pulse"
                content_class="mt-2 border-l-2 border-neutral-200 pl-3 text-neutral-600 dark:border-neutral-800 dark:text-neutral-400"
              >
                {msg.reasoning.text}
              </.chat_reasoning>
              <.chat_tool_call
                :for={{tool, i} <- Enum.with_index(msg.tools)}
                id={"#{msg.id}-tool-#{i}"}
                name={tool.name}
                status={tool.status}
                args={tool.args}
                output={tool.output}
                class="rounded-lg border border-neutral-200 text-sm dark:border-neutral-800"
                trigger_class="flex cursor-pointer items-center gap-2 px-3 py-2"
                name_class="font-mono text-xs"
                status_class="ml-auto text-xs data-[status=success]:text-green-600 data-[status=running]:animate-pulse"
                content_class="flex flex-col gap-1 border-t border-neutral-200 px-3 py-2 font-mono text-xs dark:border-neutral-800"
              />
            </div>
            <.chat_typing_indicator
              :if={msg.status == "pending" && msg.mode == :rerender}
              class="inline-flex gap-1 py-1"
              dot_class="size-1.5 animate-bounce rounded-full bg-neutral-400 [animation-delay:calc(var(--index)*150ms)]"
            />
            <.chat_stream
              :if={msg.mode == :delta || msg.status in ~w(streaming complete)}
              id={stream_id(msg.id)}
              text={if(msg.mode == :rerender, do: msg.text, else: "")}
              done={msg.status in ~w(complete error)}
              smooth
              class="block"
              caret_class="ml-0.5 inline-block h-4 w-1.5 animate-pulse bg-neutral-900 align-middle dark:bg-white"
            />
          <% end %>
          <:error>{msg.error}</:error>
        </.chat_message>

        <:empty>
          <p class="text-sm text-neutral-500">
            Pick a source above, then ask. Scroll up while it streams — the thread lets go.
          </p>
          <.chat_suggestions
            on_select="suggest"
            class="flex gap-2"
            suggestion_class="rounded-full border border-neutral-200 px-3 py-1.5 text-sm hover:bg-neutral-50 dark:border-neutral-800 dark:hover:bg-neutral-900"
          >
            <:suggestion prompt="Which flavor should we launch this summer?" />
          </.chat_suggestions>
        </:empty>

        <:footer>
          <.chat_composer
            id="lab-composer"
            on_submit="send"
            on_cancel="stop"
            running={@run != nil}
            class="flex items-end gap-2 rounded-2xl border border-neutral-200 px-3 py-2 dark:border-neutral-700"
            input_class="min-w-0 flex-1 bg-transparent py-1 text-sm outline-none placeholder:text-neutral-400"
            send_class="flex size-8 items-center justify-center rounded-full bg-neutral-900 text-white disabled:opacity-30 dark:bg-white dark:text-neutral-950"
            cancel_class="flex size-8 items-center justify-center rounded-full bg-neutral-900 text-white dark:bg-white dark:text-neutral-950"
          >
            <:send>↑</:send>
            <:cancel>■</:cancel>
          </.chat_composer>
        </:footer>
      </.chat_thread>
    </div>
    """
  end
end
