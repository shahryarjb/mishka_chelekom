defmodule DevelopmentWeb.Showcase.ChatDemoLive do
  @moduledoc """
  `/showcase/chat` — every headless chat component wired into one working AI chat.

  The "model" is `DevelopmentWeb.Showcase.ChatDemoScript`, so the page runs without an API key,
  but the plumbing is what a real app does:

    * messages are a LiveView stream (`chat_thread stream`), with the data kept in `@messages`
    * a run thinks (`chat_reasoning`), calls a tool (`chat_tool_call`), then streams its answer
      token by token with `push_event("chelekom:chat-stream", …)` into a `chat_stream` — only
      the finished text is re-rendered, once
    * stop (the composer's stop button or Escape) keeps what was streamed so far
    * regenerate creates a branch (`chat_branch_picker`), thumbs are `aria-pressed` toggles
    * a destructive request pauses on a `chat_approval` until the human decides
    * files ride in on a LiveView upload and render as `chat_attachment`
    * scrolling to the top of the first conversation loads older history above the reader
  """
  use DevelopmentWeb, :live_view

  import DevelopmentWeb.Components.Headless.ChatActionBar
  import DevelopmentWeb.Components.Headless.ChatApproval
  import DevelopmentWeb.Components.Headless.ChatAttachment
  import DevelopmentWeb.Components.Headless.ChatBranchPicker
  import DevelopmentWeb.Components.Headless.ChatComposer
  import DevelopmentWeb.Components.Headless.ChatMessage
  import DevelopmentWeb.Components.Headless.ChatReasoning
  import DevelopmentWeb.Components.Headless.ChatSources
  import DevelopmentWeb.Components.Headless.ChatStream
  import DevelopmentWeb.Components.Headless.ChatSuggestions
  import DevelopmentWeb.Components.Headless.ChatThread
  import DevelopmentWeb.Components.Headless.ChatThreadList
  import DevelopmentWeb.Components.Headless.ChatToolCall
  import DevelopmentWeb.Components.Headless.ChatTypingIndicator

  alias DevelopmentWeb.Showcase.ChatDemoScript, as: Script

  @threads [
    %{id: "t-1", title: "Summer flavor launch", meta: "Today"},
    %{id: "t-2", title: "Waffle cone suppliers", meta: "Yesterday"},
    %{id: "t-3", title: "Freezer capacity plan", meta: "Sep 12"}
  ]

  # Delays of the pretend model, in ms. Short enough to demo, long enough to watch each state;
  # config/test.exs scales them to zero.
  @scale Application.compile_env(:development, :chat_demo_delay_scale, 1)
  @think round(500 * @scale)
  @tool round(900 * @scale)
  @answer round(1_000 * @scale)
  @token round(30 * @scale)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(threads: @threads, counter: 0, run: nil, follow_ups: [])
     |> allow_upload(:files,
       accept: :any,
       max_entries: 3,
       max_file_size: 5_000_000,
       auto_upload: true
     )
     |> open_thread("t-1")}
  end

  # ── events ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("send", %{"message" => text}, socket),
    do: {:noreply, send_prompt(socket, text)}

  def handle_event("suggest", %{"prompt" => prompt}, socket),
    do: {:noreply, send_prompt(socket, prompt)}

  def handle_event("stop", _params, socket), do: {:noreply, stop_run(socket)}

  def handle_event("regenerate", %{"value" => id}, socket) do
    msg = socket.assigns.messages[id]

    if socket.assigns.run || is_nil(msg),
      do: {:noreply, socket},
      else: {:noreply, start_run(socket, msg.prompt, id, length(msg.branches) + 1)}
  end

  def handle_event("branch_prev", %{"value" => id}, socket),
    do: {:noreply, branch(socket, id, -1)}

  def handle_event("branch_next", %{"value" => id}, socket), do: {:noreply, branch(socket, id, 1)}

  def handle_event("rate", %{"value" => value}, socket) do
    [id, rating] = String.split(value, ":")
    msg = socket.assigns.messages[id]
    rating = if msg.rating == rating, do: nil, else: rating
    {:noreply, put_message(socket, %{msg | rating: rating})}
  end

  def handle_event("approve", _params, socket), do: {:noreply, decide(socket, "approved")}
  def handle_event("deny", _params, socket), do: {:noreply, decide(socket, "denied")}

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :files, ref)}

  def handle_event("new_chat", _params, socket),
    do: {:noreply, socket |> stop_run() |> open_thread("new")}

  def handle_event("open_thread", %{"id" => id}, socket),
    do: {:noreply, socket |> stop_run() |> open_thread(id)}

  def handle_event("delete_thread", %{"id" => id}, socket) do
    socket = assign(socket, threads: Enum.reject(socket.assigns.threads, &(&1.id == id)))

    if socket.assigns.thread_id == id,
      do: {:noreply, open_thread(socket, "new")},
      else: {:noreply, socket}
  end

  # Older history arrives ABOVE the reader; chat_thread keeps the message they were reading in place.
  def handle_event("load_older", _params, socket) do
    socket =
      socket.assigns.older
      |> Enum.reverse()
      |> Enum.reduce(socket, fn msg, acc -> put_message(acc, msg, at: 0) end)

    {:noreply, assign(socket, older: [])}
  end

  # ── the pretend model ────────────────────────────────────────────────────

  @impl true
  def handle_info({:run, id, stage}, %{assigns: %{run: %{id: id} = run}} = socket),
    do: {:noreply, advance(socket, run, stage)}

  # A timer from a run that was stopped or replaced.
  def handle_info({:run, _id, _stage}, socket), do: {:noreply, socket}

  defp send_prompt(socket, text) do
    text = String.trim(text)

    {_done, uploading} = uploaded_entries(socket, :files)

    # consume_uploaded_entries/3 raises while an entry is still uploading: wait for it.
    if socket.assigns.run || uploading != [] do
      socket
    else
      send_ready(socket, text)
    end
  end

  defp send_ready(socket, text) do
    attachments =
      consume_uploaded_entries(socket, :files, fn _meta, entry ->
        {:ok, %{name: entry.client_name, size: entry.client_size, type: entry.client_type}}
      end)

    if text == "" && attachments == [] do
      socket
    else
      {socket, user_id} = next_id(socket)
      prompt = if text == "", do: "What's in these files?", else: text

      socket
      |> put_message(user_message(user_id, prompt, attachments))
      |> then(fn socket ->
        {socket, id} = next_id(socket)
        start_run(socket, prompt, id, 1)
      end)
    end
  end

  defp start_run(socket, prompt, msg_id, attempt) do
    run = %{
      id: System.unique_integer([:positive]),
      msg_id: msg_id,
      prompt: prompt,
      attempt: attempt,
      reply: Script.reply(prompt, attempt),
      started: System.monotonic_time(:millisecond),
      tokens: [],
      sent: ""
    }

    previous = socket.assigns.messages[msg_id]

    msg = %{
      assistant_message(msg_id, prompt)
      | branches: (previous && previous.branches) || [],
        branch: attempt
    }

    Process.send_after(self(), {:run, run.id, :think}, @think)

    socket
    |> assign(run: run, follow_ups: [])
    |> put_message(msg)
  end

  defp advance(socket, run, :think) do
    steps = run.reply.steps |> Enum.with_index() |> Enum.map(&step_status(&1, 1))
    Process.send_after(self(), {:run, run.id, :tool}, @tool)
    update_run_message(socket, run, &put_in(&1.reasoning.steps, steps))
  end

  defp advance(socket, run, :tool) do
    seconds = max(div(System.monotonic_time(:millisecond) - run.started, 1_000), 1)
    next = if run.reply.approval, do: :approval, else: :answer
    Process.send_after(self(), {:run, run.id, next}, @answer)

    update_run_message(socket, run, fn msg ->
      %{
        msg
        | reasoning: %{status: "done", duration: seconds, steps: run.reply.steps},
          tool: Map.merge(run.reply.tool, %{status: "running", duration: nil, output: nil})
      }
    end)
  end

  defp advance(socket, run, :approval) do
    update_run_message(socket, run, fn msg ->
      %{
        msg
        | tool: %{msg.tool | status: "awaiting_approval"},
          approval: Map.put(run.reply.approval, :status, "pending")
      }
    end)
  end

  defp advance(socket, run, :answer) do
    run = %{run | tokens: Script.tokens(run.reply.text)}
    Process.send_after(self(), {:run, run.id, :token}, @token)

    socket
    |> assign(run: run)
    |> update_run_message(run, fn msg ->
      output = if run.reply.sources == [], do: "ok", else: "#{length(run.reply.sources)} results"

      %{
        msg
        | status: "streaming",
          sources: run.reply.sources,
          tool: %{msg.tool | status: "success", duration: 640, output: output}
      }
    end)
  end

  defp advance(socket, %{tokens: []} = run, :token), do: finish(socket, run, run.reply.text)

  defp advance(socket, %{tokens: [token | rest]} = run, :token) do
    Process.send_after(self(), {:run, run.id, :token}, @token)

    socket
    |> assign(run: %{run | tokens: rest, sent: run.sent <> token})
    |> push_event("chelekom:chat-stream", %{id: stream_id(run.msg_id), delta: token})
  end

  defp finish(socket, run, text) do
    msg = socket.assigns.messages[run.msg_id]

    branches =
      List.replace_at(msg.branches ++ [nil], run.attempt - 1, text) |> Enum.reject(&is_nil/1)

    socket
    |> push_event("chelekom:chat-stream", %{id: stream_id(run.msg_id), done: true})
    |> assign(run: nil, follow_ups: Script.follow_ups(run.prompt))
    |> put_message(%{
      msg
      | status: "complete",
        text: text,
        branches: branches,
        branch: length(branches)
    })
  end

  # Stopping keeps what the reader already saw, exactly like a real model cut off mid-sentence.
  defp stop_run(%{assigns: %{run: nil}} = socket), do: socket

  defp stop_run(%{assigns: %{run: run}} = socket) do
    case socket.assigns.messages[run.msg_id] do
      nil -> assign(socket, run: nil)
      _msg when run.sent == "" -> finish(socket, run, "Stopped before answering.")
      _msg -> finish(socket, run, String.trim_trailing(run.sent) <> " …")
    end
  end

  defp decide(%{assigns: %{run: %{reply: %{approval: approval}} = run}} = socket, decision)
       when is_map(approval) do
    socket =
      update_run_message(socket, run, fn msg ->
        tool_status = if decision == "approved", do: "running", else: "cancelled"

        %{
          msg
          | approval: %{msg.approval | status: decision},
            tool: %{msg.tool | status: tool_status}
        }
      end)

    if decision == "approved" do
      Process.send_after(self(), {:run, run.id, :answer}, @answer)
      socket
    else
      finish(socket, run, "Okay — I left build/ untouched.")
    end
  end

  defp decide(socket, _decision), do: socket

  # ── message store (the stream renders; @messages remembers) ──────────────

  defp open_thread(socket, id) do
    {visible, older} = seed(id)

    socket
    |> assign(thread_id: id, older: older, run: nil, follow_ups: [], last_id: nil)
    |> assign(messages: %{})
    |> stream(:messages, [], reset: true)
    |> then(fn socket -> Enum.reduce(visible, socket, &put_message(&2, &1)) end)
  end

  defp put_message(socket, msg, opts \\ []) do
    messages = Map.put(socket.assigns.messages, msg.id, msg)
    at = Keyword.get(opts, :at, -1)
    previous_last = socket.assigns.last_id

    socket = assign(socket, messages: messages)

    # `last` decides which message keeps its actions visible; re-render the one losing it.
    cond do
      at == 0 ->
        stream_insert(socket, :messages, msg, at: 0)

      previous_last in [nil, msg.id] ->
        socket |> assign(last_id: msg.id) |> stream_insert(:messages, msg)

      true ->
        socket
        |> assign(last_id: msg.id)
        |> stream_insert(:messages, messages[previous_last])
        |> stream_insert(:messages, msg)
    end
  end

  defp update_run_message(socket, run, fun) do
    case socket.assigns.messages[run.msg_id] do
      nil -> socket
      msg -> put_message(socket, fun.(msg))
    end
  end

  defp next_id(socket) do
    counter = socket.assigns.counter + 1
    {assign(socket, counter: counter), "msg-#{socket.assigns.thread_id}-#{counter}"}
  end

  defp step_status({step, index}, active) do
    status =
      cond do
        index == active -> "active"
        index < active -> "done"
        true -> "pending"
      end

    Map.put(step, :status, status)
  end

  defp branch(socket, id, step) do
    case socket.assigns.messages[id] do
      nil ->
        socket

      msg ->
        branch = min(max(msg.branch + step, 1), length(msg.branches))
        put_message(socket, %{msg | branch: branch, text: Enum.at(msg.branches, branch - 1)})
    end
  end

  defp user_message(id, text, attachments),
    do: %{
      id: id,
      role: "user",
      status: "complete",
      text: text,
      prompt: text,
      attachments: attachments,
      reasoning: nil,
      tool: nil,
      sources: [],
      approval: nil,
      branches: [text],
      branch: 1,
      rating: nil
    }

  defp assistant_message(id, prompt),
    do: %{
      id: id,
      role: "assistant",
      status: "pending",
      text: "",
      prompt: prompt,
      attachments: [],
      reasoning: %{status: "streaming", duration: nil, steps: []},
      tool: nil,
      sources: [],
      approval: nil,
      branches: [],
      branch: 1,
      rating: nil
    }

  defp answered(id, prompt) do
    reply = Script.reply(prompt)

    %{
      assistant_message(id, prompt)
      | status: "complete",
        text: reply.text,
        reasoning: %{status: "done", duration: 2, steps: reply.steps},
        tool: Map.merge(reply.tool, %{status: "success", duration: 640, output: "ok"}),
        sources: reply.sources,
        branches: [reply.text]
    }
  end

  defp seed("t-1") do
    older =
      [
        {"user", "How did June sales look?"},
        {"assistant", "Up 14% on May. Vanilla held steady; the growth came from new flavors."},
        {"user", "Which new flavors?"},
        {"assistant", "Pistachio and peach — together about two thirds of the growth."}
      ]
      |> Enum.with_index(1)
      |> Enum.map(fn {{role, text}, n} ->
        %{user_message("msg-t-1-old-#{n}", text, []) | role: role}
      end)

    prompt = "Which flavor should we launch this summer?"
    {[user_message("msg-t-1-a", prompt, []), answered("msg-t-1-b", prompt)], older}
  end

  defp seed("t-2") do
    prompt = "Find a waffle cone supplier"
    {[user_message("msg-t-2-a", prompt, []), answered("msg-t-2-b", prompt)], []}
  end

  defp seed("t-3") do
    prompt = "How much freezer space do we have?"

    {[
       user_message("msg-t-3-a", prompt, [
         %{name: "freezer-log.csv", size: 18_432, type: "text/csv"}
       ]),
       answered("msg-t-3-b", prompt)
     ], []}
  end

  defp seed(_), do: {[], []}

  defp stream_id(msg_id), do: "#{msg_id}-stream"

  # ── render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-white text-neutral-950 dark:bg-neutral-950 dark:text-white">
      <aside class="hidden w-64 shrink-0 flex-col gap-3 border-r border-neutral-200 p-3 md:flex dark:border-neutral-800">
        <.link navigate={~p"/showcase/headless"} class="text-xs text-neutral-500 hover:underline">
          ← headless components
        </.link>
        <.chat_thread_list
          on_new="new_chat"
          on_select="open_thread"
          on_delete="delete_thread"
          class="flex flex-col gap-2 text-sm"
          new_class="rounded-lg border border-neutral-200 px-3 py-2 text-left font-medium hover:bg-neutral-50 dark:border-neutral-800 dark:hover:bg-neutral-900"
          list_class="flex flex-col"
          item_class="group flex items-center rounded-lg data-[active]:bg-neutral-100 dark:data-[active]:bg-neutral-900"
          link_class="flex min-w-0 flex-1 flex-col items-start px-3 py-1.5 text-left"
          title_class="w-full truncate"
          meta_class="text-xs text-neutral-500"
          delete_class="invisible px-2 text-xs text-neutral-400 group-hover:visible group-focus-within:visible"
        >
          <:thread
            :for={thread <- @threads}
            id={thread.id}
            title={thread.title}
            meta={thread.meta}
            active={thread.id == @thread_id}
          />
          <:empty>No conversations.</:empty>
        </.chat_thread_list>
      </aside>

      <main class="flex min-w-0 flex-1 flex-col">
        <header class="border-b border-neutral-200 px-4 py-3 text-sm font-medium dark:border-neutral-800">
          Mishka Chelekom · headless AI chat ·
          <.link
            navigate={~p"/showcase/chat/lab"}
            class="font-normal text-neutral-500 hover:underline"
          >
            lab: Ash AI, Jido, ReqLLM →
          </.link>
        </header>

        <.chat_thread
          id="chat"
          stream
          running={@run != nil}
          on_top={@older != [] && "load_older"}
          class="min-h-0 flex-1"
          viewport_class="px-4"
          messages_class="mx-auto flex max-w-2xl flex-col gap-6 py-6"
          empty_class="mx-auto flex max-w-2xl flex-col items-center gap-6 py-24 text-center"
          scroll_button_class="absolute bottom-36 left-1/2 -translate-x-1/2 rounded-full border border-neutral-200 bg-white px-3 py-1 text-xs shadow-sm dark:border-neutral-700 dark:bg-neutral-900"
          footer_class="mx-auto w-full max-w-2xl px-4 pb-4"
        >
          <.chat_message
            :for={{dom_id, msg} <- @streams.messages}
            id={dom_id}
            role={msg.role}
            status={msg.status}
            name={if msg.role == "user", do: "You", else: "Assistant"}
            last={msg.id == @last_id}
            class="flex gap-3 data-[role=user]:flex-row-reverse"
            avatar_class="flex size-8 shrink-0 items-center justify-center rounded-full bg-neutral-100 text-sm dark:bg-neutral-800"
            body_class="flex min-w-0 flex-1 flex-col gap-2 [[data-role=user]_&]:items-end"
            header_class="sr-only"
            attachments_class="flex flex-wrap gap-2"
            content_class="max-w-full text-sm leading-relaxed [[data-role=user]_&]:rounded-2xl [[data-role=user]_&]:bg-neutral-100 [[data-role=user]_&]:px-4 [[data-role=user]_&]:py-2 dark:[[data-role=user]_&]:bg-neutral-800"
            footer_class="flex items-center gap-3"
          >
            <:avatar :if={msg.role == "assistant"}>✦</:avatar>
            <:attachments :if={msg.attachments != []}>
              <.chat_attachment
                :for={file <- msg.attachments}
                name={file.name}
                size={file.size}
                type={file.type}
                class="flex items-center gap-2 rounded-lg border border-neutral-200 px-2 py-1 text-xs dark:border-neutral-700"
                meta_class="text-neutral-500"
              />
            </:attachments>

            <div :if={msg.role == "assistant"} class="mb-3 flex flex-col gap-2">
              <.chat_reasoning
                :if={msg.reasoning}
                id={"#{msg.id}-reasoning"}
                status={msg.reasoning.status}
                duration={msg.reasoning.duration}
                class="text-sm"
                trigger_class="flex cursor-pointer select-none items-center gap-2 text-neutral-500 hover:text-neutral-950 dark:hover:text-white"
                label_class="data-[status=streaming]:animate-pulse"
                content_class="mt-2 border-l-2 border-neutral-200 pl-3 dark:border-neutral-800"
                steps_class="flex flex-col gap-1"
                step_class="flex items-baseline gap-2 text-neutral-600 data-[status=active]:font-medium data-[status=active]:text-neutral-950 data-[status=pending]:opacity-40 dark:text-neutral-400 dark:data-[status=active]:text-white"
                step_detail_class="text-xs text-neutral-400"
              >
                <:icon>✺</:icon>
                <:step
                  :for={step <- msg.reasoning.steps}
                  label={step.label}
                  detail={step[:detail]}
                  status={step.status}
                />
              </.chat_reasoning>

              <.chat_tool_call
                :if={msg.tool}
                id={"#{msg.id}-tool"}
                name={msg.tool.name}
                label={msg.tool.label}
                status={msg.tool.status}
                duration={msg.tool.duration}
                args={msg.tool.args}
                output={msg.tool.output}
                class="rounded-lg border border-neutral-200 text-sm dark:border-neutral-800"
                trigger_class="flex cursor-pointer items-center gap-2 px-3 py-2"
                name_class="font-mono text-xs text-neutral-500"
                label_class="flex-1 truncate"
                status_class="text-xs data-[status=success]:text-green-600 data-[status=running]:animate-pulse data-[status=awaiting_approval]:text-amber-600 data-[status=cancelled]:text-neutral-400"
                duration_class="text-xs tabular-nums text-neutral-400"
                content_class="flex flex-col gap-2 border-t border-neutral-200 px-3 py-2 dark:border-neutral-800"
                heading_class="text-xs font-medium text-neutral-500"
                args_class="flex flex-col gap-1 font-mono text-xs"
                result_class="flex flex-col gap-1 font-mono text-xs"
              />

              <.chat_approval
                :if={msg.approval}
                id={"#{msg.id}-approval"}
                title={msg.approval.title}
                description={msg.approval.description}
                status={msg.approval.status}
                on_submit="approve"
                on_deny="deny"
                class="rounded-xl border border-amber-300 bg-amber-50 p-3 dark:border-amber-800 dark:bg-amber-950"
                fieldset_class="flex flex-col gap-2"
                title_class="text-sm font-medium"
                description_class="text-xs text-neutral-600 dark:text-neutral-400"
                actions_class="flex justify-end gap-2"
                deny_class="rounded-full border border-neutral-300 px-3 py-1 text-xs disabled:opacity-50 dark:border-neutral-700"
                approve_class="rounded-full bg-neutral-900 px-3 py-1 text-xs font-medium text-white disabled:opacity-50 dark:bg-white dark:text-neutral-950"
              />
            </div>

            <.chat_typing_indicator
              :if={msg.status == "pending" && is_nil(msg.approval)}
              class="inline-flex items-center gap-1 py-2"
              dot_class="size-1.5 animate-bounce rounded-full bg-neutral-400 [animation-delay:calc(var(--index)*150ms)]"
            />
            <.chat_stream
              :if={msg.status == "streaming"}
              id={stream_id(msg.id)}
              smooth
              caret_class="ml-0.5 inline-block h-4 w-1.5 animate-pulse bg-neutral-900 align-middle dark:bg-white"
            />
            <div :if={msg.status == "complete"} id={"#{msg.id}-text"} class="flex flex-col gap-3">
              <p :for={paragraph <- String.split(msg.text, "\n\n")}>{paragraph}</p>
            </div>

            <.chat_sources
              :if={msg.sources != [] && msg.status == "complete"}
              class="mt-3 flex flex-col gap-2"
              label_class="text-xs font-medium text-neutral-500"
              list_class="flex flex-wrap gap-2"
              link_class="flex items-center gap-2 rounded-full border border-neutral-200 px-2.5 py-1 text-xs hover:bg-neutral-50 dark:border-neutral-800 dark:hover:bg-neutral-900"
              index_class="flex size-4 items-center justify-center rounded-full bg-neutral-200 text-[10px] dark:bg-neutral-800"
              domain_class="text-neutral-500"
            >
              <:source :for={source <- msg.sources} href={source.href} title={source.title} />
            </.chat_sources>

            <:actions :if={msg.role == "assistant" && msg.status == "complete"}>
              <.chat_branch_picker
                index={msg.branch}
                count={length(msg.branches)}
                value={msg.id}
                on_previous="branch_prev"
                on_next="branch_next"
                class="inline-flex items-center gap-1 text-xs text-neutral-500"
                previous_class="rounded px-1.5 hover:bg-neutral-100 disabled:opacity-30 dark:hover:bg-neutral-800"
                next_class="rounded px-1.5 hover:bg-neutral-100 disabled:opacity-30 dark:hover:bg-neutral-800"
                status_class="tabular-nums"
              />
              <.chat_action_bar
                id={"#{msg.id}-actions"}
                copy_from={"#{msg.id}-text"}
                autohide="not_last"
                class="flex items-center gap-1 text-neutral-500"
                copy_class="rounded-md px-2 py-1 text-xs hover:bg-neutral-100 data-[copied]:text-green-600 dark:hover:bg-neutral-800"
                action_class="rounded-md px-2 py-1 text-xs hover:bg-neutral-100 aria-pressed:bg-neutral-900 aria-pressed:text-white dark:hover:bg-neutral-800 dark:aria-pressed:bg-white dark:aria-pressed:text-neutral-950"
              >
                <:copy_icon>Copy</:copy_icon>
                <:action label="Regenerate" on_click="regenerate" value={msg.id}>↻</:action>
                <:action
                  label="Good answer"
                  on_click="rate"
                  value={"#{msg.id}:up"}
                  pressed={msg.rating == "up"}
                >
                  👍
                </:action>
                <:action
                  label="Bad answer"
                  on_click="rate"
                  value={"#{msg.id}:down"}
                  pressed={msg.rating == "down"}
                >
                  👎
                </:action>
              </.chat_action_bar>
            </:actions>
          </.chat_message>

          <:empty>
            <h1 class="text-2xl font-semibold">What can I help with?</h1>
            <.chat_suggestions
              on_select="suggest"
              class="grid w-full grid-cols-1 gap-2 sm:grid-cols-3"
              suggestion_class="flex flex-col items-start gap-0.5 rounded-xl border border-neutral-200 px-3 py-2 text-left hover:bg-neutral-50 dark:border-neutral-800 dark:hover:bg-neutral-900"
              title_class="text-sm font-medium"
              description_class="text-xs text-neutral-500"
            >
              <:suggestion
                :for={s <- Script.suggestions()}
                prompt={s.prompt}
                title={s.title}
                description={s.description}
              />
            </.chat_suggestions>
          </:empty>

          <:scroll_button>↓ Latest</:scroll_button>

          <:footer>
            <.chat_suggestions
              :if={@follow_ups != [] && @run == nil}
              on_select="suggest"
              label="Follow-ups"
              class="mb-2 flex flex-wrap gap-2"
              suggestion_class="rounded-full border border-neutral-200 px-3 py-1 text-xs hover:bg-neutral-50 dark:border-neutral-800 dark:hover:bg-neutral-900"
            >
              <:suggestion :for={s <- @follow_ups} prompt={s.prompt} />
            </.chat_suggestions>

            <.chat_composer
              id="chat-composer"
              on_submit="send"
              on_change="validate"
              on_cancel="stop"
              running={@run != nil}
              autofocus
              phx-drop-target={@uploads.files.ref}
              class="flex flex-col gap-2 rounded-2xl border border-neutral-200 bg-white px-3 py-2 shadow-sm dark:border-neutral-700 dark:bg-neutral-900"
              attachments_class="flex flex-wrap gap-2"
              input_class="w-full bg-transparent py-1 text-sm outline-none placeholder:text-neutral-400"
              actions_class="flex items-center justify-between gap-2"
              send_class="flex size-8 items-center justify-center rounded-full bg-neutral-900 text-white disabled:opacity-30 dark:bg-white dark:text-neutral-950"
              cancel_class="flex size-8 items-center justify-center rounded-full bg-neutral-900 text-white dark:bg-white dark:text-neutral-950"
            >
              <:attachments :if={@uploads.files.entries != []}>
                <.chat_attachment
                  :for={entry <- @uploads.files.entries}
                  name={entry.client_name}
                  size={entry.client_size}
                  type={entry.client_type}
                  status={if entry.done?, do: "complete", else: "uploading"}
                  progress={entry.progress}
                  on_remove="cancel_upload"
                  ref={entry.ref}
                  class="flex items-center gap-2 rounded-lg border border-neutral-200 px-2 py-1 text-xs dark:border-neutral-700"
                  meta_class="text-neutral-500"
                  progress_class="h-1 w-12"
                  remove_class="px-1 text-neutral-400 hover:text-neutral-950 dark:hover:text-white"
                />
              </:attachments>
              <:leading>
                <label class="cursor-pointer rounded-full px-2 py-1 text-sm text-neutral-500 hover:bg-neutral-100 dark:hover:bg-neutral-800">
                  <span class="sr-only">Attach files</span>
                  <span aria-hidden="true">＋</span>
                  <.live_file_input upload={@uploads.files} class="sr-only" />
                </label>
              </:leading>
              <:send>↑</:send>
              <:cancel>■</:cancel>
            </.chat_composer>
            <p class="mt-2 text-center text-[11px] text-neutral-400">
              A scripted demo model. Try "find a waffle cone supplier" or "delete the old build directory".
            </p>
          </:footer>
        </.chat_thread>
      </main>
    </div>
    """
  end
end
