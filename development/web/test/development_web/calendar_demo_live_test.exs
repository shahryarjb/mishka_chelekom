defmodule DevelopmentWeb.CalendarDemoLiveTest do
  use DevelopmentWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # The demo seeds its data around the real today, so the tests find their cells the same way.
  defp day(offset), do: Date.utc_today() |> Date.add(offset) |> Date.to_iso8601()

  test "every use case renders its calendar", %{conn: conn} do
    for {tab, id} <- [
          {"hotel", "hotel"},
          {"clinic", "clinic"},
          {"viewing", "viewing"},
          {"planner", "planner"}
        ] do
      {:ok, view, _html} = live(conn, "/showcase/calendar?tab=#{tab}")
      assert has_element?(view, "##{id}.chelekom-full-calendar[data-part=root]")
      # The calendar reported its range to the page on connect.
      assert view |> element("#calendar-log") |> render() =~ ":dates_set"
    end
  end

  test "a stay goes from two clicks to a saved booking", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/showcase/calendar?tab=hotel")

    # Room 101 is free from the morning Ms Karimi leaves (today + 5) until Mr Novak arrives (+ 8).
    # Show the month of the check-in first: near a month's end it may not be the current one.
    view |> element("#hotel") |> render_hook("nav", %{to: day(5)})
    view |> element("#hotel [data-part=day][data-start='#{day(5)}T00:00:00']") |> render_click()
    view |> element("#hotel [data-part=day][data-start='#{day(7)}T00:00:00']") |> render_click()

    assert view |> element("#pending") |> render() =~ "2 nights, $240"

    view |> element("#pending button", "Confirm") |> render_click()
    refute has_element?(view, "#pending")
    assert has_element?(view, "#hotel [data-part=event]", "Guest")
    # The nights just sold can no longer be picked.
    assert has_element?(
             view,
             "#hotel [data-part=day][data-start='#{day(5)}T00:00:00'][data-disabled]"
           )
  end

  test "the planner saves what the calendar reports when an event is dropped", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/showcase/calendar?tab=planner")
    monday = Date.utc_today() |> Date.beginning_of_week() |> Date.to_iso8601()
    tuesday = Date.utc_today() |> Date.beginning_of_week() |> Date.add(1) |> Date.to_iso8601()

    view |> element("#planner [data-part=view-button][data-view=week]") |> render_click()

    view
    |> element("#planner")
    |> render_hook("drop", %{
      key: "review",
      from: "#{tuesday}T14:00:00",
      to: "#{monday}T10:00:00",
      all_day: false
    })

    assert has_element?(view, "#planner [data-part=event][data-key=review]")
    assert view |> element("#planner [data-part=event][data-key=review]") |> render() =~ "10:00"
    assert view |> element("#calendar-log") |> render() =~ ":event_drop"
  end
end
