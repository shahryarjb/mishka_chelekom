defmodule DevelopmentWeb.ChatDemoLiveTest do
  @moduledoc """
  `/showcase/chat` end to end on the server: the chat components composed the way an app would,
  driven by the scripted model (config/test.exs runs it with zero delays).

  A run is asynchronous — thinking, a tool call, then streamed tokens arrive as messages to the
  LiveView — so assertions wait for the page to reach the state rather than assume timing.
  """
  use DevelopmentWeb.ConnCase
  import Phoenix.LiveViewTest

  @path "/showcase/chat"

  defp doc(html), do: LazyHTML.from_document(html)
  defp query(html, selector), do: html |> doc() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()

  # Polls the rendered page until `fun` holds (the pretend model is a chain of messages).
  defp eventually(view, fun, tries \\ 100) do
    html = render(view)

    cond do
      fun.(html) -> html
      tries == 0 -> flunk("the page never reached the expected state:\n" <> html)
      true -> Process.sleep(10) && eventually(view, fun, tries - 1)
    end
  end

  defp idle?(html), do: count(html, "#chat[data-running]") == 0

  defp send_message(view, text) do
    view |> element("#chat-composer") |> render_submit(%{"message" => text})
  end

  test "the seeded conversation renders as a busy-aware log inside a stream", %{conn: conn} do
    {:ok, _view, html} = live(conn, @path)

    assert query(html, "#chat") |> LazyHTML.attribute("phx-hook") == ["ChatThread"]
    assert query(html, "#chat-messages") |> LazyHTML.attribute("phx-update") == ["stream"]
    assert count(html, "[data-role=user]") == 1
    assert count(html, "[data-role=assistant][data-status=complete]") == 1
    # The newest answer keeps its actions visible (autohide="not_last").
    assert count(html, "[data-last][data-role=assistant] [data-autohide=not_last]") == 1

    assert query(html, "[data-part=item][data-active] [data-part=title]") |> LazyHTML.text() =~
             "Summer flavor launch"
  end

  test "a message runs through thinking, a tool call and a streamed answer", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    send_message(view, "Find a waffle cone supplier")

    # Tokens travel as pushes into chat_stream, not as re-renders of the growing text.
    assert_push_event(view, "chelekom:chat-stream", %{id: stream_id, delta: _})
    assert String.ends_with?(stream_id, "-stream")
    assert_push_event(view, "chelekom:chat-stream", %{id: ^stream_id, done: true}, 2_000)

    html = eventually(view, &idle?/1)

    assert count(html, "[data-role=user]") == 2
    answer = query(html, "[data-role=assistant][data-last]")
    assert LazyHTML.text(answer) =~ "Joy Cone is the safest pick"
    assert answer |> LazyHTML.query("[data-part=label]") |> LazyHTML.text() =~ "Thought for"
    assert answer |> LazyHTML.query("[data-part=root][data-tool=web_search]") |> Enum.count() == 1
    assert answer |> LazyHTML.query("[data-status=success]") |> Enum.count() >= 1
    assert answer |> LazyHTML.query(".chelekom-chat-sources__source") |> Enum.count() == 3
    # Follow-ups are offered once the answer is done.
    assert count(html, "[aria-label=Follow-ups] [data-part=suggestion]") == 2
  end

  test "stopping keeps what was streamed and ends the run", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    send_message(view, "Which flavor should we launch?")
    assert render(view) =~ ~s(data-running)

    view |> element("#chat-composer [data-part=cancel]") |> render_click()
    html = eventually(view, &idle?/1)

    assert count(html, "#chat-composer [data-part=send]") == 1
    assert count(html, "#chat-composer [data-part=cancel]") == 0
  end

  test "regenerate creates a second branch the picker can step back from", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    view
    |> element(~s([data-last] [data-part=action][aria-label=Regenerate]))
    |> render_click()

    html = eventually(view, &(idle?(&1) and &1 =~ "2 / 2"))
    assert count(html, "[data-last] [data-part=previous]:not([disabled])") == 1

    view |> element("[data-last] [data-part=previous]") |> render_click()
    html = render(view)
    assert html =~ "1 / 2"
    # Back on the first version: nothing before it, the regenerated one after it.
    assert query(html, "[data-last] [data-part=previous]") |> LazyHTML.attribute("disabled") == [
             ""
           ]

    assert query(html, "[data-last] [data-part=next]") |> LazyHTML.attribute("disabled") == []
  end

  test "feedback is a toggle", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    good = ~s([data-last] [data-part=action][aria-label="Good answer"])

    view |> element(good) |> render_click()
    assert query(render(view), good) |> LazyHTML.attribute("aria-pressed") == ["true"]

    view |> element(good) |> render_click()
    assert query(render(view), good) |> LazyHTML.attribute("aria-pressed") == ["false"]
  end

  test "a destructive request waits for approval, then finishes", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    send_message(view, "Delete the old build directory")
    html = eventually(view, &(count(&1, "form[data-part=root][data-status=pending]") == 1))
    assert count(html, "[data-tool=shell][data-status=awaiting_approval]") == 1
    refute idle?(html), "the run is paused on the human, not finished"

    view |> element(~s(form[data-part=root][data-status=pending])) |> render_submit(%{})
    html = eventually(view, &idle?/1)

    assert html =~ "build/ is gone"
    assert count(html, ~s(form[data-status=approved] fieldset[disabled])) == 1
  end

  test "denying finishes without running the tool", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    send_message(view, "Delete the old build directory")
    eventually(view, &(count(&1, "form[data-part=root][data-status=pending]") == 1))

    view |> element("[data-part=deny]") |> render_click()
    html = eventually(view, &idle?/1)

    assert html =~ "I left build/ untouched"
    assert count(html, "[data-tool=shell][data-status=cancelled]") == 1
  end

  test "reaching the top loads older history above the conversation", %{conn: conn} do
    {:ok, view, html} = live(conn, @path)
    assert query(html, "#chat") |> LazyHTML.attribute("data-on-top") == ["load_older"]

    html = render_hook(view, "load_older", %{})

    ids = html |> query("#chat-messages > [data-part=root]") |> LazyHTML.attribute("id")
    assert length(ids) == 6
    assert hd(ids) =~ "old-1", "older messages must be inserted before the current ones"
    assert query(html, "#chat") |> LazyHTML.attribute("data-on-top") == []
  end

  test "a new chat starts empty with starter suggestions that send", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    html = view |> element("[data-part=new]") |> render_click()
    assert count(html, "#chat-messages > *") == 0
    assert count(html, "[data-part=empty] [data-part=suggestion]") == 3

    view
    |> element(
      ~s([data-part=empty] [data-part=suggestion][data-prompt="Find a waffle cone supplier"])
    )
    |> render_click()

    html = eventually(view, &idle?/1)
    assert count(html, "[data-role=user]") == 1
    assert html =~ "Joy Cone"
  end

  test "switching and deleting conversations", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    html = view |> element(~s(button[data-part=link][phx-value-id="t-3"])) |> render_click()
    assert html =~ "freezer-log.csv"

    html = view |> element(~s([data-part=delete][phx-value-id="t-3"])) |> render_click()
    refute html =~ "Freezer capacity plan"
    assert count(html, "[data-part=empty] [data-part=suggestion]") == 3
  end
end
