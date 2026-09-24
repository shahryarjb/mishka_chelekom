defmodule DevelopmentWeb.Showcase.CalendarDemoLive do
  @moduledoc """
  `/showcase/calendar` — the headless `full_calendar` doing four real jobs, one per tab.

    * **Hotel**: pick a room, then a stay. Check-out semantics, a two-night minimum, prices and
      arrival-only days from `day_info`, the timeline as the front desk's room chart.
    * **Clinic**: one column per doctor, each with their own hours; a 15 minute grid books a
      30 minute appointment.
    * **House viewing**: a buyer proposes up to three viewing times in one go.
    * **Planner**: drag, resize, a recurring stand-up, a background lunch block, live settings.

  The page owns the data. The calendar only reports (`handle_info/2` below) and the page decides
  what to save, which is the whole integration contract.
  """
  use DevelopmentWeb, :live_view

  alias DevelopmentWeb.Components.Headless.FullCalendar

  import FullCalendar, only: [full_calendar: 1]

  @tabs [
    {"hotel", "Hotel"},
    {"clinic", "Clinic"},
    {"viewing", "House viewing"},
    {"planner", "Planner"}
  ]

  @rooms [
    %{id: "101", title: "101 · Double", rate: 120},
    %{id: "102", title: "102 · Twin", rate: 110},
    %{id: "201", title: "201 · Suite", rate: 240}
  ]

  @doctors [
    %{
      id: "rahimi",
      title: "Dr Rahimi · GP",
      business_hours: %{days: [1, 2, 3, 4, 5], hours: 9..17}
    },
    %{
      id: "chen",
      title: "Dr Chen · Dentist",
      business_hours: [%{days: [1, 3, 5], hours: 8..12}, %{days: [2, 4], hours: 13..19}]
    },
    %{
      id: "okafor",
      title: "Dr Okafor · Pediatrics",
      business_hours: %{days: [1, 2, 3, 4, 6], hours: 10..16}
    }
  ]

  # One skin for every calendar on the page: the component ships layout only, so this is all the
  # styling there is. Data attributes carry the state (`data-selected`, `data-disabled`, …).
  @skin [
    class:
      "overflow-hidden rounded-xl border border-neutral-200 bg-white text-sm text-neutral-900 shadow-sm dark:border-neutral-800 dark:bg-neutral-950 dark:text-neutral-100 [--fc-head-background:white] dark:[--fc-head-background:var(--color-neutral-950)] [--fc-row-min-height:6.5rem] [--fc-slot-height:2.25rem] [&.phx-click-loading_[data-part=view]]:opacity-60",
    toolbar_class: "gap-2 border-b border-neutral-200 p-3 dark:border-neutral-800",
    title_class: "order-first w-full text-base font-semibold sm:order-none sm:w-auto",
    nav_class:
      "-ms-px border border-neutral-200 px-3 py-1.5 first:ms-0 first:rounded-s-md last:rounded-e-md hover:bg-neutral-100 dark:border-neutral-700 dark:hover:bg-neutral-800",
    view_button_class:
      "-ms-px border border-neutral-200 px-3 py-1.5 first:ms-0 first:rounded-s-md last:rounded-e-md hover:bg-neutral-100 aria-pressed:bg-neutral-900 aria-pressed:text-white dark:border-neutral-700 dark:hover:bg-neutral-800 dark:aria-pressed:bg-white dark:aria-pressed:text-neutral-900",
    header_class:
      "flex items-center justify-center gap-1 border-b border-e border-neutral-200 py-2 text-xs font-medium text-neutral-500 dark:border-neutral-800 data-[today]:text-blue-600",
    week_class: "border-b border-neutral-200 dark:border-neutral-800",
    day_class:
      "border-e border-neutral-200 p-1 text-[11px] text-emerald-700 outline-none hover:bg-neutral-50 focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-blue-500 dark:border-neutral-800 dark:text-emerald-400 dark:hover:bg-neutral-900 data-[outside]:bg-neutral-50/80 dark:data-[outside]:bg-neutral-900/50 data-[shaded]:bg-amber-50 dark:data-[shaded]:bg-amber-950/30 data-[disabled]:cursor-not-allowed data-[disabled]:bg-[repeating-linear-gradient(135deg,transparent_0_6px,rgb(0_0_0/0.045)_6px_12px)] data-[disabled]:text-neutral-400 data-[status=check_in_only]:text-sky-700 data-[status=check_in_only]:after:content-['arrival_only'] data-[selected]:bg-blue-100 dark:data-[selected]:bg-blue-900/50 data-[range-end]:bg-blue-100 dark:data-[range-end]:bg-blue-900/50 data-[anchor]:bg-blue-200 dark:data-[anchor]:bg-blue-800/60 data-[selecting]:bg-blue-50 dark:data-[selecting]:bg-blue-950",
    day_number_class:
      "m-1 grid size-6 place-items-center rounded-full text-xs hover:bg-neutral-200 data-[outside]:text-neutral-400 data-[today]:bg-blue-600 data-[today]:text-white dark:hover:bg-neutral-700",
    slot_class:
      "border-e border-b border-neutral-100 outline-none hover:bg-blue-50 focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-blue-500 dark:border-neutral-800/70 dark:hover:bg-blue-950/60 not-data-[business]:bg-neutral-50 dark:not-data-[business]:bg-neutral-900/60 data-[disabled]:cursor-not-allowed data-[disabled]:bg-[repeating-linear-gradient(135deg,transparent_0_6px,rgb(0_0_0/0.045)_6px_12px)] data-[selected]:bg-blue-200 dark:data-[selected]:bg-blue-800/60 data-[selecting]:bg-blue-100 dark:data-[selecting]:bg-blue-900",
    axis_class: "pe-2 text-end text-[11px] leading-none text-neutral-500",
    event_class:
      "m-px truncate rounded-md px-1.5 py-0.5 text-start text-xs font-medium text-white shadow-sm [background:var(--fc-event-color,#2563eb)] hover:brightness-110 data-[cut-start]:rounded-s-none data-[cut-end]:rounded-e-none data-[dragging]:opacity-80 data-[dragging]:shadow-xl data-[status=pending]:opacity-70 data-[status=pending]:ring-2 data-[status=pending]:ring-white/70 data-[status=pending]:ring-inset",
    more_class:
      "mx-1 rounded px-1 text-xs font-medium text-neutral-600 hover:bg-neutral-100 dark:text-neutral-300 dark:hover:bg-neutral-800",
    popover_class:
      "flex flex-col gap-1.5 rounded-lg border border-neutral-200 bg-white p-3 shadow-xl dark:border-neutral-700 dark:bg-neutral-900",
    list_day_class:
      "flex flex-col gap-1 border-b border-neutral-200 p-3 dark:border-neutral-800 [&_h3]:text-xs [&_h3]:font-semibold [&_h3]:uppercase [&_h3]:text-neutral-500 data-[today]:bg-blue-50/60 dark:data-[today]:bg-blue-950/30",
    resource_class:
      "flex items-center gap-2 border-e border-b border-neutral-200 px-3 text-xs font-medium dark:border-neutral-800",
    now_class:
      "border-t-2 border-red-500 before:absolute before:-top-[5px] before:-start-1 before:size-2 before:rounded-full before:bg-red-500",
    status_class:
      "flex items-center justify-between gap-2 bg-red-50 px-3 py-2 text-sm text-red-700 data-[empty]:hidden dark:bg-red-950/40 dark:text-red-300"
  ]

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(
       tabs: @tabs,
       rooms: @rooms,
       doctors: @doctors,
       skin: @skin,
       today: today,
       log: [],
       pending: nil,
       counter: 0
     )
     |> assign(room: "101", shown_doctors: Enum.map(@doctors, & &1.id))
     |> assign(settings: %{first_day_of_week: 1, hour12: false, persian: false, weekends: true})
     |> assign(bookings: seed_bookings(today), appointments: seed_appointments(today))
     |> assign(viewings: seed_viewings(today), plans: seed_plans(today))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in Enum.map(@tabs, &elem(&1, 0)), do: params["tab"], else: "hotel"
    {:noreply, assign(socket, tab: tab, pending: nil)}
  end

  # ── what the calendars report ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({FullCalendar, id, name, payload}, socket) do
    socket = log(socket, id, name, payload)
    {:noreply, react(socket, id, name, payload)}
  end

  defp react(socket, _id, :select, nil), do: assign(socket, :pending, nil)
  defp react(socket, _id, :select, []), do: assign(socket, :pending, nil)
  defp react(socket, id, :select, selection), do: assign(socket, :pending, {id, selection})

  defp react(socket, "planner", name, %{id: id} = change)
       when name in [:event_drop, :event_resize] do
    update(socket, :plans, fn plans -> Enum.map(plans, &move_plan(&1, id, change)) end)
  end

  defp react(socket, _id, _name, _payload), do: socket

  # A recurring event's change applies to the whole series here; a real app would ask.
  defp move_plan(%{id: id} = plan, id, change) do
    if plan[:recurrence] do
      shift = NaiveDateTime.diff(to_naive(change.start), to_naive(change.previous.start))

      %{
        plan
        | start: NaiveDateTime.add(plan.start, shift),
          end: NaiveDateTime.add(plan.end, shift)
      }
    else
      Map.merge(plan, %{start: change.start, end: change.end, all_day: change.all_day})
    end
  end

  defp move_plan(plan, _id, _change), do: plan

  defp to_naive(%Date{} = date), do: NaiveDateTime.new!(date, ~T[00:00:00])
  defp to_naive(time), do: time

  defp log(socket, id, name, payload) do
    line = %{
      at: Time.utc_now() |> Time.truncate(:second),
      calendar: id,
      name: name,
      payload: summarize(payload)
    }

    update(socket, :log, &Enum.take([line | &1], 8))
  end

  defp summarize(%{start: from, end: to} = span),
    do: "#{from} → #{to}#{if span[:resource_id], do: " · #{span.resource_id}"}"

  defp summarize(%{id: id}), do: "event #{id}"
  defp summarize(%{reason: reason}), do: to_string(reason)
  defp summarize(list) when is_list(list), do: "#{length(list)} picked"
  defp summarize(other), do: inspect(other)

  # ── the page's own events ─────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("room", %{"room" => room}, socket) do
    FullCalendar.clear_selection("hotel")
    {:noreply, assign(socket, room: room, pending: nil)}
  end

  def handle_event("doctors", params, socket) do
    shown = Map.get(params, "doctors", [])
    {:noreply, assign(socket, :shown_doctors, shown)}
  end

  def handle_event("settings", params, socket) do
    settings = %{
      first_day_of_week: String.to_integer(params["first_day_of_week"] || "1"),
      hour12: params["hour12"] == "true",
      persian: params["persian"] == "true",
      weekends: params["weekends"] == "true"
    }

    {:noreply, assign(socket, :settings, settings)}
  end

  def handle_event("cancel", _params, socket) do
    {id, _} = socket.assigns.pending
    FullCalendar.clear_selection(id)
    {:noreply, assign(socket, :pending, nil)}
  end

  def handle_event("confirm", _params, socket) do
    {id, selection} = socket.assigns.pending
    FullCalendar.clear_selection(id)
    {:noreply, socket |> save(id, selection) |> assign(:pending, nil)}
  end

  def handle_event("delete_plan", %{"id" => id}, socket) do
    {:noreply, update(socket, :plans, fn plans -> Enum.reject(plans, &(&1.id == id)) end)}
  end

  defp save(socket, "hotel", stay) do
    event = %{
      id: next_id(socket),
      title: "Guest",
      start: stay.start,
      end: stay.end,
      resource_id: stay.resource_id,
      color: "#0f766e"
    }

    socket |> bump() |> update(:bookings, &[event | &1])
  end

  defp save(socket, "clinic", slot) do
    event = %{
      id: next_id(socket),
      title: "New patient",
      start: slot.start,
      end: slot.end,
      resource_id: slot.resource_id,
      color: "#7c3aed"
    }

    socket |> bump() |> update(:appointments, &[event | &1])
  end

  defp save(socket, "viewing", slots) do
    requested =
      slots
      |> Enum.with_index()
      |> Enum.map(fn {slot, i} ->
        %{
          id: "#{next_id(socket)}-#{i}",
          title: "Requested viewing",
          start: slot.start,
          end: slot.end,
          status: "pending",
          color: "#ea580c"
        }
      end)

    socket |> bump() |> update(:viewings, &(requested ++ &1))
  end

  defp save(socket, "planner", span) do
    event = %{
      id: next_id(socket),
      title: "New event",
      start: span.start,
      end: span.end,
      all_day: span.all_day,
      color: "#2563eb"
    }

    socket |> bump() |> update(:plans, &[event | &1])
  end

  defp next_id(socket), do: "new-#{socket.assigns.counter}"
  defp bump(socket), do: update(socket, :counter, &(&1 + 1))

  # ── data ──────────────────────────────────────────────────────────────────────────────────────

  defp seed_bookings(today) do
    [
      %{
        id: "b1",
        title: "Ms Karimi",
        start: Date.add(today, 2),
        end: Date.add(today, 5),
        resource_id: "101",
        color: "#0f766e"
      },
      %{
        id: "b2",
        title: "Mr Novak",
        start: Date.add(today, 8),
        end: Date.add(today, 10),
        resource_id: "101",
        color: "#0f766e"
      },
      %{
        id: "b3",
        title: "Tour group",
        start: Date.add(today, -1),
        end: Date.add(today, 6),
        resource_id: "102",
        color: "#0369a1"
      },
      %{
        id: "b4",
        title: "Honeymoon",
        start: Date.add(today, 4),
        end: Date.add(today, 11),
        resource_id: "201",
        color: "#be185d"
      },
      %{
        id: "b5",
        title: "Maintenance",
        start: Date.add(today, 13),
        end: Date.add(today, 15),
        resource_id: "102",
        color: "#6b7280"
      }
    ]
  end

  # Prices on every day, dearer at weekends; one arrival-only day to show the rule.
  defp day_info(today) do
    for offset <- -7..60, into: %{} do
      date = Date.add(today, offset)
      weekend = Date.day_of_week(date) in [5, 6]
      info = %{label: if(weekend, do: "$150", else: "$120")}
      {date, if(offset == 12, do: Map.put(info, :status, "check_in_only"), else: info)}
    end
  end

  defp seed_appointments(today) do
    day = next_weekday(today)

    [
      appointment("a1", day, ~T[09:00:00], 30, "rahimi", "Checkup"),
      appointment("a2", day, ~T[10:30:00], 45, "rahimi", "Follow-up"),
      appointment("a3", day, ~T[08:30:00], 60, "chen", "Root canal"),
      appointment("a4", day, ~T[11:00:00], 30, "okafor", "Vaccination"),
      %{
        id: "lunch",
        title: "Lunch",
        start: NaiveDateTime.new!(day, ~T[12:30:00]),
        end: NaiveDateTime.new!(day, ~T[13:30:00]),
        display: "background"
      }
    ]
  end

  defp appointment(id, day, time, minutes, doctor, title) do
    start = NaiveDateTime.new!(day, time)

    %{
      id: id,
      title: title,
      start: start,
      end: NaiveDateTime.add(start, minutes * 60),
      resource_id: doctor,
      color: "#4f46e5"
    }
  end

  defp next_weekday(date) do
    if Date.day_of_week(date) in [6, 7], do: next_weekday(Date.add(date, 1)), else: date
  end

  defp seed_viewings(today) do
    [
      %{
        id: "v1",
        title: "Viewing · the Parsas",
        start: NaiveDateTime.new!(Date.add(today, 1), ~T[11:00:00]),
        end: NaiveDateTime.new!(Date.add(today, 1), ~T[11:30:00]),
        color: "#16a34a"
      },
      %{
        id: "v2",
        title: "Open house",
        start: NaiveDateTime.new!(Date.add(today, 3), ~T[14:00:00]),
        end: NaiveDateTime.new!(Date.add(today, 3), ~T[16:00:00]),
        color: "#0891b2"
      }
    ]
  end

  defp seed_plans(today) do
    monday = Date.beginning_of_week(today)

    [
      %{
        id: "standup",
        title: "Stand-up",
        start: NaiveDateTime.new!(monday, ~T[09:30:00]),
        end: NaiveDateTime.new!(monday, ~T[09:45:00]),
        recurrence: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
        color: "#0891b2"
      },
      %{
        id: "offsite",
        title: "Team offsite",
        start: Date.add(monday, 3),
        end: Date.add(monday, 5),
        all_day: true,
        color: "#db2777"
      },
      %{
        id: "review",
        title: "Design review",
        start: NaiveDateTime.new!(Date.add(monday, 1), ~T[14:00:00]),
        end: NaiveDateTime.new!(Date.add(monday, 1), ~T[15:30:00]),
        color: "#7c3aed"
      },
      %{
        id: "one-on-one",
        title: "1:1 with Sam",
        start: NaiveDateTime.new!(Date.add(monday, 1), ~T[14:30:00]),
        end: NaiveDateTime.new!(Date.add(monday, 1), ~T[15:00:00]),
        color: "#ea580c"
      },
      %{
        id: "release",
        title: "Release v2",
        start: Date.add(monday, 9),
        end: Date.add(monday, 10),
        all_day: true,
        color: "#16a34a"
      },
      %{
        id: "lunch",
        title: "Lunch",
        start: NaiveDateTime.new!(monday, ~T[12:00:00]),
        end: NaiveDateTime.new!(monday, ~T[13:00:00]),
        display: "background",
        recurrence: %{freq: :daily, count: 60}
      }
    ]
  end

  # ── render ────────────────────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-neutral-50 text-neutral-900 dark:bg-neutral-900 dark:text-neutral-100">
      <div class="mx-auto flex max-w-7xl flex-col gap-4 p-4 sm:p-6">
        <header class="flex flex-col gap-1">
          <.link
            navigate={~p"/showcase/headless/full_calendar"}
            class="text-xs text-neutral-500 hover:underline"
          >
            ← full_calendar reference
          </.link>
          <h1 class="text-2xl font-semibold">Full calendar</h1>
          <p class="max-w-3xl text-sm text-neutral-600 dark:text-neutral-400">
            One headless LiveComponent. The page owns the data, and the calendar reports picks, drops and
            ranges as messages. Everything below is the same component with different options.
          </p>
        </header>

        <nav
          class="flex gap-1 border-b border-neutral-200 dark:border-neutral-800"
          aria-label="Use cases"
        >
          <.link
            :for={{id, label} <- @tabs}
            patch={~p"/showcase/calendar?tab=#{id}"}
            aria-current={@tab == id && "page"}
            class="-mb-px border-b-2 border-transparent px-3 py-2 text-sm font-medium text-neutral-500 hover:text-neutral-900 aria-[current=page]:border-blue-600 aria-[current=page]:text-neutral-900 dark:hover:text-white dark:aria-[current=page]:text-white"
          >{label}</.link>
        </nav>

        <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <div class="flex min-w-0 flex-col gap-3">
            <.use_case tab={@tab} {assigns} />
          </div>

          <aside class="flex flex-col gap-3">
            <.booking pending={@pending} rooms={@rooms} doctors={@doctors} />
            <section class="rounded-xl border border-neutral-200 bg-white p-3 dark:border-neutral-800 dark:bg-neutral-950">
              <h2 class="mb-2 text-xs font-semibold uppercase text-neutral-500">
                Messages to the page
              </h2>
              <p :if={@log == []} class="text-xs text-neutral-500">
                Nothing yet — page, pick or drag.
              </p>
              <ol class="flex flex-col gap-1.5 font-mono text-[11px]" id="calendar-log">
                <li :for={line <- @log} class="flex flex-col">
                  <span class="text-neutral-500">{line.at} · {line.calendar}</span>
                  <span><b>:{line.name}</b> {line.payload}</span>
                </li>
              </ol>
            </section>
          </aside>
        </div>
      </div>
    </div>
    """
  end

  defp use_case(%{tab: "hotel"} = assigns) do
    assigns = assign(assigns, :day_info, day_info(assigns.today))

    ~H"""
    <form phx-change="room" class="flex flex-wrap items-center gap-2 text-sm">
      <span class="font-medium">Room</span>
      <label
        :for={room <- @rooms}
        class="flex cursor-pointer items-center gap-2 rounded-lg border border-neutral-200 bg-white px-3 py-1.5 has-checked:border-teal-600 has-checked:ring-1 has-checked:ring-teal-600 dark:border-neutral-800 dark:bg-neutral-950"
      >
        <input
          type="radio"
          name="room"
          value={room.id}
          checked={room.id == @room}
          class="accent-teal-700"
        />
        {room.title} <span class="text-neutral-500">${room.rate}</span>
      </label>
    </form>
    <.full_calendar
      id="hotel"
      preset="hotel"
      min_nights={2}
      max_nights={14}
      resources={@rooms}
      resource_id={@room}
      events={@bookings}
      day_info={@day_info}
      {@skin}
    />
    <p class="text-xs text-neutral-500">
      Month shows the chosen room; <b>Timeline</b>
      is every room (pick a stay on a row). Leaving on the
      morning another guest arrives is allowed; the day marked in the price row is arrival-only.
    </p>
    """
  end

  defp use_case(%{tab: "clinic"} = assigns) do
    ~H"""
    <form phx-change="doctors" class="flex flex-wrap items-center gap-2 text-sm">
      <span class="font-medium">Doctors</span>
      <input type="hidden" name="doctors[]" value="" />
      <label
        :for={doctor <- @doctors}
        class="flex cursor-pointer items-center gap-2 rounded-lg border border-neutral-200 bg-white px-3 py-1.5 has-checked:border-indigo-600 dark:border-neutral-800 dark:bg-neutral-950"
      >
        <input
          type="checkbox"
          name="doctors[]"
          value={doctor.id}
          checked={doctor.id in @shown_doctors}
          class="accent-indigo-600"
        />
        {doctor.title}
      </label>
    </form>
    <.full_calendar
      id="clinic"
      preset="doctor"
      select_duration={30}
      date={next_weekday(@today)}
      resources={Enum.filter(@doctors, &(&1.id in @shown_doctors))}
      events={@appointments}
      {@skin}
    />
    <p class="text-xs text-neutral-500">
      15 minute rows, 30 minute appointments, each doctor's own hours, lunch as a background block.
      A slot that would run into another booking is not offered.
    </p>
    """
  end

  defp use_case(%{tab: "viewing"} = assigns) do
    ~H"""
    <.full_calendar id="viewing" preset="viewing" events={@viewings} {@skin} />
    <p class="text-xs text-neutral-500">
      Tap up to three half-hour slots between 10:00 and 19:00, then request them together. Tap a slot again
      to give it back.
    </p>
    """
  end

  defp use_case(%{tab: "planner"} = assigns) do
    ~H"""
    <form phx-change="settings" class="flex flex-wrap items-center gap-3 text-sm">
      <label class="flex items-center gap-2">
        Week starts
        <select
          name="first_day_of_week"
          class="rounded-md border border-neutral-200 bg-white px-2 py-1 dark:border-neutral-700 dark:bg-neutral-950"
        >
          <option
            :for={{day, label} <- [{1, "Monday"}, {6, "Saturday"}, {7, "Sunday"}]}
            value={day}
            selected={@settings.first_day_of_week == day}
          >
            {label}
          </option>
        </select>
      </label>
      <.toggle name="weekends" checked={@settings.weekends} label="Weekends" />
      <.toggle name="hour12" checked={@settings.hour12} label="12-hour" />
      <.toggle name="persian" checked={@settings.persian} label="Persian digits, RTL" />
    </form>
    <.full_calendar
      id="planner"
      preset="planner"
      views={["month", "week", "day", "list"]}
      events={@plans}
      first_day_of_week={@settings.first_day_of_week}
      hidden_weekdays={if @settings.weekends, do: [], else: [6, 7]}
      hour12={@settings.hour12}
      labels={if @settings.persian, do: %{digits: ~w(۰ ۱ ۲ ۳ ۴ ۵ ۶ ۷ ۸ ۹)}, else: %{}}
      dir={if @settings.persian, do: "rtl", else: "ltr"}
      {@skin}
    >
      <:popover_content :let={occ}>
        <button
          :if={not occ.background}
          type="button"
          phx-click="delete_plan"
          phx-value-id={occ.id}
          class="self-start rounded-md border border-red-200 px-2 py-1 text-xs text-red-700 hover:bg-red-50 dark:border-red-900 dark:text-red-300"
        >Delete</button>
      </:popover_content>
    </.full_calendar>
    <p class="text-xs text-neutral-500">
      Drag an event to move it, drag its edge to resize, drag across days (or two clicks) to create one.
      The stand-up repeats every weekday; lunch is a background block.
    </p>
    """
  end

  attr :name, :string, required: true
  attr :checked, :boolean, required: true
  attr :label, :string, required: true

  defp toggle(assigns) do
    ~H"""
    <label class="flex items-center gap-2">
      <input type="hidden" name={@name} value="false" />
      <input type="checkbox" name={@name} value="true" checked={@checked} class="accent-blue-600" />
      {@label}
    </label>
    """
  end

  attr :pending, :any, required: true
  attr :rooms, :list, required: true
  attr :doctors, :list, required: true

  defp booking(assigns) do
    ~H"""
    <section
      :if={@pending}
      id="pending"
      class="flex flex-col gap-2 rounded-xl border border-blue-200 bg-blue-50 p-3 text-sm dark:border-blue-900 dark:bg-blue-950/40"
    >
      <h2 class="text-xs font-semibold uppercase text-blue-700 dark:text-blue-300">
        {pending_title(@pending)}
      </h2>
      <p>{pending_text(@pending, @rooms, @doctors)}</p>
      <div class="flex gap-2">
        <button
          type="button"
          phx-click="confirm"
          class="rounded-md bg-blue-600 px-3 py-1.5 font-medium text-white hover:bg-blue-700"
        >
          Confirm
        </button>
        <button
          type="button"
          phx-click="cancel"
          class="rounded-md px-3 py-1.5 hover:bg-blue-100 dark:hover:bg-blue-900"
        >
          Cancel
        </button>
      </div>
    </section>
    """
  end

  defp pending_title({"hotel", _}), do: "Your stay"
  defp pending_title({"clinic", _}), do: "Your appointment"
  defp pending_title({"viewing", _}), do: "Viewing request"
  defp pending_title({_id, _}), do: "New event"

  defp pending_text({"hotel", stay}, rooms, _doctors) do
    room = Enum.find(rooms, &(&1.id == stay.resource_id)) || hd(rooms)

    "#{room.title}: #{stay.start} → #{stay.end}, #{stay.nights} nights, $#{stay.nights * room.rate}"
  end

  defp pending_text({"clinic", slot}, _rooms, doctors) do
    doctor = Enum.find(doctors, &(&1.id == slot.resource_id))

    "#{doctor && doctor.title}: #{slot.start |> NaiveDateTime.to_date()} at #{slot.start |> NaiveDateTime.to_time() |> Time.to_string() |> String.slice(0, 5)}"
  end

  defp pending_text({"viewing", slots}, _rooms, _doctors) do
    Enum.map_join(
      slots,
      ", ",
      &"#{NaiveDateTime.to_date(&1.start)} #{&1.start |> NaiveDateTime.to_time() |> Time.to_string() |> String.slice(0, 5)}"
    )
  end

  defp pending_text({_id, span}, _rooms, _doctors), do: "#{span.start} → #{span.end}"
end
