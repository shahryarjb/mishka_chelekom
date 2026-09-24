defmodule DevelopmentWeb.Showcase.CalendarSamples do
  @moduledoc """
  Fixed sample data for the `full_calendar` galleries and preview. The galleries pin `now` to
  Wednesday 11 March 2026 so every visit (and every test) sees the same week.
  """

  @doc "The moment the gallery calendars treat as now."
  @spec now() :: NaiveDateTime.t()
  def now, do: ~N[2026-03-11 10:00:00]

  @doc "A planner's week: overlaps, an all-day span, a recurring stand-up and a lunch block."
  @spec events() :: [map()]
  def events do
    [
      %{
        id: "standup",
        title: "Stand-up",
        start: ~N[2026-03-02 09:30:00],
        end: ~N[2026-03-02 09:45:00],
        recurrence: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
        color: "#0891b2"
      },
      %{
        id: "review",
        title: "Design review",
        start: ~N[2026-03-10 14:00:00],
        end: ~N[2026-03-10 15:30:00],
        color: "#7c3aed"
      },
      %{
        id: "one-on-one",
        title: "1:1 with Sam",
        start: ~N[2026-03-10 14:30:00],
        end: ~N[2026-03-10 15:00:00],
        color: "#ea580c"
      },
      %{
        id: "offsite",
        title: "Team offsite",
        start: ~D[2026-03-12],
        end: ~D[2026-03-14],
        color: "#db2777"
      },
      %{id: "release", title: "Release v2", start: ~D[2026-03-18], color: "#16a34a"},
      %{
        id: "lunch",
        title: "Lunch",
        start: ~N[2026-03-09 12:00:00],
        end: ~N[2026-03-09 13:00:00],
        display: "background",
        recurrence: %{freq: :daily, count: 30}
      }
    ]
  end

  @doc "Doctors, each with their own hours."
  @spec doctors() :: [map()]
  def doctors do
    [
      %{id: "rahimi", title: "Dr Rahimi", business_hours: %{days: [1, 2, 3, 4, 5], hours: 9..17}},
      %{id: "chen", title: "Dr Chen", business_hours: %{days: [1, 3, 5], hours: 8..13}},
      %{id: "okafor", title: "Dr Okafor", business_hours: %{days: [2, 3, 4], hours: 10..16}}
    ]
  end

  @doc "A day of appointments for `doctors/0`."
  @spec appointments() :: [map()]
  def appointments do
    [
      %{
        id: "a1",
        title: "Checkup",
        start: ~N[2026-03-11 09:00:00],
        end: ~N[2026-03-11 09:30:00],
        resource_id: "rahimi"
      },
      %{
        id: "a2",
        title: "Follow-up",
        start: ~N[2026-03-11 11:00:00],
        end: ~N[2026-03-11 11:45:00],
        resource_id: "rahimi"
      },
      %{
        id: "a3",
        title: "Root canal",
        start: ~N[2026-03-11 08:30:00],
        end: ~N[2026-03-11 09:30:00],
        resource_id: "chen"
      },
      %{
        id: "a4",
        title: "Vaccination",
        start: ~N[2026-03-11 10:30:00],
        end: ~N[2026-03-11 11:00:00],
        resource_id: "okafor"
      }
    ]
  end

  @doc "Hotel rooms."
  @spec rooms() :: [map()]
  def rooms do
    [
      %{id: "101", title: "101 · Double"},
      %{id: "102", title: "102 · Twin"},
      %{id: "201", title: "201 · Suite"}
    ]
  end

  @doc "Stays across `rooms/0`."
  @spec bookings() :: [map()]
  def bookings do
    [
      %{
        id: "b1",
        title: "Ms Karimi",
        start: ~D[2026-03-11],
        end: ~D[2026-03-14],
        resource_id: "101",
        color: "#0f766e"
      },
      %{
        id: "b2",
        title: "Tour group",
        start: ~D[2026-03-09],
        end: ~D[2026-03-16],
        resource_id: "102",
        color: "#0369a1"
      },
      %{
        id: "b3",
        title: "Honeymoon",
        start: ~D[2026-03-14],
        end: ~D[2026-03-20],
        resource_id: "201",
        color: "#be185d"
      },
      %{
        id: "b4",
        title: "Mr Novak",
        start: ~D[2026-03-17],
        end: ~D[2026-03-19],
        resource_id: "101",
        color: "#0f766e"
      }
    ]
  end

  @doc "Nightly prices for the booking examples, dearer at weekends."
  @spec prices() :: map()
  def prices do
    for day <- Date.range(~D[2026-02-23], ~D[2026-04-12]), into: %{} do
      {day, %{label: if(Date.day_of_week(day) in [5, 6], do: "$150", else: "$120")}}
    end
  end
end
