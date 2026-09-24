defmodule DevelopmentWeb.ChatLabLiveTest do
  @moduledoc """
  `/showcase/chat/lab`: the chat components fed the way Ash AI, Jido AI and ReqLLM feed a
  LiveView. The producers run in their own processes (PubSub broadcasts, signals to the pid, a
  task forwarding stream chunks), so these tests exercise the real lifecycle — `handle_info/2`,
  `stream_insert/4`, `push_event/3` — not a shortcut around it.
  """
  use DevelopmentWeb.ConnCase
  import Phoenix.LiveViewTest

  alias DevelopmentWeb.Showcase.ChatLabSources, as: Sources

  @path "/showcase/chat/lab"

  defp query(html, selector), do: html |> LazyHTML.from_document() |> LazyHTML.query(selector)

  defp configure(view, params) do
    view
    |> form(
      "#lab-config",
      Map.merge(
        %{"speed" => "fast", "chunking" => "token", "shuffle" => "false", "fail" => "false"},
        params
      )
    )
    |> render_change()
  end

  defp ask(view),
    do: view |> element("#lab-composer") |> render_submit(%{"message" => "Which flavor?"})

  # Every chelekom:chat-stream push until the one that says done.
  defp pushes(view, acc \\ []) do
    assert_push_event(view, "chelekom:chat-stream", payload, 2_000)
    if payload[:done], do: Enum.reverse(acc), else: pushes(view, [payload | acc])
  end

  defp eventually(view, fun, tries \\ 200) do
    html = render(view)

    cond do
      fun.(html) -> html
      tries == 0 -> flunk("never reached the expected state:\n" <> html)
      true -> Process.sleep(10) && eventually(view, fun, tries - 1)
    end
  end

  defp idle?(html), do: query(html, "#lab[data-running]") |> Enum.count() == 0

  test "Ash AI: the whole message is re-broadcast and re-inserted at the top of a reversed list",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    configure(view, %{"source" => "ash_ai"})
    ask(view)

    html = eventually(view, &(idle?(&1) and &1 =~ "data-done"))

    # Newest first in the DOM (at: 0); flex-col-reverse shows it last.
    roles = html |> query("#lab-messages > [data-part=root]") |> LazyHTML.attribute("data-role")
    assert roles == ["assistant", "user"]

    assert query(html, "#lab-messages") |> LazyHTML.attribute("class") |> hd() =~
             "flex-col-reverse"

    # Re-render mode: the final text is the attribute the hook appends from.
    assert query(html, "[data-part=text]") |> LazyHTML.attribute("data-text") == [
             Sources.answer()
           ]

    assert query(html, "[data-tool=sales_report][data-status=success]") |> Enum.count() == 1
  end

  test "Jido AI: out-of-order deltas carry seq, and seq order rebuilds the exact answer",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    configure(view, %{"source" => "jido", "shuffle" => "true"})
    ask(view)

    deltas = pushes(view)
    seqs = Enum.map(deltas, & &1.seq)

    assert seqs != Enum.sort(seqs), "the source was asked to deliver out of order"
    assert deltas |> Enum.sort_by(& &1.seq) |> Enum.map_join(& &1.delta) == Sources.answer()

    html = eventually(view, &idle?/1)

    assert query(html, "[data-part=root][data-status=done] [data-part=label]") |> LazyHTML.text() =~
             "Thought"

    assert html =~ Sources.thinking() |> String.split(".") |> hd()
    assert query(html, "[data-tool=sales_report][data-status=success]") |> Enum.count() == 1
  end

  test "ReqLLM: stream chunks become deltas in arrival order", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    configure(view, %{"source" => "req_llm", "chunking" => "burst"})
    ask(view)

    assert view |> pushes() |> Enum.map_join(& &1.delta) == Sources.answer()
    html = eventually(view, &idle?/1)
    assert query(html, "[data-role=assistant][data-status=complete]") |> Enum.count() == 1
  end

  test "a failed request ends the run with an alert, for every source", %{conn: conn} do
    for source <- ~w(ash_ai jido req_llm) do
      {:ok, view, _html} = live(conn, @path)
      configure(view, %{"source" => source, "fail" => "true"})
      ask(view)

      html = eventually(view, &idle?/1)

      assert query(html, "[data-status=error] [data-part=error]") |> LazyHTML.text() =~
               "timed out",
             "#{source} did not surface the failure"
    end
  end

  test "the wire counter shows re-rendering costs more than deltas for the same answer", %{
    conn: conn
  } do
    wire = fn source ->
      {:ok, view, _html} = live(conn, @path)
      configure(view, %{"source" => source})
      ask(view)
      html = eventually(view, &idle?/1)
      [bytes] = html |> query("#lab-stats strong") |> Enum.map(&LazyHTML.text/1) |> tl()
      String.to_integer(bytes)
    end

    assert wire.("ash_ai") > 5 * wire.("req_llm")
  end
end
