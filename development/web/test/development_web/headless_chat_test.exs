defmodule DevelopmentWeb.HeadlessChatTest do
  @moduledoc """
  The server-rendered contract of the headless AI-chat components.

  The hooks (stick-to-bottom scrolling, IME-safe sending, streamed text, copy) are verified in a
  browser; what has to hold here is everything the server alone decides — the state attributes a
  skin and the hooks key off, the accessibility wiring, and which controls exist in which state.
  """
  use DevelopmentWeb.ConnCase, async: true

  import DevelopmentWeb.HeadlessDOM
  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias DevelopmentWeb.Components.Headless.{
    ChatActionBar,
    ChatApproval,
    ChatAttachment,
    ChatBranchPicker,
    ChatComposer,
    ChatMessage,
    ChatReasoning,
    ChatSources,
    ChatStream,
    ChatSuggestions,
    ChatThread,
    ChatThreadList,
    ChatToolCall,
    ChatTypingIndicator
  }

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&String.trim(LazyHTML.text(&1)))

  describe "chat_thread" do
    test "the hook sits on the root, the messages are a log that is busy while running" do
      doc = doc(render_component(&ChatThread.chat_thread/1, id: "t", running: true, inner_block: []))

      assert attr(doc, "[data-part=root]", "phx-hook") == "ChatThread"
      assert attr(doc, "[data-part=messages]", "role") == "log"
      assert attr(doc, "[data-part=messages]", "id") == "t-messages"
      assert attr(doc, "[data-part=messages]", "aria-busy") == "true"
      assert has_attr?(doc, "[data-part=root]", "data-running")

      idle = doc(render_component(&ChatThread.chat_thread/1, id: "t", inner_block: []))
      assert attr(idle, "[data-part=messages]", "aria-busy") == "false"
      refute has_attr?(idle, "[data-part=root]", "data-running")
    end

    test "stream mode, the top event and a scroll button that starts hidden and labelled" do
      doc =
        doc(
          render_component(&ChatThread.chat_thread/1,
            id: "t",
            stream: true,
            on_top: "older",
            inner_block: []
          )
        )

      assert attr(doc, "[data-part=messages]", "phx-update") == "stream"
      assert attr(doc, "[data-part=root]", "data-on-top") == "older"
      assert has_attr?(doc, "[data-part=scroll-button]", "hidden")
      assert attr(doc, "[data-part=scroll-button]", "aria-label") == "Scroll to latest"
      assert attr(doc, "[data-part=viewport]", "tabindex") == "0"
    end
  end

  describe "chat_message" do
    defp message(assigns) do
      ~H"""
      <ChatMessage.chat_message {@attrs}>
        Hello
        <:error :if={@error}>It broke</:error>
      </ChatMessage.chat_message>
      """
    end

    defp render_message(attrs, error \\ false),
      do: doc(render_component(&message/1, attrs: attrs, error: error))

    test "role and status are exposed, and the accessible name names the author" do
      doc = render_message(%{role: "user", name: "Ada"})

      assert attr(doc, "[data-part=root]", "data-role") == "user"
      assert attr(doc, "[data-part=root]", "data-status") == "complete"
      assert attr(doc, "[data-part=root]", "role") == "article"
      assert attr(doc, "[data-part=root]", "aria-label") == "Ada message"
      assert attr(render_message(%{}), "[data-part=root]", "aria-label") == "Assistant message"
    end

    test "streaming is busy and shows the caret; complete is neither" do
      streaming = render_message(%{status: "streaming"})
      assert attr(streaming, "[data-part=root]", "aria-busy") == "true"
      assert has_attr?(streaming, "[data-part=caret]", "aria-hidden")

      done = render_message(%{})
      assert attr(done, "[data-part=root]", "aria-busy") == "false"
      refute has_attr?(done, "[data-part=caret]", "data-part")
    end

    test "the error slot is an alert, rendered only for a failed message" do
      assert attr(render_message(%{status: "error"}, true), "[data-part=error]", "role") == "alert"
      refute has_attr?(render_message(%{}, true), "[data-part=error]", "role")
    end

    test "the timestamp is machine-readable and shown as HH:MM" do
      doc = render_message(%{timestamp: ~N[2026-09-24 09:05:00]})

      assert attr(doc, "time[data-part=time]", "datetime") == "2026-09-24T09:05:00"
      assert texts(doc, "[data-part=time]") == ["09:05"]
    end
  end

  describe "chat_stream" do
    test "the hook owns an ignored text part and knows the id pushes target" do
      doc = doc(render_component(&ChatStream.chat_stream/1, id: "a", text: "Hi", smooth: true))

      assert attr(doc, "[data-part=text]", "phx-hook") == "ChatStream"
      assert attr(doc, "[data-part=text]", "phx-update") == "ignore"
      assert attr(doc, "[data-part=text]", "id") == "a-text"
      assert attr(doc, "[data-part=text]", "data-root-id") == "a"
      assert attr(doc, "[data-part=text]", "data-text") == "Hi"
      assert has_attr?(doc, "[data-part=text]", "data-smooth")
      assert has_attr?(doc, "[data-part=caret]", "aria-hidden")
    end

    test "a finished stream is marked done and drops its caret" do
      doc = doc(render_component(&ChatStream.chat_stream/1, id: "a", text: "Hi", done: true))

      assert has_attr?(doc, "[data-part=root]", "data-done")
      refute has_attr?(doc, "[data-part=caret]", "data-part")
    end
  end

  describe "chat_composer" do
    defp composer(attrs), do: doc(render_component(&ChatComposer.chat_composer/1, attrs))

    test "a form with the hook, a labelled textarea and a send button disabled while blank" do
      doc = composer(id: "c", on_submit: "send")

      assert tag(doc, "[data-part=root]") == "form"
      assert attr(doc, "[data-part=root]", "phx-hook") == "ChatComposer"
      assert attr(doc, "[data-part=root]", "phx-submit") == "send"
      assert attr(doc, "[data-part=root]", "data-submit-mode") == "enter"
      assert attr(doc, "[data-part=input]", "name") == "message"
      assert attr(doc, "[data-part=input]", "aria-label") == "Message"
      assert attr(doc, "[data-part=send]", "type") == "submit"
      assert has_attr?(doc, "[data-part=send]", "disabled")
      refute has_attr?(composer(id: "c", value: "hi"), "[data-part=send]", "disabled")
    end

    test "while running the stop button replaces send, and Escape knows the same event" do
      doc = composer(id: "c", running: true, on_cancel: "stop")

      assert attr(doc, "[data-part=cancel]", "phx-click") == "stop"
      assert attr(doc, "[data-part=root]", "data-on-cancel") == "stop"
      refute has_attr?(doc, "[data-part=send]", "data-part")

      # Without a stop event there is nothing to stop with: send stays, disabled.
      assert has_attr?(composer(id: "c", running: true, value: "x"), "[data-part=send]", "disabled")
    end
  end

  describe "chat_action_bar" do
    defp bar(assigns) do
      ~H"""
      <ChatActionBar.chat_action_bar id={@id} copy={@copy}>
        <:action label="Retry" on_click="retry" value="m1" />
        <:action label="Good" on_click="rate" value="up" pressed={true} />
      </ChatActionBar.chat_action_bar>
      """
    end

    test "copying needs an id and text: only then does the hook and the copy button exist" do
      doc = doc(render_component(&bar/1, id: "b", copy: "text"))

      assert attr(doc, "[data-part=root]", "phx-hook") == "ChatActionBar"
      assert attr(doc, "[data-part=root]", "data-copy-text") == "text"
      assert attr(doc, "[data-part=copy]", "aria-label") == "Copy"
      assert attr(doc, "[data-part=copy-status]", "role") == "status"

      bare = doc(render_component(&bar/1, id: nil, copy: "text"))
      refute has_attr?(bare, "[data-part=root]", "phx-hook")
      refute has_attr?(bare, "[data-part=copy]", "data-part")
    end

    test "actions send their event; only toggles carry aria-pressed" do
      doc = doc(render_component(&bar/1, id: "b", copy: nil))

      assert LazyHTML.attribute(LazyHTML.query(doc, "[data-part=action]"), "phx-click") ==
               ["retry", "rate"]

      assert LazyHTML.attribute(LazyHTML.query(doc, "[data-part=action]"), "aria-pressed") ==
               ["true"]
    end
  end

  describe "chat_branch_picker" do
    defp picker(attrs), do: doc(render_component(&ChatBranchPicker.chat_branch_picker/1, attrs))

    test "renders nothing for a single version" do
      refute has_attr?(picker(index: 1, count: 1), "[data-part=root]", "data-part")
      assert has_attr?(picker(index: 1, count: 1, always: true), "[data-part=root]", "data-part")
    end

    test "the ends disable their button and the position reads n / count" do
      first = picker(index: 1, count: 3)
      assert has_attr?(first, "[data-part=previous]", "disabled")
      refute has_attr?(first, "[data-part=next]", "disabled")
      assert texts(first, "[data-part=status]") == ["1 / 3"]

      last = picker(index: 3, count: 3)
      refute has_attr?(last, "[data-part=previous]", "disabled")
      assert has_attr?(last, "[data-part=next]", "disabled")
    end
  end

  describe "chat_reasoning" do
    defp reasoning(assigns) do
      ~H"""
      <ChatReasoning.chat_reasoning id="r" status={@status} duration={@duration}>
        <:step label="Search" status="done" />
        <:step label="Read joycone.com" href="https://joycone.com" status="active" />
      </ChatReasoning.chat_reasoning>
      """
    end

    test "a native disclosure with the hook, open and busy while streaming" do
      doc = doc(render_component(&reasoning/1, status: "streaming", duration: nil))

      assert tag(doc, "[data-part=root]") == "details"
      assert attr(doc, "[data-part=root]", "phx-hook") == "ChatReasoning"
      assert has_attr?(doc, "[data-part=root]", "open")
      assert attr(doc, "[data-part=root]", "aria-busy") == "true"
      assert texts(doc, "[data-part=label]") == ["Thinking"]
    end

    test "done reads how long it took" do
      assert texts(doc(render_component(&reasoning/1, status: "done", duration: 4)), "[data-part=label]") ==
               ["Thought for 4 seconds"]

      assert texts(doc(render_component(&reasoning/1, status: "done", duration: 1)), "[data-part=label]") ==
               ["Thought for 1 second"]

      assert texts(doc(render_component(&reasoning/1, status: "done", duration: nil)), "[data-part=label]") ==
               ["Thought"]
    end

    test "the active step is the current one, and a step with href is an external link" do
      doc = doc(render_component(&reasoning/1, status: "streaming", duration: nil))

      assert attr(doc, "[data-part=step][data-status=active]", "aria-current") == "step"
      assert attr(doc, "a[data-part=step-label]", "href") == "https://joycone.com"
      assert attr(doc, "a[data-part=step-label]", "rel") == "noopener noreferrer"
    end
  end

  describe "chat_tool_call" do
    defp tool(attrs),
      do: doc(render_component(&ChatToolCall.chat_tool_call/1, Keyword.put_new(attrs, :name, "web_search")))

    test "status is an attribute and a word, and running is busy" do
      doc = tool(status: "running")

      assert attr(doc, "[data-part=root]", "data-status") == "running"
      assert attr(doc, "[data-part=root]", "aria-busy") == "true"
      assert texts(doc, "[data-part=status]") == ["Running"]
      assert texts(tool(status: "awaiting_approval"), "[data-part=status]") == ["Waiting for approval"]
      assert texts(tool(status: "success", status_labels: %{"success" => "Ok"}), "[data-part=status]") == ["Ok"]
    end

    test "arguments render as JSON, and a short duration in milliseconds" do
      doc = tool(status: "success", args: %{"query" => "cones"}, output: "3 results", duration: 320)

      assert [args] = texts(doc, "[data-part=args] code")
      assert Jason.decode!(args) == %{"query" => "cones"}
      assert texts(doc, "[data-part=result] code") == ["3 results"]
      assert texts(doc, "[data-part=duration]") == ["320 ms"]
      assert texts(tool(duration: 1_450), "[data-part=duration]") == ["1.5 s"]
    end
  end

  describe "chat_approval" do
    defp approval(assigns) do
      ~H"""
      <ChatApproval.chat_approval id="q" title="Pick" multiple={@multiple} status={@status} on_deny="skip">
        <:option :for={value <- @options} value={value} label={value} />
      </ChatApproval.chat_approval>
      """
    end

    defp render_approval(opts),
      do: doc(render_component(&approval/1, Enum.into(opts, %{multiple: false, status: "pending", options: ~w(a b)})))

    test "options are native radios named after the field, checkboxes post a list" do
      radios = render_approval([])
      assert LazyHTML.attribute(LazyHTML.query(radios, "[data-part=option-input]"), "type") == ["radio", "radio"]
      assert attr(radios, "[data-part=option-input]", "name") == "approval"
      assert texts(radios, "legend[data-part=title]") == ["Pick"]

      checks = render_approval(multiple: true)
      assert attr(checks, "[data-part=option-input]", "type") == "checkbox"
      assert attr(checks, "[data-part=option-input]", "name") == "approval[]"
    end

    test "labels follow the shape: continue/skip with options, approve/deny without" do
      assert texts(render_approval([]), "[data-part=approve]") == ["Continue"]
      assert texts(render_approval([]), "[data-part=deny]") == ["Skip"]
      assert texts(render_approval(options: []), "[data-part=approve]") == ["Approve"]
      assert texts(render_approval(options: []), "[data-part=deny]") == ["Deny"]
    end

    test "a decision disables the fieldset so the choice stays visible but fixed" do
      refute has_attr?(render_approval([]), "[data-part=fieldset]", "disabled")
      assert has_attr?(render_approval(status: "approved"), "[data-part=fieldset]", "disabled")
    end
  end

  describe "chat_suggestions" do
    defp suggestions(assigns) do
      ~H"""
      <ChatSuggestions.chat_suggestions on_select="pick">
        <:suggestion prompt="Explain quantum computing" />
        <:suggestion prompt="Plan a trip to Tokyo" title="Tokyo trip" description="5 days" />
      </ChatSuggestions.chat_suggestions>
      """
    end

    test "each suggestion sends its prompt; the title falls back to the prompt" do
      doc = doc(render_component(&suggestions/1, %{}))

      assert LazyHTML.attribute(LazyHTML.query(doc, "[data-part=suggestion]"), "phx-value-prompt") ==
               ["Explain quantum computing", "Plan a trip to Tokyo"]

      assert attr(doc, "[data-part=suggestion]", "phx-click") == "pick"
      assert texts(doc, "[data-part=title]") == ["Explain quantum computing", "Tokyo trip"]
      assert texts(doc, "[data-part=description]") == ["5 days"]
    end
  end

  describe "chat_attachment" do
    defp file(attrs), do: doc(render_component(&ChatAttachment.chat_attachment/1, attrs))

    test "the kind comes from the MIME type or the extension, the size is human" do
      assert attr(file(name: "a.png", type: "image/png"), "[data-part=root]", "data-kind") == "image"
      assert attr(file(name: "report.pdf"), "[data-part=root]", "data-kind") == "pdf"
      assert attr(file(name: "notes.MD"), "[data-part=root]", "data-kind") == "document"
      assert attr(file(name: "blob.xyz"), "[data-part=root]", "data-kind") == "file"
      assert texts(file(name: "a", size: 482_133), "[data-part=meta]") == ["470.8 KB"]
      assert texts(file(name: "a", size: 512), "[data-part=meta]") == ["512 B"]
    end

    test "progress only while uploading, and remove is labelled with the file name" do
      uploading = file(name: "q.xlsx", status: "uploading", progress: 64, on_remove: "rm", ref: "3")

      assert attr(uploading, "progress[data-part=progress]", "value") == "64"
      assert attr(uploading, "[data-part=root]", "aria-busy") == "true"
      assert attr(uploading, "[data-part=remove]", "aria-label") == "Remove q.xlsx"
      assert attr(uploading, "[data-part=remove]", "phx-value-ref") == "3"
      refute has_attr?(file(name: "q.xlsx", progress: 64), "[data-part=progress]", "data-part")
    end
  end

  describe "chat_sources" do
    defp sources(assigns) do
      ~H"""
      <ChatSources.chat_sources>
        <:source href="https://www.joycone.com/cones" title="Joy Cone" />
        <:source href="https://thekonery.com/" />
      </ChatSources.chat_sources>
      """
    end

    test "numbered, external, with the domain derived from the link" do
      doc = doc(render_component(&sources/1, %{}))

      assert texts(doc, "[data-part=index]") == ["1", "2"]
      assert texts(doc, "[data-part=domain]") == ["joycone.com", "thekonery.com"]
      assert texts(doc, "[data-part=title]") == ["Joy Cone", "thekonery.com"]
      assert attr(doc, "[data-part=link]", "target") == "_blank"
      assert attr(doc, "[data-part=root]", "aria-label") == "Sources"
    end
  end

  describe "chat_typing_indicator" do
    test "a polite status with hidden, indexed dots" do
      doc = doc(render_component(&ChatTypingIndicator.chat_typing_indicator/1, dots: 3))

      assert attr(doc, "[data-part=root]", "role") == "status"
      assert LazyHTML.attribute(LazyHTML.query(doc, "[data-part=dot]"), "data-index") == ~w(1 2 3)
      assert texts(doc, "[data-part=label]") == ["Assistant is typing"]
      assert attr(doc, "[data-part=label]", "class") =~ "chelekom-sr-only"

      none = doc(render_component(&ChatTypingIndicator.chat_typing_indicator/1, dots: 0))
      assert LazyHTML.query(none, "[data-part=dot]") |> Enum.count() == 0
    end
  end

  describe "chat_thread_list" do
    defp threads(assigns) do
      ~H"""
      <ChatThreadList.chat_thread_list on_select="open" on_delete="del" on_new="new">
        <:thread id="t1" title="Launch" href="/chat/t1" active />
        <:thread id="t2" title="Cones" />
      </ChatThreadList.chat_thread_list>
      """
    end

    test "linked threads are links, the rest buttons; the current one is aria-current" do
      doc = doc(render_component(&threads/1, %{}))

      assert attr(doc, "a[data-part=link]", "href") == "/chat/t1"
      assert attr(doc, "a[data-part=link]", "aria-current") == "page"
      assert attr(doc, "button[data-part=link]", "phx-value-id") == "t2"
      assert has_attr?(doc, "[data-part=item][data-active]", "data-part")
      assert attr(doc, "[data-part=new]", "phx-click") == "new"

      assert LazyHTML.attribute(LazyHTML.query(doc, "[data-part=delete]"), "aria-label") ==
               ["Delete Launch", "Delete Cones"]
    end
  end
end
