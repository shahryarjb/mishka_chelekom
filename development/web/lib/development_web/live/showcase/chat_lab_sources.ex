defmodule DevelopmentWeb.Showcase.ChatLabSources do
  @moduledoc """
  Stand-ins for the three ways Elixir AI stacks deliver model output to a LiveView, used by
  `/showcase/chat/lab` to prove the chat components against each of them.

  Each source runs in its own process and talks to the LiveView through the same channel, with the
  same message shapes, as the real library — so the LiveView code in the lab is the code an app
  writes, only the producer is fake:

    * `ash_ai/3` — Ash AI's generated chat (`mix ash_ai.gen.chat`). An Oban job consumes
      `AshAi.ToolLoop.stream/2`, upserts the response message on every `{:content, chunk}` (the
      `:upsert_response` action appends to `text`), and `Ash.Notifier.PubSub` broadcasts the
      **whole message** as a `%Phoenix.Socket.Broadcast{}` on `"chat:messages:<conversation>"`.
      The LiveView re-inserts it with `stream_insert(:messages, message, at: 0)`.
    * `jido/3` — Jido AI signals (`Jido.AI.Signal.*`), dispatched to the LiveView pid (the
      `{:pid, target: pid}` dispatch of `%Directive.Emit{}`): `ai.request.started`,
      `ai.llm.delta` (`chunk_type: :thinking | :content`, with a monotonic `seq`),
      `ai.tool.started`, `ai.tool.result`, `ai.request.completed` / `ai.request.failed`. Jido's
      contract says delivery order is not guaranteed — order by `seq` — so this source can shuffle.
    * `req_llm/3` — `ReqLLM.stream_text/3` consumed in a `Task`, forwarding each
      `%ReqLLM.StreamChunk{type: :content | :thinking | :tool_call}` to the LiveView.

  Signals are plain maps `%{type: "ai.llm.delta", data: %{...}}`, so a LiveView clause matching
  `%{type: type, data: data}` handles the real `%Jido.Signal{}` struct unchanged.
  """

  @scale Application.compile_env(:development, :chat_demo_delay_scale, 1)

  @answer "Pistachio should lead the summer line. It grew 23% last month, its margin beats " <>
            "vanilla by 8 points, and it holds up in the heat of a scoop truck.\n\n" <>
            "Peach is the runner-up: stone fruit trends in the same range, and it pairs with " <>
            "the waffle cones you already stock."

  @thinking "The question is which flavor to launch. Recent sales matter most, then margin, " <>
              "then how the flavor survives a hot truck. Pistachio leads on all three."

  @doc "The answer every source streams — tests compare the rendered text against it."
  @spec answer() :: String.t()
  def answer, do: @answer

  @doc "The reasoning every source streams before the answer."
  @spec thinking() :: String.t()
  def thinking, do: @thinking

  @doc """
  Split text the way a model delivers it: `:token` (a word at a time) or `:burst` (a few words
  at once, like a provider flushing its buffer).
  """
  @spec chunks(text :: String.t(), chunking :: :token | :burst) :: [String.t()]
  def chunks(text, :token), do: Regex.split(~r/(?<=\s)/u, text, trim: true)

  def chunks(text, :burst) do
    text
    |> chunks(:token)
    |> Enum.chunk_every(5)
    |> Enum.map(&Enum.join/1)
  end

  # ── Ash AI ───────────────────────────────────────────────────────────────

  @doc """
  Run the Ash AI response job for `message` (the user's message) and broadcast every upsert of
  the agent's response on `topic`, like `Ash.Notifier.PubSub` does.
  """
  @spec ash_ai(topic :: String.t(), response :: map(), opts :: map()) :: {:ok, pid()}
  def ash_ai(topic, response, opts) do
    Task.start(fn ->
      tool_call = %{id: "call_1", name: "sales_report", arguments: %{"period" => "30d"}}
      result = %{tool_call_id: "call_1", content: "pistachio +23%", is_error: false}

      # The response row. Like `:upsert_response`, an upsert only changes what it is given (text
      # is appended while streaming), and the notifier broadcasts the whole row every time.
      row = Map.merge(response, %{text: "", complete: false, tool_calls: [], tool_results: []})

      upsert = fn row, changes ->
        row = Map.merge(row, changes)
        broadcast(topic, row)
        row
      end

      pause(opts, 300)
      row = upsert.(row, %{tool_calls: [tool_call]})
      pause(opts, 500)
      row = upsert.(row, %{tool_results: [result]})

      if opts.fail do
        pause(opts, 300)
        upsert.(row, %{complete: true, error: "The model provider timed out."})
      else
        row |> stream_rows(upsert, opts) |> upsert.(%{complete: true})
      end
    end)
  end

  # One upsert per chunk, each appending to the row's text.
  defp stream_rows(row, upsert, opts) do
    @answer
    |> chunks(opts.chunking)
    |> Enum.reduce(row, fn chunk, row ->
      pause(opts, 40)
      upsert.(row, %{text: row.text <> chunk})
    end)
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Development.PubSub, topic, %Phoenix.Socket.Broadcast{
      topic: topic,
      event: "upsert_response",
      payload: message
    })
  end

  # ── Jido AI ──────────────────────────────────────────────────────────────

  @doc "Emit the Jido AI signals of one request to `pid`."
  @spec jido(pid :: pid(), call_id :: String.t(), opts :: map()) :: {:ok, pid()}
  def jido(pid, call_id, opts) do
    Task.start(fn ->
      # One monotonic runtime counter across every event, like Jido's `Runtime.Event.seq`: the
      # content deltas' seqs therefore have gaps wherever thinking or tool events came between.
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      next_seq = fn -> Agent.get_and_update(counter, &{&1 + 1, &1 + 1}) end

      emit = fn type, data ->
        send(pid, %{type: type, data: Map.merge(data, %{call_id: call_id, seq: next_seq.()})})
      end

      emit.("ai.request.started", %{query: "Which flavor should we launch?"})

      @thinking
      |> chunks(:burst)
      |> Enum.each(fn delta ->
        pause(opts, 60)
        emit.("ai.llm.delta", %{delta: delta, chunk_type: :thinking})
      end)

      pause(opts, 200)

      emit.("ai.tool.started", %{
        tool_call_id: "tc_1",
        tool_name: "sales_report",
        arguments: %{"period" => "30d"}
      })

      pause(opts, 500)

      emit.("ai.tool.result", %{
        tool_call_id: "tc_1",
        tool_name: "sales_report",
        result: {:ok, %{"pistachio" => "+23%", "peach" => "+17%"}}
      })

      if opts.fail do
        pause(opts, 200)
        emit.("ai.request.failed", %{error: "The model provider timed out."})
      else
        # Seqs are taken in order, then delivery is shuffled: the same data, arriving the way two
        # PubSub nodes or a retried send can deliver it.
        next_seq
        |> content_deltas(opts)
        |> maybe_shuffle(opts.shuffle)
        |> Enum.each(&send_delta(pid, call_id, &1, opts))

        emit.("ai.request.completed", %{result: @answer})
      end

      Agent.stop(counter)
    end)
  end

  defp send_delta(pid, call_id, data, opts) do
    pause(opts, 40)
    send(pid, %{type: "ai.llm.delta", data: Map.put(data, :call_id, call_id)})
  end

  # A keepalive/checkpoint every few deltas takes a seq too: gaps inside the text, like a real run.
  defp content_deltas(next_seq, opts) do
    @answer
    |> chunks(opts.chunking)
    |> Enum.with_index()
    |> Enum.map(fn {delta, i} ->
      if rem(i, 4) == 3, do: next_seq.()
      %{delta: delta, chunk_type: :content, seq: next_seq.()}
    end)
  end

  # Swap neighbours in every window of three: the same deltas, delivered out of order the way two
  # PubSub nodes or a retried send can deliver them.
  defp maybe_shuffle(indexed, false), do: indexed

  defp maybe_shuffle(indexed, true) do
    indexed
    |> Enum.chunk_every(3)
    |> Enum.flat_map(fn
      [a, b, c] -> [b, a, c]
      short -> short
    end)
  end

  # ── ReqLLM ───────────────────────────────────────────────────────────────

  @doc """
  Consume a `ReqLLM.stream_text/3`-shaped stream in a task and forward each chunk to `pid` as
  `{:req_llm, ref, chunk}`, then `{:req_llm, ref, :done}`.
  """
  @spec req_llm(pid :: pid(), ref :: reference(), opts :: map()) :: {:ok, pid()}
  def req_llm(pid, ref, opts) do
    Task.start(fn ->
      opts
      |> stream_text()
      |> Enum.each(fn chunk ->
        pause(opts, 40)
        send(pid, {:req_llm, ref, chunk})
      end)

      send(
        pid,
        {:req_llm, ref, if(opts.fail, do: {:error, "The model provider timed out."}, else: :done)}
      )
    end)
  end

  # What `ReqLLM.StreamResponse.tokens/1` style consumers iterate: `%ReqLLM.StreamChunk{}`s.
  defp stream_text(opts) do
    thinking = for text <- chunks(@thinking, :burst), do: %{type: :thinking, text: text}

    tool = [
      %{type: :tool_call, name: "sales_report", arguments: %{"period" => "30d"}, text: nil}
    ]

    content =
      if opts.fail,
        do: [],
        else: for(text <- chunks(@answer, opts.chunking), do: %{type: :content, text: text})

    Stream.concat([thinking, tool, content])
  end

  defp pause(opts, ms) do
    factor = %{"slow" => 3, "normal" => 1, "fast" => 0.3}[opts.speed] || 1
    Process.sleep(round(ms * factor * @scale))
  end
end
