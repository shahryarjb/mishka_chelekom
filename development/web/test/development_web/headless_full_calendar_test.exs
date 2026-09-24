defmodule DevelopmentWeb.HeadlessFullCalendarTest.Host do
  @moduledoc false
  # A real parent LiveView: it renders the calendar from its assigns, relays every message the
  # calendar sends to the test process, and can change its attrs mid-test the way a page would.
  use Phoenix.LiveView

  alias DevelopmentWeb.Components.Headless.FullCalendar

  import FullCalendar, only: [full_calendar: 1]

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign(socket, test: session["test"], attrs: session["attrs"])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.full_calendar id="cal" {@attrs} />
    """
  end

  @impl true
  def handle_info({FullCalendar, id, name, payload}, socket) do
    send(socket.assigns.test, {:calendar, id, name, payload})
    {:noreply, socket}
  end

  def handle_info({:attrs, attrs}, socket) do
    {:noreply, assign(socket, :attrs, Map.merge(socket.assigns.attrs, attrs))}
  end

  def handle_info(:clear_selection, socket) do
    FullCalendar.clear_selection("cal")
    {:noreply, socket}
  end
end

defmodule DevelopmentWeb.HeadlessFullCalendarTest do
  use DevelopmentWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DevelopmentWeb.Components.Headless.FullCalendar
  alias DevelopmentWeb.HeadlessFullCalendarTest.Host

  # Wednesday 11 March 2026, mid-morning — every test sees the same "now".
  @now ~N[2026-03-11 10:00:00]

  defp mount_calendar(conn, attrs) do
    attrs = Map.merge(%{now: @now}, Map.new(attrs))
    {:ok, view, html} = live_isolated(conn, Host, session: %{"test" => self(), "attrs" => attrs})
    {view, html}
  end

  defp opts(given \\ %{}), do: FullCalendar.options(Map.merge(%{now: @now}, Map.new(given)))

  defp ctx(given, events \\ []) do
    opts = opts(given)
    occurrences = FullCalendar.occurrences(events, {~D[2026-02-01], ~D[2026-05-01]}, opts)
    %{opts: opts, now: @now, today: ~D[2026-03-11], occurrences: occurrences}
  end

  defp day(date),
    do: %{
      start: NaiveDateTime.new!(date, ~T[00:00:00]),
      end: NaiveDateTime.new!(Date.add(date, 1), ~T[00:00:00]),
      all_day: true,
      resource_id: nil
    }

  defp stay(from, to), do: %{day(from) | end: NaiveDateTime.new!(to, ~T[00:00:00])}

  defp slot(time, minutes, resource) do
    %{
      start: time,
      end: NaiveDateTime.add(time, minutes * 60),
      all_day: false,
      resource_id: resource
    }
  end

  defp event(id, start, finish, extra \\ %{}) do
    Map.merge(%{id: id, title: "Event #{id}", start: start, end: finish}, extra)
  end

  describe "the month grid" do
    test "starts on the configured weekday and always shows six weeks" do
      weeks = FullCalendar.weeks(~D[2026-03-11], opts())

      assert length(weeks) == 6
      assert Enum.all?(weeks, &(length(&1) == 7))
      # 1 March 2026 is a Sunday, so a Monday-first grid opens on the Monday before.
      assert weeks |> hd() |> hd() == ~D[2026-02-23]

      sunday_first = FullCalendar.weeks(~D[2026-03-11], opts(first_day_of_week: 7))
      assert sunday_first |> hd() |> hd() == ~D[2026-03-01]
    end

    test "sizes itself to the month without fixed weeks, and drops hidden weekdays" do
      # February 2027 starts on a Monday and has 28 days: exactly four rows.
      assert length(FullCalendar.weeks(~D[2027-02-10], opts(fixed_weeks: false))) == 4

      workweek = FullCalendar.weeks(~D[2026-03-11], opts(hidden_weekdays: [6, 7]))
      assert Enum.all?(workweek, &(length(&1) == 5))
      refute Enum.any?(List.flatten(workweek), &(Date.day_of_week(&1) in [6, 7]))
    end

    test "every view knows its visible range" do
      o = opts()

      assert FullCalendar.visible_range("week", ~D[2026-03-11], o) ==
               {~D[2026-03-09], ~D[2026-03-16]}

      assert FullCalendar.visible_range("day", ~D[2026-03-11], o) ==
               {~D[2026-03-11], ~D[2026-03-12]}

      assert FullCalendar.visible_range("month", ~D[2026-03-11], o) ==
               {~D[2026-02-23], ~D[2026-04-06]}

      assert FullCalendar.visible_range("timeline", ~D[2026-03-11], o) ==
               {~D[2026-03-09], ~D[2026-03-23]}
    end
  end

  describe "recurring events" do
    test "an RRULE string and the equivalent map expand to the same occurrences" do
      rule = "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4"
      map = %{freq: :weekly, by_day: [1, 3], count: 4}

      for recurrence <- [rule, map] do
        occurrences =
          FullCalendar.occurrences(
            [
              event("standup", ~N[2026-03-02 10:00:00], ~N[2026-03-02 10:15:00], %{
                recurrence: recurrence
              })
            ],
            {~D[2026-03-09], ~D[2026-03-16]},
            opts()
          )

        # COUNT counts from the first occurrence (2 and 4 March), not from the visible range.
        assert Enum.map(occurrences, & &1.start) == [
                 ~N[2026-03-09 10:00:00],
                 ~N[2026-03-11 10:00:00]
               ]

        assert Enum.map(occurrences, & &1.key) == [
                 "standup@2026-03-09T10:00:00",
                 "standup@2026-03-11T10:00:00"
               ]

        assert Enum.all?(occurrences, &(&1.end == NaiveDateTime.add(&1.start, 15 * 60)))
      end
    end

    test "UNTIL, INTERVAL and exdates bound the series; months without the day are skipped" do
      daily = %{freq: "daily", interval: 2, until: "20260310", exdates: [~D[2026-03-05]]}

      starts =
        [event("d", ~D[2026-03-01], nil, %{recurrence: daily})]
        |> FullCalendar.occurrences({~D[2026-03-01], ~D[2026-04-01]}, opts())
        |> Enum.map(&NaiveDateTime.to_date(&1.start))

      assert starts == [~D[2026-03-01], ~D[2026-03-03], ~D[2026-03-07], ~D[2026-03-09]]

      monthly =
        [event("m", ~D[2026-01-31], nil, %{recurrence: "FREQ=MONTHLY;COUNT=3"})]
        |> FullCalendar.occurrences({~D[2026-01-01], ~D[2026-12-31]}, opts())
        |> Enum.map(&NaiveDateTime.to_date(&1.start))

      assert monthly == [~D[2026-01-31], ~D[2026-03-31], ~D[2026-05-31]]
    end
  end

  describe "layout" do
    defp occ(id, from, to),
      do:
        FullCalendar.occurrences([event(id, from, to)], {~D[2026-01-01], ~D[2027-01-01]}, opts())

    test "day rows pack bars into the first level they fit and count what overflows" do
      events =
        occ("a", ~D[2026-03-09], ~D[2026-03-12]) ++
          occ("b", ~D[2026-03-10], ~D[2026-03-11]) ++ occ("c", ~D[2026-03-10], ~D[2026-03-13])

      columns = for d <- 9..15, do: %{date: Date.new!(2026, 3, d), resource_id: nil}
      row = FullCalendar.day_row(columns, events, nil)
      levels = Map.new(row.segments, &{&1.event.id, {&1.col, &1.span, &1.level}})

      assert levels == %{"a" => {0, 3, 0}, "c" => {1, 3, 1}, "b" => {1, 1, 2}}
      assert row.levels == 3

      capped = FullCalendar.day_row(columns, events, 2)
      assert Enum.map(capped.segments, & &1.event.id) |> Enum.sort() == ["a", "c"]
      assert capped.more == %{1 => 1}
    end

    test "a bar that crosses the week edge is cut and flagged on the right side" do
      events = occ("trip", ~D[2026-03-13], ~D[2026-03-18])
      this_week = for d <- 9..15, do: %{date: Date.new!(2026, 3, d), resource_id: nil}
      next_week = for d <- 16..22, do: %{date: Date.new!(2026, 3, d), resource_id: nil}

      [first] = FullCalendar.day_row(this_week, events, nil).segments
      [second] = FullCalendar.day_row(next_week, events, nil).segments

      assert {first.col, first.span, first.starts, first.ends} == {4, 3, true, false}
      assert {second.col, second.span, second.starts, second.ends} == {0, 2, false, true}
    end

    test "overlapping timed events share the column and widen into free space" do
      placed =
        (occ("a", ~N[2026-03-11 09:00:00], ~N[2026-03-11 11:00:00]) ++
           occ("b", ~N[2026-03-11 09:30:00], ~N[2026-03-11 10:00:00]) ++
           occ("c", ~N[2026-03-11 10:30:00], ~N[2026-03-11 11:30:00]) ++
           occ("d", ~N[2026-03-11 12:00:00], ~N[2026-03-11 13:00:00]))
        |> FullCalendar.time_layout()
        |> Map.new(&{&1.id, {&1.left, &1.width}})

      assert placed == %{
               "a" => {0.0, 0.5},
               "b" => {0.5, 0.5},
               "c" => {0.5, 0.5},
               "d" => {0.0, 1.0}
             }
    end
  end

  describe "booking rules" do
    test "presets fill in defaults and explicit options win" do
      hotel = opts(preset: "hotel")

      assert {hotel.selectable, hotel.range_end, hotel.select_overlap} ==
               {"range", "checkout", false}

      doctor = opts(preset: "doctor", slot_duration: 20)

      assert {doctor.view, doctor.slot_duration, doctor.hours} ==
               {"resource_day", 20, {480, 1080}}
    end

    test "stays: nights, overlap with half-open bookings, and check-in/out-only days" do
      booked = [event("guest", ~D[2026-03-14], ~D[2026-03-16])]
      hotel = ctx(%{preset: "hotel", min_nights: 2}, booked)

      assert FullCalendar.check(stay(~D[2026-03-12], ~D[2026-03-13]), hotel, edge: :range) ==
               {:error, {:min_nights, 2}}

      # Leaving on the morning the next guest arrives is not an overlap.
      assert FullCalendar.check(stay(~D[2026-03-12], ~D[2026-03-14]), hotel, edge: :range) == :ok

      assert FullCalendar.check(stay(~D[2026-03-12], ~D[2026-03-15]), hotel, edge: :range) ==
               {:error, :overlap}

      assert FullCalendar.check(day(~D[2026-03-10]), hotel, edge: :start) == {:error, :past}

      info = %{
        ~D[2026-03-20] => %{status: "check_in_only"},
        ~D[2026-03-22] => %{status: "check_out_only"}
      }

      hotel = ctx(%{preset: "hotel", day_info: info})

      assert FullCalendar.check(stay(~D[2026-03-18], ~D[2026-03-20]), hotel, edge: :range) ==
               {:error, :no_check_out}

      assert FullCalendar.check(day(~D[2026-03-22]), hotel, edge: :start) ==
               {:error, :no_check_in}

      assert FullCalendar.check(stay(~D[2026-03-20], ~D[2026-03-22]), hotel, edge: :range) == :ok
    end

    test "appointments: business hours, per-resource hours, notice and bounds" do
      resources = [
        %{id: "ali", title: "Dr Ali", business_hours: %{days: [3], hours: 13..15}},
        %{id: "sara", title: "Dr Sara"}
      ]

      doctor = ctx(%{preset: "doctor", resources: resources, min_notice: 60, max: ~D[2026-03-31]})

      assert FullCalendar.check(slot(~N[2026-03-12 08:00:00], 15, "sara"), doctor) ==
               {:error, :outside_hours}

      assert FullCalendar.check(slot(~N[2026-03-12 09:00:00], 15, "sara"), doctor) == :ok
      # Dr Ali only works Wednesday afternoons.
      assert FullCalendar.check(slot(~N[2026-03-12 09:00:00], 15, "ali"), doctor) ==
               {:error, :outside_hours}

      assert FullCalendar.check(slot(~N[2026-03-18 13:00:00], 15, "ali"), doctor) == :ok
      # An hour's notice: 10:30 today is too soon, 11:00 is fine.
      assert FullCalendar.check(slot(~N[2026-03-11 10:30:00], 15, "sara"), doctor) ==
               {:error, :past}

      assert FullCalendar.check(slot(~N[2026-03-11 11:00:00], 15, "sara"), doctor) == :ok

      assert FullCalendar.check(slot(~N[2026-04-01 09:00:00], 15, "sara"), doctor) ==
               {:error, :unavailable}
    end

    test "a busy slot blocks only its own resource" do
      busy = [event("x", ~N[2026-03-12 09:00:00], ~N[2026-03-12 09:30:00], %{resource_id: "ali"})]
      doctor = ctx(%{preset: "doctor", resources: [%{id: "ali"}, %{id: "sara"}]}, busy)

      assert FullCalendar.check(slot(~N[2026-03-12 09:15:00], 15, "ali"), doctor) ==
               {:error, :overlap}

      assert FullCalendar.check(slot(~N[2026-03-12 09:15:00], 15, "sara"), doctor) == :ok
      assert FullCalendar.check(slot(~N[2026-03-12 09:30:00], 15, "ali"), doctor) == :ok
    end
  end

  describe "the live component" do
    test "renders the month before and after connecting, and reports its range", %{conn: conn} do
      {view, html} =
        mount_calendar(conn, events: [event(1, ~D[2026-03-12], nil, %{title: "Launch"})])

      assert html =~ "March 2026"

      assert_receive {:calendar, "cal", :dates_set,
                      %{view: "month", start: ~D[2026-02-23], end: ~D[2026-04-06]}}

      assert view |> element("[data-part=event]", "Launch") |> has_element?()

      assert view |> element("[data-part=day][data-today][aria-current=date]") |> render() =~
               "Wednesday, 11 March 2026"

      # The dead render (no socket) works too, through the wrapper alone.
      dead = render_component(&FullCalendar.full_calendar/1, id: "dead", now: @now)
      assert dead =~ "March 2026"
      assert length(Regex.scan(~r/data-part="day"/, dead)) == 42
    end

    test "paging and switching views update the title and report the new range", %{conn: conn} do
      {view, _html} = mount_calendar(conn, [])
      assert_receive {:calendar, "cal", :dates_set, _}

      view |> element("[data-part=next]") |> render_click()
      assert view |> element("[data-part=title]") |> render() =~ "April 2026"
      assert_receive {:calendar, "cal", :dates_set, %{start: ~D[2026-03-30]}}

      view |> element("[data-part=today]") |> render_click()
      view |> element("[data-part=view-button][data-view=week]") |> render_click()
      assert view |> element("[data-part=title]") |> render() =~ "9 – 15 March 2026"

      assert_receive {:calendar, "cal", :dates_set,
                      %{view: "week", start: ~D[2026-03-09], end: ~D[2026-03-16]}}

      assert has_element?(view, "[data-part=slot][data-start='2026-03-11T09:00:00']")

      # A day number jumps to that day.
      view |> element("[data-part=view-button][data-view=month]") |> render_click()

      view
      |> element("[data-part=day-number][aria-label='Friday, 13 March 2026']")
      |> render_click()

      assert view |> element("[data-part=title]") |> render() =~ "Friday, 13 March 2026"
    end

    test "a hotel stay: two clicks, check-out semantics and the nights it reports", %{conn: conn} do
      booked = [event("guest", ~D[2026-03-18], ~D[2026-03-20], %{title: "Booked"})]
      {view, _html} = mount_calendar(conn, preset: "hotel", min_nights: 2, events: booked)

      # Past days and nights already taken cannot be picked.
      assert has_element?(
               view,
               "[data-part=day][data-start='2026-03-10T00:00:00'][data-disabled]"
             )

      assert has_element?(
               view,
               "[data-part=day][data-start='2026-03-18T00:00:00'][data-disabled]"
             )

      view |> element("[data-part=day][data-start='2026-03-12T00:00:00']") |> render_click()
      assert has_element?(view, "[data-part=day][data-anchor][data-start='2026-03-12T00:00:00']")

      # The day a stay would run into the next booking is still a valid check-out…
      refute has_element?(
               view,
               "[data-part=day][data-start='2026-03-18T00:00:00'][data-disabled]"
             )

      # …but nothing beyond it is.
      assert has_element?(
               view,
               "[data-part=day][data-start='2026-03-19T00:00:00'][data-disabled]"
             )

      view |> element("[data-part=day][data-start='2026-03-13T00:00:00']") |> render_click()
      assert view |> element("[data-part=status]") |> render() =~ "Choose at least 2 nights"
      assert_receive {:calendar, "cal", :select_rejected, %{reason: :min_nights}}

      view |> element("[data-part=day][data-start='2026-03-15T00:00:00']") |> render_click()

      assert_receive {:calendar, "cal", :select,
                      %{start: ~D[2026-03-12], end: ~D[2026-03-15], nights: 3, all_day: true}}

      assert has_element?(
               view,
               "[data-part=day][data-range-start][data-start='2026-03-12T00:00:00']"
             )

      assert has_element?(
               view,
               "[data-part=day][data-range-end][data-start='2026-03-15T00:00:00']"
             )

      assert has_element?(
               view,
               "[data-part=day][data-selected][data-start='2026-03-14T00:00:00']"
             )

      refute has_element?(
               view,
               "[data-part=day][data-selected][data-start='2026-03-15T00:00:00']"
             )
    end

    test "a doctor's slot per resource, and a parent that clears it after booking", %{conn: conn} do
      resources = [%{id: "ali", title: "Dr Ali"}, %{id: "sara", title: "Dr Sara"}]

      busy = [
        event("p1", ~N[2026-03-11 11:00:00], ~N[2026-03-11 11:30:00], %{
          resource_id: "ali",
          title: "Patient"
        })
      ]

      {view, _html} = mount_calendar(conn, preset: "doctor", resources: resources, events: busy)

      assert view |> element("[data-part=header][data-resource=sara]") |> render() =~ "Dr Sara"

      assert has_element?(
               view,
               "[data-part=slot][data-resource=ali][data-start='2026-03-11T11:15:00'][data-disabled]"
             )

      assert has_element?(
               view,
               "[data-part=slot][data-resource=ali][data-start='2026-03-11T08:30:00'][data-disabled]"
             )

      view
      |> element("[data-part=slot][data-resource=sara][data-start='2026-03-11T11:15:00']")
      |> render_click()

      assert_receive {:calendar, "cal", :select,
                      %{
                        start: ~N[2026-03-11 11:15:00],
                        end: ~N[2026-03-11 11:30:00],
                        resource_id: "sara",
                        minutes: 15
                      }}

      assert has_element?(view, "[data-part=slot][data-selected][data-resource=sara]")

      # The parent's handle_info calls `send_update/3`, which lands one message later.
      send(view.pid, :clear_selection)
      _ = render(view)
      refute has_element?(view, "[data-part=slot][data-selected]")
    end

    test "house viewings: several slots, toggled, capped", %{conn: conn} do
      {view, _html} = mount_calendar(conn, preset: "viewing", max_selections: 2)

      pick = fn start ->
        view |> element("[data-part=slot][data-start='#{start}']") |> render_click()
      end

      pick.("2026-03-12T10:00:00")
      assert_receive {:calendar, "cal", :select, [%{start: ~N[2026-03-12 10:00:00]}]}
      pick.("2026-03-13T15:00:00")
      assert_receive {:calendar, "cal", :select, [_, %{start: ~N[2026-03-13 15:00:00]}]}

      pick.("2026-03-14T11:00:00")
      assert_receive {:calendar, "cal", :select_rejected, %{reason: :max_selections}}
      assert view |> element("[data-part=status]") |> render() =~ "You can choose up to 2"

      # Clicking a picked slot again gives it back.
      pick.("2026-03-12T10:00:00")
      assert_receive {:calendar, "cal", :select, [%{start: ~N[2026-03-13 15:00:00]}]}
    end

    test "events: popover on click, drag to move, drag the edge to resize", %{conn: conn} do
      events = [event("m", ~N[2026-03-11 09:00:00], ~N[2026-03-11 10:00:00], %{title: "Meeting"})]
      {view, _html} = mount_calendar(conn, preset: "planner", view: "week", events: events)

      view |> element("[data-part=event][data-key=m]") |> render_click()
      assert_receive {:calendar, "cal", :event_click, %{id: "m"}}

      assert view |> element("[data-part=popover]") |> render() =~
               "Wednesday, 11 March 2026 · 09:00 – 10:00"

      view |> element("[data-part=close]") |> render_click()
      refute has_element?(view, "[data-part=popover]")

      # What the hook pushes when an event is dropped one day later and half an hour down.
      view
      |> element("#cal")
      |> render_hook("drop", %{
        key: "m",
        from: "2026-03-11T09:00:00",
        to: "2026-03-12T09:30:00",
        resource: "",
        all_day: false
      })

      assert_receive {:calendar, "cal", :event_drop,
                      %{
                        id: "m",
                        start: ~N[2026-03-12 09:30:00],
                        end: ~N[2026-03-12 10:30:00],
                        previous: %{start: ~N[2026-03-11 09:00:00]}
                      }}

      view |> element("#cal") |> render_hook("resize", %{key: "m", to: "2026-03-11T11:30:00"})

      assert_receive {:calendar, "cal", :event_resize,
                      %{id: "m", start: ~N[2026-03-11 09:00:00], end: ~N[2026-03-11 11:30:00]}}

      # Dropping a timed event on the all-day lane turns it into an all-day event.
      view
      |> element("#cal")
      |> render_hook("drop", %{
        key: "m",
        from: "2026-03-11T09:00:00",
        to: "2026-03-13T00:00:00",
        all_day: true
      })

      assert_receive {:calendar, "cal", :event_drop,
                      %{start: ~D[2026-03-13], end: ~D[2026-03-14], all_day: true}}
    end

    test "a drag across days selects the range in one gesture", %{conn: conn} do
      {view, _html} = mount_calendar(conn, preset: "planner")

      view
      |> element("#cal")
      |> render_hook("span", %{
        from: "2026-03-16T00:00:00",
        to: "2026-03-19T00:00:00",
        unit: "day",
        resource: ""
      })

      assert_receive {:calendar, "cal", :select,
                      %{start: ~D[2026-03-16], end: ~D[2026-03-20], nights: 4}}
    end

    test "overflowing days get a +N more list that opens without the server", %{conn: conn} do
      events =
        for i <- 1..4,
            do:
              event("e#{i}", ~N[2026-03-12 09:00:00], ~N[2026-03-12 10:00:00], %{
                title: "Busy #{i}"
              })

      {view, _html} = mount_calendar(conn, events: events, day_max_events: 2)

      more = view |> element("[data-part=more]") |> render()
      assert more =~ "+2 more"
      assert more =~ ~s(aria-expanded="false")

      popover = view |> element("[data-part=more-popover]") |> render()
      assert popover =~ "hidden"
      assert length(Regex.scan(~r/data-part="event"/, popover)) == 4
    end

    test "recurring events, background blocks and the parent changing the date", %{conn: conn} do
      events = [
        event("gym", ~N[2026-03-02 07:00:00], ~N[2026-03-02 08:00:00], %{
          title: "Gym",
          recurrence: "FREQ=WEEKLY;BYDAY=MO"
        }),
        event("lunch", ~N[2026-03-11 12:00:00], ~N[2026-03-11 13:00:00], %{
          display: "background",
          title: "Lunch"
        })
      ]

      {view, _html} =
        mount_calendar(conn,
          events: events,
          view: "week",
          selectable: "single",
          select_overlap: false
        )

      assert has_element?(
               view,
               "[data-part=event][data-recurring][data-key='gym@2026-03-09T07:00:00']"
             )

      assert has_element?(view, "[data-part=background][title=Lunch]")

      assert has_element?(
               view,
               "[data-part=slot][data-start='2026-03-11T12:30:00'][data-disabled]"
             )

      send(view.pid, {:attrs, %{date: ~D[2026-03-18]}})
      assert has_element?(view, "[data-part=event][data-key='gym@2026-03-16T07:00:00']")
      assert view |> element("[data-part=title]") |> render() =~ "16 – 22 March 2026"
    end

    test "labels and digits can be localized", %{conn: conn} do
      digits = ~w(۰ ۱ ۲ ۳ ۴ ۵ ۶ ۷ ۸ ۹)

      {_view, html} =
        mount_calendar(conn, labels: %{digits: digits, today: "امروز"}, rest: %{dir: "rtl"})

      assert html =~ "March ۲۰۲۶"
      assert html =~ "امروز"
      assert html =~ ~s(dir="rtl")
    end

    test "a browser time zone is only adopted when it is known", %{conn: conn} do
      {view, _html} = mount_calendar(conn, time_zone: "auto")
      assert has_element?(view, "#cal[data-time-zone=auto]")

      view |> element("#cal") |> render_hook("time_zone", %{time_zone: "Mars/Olympus_Mons"})
      view |> element("#cal") |> render_hook("nonsense", %{})
      assert has_element?(view, "#cal[data-part=root]")
    end
  end
end
