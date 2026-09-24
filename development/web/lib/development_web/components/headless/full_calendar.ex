defmodule DevelopmentWeb.Components.Headless.FullCalendar do
  @moduledoc """
  Headless **full calendar** — month, week, day, list, resource and timeline views in one
  LiveComponent, with selection, booking rules, drag-and-drop and recurring events.

  The calendar is a `Phoenix.LiveComponent`, so it keeps its own state: the view, the visible date
  and what is being selected. It still follows the LiveView life cycle. The grid is `Date`
  arithmetic done on the server. It renders correctly before the socket connects, survives a
  reconnect, and takes its events from the parent like any other assign. Anything that has to
  happen *between* two server messages uses `Phoenix.LiveView.JS`, with no round trip:

  - the "+N more" popovers;
  - `aria-expanded`;
  - loading states.

  One colocated hook (`.FullCalendar`, extracted by LiveView at compile time) does the few things a
  server cannot do:

  - pointer dragging, resizing and drag-to-select;
  - arrow-key focus movement;
  - scrolling the time grid to the working day;
  - moving the "now" line.

  It never renders; it pushes one event when a gesture ends, and the server decides.

  ## Views

  | view | shows | columns |
  | --- | --- | --- |
  | `month` | the month grid, multi-day events as bars, "+N more" when a day overflows | days |
  | `week` / `day` | the time grid, with an all-day lane and overlapping events side by side | days |
  | `resource_day` | the time grid for one day, one column per resource (a doctor, an agent, a room) | resources |
  | `timeline` | one row per resource, days across (a hotel's room chart) | days |
  | `list` | an agenda of the coming days | — |

  ## Selection

  `selectable` decides what a click on a day or a time slot does:

  - `"none"`: it reports a `:date_click`.
  - `"single"`: it picks one day or slot (a doctor's appointment).
  - `"multiple"`: it toggles several (the times a buyer could view a house).
  - `"range"`: it picks a start and an end (a hotel stay, a leave request). A range can be picked
    with two clicks or one drag.

  Every pick is checked on the server against the same rules:

  - `min` / `max`, `allow_past`, `min_notice`;
  - `disabled_dates` / `disabled_weekdays`;
  - the per-day `day_info` status (`"unavailable"`, `"check_in_only"`, `"check_out_only"`);
  - business hours (`select_constraint: "business_hours"`);
  - overlap with existing events (`select_overlap: false`);
  - `min_nights` / `max_nights`, `min_duration` / `max_duration`, `max_selections`.

  The same function also marks the cells it would refuse, so the grid shows what can be picked
  before anyone clicks.

  ## Presets

  `preset` fills in sensible defaults, and anything you set yourself wins:

  - `"hotel"`: month and timeline, range stays with check-out semantics, no overlap, no past.
  - `"doctor"`: resource day, a 15 minute grid, a single slot inside business hours.
  - `"viewing"`: a week grid, several 30 minute viewing slots.
  - `"planner"`: every view, drag and drop, range selection.

  ## Talking to the parent

  The component never changes your data. It tells the LiveView it lives in and lets it decide:

      def handle_info({FullCalendar, "calendar", :select, span}, socket)
      def handle_info({FullCalendar, "calendar", :event_drop, change}, socket)
      def handle_info({FullCalendar, "calendar", :dates_set, %{start: from, end: to}}, socket)

  The messages are:

  - `:dates_set` is sent whenever the visible range changes, including the first connected render,
    so the parent can load only the events it needs.
  - `:select`, `:date_click`, `:event_click`, `:event_drop` and `:event_resize` carry plain maps
    (see `span/0`).
  - `:select_rejected` carries the reason a pick was refused.

  A drop you do not persist simply renders where it was: reverting is free.

  Push changes the other way with `navigate/2`, `change_view/2` and `clear_selection/1`, which use
  `send_update/3`, or pass `view`, `date` and `selection` again.

  ## Calendars, time zones, languages

  Every date is a `Date` in the calendar you pass (`calendar`, default `Calendar.ISO`). The grid only
  uses functions every `Calendar` implementation provides (`beginning_of_month`, `add`,
  `day_of_week`, …), so a Jalali (Shamsi), Hijri or any other calendar module lays out its own
  months. Data on the wire stays ISO 8601, and `labels` carries the month names, the weekday names
  and the digits. Event times are shown in `time_zone`. `"auto"` asks the browser, which needs a
  time zone database such as `tz` or `tzdata`.

  Parts are `root`, `toolbar`, `title`, `previous`, `next`, `today`, `view-button`, `view`, `header`,
  `week`, `day`, `day-number`, `slot`, `axis`, `event`, `resizer`, `more`, `more-popover`,
  `popover`, `list-day`, `resource`, `now` and `status`.

  Ships **no** colors or spacing: layout only. Style via `chelekom-full-calendar*` and the `data-*`
  state attributes, or the per-part `*_class` attributes.

  **Documentation:** https://mishka.tools/chelekom/docs/headless/full_calendar
  """
  use Phoenix.LiveComponent

  alias Phoenix.LiveView.JS

  @views ~w(month week day list resource_day timeline)
  @minute 60
  @day_minutes 1440

  @labels %{
    months:
      ~w(January February March April May June July August September October November December),
    weekdays: ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday),
    weekdays_short: ~w(Mon Tue Wed Thu Fri Sat Sun),
    views: %{
      "month" => "Month",
      "week" => "Week",
      "day" => "Day",
      "list" => "List",
      "resource_day" => "Resources",
      "timeline" => "Timeline"
    },
    today: "Today",
    previous: "Previous",
    next: "Next",
    all_day: "All day",
    more: "+%{count} more",
    no_events: "Nothing scheduled",
    close: "Close",
    week: "W",
    am: "AM",
    pm: "PM",
    digits: nil,
    errors: %{
      unavailable: "That time is not available",
      past: "That time has already passed",
      outside_hours: "That is outside business hours",
      overlap: "That overlaps something already booked",
      no_check_in: "Check-in is not possible on that day",
      no_check_out: "Check-out is not possible on that day",
      min_nights: "Choose at least %{count} nights",
      max_nights: "Choose at most %{count} nights",
      min_duration: "Choose at least %{count} minutes",
      max_duration: "Choose at most %{count} minutes",
      max_selections: "You can choose up to %{count}"
    }
  }

  # Every option lives here once; the wrapper's attrs default to `nil` so "not given" can fall
  # through to the preset, and then to these.
  @defaults %{
    view: "month",
    views: ["month", "week", "day", "list"],
    date: nil,
    events: [],
    resources: [],
    resource_id: nil,
    selectable: "none",
    range_end: "inclusive",
    editable: false,
    calendar: Calendar.ISO,
    first_day_of_week: 1,
    hidden_weekdays: [],
    time_zone: "Etc/UTC",
    now: nil,
    hours: 0..24,
    slot_duration: 30,
    select_duration: nil,
    scroll_to: 8,
    business_hours: nil,
    select_constraint: nil,
    min: nil,
    max: nil,
    disabled_dates: [],
    disabled_weekdays: [],
    allow_past: true,
    min_notice: 0,
    select_overlap: true,
    event_overlap: true,
    min_nights: nil,
    max_nights: nil,
    min_duration: nil,
    max_duration: nil,
    max_selections: nil,
    day_max_events: 3,
    fixed_weeks: true,
    all_day_slot: true,
    week_numbers: false,
    now_indicator: true,
    hour12: false,
    timeline_days: 14,
    list_days: 7,
    default_duration: 60,
    day_info: %{},
    labels: %{},
    event_popover: true,
    notify: true
  }

  @presets %{
    "hotel" => %{
      view: "month",
      views: ["month", "timeline"],
      selectable: "range",
      range_end: "checkout",
      min_nights: 1,
      allow_past: false,
      select_overlap: false,
      day_max_events: 2,
      timeline_days: 14
    },
    "doctor" => %{
      view: "resource_day",
      views: ["resource_day", "week", "day", "list"],
      selectable: "single",
      slot_duration: 15,
      hours: 8..18,
      scroll_to: 8,
      business_hours: %{days: [1, 2, 3, 4, 5], hours: 9..17},
      select_constraint: "business_hours",
      allow_past: false,
      all_day_slot: false,
      select_overlap: false,
      event_overlap: false
    },
    "viewing" => %{
      view: "week",
      views: ["week", "day", "list"],
      selectable: "multiple",
      slot_duration: 30,
      select_duration: 30,
      hours: 9..20,
      scroll_to: 9,
      business_hours: %{days: [1, 2, 3, 4, 5, 6, 7], hours: 10..19},
      select_constraint: "business_hours",
      allow_past: false,
      all_day_slot: false,
      select_overlap: false,
      max_selections: 3
    },
    "planner" => %{
      view: "month",
      views: ["month", "week", "day", "list"],
      selectable: "range",
      editable: true
    }
  }

  @class_keys ~w(class toolbar_class title_class nav_class view_button_class view_class
                 header_class week_class day_class day_number_class slot_class axis_class
                 event_class more_class popover_class list_day_class resource_class now_class
                 status_class)a

  @slot_keys [:event_content, :popover_content, :toolbar_extra, :no_events]
  @controlled [:view, :date, :selection]

  @typedoc """
  What the component reports for a pick, a drop or a resize.

  All-day spans carry `Date`s. Their `end` is exclusive, so `nights` is simply
  `Date.diff(end, start)`. Timed spans carry `NaiveDateTime`s: wall-clock time in `time_zone`,
  which comes along so the parent can turn it into a `DateTime`.
  """
  @type span :: %{
          start: Date.t() | NaiveDateTime.t(),
          end: Date.t() | NaiveDateTime.t(),
          all_day: boolean(),
          resource_id: String.t() | nil,
          time_zone: String.t()
        }

  # ── public wrapper ───────────────────────────────────────────────────────────────────────────

  @doc type: :component
  attr :id, :string, required: true, doc: "Unique id — the component's identity and DOM id"

  attr :preset, :string,
    default: nil,
    values: [nil, "hotel", "doctor", "viewing", "planner"],
    doc: "Defaults for a use case; anything set explicitly wins"

  attr :view, :string, default: nil, values: [nil | @views], doc: "Current view (default `month`)"
  attr :views, :list, default: nil, doc: "The view buttons in the toolbar, in order"
  attr :date, :any, default: nil, doc: "A date inside the period to show (default today)"

  attr :events, :list,
    default: nil,
    doc:
      "Maps or structs: `id`, `title`, `start`, `end`, `all_day`, `resource_id`, `color`, " <>
        "`status`, `display` (`\"background\"` to shade), `editable`, `recurrence`"

  attr :resources, :list,
    default: nil,
    doc: "Maps: `id`, `title`, optional `business_hours` — doctors, agents, rooms"

  attr :resource_id, :string,
    default: nil,
    doc:
      "Scope the month, week, day and list views to one resource — one room's availability, " <>
        "one doctor's diary. Picks then carry that `resource_id`"

  attr :selection, :any,
    default: nil,
    doc: "Controlled selection: a span map, a list of them, a `Date` or a `{from, to}` tuple"

  attr :selectable, :string,
    default: nil,
    values: [nil, "none", "single", "multiple", "range"],
    doc: "What a click on a day or slot picks (default `none`)"

  attr :range_end, :string,
    default: nil,
    values: [nil, "inclusive", "checkout"],
    doc: "`checkout`: the second day of a range is the day a stay ends, not its last night"

  attr :editable, :boolean, default: nil, doc: "Drag to move, drag the edge to resize"
  attr :calendar, :atom, default: nil, doc: "A `Calendar` implementation (default `Calendar.ISO`)"

  attr :first_day_of_week, :integer,
    default: nil,
    doc: "1 is Monday … 7 is Sunday (default 1); 6 for a Saturday-first (Shamsi) week"

  attr :hidden_weekdays, :list, default: nil, doc: "Weekdays (1–7) left out of every view"

  attr :time_zone, :string,
    default: nil,
    doc: "Zone event times are shown in (default `Etc/UTC`); `auto` asks the browser"

  attr :now, :any, default: nil, doc: "Override the current time (tests, demos)"

  attr :hours, :any,
    default: nil,
    doc: "Visible part of the day: `8..20`, or `{~T[08:30:00], ~T[19:00:00]}` (default `0..24`)"

  attr :slot_duration, :integer, default: nil, doc: "Minutes per time-grid row (default 30)"

  attr :select_duration, :integer,
    default: nil,
    doc: "Minutes a click on a slot picks — an appointment's length (default one slot)"

  attr :scroll_to, :integer, default: nil, doc: "Hour the time grid scrolls to (default 8)"

  attr :business_hours, :any,
    default: nil,
    doc: "`true`, `%{days: [1..5], hours: 9..17}` or a list of those; resources may override"

  attr :select_constraint, :string,
    default: nil,
    values: [nil, "business_hours"],
    doc: "Only allow timed picks inside business hours"

  attr :min, :any, default: nil, doc: "First selectable date"
  attr :max, :any, default: nil, doc: "Last selectable date"
  attr :disabled_dates, :list, default: nil, doc: "Dates that cannot be picked"
  attr :disabled_weekdays, :list, default: nil, doc: "Weekdays (1–7) that cannot be picked"
  attr :allow_past, :boolean, default: nil, doc: "Allow picks before now (default true)"
  attr :min_notice, :integer, default: nil, doc: "Minutes of notice a timed pick needs"
  attr :select_overlap, :boolean, default: nil, doc: "Allow picks on top of events"
  attr :event_overlap, :boolean, default: nil, doc: "Allow drops on top of other events"
  attr :min_nights, :integer, default: nil, doc: "Shortest day range, in nights"
  attr :max_nights, :integer, default: nil, doc: "Longest day range, in nights"
  attr :min_duration, :integer, default: nil, doc: "Shortest timed range, in minutes"
  attr :max_duration, :integer, default: nil, doc: "Longest timed range, in minutes"
  attr :max_selections, :integer, default: nil, doc: "Most picks in `multiple` mode"

  attr :day_max_events, :integer,
    default: nil,
    doc: "Event rows per day before \"+N more\" (default 3; `0` for no limit)"

  attr :fixed_weeks, :boolean, default: nil, doc: "Always six weeks in the month view"
  attr :all_day_slot, :boolean, default: nil, doc: "Show the all-day lane above time grids"
  attr :week_numbers, :boolean, default: nil, doc: "Show ISO week numbers in the month view"
  attr :now_indicator, :boolean, default: nil, doc: "Draw the current time in time grids"
  attr :hour12, :boolean, default: nil, doc: "12-hour time labels"
  attr :timeline_days, :integer, default: nil, doc: "Days the timeline view shows (default 14)"
  attr :list_days, :integer, default: nil, doc: "Days the list view shows (default 7)"
  attr :default_duration, :integer, default: nil, doc: "Minutes for timed events with no end"

  attr :day_info, :map,
    default: nil,
    doc:
      ~s|Per day: `%{~D[2026-03-03] => %{label: "$120", status: "check_in_only"}}` — | <>
        "statuses `unavailable`, `check_in_only`, `check_out_only`"

  attr :labels, :map,
    default: nil,
    doc: "Overrides for any text: `months`, `weekdays`, `weekdays_short`, `digits`, `views`, …"

  attr :event_popover, :boolean, default: nil, doc: "Open a details popover on event click"
  attr :notify, :boolean, default: nil, doc: "Send messages to the parent (default true)"

  attr :class, :any, default: nil, doc: "Extra classes for the root"
  attr :toolbar_class, :any, default: nil, doc: ~s|Extra classes for `data-part="toolbar"`|
  attr :title_class, :any, default: nil, doc: ~s|Extra classes for `data-part="title"`|

  attr :nav_class, :any,
    default: nil,
    doc: ~s|Extra classes for the `previous`, `next` and `today` buttons|

  attr :view_button_class, :any,
    default: nil,
    doc: ~s|Extra classes for `data-part="view-button"`|

  attr :view_class, :any, default: nil, doc: ~s|Extra classes for `data-part="view"`|
  attr :header_class, :any, default: nil, doc: ~s|Extra classes for `data-part="header"` cells|
  attr :week_class, :any, default: nil, doc: ~s|Extra classes for `data-part="week"` rows|
  attr :day_class, :any, default: nil, doc: ~s|Extra classes for `data-part="day"`|
  attr :day_number_class, :any, default: nil, doc: ~s|Extra classes for `data-part="day-number"`|
  attr :slot_class, :any, default: nil, doc: ~s|Extra classes for `data-part="slot"`|
  attr :axis_class, :any, default: nil, doc: ~s|Extra classes for `data-part="axis"` labels|
  attr :event_class, :any, default: nil, doc: ~s|Extra classes for `data-part="event"`|
  attr :more_class, :any, default: nil, doc: ~s|Extra classes for `data-part="more"`|

  attr :popover_class, :any,
    default: nil,
    doc: ~s|Extra classes for `data-part="popover"` and `data-part="more-popover"`|

  attr :list_day_class, :any, default: nil, doc: ~s|Extra classes for `data-part="list-day"`|
  attr :resource_class, :any, default: nil, doc: ~s|Extra classes for `data-part="resource"`|
  attr :now_class, :any, default: nil, doc: ~s|Extra classes for `data-part="now"`|
  attr :status_class, :any, default: nil, doc: ~s|Extra classes for `data-part="status"`|
  attr :rest, :global

  slot :event_content, doc: "Replaces an event's content; receives the occurrence"
  slot :popover_content, doc: "Extra content in the event popover; receives the occurrence"
  slot :toolbar_extra, doc: "Rendered at the end of the toolbar"
  slot :no_events, doc: "Shown by the list view when the period is empty"

  def full_calendar(assigns) do
    forward =
      assigns
      |> Map.drop([:__changed__, :id])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    assigns = assign(assigns, :forward, forward)

    ~H"""
    <.live_component module={__MODULE__} id={@id} {@forward} />
    """
  end

  # ── server-pushed commands ───────────────────────────────────────────────────────────────────

  @doc "Shows the period containing `date` in the calendar with `id`."
  @spec navigate(id :: String.t(), date :: Date.t()) :: :ok
  def navigate(id, date), do: send_update(__MODULE__, id: id, action: {:navigate, date})

  @doc "Switches the calendar with `id` to `view`."
  @spec change_view(id :: String.t(), view :: String.t()) :: :ok
  def change_view(id, view), do: send_update(__MODULE__, id: id, action: {:view, view})

  @doc "Drops the current selection of the calendar with `id` (after a booking is saved)."
  @spec clear_selection(id :: String.t()) :: :ok
  def clear_selection(id), do: send_update(__MODULE__, id: id, action: :clear_selection)

  # ── life cycle ───────────────────────────────────────────────────────────────────────────────

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       view: nil,
       date: nil,
       selection: [],
       anchor: nil,
       open_event: nil,
       notice: nil,
       given: %{},
       client_time_zone: nil,
       reported: nil
     )}
  end

  @impl true
  def update(%{action: action}, socket) do
    {:ok, socket |> act(action) |> refresh()}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign(:settings, Map.take(assigns, Map.keys(@defaults) ++ [:preset]))
      |> assign(:classes, Map.take(assigns, @class_keys))
      |> assign(:rest, Map.get(assigns, :rest, %{}))
      |> assign(Map.new(@slot_keys, &{&1, Map.get(assigns, &1, [])}))
      |> adopt(assigns)
      |> refresh()

    {:ok, socket}
  end

  # A controlled value is only taken when the parent actually changes it, so the calendar can
  # still page and pick on its own between the parent's renders.
  defp adopt(socket, assigns) do
    Enum.reduce(@controlled, socket, fn key, acc ->
      given = Map.get(assigns, key)

      if Map.has_key?(assigns, key) and given != Map.get(acc.assigns.given, key) do
        acc
        |> assign(:given, Map.put(acc.assigns.given, key, given))
        |> control(key, given)
      else
        acc
      end
    end)
  end

  defp control(socket, :view, view), do: assign(socket, :view, view)
  defp control(socket, :date, date), do: assign(socket, :date, date && to_date(date))

  defp control(socket, :selection, value) do
    assign(socket, selection: selection_from(value), anchor: nil)
  end

  defp act(socket, {:navigate, date}), do: assign(socket, date: to_date(date), open_event: nil)
  defp act(socket, {:view, view}) when view in @views, do: assign(socket, view: view)
  defp act(socket, :clear_selection), do: assign(socket, selection: [], anchor: nil, notice: nil)
  defp act(socket, _unknown), do: socket

  # Everything the template needs is derived here, once per change, from the state plus options.
  defp refresh(socket) do
    opts = options(socket.assigns.settings, socket.assigns.client_time_zone)
    view = if socket.assigns.view in @views, do: socket.assigns.view, else: opts.view
    now = current_time(opts)
    date = socket.assigns.date || to_date(opts.date) || NaiveDateTime.to_date(now)

    ctx = %{
      opts: opts,
      view: view,
      now: now,
      today: NaiveDateTime.to_date(now),
      date: date,
      selection: socket.assigns.selection,
      anchor: socket.assigns.anchor
    }

    {first, last} = visible_range(view, date, opts)
    ctx = Map.put(ctx, :occurrences, occurrences(opts.events, {first, last}, opts))

    socket
    |> assign(:options, opts)
    |> assign(:ctx, ctx)
    |> assign(:open, socket.assigns.open_event && find_occurrence(ctx, socket.assigns.open_event))
    |> assign(:model, model(view, ctx, {first, last}))
    |> report_dates(view, first, last)
  end

  defp report_dates(socket, view, first, last) do
    range = {view, first, last}

    if connected?(socket) and socket.assigns.reported != range do
      socket
      |> assign(:reported, range)
      |> notify(:dates_set, %{view: view, start: first, end: last})
    else
      socket
    end
  end

  defp notify(socket, name, payload) do
    if socket.assigns.options.notify,
      do: send(self(), {__MODULE__, socket.assigns.id, name, payload})

    socket
  end

  # ── events from the page ─────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("nav", %{"to" => to}, socket) do
    %{ctx: ctx} = socket.assigns

    date =
      case to do
        "today" -> ctx.today
        "previous" -> step(ctx.view, ctx.date, -1, ctx.opts)
        "next" -> step(ctx.view, ctx.date, 1, ctx.opts)
        iso -> to_date(iso) || ctx.date
      end

    {:noreply, socket |> assign(date: date, open_event: nil) |> refresh()}
  end

  def handle_event("view", %{"view" => view} = params, socket) when view in @views do
    date = to_date(params["date"]) || socket.assigns.ctx.date
    {:noreply, socket |> assign(view: view, date: date, open_event: nil) |> refresh()}
  end

  def handle_event("pick", params, socket) do
    {:noreply, socket |> pick(hit_span(params, socket.assigns.ctx)) |> refresh()}
  end

  # A drag across cells: the first cell becomes the anchor and the last one completes the range.
  def handle_event("span", %{"from" => from, "to" => to} = params, socket) do
    %{ctx: ctx} = socket.assigns
    unit = Map.take(params, ["resource", "unit"])
    first = hit_span(Map.put(unit, "start", from), ctx)
    second = hit_span(Map.put(unit, "start", to), ctx)

    socket =
      if (ctx.opts.selectable == "range" and first) && second do
        socket |> assign(:anchor, first) |> finish_range(second)
      else
        socket
      end

    {:noreply, refresh(socket)}
  end

  def handle_event("event_click", %{"key" => key}, socket) do
    socket =
      case find_occurrence(socket.assigns.ctx, key) do
        nil ->
          socket

        occ ->
          socket
          |> assign(:open_event, if(socket.assigns.options.event_popover, do: key))
          |> notify(:event_click, occurrence_payload(occ))
      end

    {:noreply, refresh(socket)}
  end

  def handle_event("close_popover", _params, socket) do
    {:noreply, socket |> assign(:open_event, nil) |> refresh()}
  end

  def handle_event("drop", %{"key" => key, "from" => from, "to" => to} = params, socket) do
    ctx = socket.assigns.ctx

    with %{} = occ <- find_occurrence(ctx, key),
         true <- occ.editable,
         {:ok, moved} <- move(occ, from, to, params, ctx.opts) do
      {:noreply, socket |> commit_change(occ, moved, :event_drop) |> refresh()}
    else
      _other -> {:noreply, refresh(socket)}
    end
  end

  def handle_event("resize", %{"key" => key, "to" => to}, socket) do
    ctx = socket.assigns.ctx

    with %{} = occ <- find_occurrence(ctx, key),
         true <- occ.editable,
         %NaiveDateTime{} = new_end <- to_naive(to, ctx.opts.time_zone) do
      min_end = NaiveDateTime.add(occ.start, unit_minutes(occ, ctx.opts) * @minute)
      new_end = latest(new_end, min_end)
      {:noreply, socket |> commit_change(occ, %{occ | end: new_end}, :event_resize) |> refresh()}
    else
      _other -> {:noreply, refresh(socket)}
    end
  end

  def handle_event("time_zone", %{"time_zone" => zone}, socket) when is_binary(zone) do
    zone = if zone_supported?(zone), do: zone
    {:noreply, socket |> assign(:client_time_zone, zone) |> refresh()}
  end

  def handle_event("dismiss", _params, socket) do
    {:noreply, socket |> assign(notice: nil, anchor: nil) |> refresh()}
  end

  # A stale page or a hand-made payload is ignored rather than crashing the parent LiveView.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # ── selection ────────────────────────────────────────────────────────────────────────────────

  defp pick(socket, nil), do: socket

  defp pick(socket, span) do
    %{ctx: %{opts: opts} = ctx} = socket.assigns

    case opts.selectable do
      "none" ->
        notify(socket, :date_click, public_span(span, opts))

      "single" ->
        with_valid(socket, check(span, ctx), fn socket ->
          socket
          |> assign(selection: [span], notice: nil)
          |> notify(:select, public_span(span, opts))
        end)

      "multiple" ->
        toggle(socket, span)

      "range" ->
        if socket.assigns.anchor, do: finish_range(socket, span), else: start_range(socket, span)
    end
  end

  defp toggle(socket, span) do
    %{ctx: %{opts: opts} = ctx, selection: selection} = socket.assigns

    if Enum.any?(selection, &same_span?(&1, span)) do
      selection = Enum.reject(selection, &same_span?(&1, span))
      report_selection(assign(socket, selection: selection, notice: nil), opts)
    else
      result =
        if opts.max_selections && length(selection) >= opts.max_selections,
          do: {:error, {:max_selections, opts.max_selections}},
          else: check(span, ctx)

      with_valid(socket, result, fn socket ->
        socket
        |> assign(
          selection: Enum.sort_by(selection ++ [span], & &1.start, NaiveDateTime),
          notice: nil
        )
        |> report_selection(opts)
      end)
    end
  end

  defp report_selection(socket, opts) do
    notify(socket, :select, Enum.map(socket.assigns.selection, &public_span(&1, opts)))
  end

  # The first click of a range. For a stay, the first day must allow a check-in.
  defp start_range(socket, span) do
    %{ctx: ctx} = socket.assigns

    with_valid(socket, check(span, ctx, edge: :start), fn socket ->
      assign(socket, anchor: span, selection: [], notice: nil)
    end)
  end

  defp finish_range(socket, span) do
    %{ctx: %{opts: opts} = ctx, anchor: anchor} = socket.assigns

    cond do
      anchor.resource_id != span.resource_id or anchor.all_day != span.all_day ->
        start_range(assign(socket, :anchor, nil), span)

      NaiveDateTime.compare(span.start, anchor.start) == :lt ->
        start_range(assign(socket, :anchor, nil), span)

      true ->
        range = join(anchor, span, opts)

        with_valid(socket, check(range, ctx, edge: :range), fn socket ->
          socket
          |> assign(selection: [range], anchor: nil, notice: nil)
          |> notify(:select, public_span(range, opts))
        end)
    end
  end

  # With check-out semantics the second click is the morning the stay ends, so it adds no night;
  # clicking the check-in day again is read as a one-night stay rather than an empty one.
  defp join(anchor, span, %{range_end: "checkout"}) do
    finish = if span.all_day, do: latest(span.start, anchor.end), else: span.end
    %{anchor | end: finish}
  end

  defp join(anchor, span, _opts), do: %{anchor | end: latest(anchor.end, span.end)}

  defp with_valid(socket, :ok, fun), do: fun.(socket)

  defp with_valid(socket, {:error, reason}, _fun) do
    opts = socket.assigns.ctx.opts

    socket
    |> assign(:notice, error_text(reason, opts.labels))
    |> notify(:select_rejected, %{reason: reason_key(reason)})
  end

  defp commit_change(socket, occ, changed, name) do
    %{ctx: ctx} = socket.assigns
    span = Map.take(changed, [:start, :end, :all_day, :resource_id])

    case check(span, ctx, overlap: ctx.opts.event_overlap, except: occ.id) do
      :ok ->
        payload =
          occ
          |> occurrence_payload()
          |> Map.merge(public_span(span, ctx.opts))
          |> Map.put(:previous, public_span(occ, ctx.opts))

        notify(assign(socket, :notice, nil), name, payload)

      {:error, reason} ->
        assign(socket, :notice, error_text(reason, ctx.opts.labels))
    end
  end

  defp move(occ, from, to, params, opts) do
    with %NaiveDateTime{} = from <- to_naive(from, opts.time_zone),
         %NaiveDateTime{} = to <- to_naive(to, opts.time_zone) do
      target_all_day = params["all_day"] in ["true", true]
      resource = blank_to_nil(params["resource"]) || occ.resource_id

      {:ok, %{shift(occ, from, to, target_all_day, opts) | resource_id: resource}}
    else
      _invalid -> :error
    end
  end

  defp shift(%{all_day: all_day} = occ, from, to, all_day, _opts) do
    delta = NaiveDateTime.diff(to, from)
    %{occ | start: NaiveDateTime.add(occ.start, delta), end: NaiveDateTime.add(occ.end, delta)}
  end

  # Crossing between the all-day lane and the time grid changes what the event is.
  defp shift(occ, _from, to, all_day, opts) do
    minutes = if all_day, do: @day_minutes, else: opts.default_duration
    %{occ | start: to, end: NaiveDateTime.add(to, minutes * @minute), all_day: all_day}
  end

  @doc """
  Checks a span against every booking rule and returns `:ok` or `{:error, reason}`.

  `ctx` is the calendar state (`opts`, `now`, `today`, `occurrences`), which is what the component
  itself passes; it is public so a parent can re-check a pick before saving it. `edge: :start`
  checks only what the first click of a range needs, and `edge: :range` the whole range.
  """
  @spec check(span :: map(), ctx :: map(), rules :: keyword()) :: :ok | {:error, term()}
  def check(span, ctx, rules \\ []) do
    opts = ctx.opts
    overlap_allowed = Keyword.get(rules, :overlap, opts.select_overlap)
    days = covered_days(span)
    edge = edge_problem(span, days, opts, rules[:edge])

    cond do
      Enum.any?(days, &out_of_bounds?(&1, opts)) ->
        {:error, :unavailable}

      past?(span, ctx) ->
        {:error, :past}

      Enum.any?(days, &blocked_day?(&1, opts)) ->
        {:error, :unavailable}

      edge ->
        {:error, edge}

      not within_hours?(span, opts) ->
        {:error, :outside_hours}

      not overlap_allowed and overlaps_event?(span, ctx.occurrences, rules[:except]) ->
        {:error, :overlap}

      true ->
        length_check(span, opts, Keyword.get(rules, :edge))
    end
  end

  defp covered_days(span) do
    last = span.end |> NaiveDateTime.add(-1) |> NaiveDateTime.to_date()
    Date.range(NaiveDateTime.to_date(span.start), last) |> Enum.to_list()
  end

  defp out_of_bounds?(date, opts) do
    (opts.min && Date.compare(date, opts.min) == :lt) ||
      (opts.max && Date.compare(date, opts.max) == :gt) || false
  end

  defp past?(%{all_day: true} = span, ctx) do
    not ctx.opts.allow_past and Date.compare(NaiveDateTime.to_date(span.start), ctx.today) == :lt
  end

  defp past?(span, ctx) do
    earliest = NaiveDateTime.add(ctx.now, ctx.opts.min_notice * @minute)
    not ctx.opts.allow_past and NaiveDateTime.compare(span.start, earliest) == :lt
  end

  defp blocked_day?(date, opts) do
    MapSet.member?(opts.disabled_dates, date) or
      Date.day_of_week(date) in opts.disabled_weekdays or
      day_status(date, opts) == "unavailable"
  end

  defp day_status(date, opts) do
    case Map.get(opts.day_info, date) do
      %{} = info -> info |> field(:status) |> blank_to_nil()
      _none -> nil
    end
  end

  # Hotel days can forbid arriving or leaving: the first night must allow a check-in and the
  # morning after the last night must allow a check-out.
  defp edge_problem(%{all_day: true}, [first | _] = days, opts, edge)
       when edge in [:start, :range] do
    checkout = days |> List.last() |> Date.add(1)

    cond do
      day_status(first, opts) == "check_out_only" -> :no_check_in
      edge == :range and day_status(checkout, opts) == "check_in_only" -> :no_check_out
      true -> nil
    end
  end

  defp edge_problem(_span, _days, _opts, _edge), do: nil

  defp within_hours?(%{all_day: true}, _opts), do: true
  defp within_hours?(_span, %{select_constraint: nil}), do: true

  defp within_hours?(span, opts) do
    date = NaiveDateTime.to_date(span.start)
    from = minute_of_day(span.start)
    to = from + div(NaiveDateTime.diff(span.end, span.start), @minute)

    opts
    |> business_windows(span.resource_id)
    |> Enum.any?(fn window ->
      Date.day_of_week(date) in window.days and from >= window.from and to <= window.to
    end)
  end

  defp overlaps_event?(span, occurrences, except) do
    Enum.any?(occurrences, fn occ ->
      occ.id != except and same_resource?(occ.resource_id, span.resource_id) and
        overlap?(occ, span)
    end)
  end

  defp length_check(span, opts, :range) do
    if span.all_day do
      nights = NaiveDateTime.diff(span.end, span.start, :day)
      bounds(nights, opts.min_nights, opts.max_nights, :min_nights, :max_nights)
    else
      minutes = div(NaiveDateTime.diff(span.end, span.start), @minute)
      bounds(minutes, opts.min_duration, opts.max_duration, :min_duration, :max_duration)
    end
  end

  defp length_check(_span, _opts, _edge), do: :ok

  defp bounds(value, min, _max, min_reason, _max_reason) when is_integer(min) and value < min,
    do: {:error, {min_reason, min}}

  defp bounds(value, _min, max, _min_reason, max_reason) when is_integer(max) and value > max,
    do: {:error, {max_reason, max}}

  defp bounds(_value, _min, _max, _min_reason, _max_reason), do: :ok

  defp reason_key({reason, _count}), do: reason
  defp reason_key(reason), do: reason

  defp error_text({reason, count}, labels) do
    labels.errors |> Map.get(reason, to_string(reason)) |> interpolate(count, labels)
  end

  defp error_text(reason, labels), do: Map.get(labels.errors, reason, to_string(reason))

  # ── options ──────────────────────────────────────────────────────────────────────────────────

  @doc """
  Resolves the options a calendar runs with: the defaults, then the `preset`, then everything
  given explicitly (`nil` counts as not given). Public so the rules can be tested and reused.
  """
  @spec options(given :: map(), client_time_zone :: String.t() | nil) :: map()
  def options(given, client_time_zone \\ nil) do
    preset = Map.get(@presets, to_string(given[:preset]), %{})

    explicit =
      for {key, value} <- given,
          Map.has_key?(@defaults, key),
          not is_nil(value),
          into: %{},
          do: {key, value}

    opts = @defaults |> Map.merge(preset) |> Map.merge(explicit)
    labels = merge_labels(opts.labels)

    %{
      opts
      | views: Enum.filter(opts.views, &(&1 in @views)),
        labels: labels,
        time_zone: resolve_zone(opts.time_zone, client_time_zone),
        hours: minutes_window(opts.hours),
        business_hours: windows(opts.business_hours),
        disabled_dates: MapSet.new(opts.disabled_dates, &to_date/1),
        min: to_date(opts.min),
        max: to_date(opts.max),
        day_info: Map.new(opts.day_info, fn {date, info} -> {to_date(date), info} end),
        select_duration: opts.select_duration || opts.slot_duration,
        day_max_events: if(opts.day_max_events in [0, nil], do: nil, else: opts.day_max_events),
        resources: Enum.map(opts.resources, &normalize_resource/1),
        resource_id: maybe_string(opts.resource_id)
    }
  end

  defp merge_labels(overrides) do
    overrides = Map.new(overrides, fn {key, value} -> {to_atom_key(key), value} end)

    Map.merge(@labels, overrides, fn
      key, default, given when key in [:views, :errors] and is_map(given) ->
        Map.merge(default, given)

      _key, _default, given ->
        given
    end)
  end

  defp to_atom_key(key) when is_atom(key), do: key
  defp to_atom_key(key) when is_binary(key), do: String.to_existing_atom(key)

  defp resolve_zone("auto", client), do: client || "Etc/UTC"
  defp resolve_zone(zone, _client), do: zone

  defp zone_supported?(zone) do
    match?({:ok, _}, DateTime.shift_zone(DateTime.utc_now(), zone))
  rescue
    _error -> false
  end

  # Hours are given the way people say them — `9..17` — or as exact times; the grid works in
  # minutes of the day either way.
  defp minutes_window(%Range{first: from, last: to}), do: {from * 60, to * 60}
  defp minutes_window({%Time{} = from, %Time{} = to}), do: {minute_of_day(from), time_end(to)}
  defp minutes_window(_other), do: {0, @day_minutes}

  defp time_end(~T[00:00:00]), do: @day_minutes
  defp time_end(time), do: minute_of_day(time)

  defp windows(nil), do: []
  defp windows(false), do: []
  defp windows(true), do: windows(%{days: [1, 2, 3, 4, 5], hours: 9..17})
  defp windows(list) when is_list(list), do: Enum.flat_map(list, &windows/1)

  defp windows(%{} = window) do
    {from, to} = window |> field(:hours) |> minutes_window()
    days = window |> field(:days) |> Kernel.||(1..7) |> Enum.to_list()
    [%{days: days, from: from, to: to}]
  end

  defp business_windows(opts, resource_id) do
    case Enum.find(opts.resources, &(&1.id == resource_id)) do
      %{business_hours: [_ | _] = own} -> own
      _other -> opts.business_hours
    end
  end

  defp normalize_resource(resource) do
    %{
      id: resource |> field(:id) |> to_string(),
      title: field(resource, :title) || to_string(field(resource, :id)),
      business_hours: windows(field(resource, :business_hours)),
      source: resource
    }
  end

  # ── visible range and navigation ─────────────────────────────────────────────────────────────

  @doc """
  The first visible ISO date and the exclusive last one for `view` around `date`.

  Month boundaries come from `opts.calendar`, so a Shamsi month is the Shamsi month.
  """
  @spec visible_range(view :: String.t(), date :: Date.t(), opts :: map()) :: {Date.t(), Date.t()}
  def visible_range("month", date, opts) do
    weeks = weeks(date, opts)
    {weeks |> hd() |> hd(), weeks |> List.last() |> List.last() |> Date.add(1)}
  end

  def visible_range(view, date, opts) when view in ["week", "list"] do
    first = week_start(date, opts)
    days = if view == "list", do: opts.list_days, else: 7
    {first, Date.add(first, days)}
  end

  def visible_range("timeline", date, opts) do
    first = if opts.timeline_days >= 7, do: week_start(date, opts), else: date
    {first, Date.add(first, opts.timeline_days)}
  end

  def visible_range(_day_view, date, _opts), do: {date, Date.add(date, 1)}

  @doc """
  The weeks of the month containing `date`, as ISO `Date`s, laid out by `opts.calendar` and
  `opts.first_day_of_week`, with hidden weekdays left out.
  """
  @spec weeks(date :: Date.t(), opts :: map()) :: [[Date.t()]]
  def weeks(date, opts) do
    local = in_calendar(date, opts)
    first = Date.beginning_of_month(local)
    start = local_week_start(first, opts)
    last_day = Date.end_of_month(local)
    count = if opts.fixed_weeks, do: 6, else: ceil((Date.diff(last_day, start) + 1) / 7)

    for week <- 0..(count - 1) do
      for day <- 0..6,
          iso = start |> Date.add(week * 7 + day) |> Date.convert!(Calendar.ISO),
          Date.day_of_week(iso) not in opts.hidden_weekdays,
          do: iso
    end
  end

  defp week_start(date, opts) do
    date |> in_calendar(opts) |> local_week_start(opts) |> Date.convert!(Calendar.ISO)
  end

  defp local_week_start(date, opts) do
    Date.beginning_of_week(date, weekday_atom(opts.first_day_of_week))
  end

  defp weekday_atom(day),
    do: Enum.at(~w(monday tuesday wednesday thursday friday saturday sunday)a, day - 1)

  defp in_calendar(date, opts), do: Date.convert!(date, opts.calendar)

  # Months are paged in the display calendar: the day after the end of this month, or the day
  # before its start — never `month ± 1`, which only means something in one calendar.
  defp step("month", date, direction, opts) do
    local = date |> in_calendar(opts) |> Date.beginning_of_month()

    target =
      if direction > 0,
        do: local |> Date.end_of_month() |> Date.add(1),
        else: local |> Date.add(-1) |> Date.beginning_of_month()

    Date.convert!(target, Calendar.ISO)
  end

  defp step("week", date, direction, _opts), do: Date.add(date, 7 * direction)
  defp step("list", date, direction, opts), do: Date.add(date, opts.list_days * direction)
  defp step("timeline", date, direction, opts), do: Date.add(date, opts.timeline_days * direction)
  defp step(_day_view, date, direction, _opts), do: Date.add(date, direction)

  defp visible_days(first, last, opts) do
    first
    |> Date.range(Date.add(last, -1))
    |> Enum.reject(&(Date.day_of_week(&1) in opts.hidden_weekdays))
  end

  # ── events ───────────────────────────────────────────────────────────────────────────────────

  @doc """
  Normalizes `events` and expands recurring ones into the occurrences that touch `{first, last}`.

  An event is a map or struct with atom or string keys. Times may be `Date`, `NaiveDateTime`,
  `DateTime` (shifted to `opts.time_zone`) or ISO 8601 strings. `recurrence` is a map
  (`freq`, `interval`, `by_day`, `count`, `until`, `exdates`) or an RRULE string such as
  `"FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10"`.
  """
  @spec occurrences(events :: [map()], range :: {Date.t(), Date.t()}, opts :: map()) :: [map()]
  def occurrences(events, {first, last}, opts) do
    window = %{start: midnight(first), end: midnight(last)}

    events
    |> Enum.flat_map(fn event ->
      case normalize_event(event, opts) do
        nil -> []
        occ -> expand(occ, field(event, :recurrence), window)
      end
    end)
    |> Enum.filter(&overlap?(&1, window))
    |> Enum.sort_by(&order_key/1)
  end

  # FullCalendar's default order: earlier first, then longer first, all-day before timed, title.
  defp order_key(occ) do
    {NaiveDateTime.to_gregorian_seconds(occ.start), -NaiveDateTime.diff(occ.end, occ.start),
     not occ.all_day, occ.title}
  end

  defp normalize_event(event, opts) do
    start = event |> field(:start) |> to_naive(opts.time_zone)
    id = field(event, :id)

    if start && id, do: build_event(event, to_string(id), start, opts)
  end

  defp build_event(event, id, start, opts) do
    all_day = all_day?(event)
    start = if all_day, do: NaiveDateTime.beginning_of_day(start), else: start
    background = event |> field(:display) |> to_string() == "background"

    %{
      id: id,
      key: id,
      title: to_string(field(event, :title) || ""),
      start: start,
      end: event_end(event, start, all_day, opts),
      all_day: all_day,
      resource_id: event |> field(:resource_id) |> blank_to_nil() |> maybe_string(),
      color: event |> field(:color) |> safe_color(),
      status: event |> field(:status) |> maybe_string(),
      background: background,
      editable: not background and editable?(event, opts),
      recurring: not is_nil(field(event, :recurrence)),
      source: event
    }
  end

  # A missing or backwards end means a default length; an all-day end that is not midnight still
  # covers that day.
  defp event_end(event, start, all_day, opts) do
    finish = event |> field(:end) |> to_naive(opts.time_zone)

    cond do
      is_nil(finish) or NaiveDateTime.compare(finish, start) != :gt ->
        minutes = if all_day, do: @day_minutes, else: opts.default_duration
        NaiveDateTime.add(start, minutes * @minute)

      all_day ->
        ceil_day(finish)

      true ->
        finish
    end
  end

  defp all_day?(event) do
    case field(event, :all_day) do
      nil -> match?(%Date{}, field(event, :start)) or date_string?(field(event, :start))
      value -> value in [true, "true"]
    end
  end

  defp editable?(event, opts) do
    case field(event, :editable) do
      nil -> opts.editable == true
      value -> value in [true, "true"]
    end
  end

  defp ceil_day(time) do
    if NaiveDateTime.to_time(time) == ~T[00:00:00],
      do: time,
      else: time |> NaiveDateTime.beginning_of_day() |> NaiveDateTime.add(@day_minutes * @minute)
  end

  defp expand(occ, nil, _window), do: [occ]

  defp expand(occ, rule, window) do
    rule = recurrence(rule)
    first_day = NaiveDateTime.to_date(occ.start)
    duration = NaiveDateTime.diff(occ.end, occ.start)
    time = NaiveDateTime.to_time(occ.start)
    window_end = NaiveDateTime.to_date(window.end)

    rule
    |> candidates(first_day)
    |> Stream.filter(&(Date.compare(&1, first_day) != :lt))
    |> Stream.take_while(&(Date.compare(&1, window_end) == :lt))
    |> Stream.take_while(&(is_nil(rule.until) or Date.compare(&1, rule.until) != :gt))
    |> take_count(rule.count)
    |> Stream.take(5000)
    |> Stream.reject(&(&1 in rule.exdates))
    |> Enum.map(fn day ->
      start = NaiveDateTime.new!(day, time)

      %{
        occ
        | start: start,
          end: NaiveDateTime.add(start, duration),
          key: "#{occ.id}@#{NaiveDateTime.to_iso8601(start)}"
      }
    end)
  end

  defp take_count(stream, nil), do: stream
  defp take_count(stream, count), do: Stream.take(stream, count)

  defp candidates(%{freq: :daily, interval: step}, first) do
    Stream.iterate(first, &Date.add(&1, step))
  end

  defp candidates(%{freq: :weekly, interval: step, by_day: by_day}, first) do
    days = if by_day == [], do: [Date.day_of_week(first)], else: Enum.sort(by_day)
    monday = Date.beginning_of_week(first)

    Stream.iterate(monday, &Date.add(&1, 7 * step))
    |> Stream.flat_map(fn week -> Enum.map(days, &Date.add(week, &1 - 1)) end)
  end

  defp candidates(%{freq: freq, interval: step}, first) when freq in [:monthly, :yearly] do
    months = if freq == :yearly, do: 12 * step, else: step

    Stream.iterate(0, &(&1 + months))
    |> Stream.flat_map(fn offset ->
      total = first.year * 12 + first.month - 1 + offset

      case Date.new(div(total, 12), rem(total, 12) + 1, first.day) do
        {:ok, day} -> [day]
        {:error, _no_such_day} -> []
      end
    end)
  end

  @doc """
  Reads a recurrence rule: a map (atom or string keys) or an RRULE string. Supports `FREQ`
  (`DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY`), `INTERVAL`, `BYDAY`, `COUNT` and `UNTIL`, plus
  `exdates` in the map form.
  """
  @rrule_keys %{
    "freq" => :freq,
    "interval" => :interval,
    "byday" => :by_day,
    "count" => :count,
    "until" => :until
  }

  @spec recurrence(rule :: map() | String.t()) :: map()
  def recurrence("RRULE:" <> rule), do: recurrence(rule)

  def recurrence(rule) when is_binary(rule) do
    rule
    |> String.split(";", trim: true)
    |> Map.new(fn part ->
      [key, value] = String.split(part, "=", parts: 2)
      {String.downcase(key), value}
    end)
    |> Map.update("byday", [], &String.split(&1, ","))
    |> Map.take(Map.keys(@rrule_keys))
    |> Map.new(fn {key, value} -> {Map.fetch!(@rrule_keys, key), value} end)
    |> recurrence()
  end

  def recurrence(%{} = rule) do
    %{
      freq: rule |> field(:freq) |> to_string() |> String.downcase() |> freq(),
      interval: rule |> field(:interval) |> to_int(1) |> max(1),
      by_day: rule |> field(:by_day) |> List.wrap() |> Enum.map(&weekday_number/1),
      count: rule |> field(:count) |> to_int(nil),
      until: rule |> field(:until) |> to_date(),
      exdates: rule |> field(:exdates) |> List.wrap() |> Enum.map(&to_date/1)
    }
  end

  defp freq("daily"), do: :daily
  defp freq("monthly"), do: :monthly
  defp freq("yearly"), do: :yearly
  defp freq(_weekly), do: :weekly

  @rrule_days %{"MO" => 1, "TU" => 2, "WE" => 3, "TH" => 4, "FR" => 5, "SA" => 6, "SU" => 7}

  defp weekday_number(day) when is_integer(day), do: day
  defp weekday_number(day), do: Map.fetch!(@rrule_days, day |> to_string() |> String.upcase())

  defp find_occurrence(ctx, key), do: Enum.find(ctx.occurrences, &(&1.key == key))

  defp occurrence_payload(occ) do
    %{id: occ.id, key: occ.key, event: occ.source, recurring: occ.recurring}
  end

  # ── layout ───────────────────────────────────────────────────────────────────────────────────

  @doc """
  Lays events out in a row of day columns — a month week, the all-day lane of a week, a
  resource's row in the timeline. Each column is `%{date: Date, resource_id: id | nil}`.

  An event becomes one bar per run of columns it covers, flagged where it really starts and ends.
  Bars take the first level (row) where they fit, which is FullCalendar's classic packing. With
  `max_levels`, bars below the limit are hidden and counted per column for "+N more".
  """
  @spec day_row(columns :: [map()], events :: [map()], max_levels :: pos_integer() | nil) :: map()
  def day_row(columns, events, max_levels) do
    indexed = Enum.with_index(columns)

    segments =
      events
      |> Enum.reject(& &1.background)
      |> Enum.flat_map(&segments_for(&1, indexed))
      |> Enum.sort_by(fn seg -> {seg.col, -seg.span, order_key(seg.event)} end)

    {placed, hidden, _levels} =
      Enum.reduce(segments, {[], [], []}, fn seg, {placed, hidden, levels} ->
        cols = MapSet.new(seg.col..(seg.col + seg.span - 1))
        level = Enum.find_index(levels, &MapSet.disjoint?(&1, cols)) || length(levels)

        if max_levels && level >= max_levels do
          {placed, [seg | hidden], levels}
        else
          levels = List.update_at(levels ++ [MapSet.new()], level, &MapSet.union(&1, cols))

          {[Map.put(seg, :level, level) | placed], hidden,
           Enum.reject(levels, &(&1 == MapSet.new()))}
        end
      end)

    more =
      for seg <- hidden, col <- seg.col..(seg.col + seg.span - 1), reduce: %{} do
        acc -> Map.update(acc, col, 1, &(&1 + 1))
      end

    %{
      segments: Enum.reverse(placed),
      more: more,
      levels: placed |> Enum.map(& &1.level) |> Enum.max(fn -> -1 end) |> Kernel.+(1),
      backgrounds: Enum.filter(events, & &1.background)
    }
  end

  defp segments_for(event, indexed) do
    indexed
    |> Enum.filter(fn {column, _index} ->
      same_resource?(event.resource_id, column.resource_id) and
        overlap?(event, day_span(column.date))
    end)
    |> Enum.map(fn {_column, index} -> index end)
    |> Enum.chunk_while([], &chunk_run/2, &{:cont, Enum.reverse(&1), []})
    |> Enum.reject(&(&1 == []))
    |> Enum.map(fn [first | _] = run ->
      last = List.last(run)
      {first_col, _} = Enum.at(indexed, first)
      {last_col, _} = Enum.at(indexed, last)

      %{
        event: event,
        col: first,
        span: length(run),
        starts: NaiveDateTime.compare(event.start, midnight(first_col.date)) != :lt,
        ends: NaiveDateTime.compare(event.end, day_span(last_col.date).end) != :gt
      }
    end)
  end

  defp chunk_run(index, []), do: {:cont, [index]}
  defp chunk_run(index, [prev | _] = run) when index == prev + 1, do: {:cont, [index | run]}
  defp chunk_run(index, run), do: {:cont, Enum.reverse(run), [index]}

  @doc """
  Places timed events side by side in one time-grid column — FullCalendar's v7 approach.

  1. Pack the events into levels. Each level becomes a sub-column.
  2. Group events that touch, directly or through others; each group splits the width by its
     deepest level.
  3. Let each event widen until the first deeper event it collides with.

  Returns each event with `level`, `left` and `width` as fractions of the column.
  """
  @spec time_layout(events :: [map()]) :: [map()]
  def time_layout(events) do
    sorted = Enum.sort_by(events, &order_key/1)

    {placed, _levels} =
      Enum.reduce(sorted, {[], []}, fn event, {placed, levels} ->
        level =
          Enum.find_index(levels, fn level -> not Enum.any?(level, &overlap?(&1, event)) end)

        level = level || length(levels)
        levels = List.update_at(levels ++ [[]], level, &[event | &1]) |> Enum.reject(&(&1 == []))
        {[{event, level} | placed], levels}
      end)

    placed = Enum.reverse(placed)
    groups = collision_groups(placed)

    Enum.map(placed, fn {event, level} ->
      depth = groups |> Map.fetch!(event.key) |> Kernel.+(1)

      far =
        placed
        |> Enum.filter(fn {other, other_level} ->
          other_level > level and overlap?(other, event)
        end)
        |> Enum.map(fn {_other, other_level} -> other_level end)
        |> Enum.min(fn -> depth end)

      Map.merge(event, %{level: level, left: level / depth, width: (far - level) / depth})
    end)
  end

  # The deepest level reachable from each event through a chain of overlaps.
  defp collision_groups(placed) do
    placed
    |> Enum.reduce([], fn {event, level}, groups ->
      {touching, apart} = Enum.split_with(groups, &touches?(&1, event))

      [[{event, level} | List.flatten(touching)] | apart]
    end)
    |> Enum.flat_map(fn group ->
      deepest = group |> Enum.map(&elem(&1, 1)) |> Enum.max()
      Enum.map(group, fn {event, _level} -> {event.key, deepest} end)
    end)
    |> Map.new()
  end

  defp touches?(group, event),
    do: Enum.any?(group, fn {other, _level} -> overlap?(other, event) end)

  # ── the view model ───────────────────────────────────────────────────────────────────────────

  defp model(view, ctx, {first, last}) do
    base = %{
      view: view,
      title: title(view, ctx.date, {first, last}, ctx.opts),
      first: first,
      last: last
    }

    Map.merge(base, body(view, ctx, {first, last}))
  end

  defp body("month", ctx, _range) do
    %{opts: opts} = ctx
    weeks = weeks(ctx.date, opts)
    month = ctx.date |> in_calendar(opts) |> Map.take([:year, :month])
    focus = focus_date(ctx, List.flatten(weeks))

    rows =
      weeks
      |> Enum.with_index()
      |> Enum.map(fn {days, row} ->
        columns = Enum.map(days, &%{date: &1, resource_id: opts.resource_id})

        %{
          number: week_number(hd(days)),
          layout: day_row(columns, ctx.occurrences, opts.day_max_events),
          hits:
            Enum.with_index(columns, fn column, col ->
              day_hit(column, row, col, ctx, focus, month)
            end),
          more: more_lists(columns, ctx.occurrences)
        }
      end)

    %{weekdays: weekday_headers(hd(weeks), opts), rows: rows}
  end

  defp body(view, ctx, {first, last}) when view in ["week", "day", "resource_day"] do
    %{opts: opts} = ctx
    days = visible_days(first, last, opts)

    columns =
      if view == "resource_day" and opts.resources != [] do
        for day <- days,
            resource <- opts.resources,
            do: %{date: day, resource_id: resource.id, title: resource.title}
      else
        Enum.map(days, &%{date: &1, resource_id: opts.resource_id, title: nil})
      end

    {from, to} = opts.hours
    slot_count = div(to - from + opts.slot_duration - 1, opts.slot_duration)
    focus = focus_slot(ctx, columns, from)

    %{
      columns: Enum.map(columns, &Map.put(&1, :today, &1.date == ctx.today)),
      all_day: all_day_lane(columns, ctx),
      all_day_hits:
        Enum.with_index(columns, fn column, col ->
          day_hit(Map.take(column, [:date, :resource_id]), 0, col, ctx, nil, nil)
        end),
      axis:
        for(i <- 0..(slot_count - 1), do: format_minutes(from + i * opts.slot_duration, opts)),
      scroll_row: max(div(opts.scroll_to * 60 - from, opts.slot_duration), 0),
      slots:
        Enum.with_index(columns, fn column, col ->
          for i <- 0..(slot_count - 1), do: slot_hit(column, i, col, from, ctx, focus)
        end),
      timed: Enum.map(columns, &timed_in_column(&1, ctx)),
      now: now_line(columns, ctx),
      window: {from, to}
    }
  end

  defp body("timeline", ctx, {first, last}) do
    %{opts: opts} = ctx
    days = visible_days(first, last, opts)
    resources = if opts.resources == [], do: [%{id: nil, title: ""}], else: opts.resources
    focus = focus_date(ctx, days)

    rows =
      resources
      |> Enum.with_index()
      |> Enum.map(fn {resource, row} ->
        columns = Enum.map(days, &%{date: &1, resource_id: resource.id})

        %{
          resource: resource,
          layout: day_row(columns, ctx.occurrences, nil),
          hits:
            Enum.with_index(columns, fn column, col ->
              day_hit(column, row, col, ctx, row == 0 && focus, nil)
            end),
          more: %{}
        }
      end)

    %{days: Enum.map(days, &day_header(&1, ctx)), rows: rows}
  end

  defp body("list", ctx, {first, last}) do
    days =
      for day <- visible_days(first, last, ctx.opts),
          events = Enum.filter(ctx.occurrences, &listed?(&1, day, ctx.opts)),
          events != [],
          do: %{
            date: day,
            label: long_date(day, ctx.opts),
            today: day == ctx.today,
            events: events
          }

    %{days: days}
  end

  defp listed?(occ, day, opts) do
    not occ.background and same_resource?(occ.resource_id, opts.resource_id) and
      overlap?(occ, day_span(day))
  end

  defp all_day_lane(columns, ctx) do
    events = Enum.filter(ctx.occurrences, & &1.all_day)
    day_row(Enum.map(columns, &Map.take(&1, [:date, :resource_id])), events, nil)
  end

  defp more_lists(columns, occurrences) do
    columns
    |> Enum.with_index()
    |> Map.new(fn {column, col} ->
      {col,
       Enum.filter(occurrences, fn occ ->
         not occ.background and same_resource?(occ.resource_id, column.resource_id) and
           overlap?(occ, day_span(column.date))
       end)}
    end)
  end

  defp timed_in_column(column, ctx) do
    {from, to} = ctx.opts.hours
    window = %{start: at(column.date, from), end: at(column.date, to)}
    total = (to - from) * @minute

    in_column =
      Enum.filter(ctx.occurrences, fn occ ->
        not occ.all_day and same_resource?(occ.resource_id, column.resource_id) and
          overlap?(occ, window)
      end)

    {backgrounds, events} = Enum.split_with(in_column, & &1.background)

    position = fn occ ->
      start = latest(occ.start, window.start)
      finish = earliest(occ.end, window.end)

      Map.merge(occ, %{
        top: NaiveDateTime.diff(start, window.start) / total,
        height: NaiveDateTime.diff(finish, start) / total,
        cut_start: NaiveDateTime.compare(occ.start, window.start) == :lt,
        cut_end: NaiveDateTime.compare(occ.end, window.end) == :gt
      })
    end

    %{
      events: events |> Enum.map(position) |> time_layout(),
      backgrounds: Enum.map(backgrounds, &(&1 |> position.() |> Map.merge(%{left: 0, width: 1})))
    }
  end

  defp now_line(columns, ctx) do
    {from, to} = ctx.opts.hours
    minute = minute_of_day(ctx.now)

    if ctx.opts.now_indicator and minute >= from and minute < to do
      columns
      |> Enum.with_index()
      |> Enum.filter(fn {column, _} -> column.date == ctx.today end)
      |> Enum.map(fn {_column, col} -> col end)
      |> then(&%{columns: &1, minute: minute, top: (minute - from) / (to - from)})
    end
  end

  # ── cells ────────────────────────────────────────────────────────────────────────────────────

  defp day_hit(column, row, col, ctx, focus, month) do
    span = %{
      start: midnight(column.date),
      end: day_span(column.date).end,
      all_day: true,
      resource_id: column.resource_id
    }

    Map.merge(span, %{
      date: column.date,
      row: row,
      col: col,
      label: long_date(column.date, ctx.opts),
      number:
        column.date |> in_calendar(ctx.opts) |> Map.fetch!(:day) |> localize_number(ctx.opts),
      today: column.date == ctx.today,
      outside:
        month != nil and Map.take(in_calendar(column.date, ctx.opts), [:year, :month]) != month,
      focus: focus == column.date,
      info: Map.get(ctx.opts.day_info, column.date),
      status: day_status(column.date, ctx.opts),
      shaded: Enum.any?(ctx.occurrences, &shades?(&1, span))
    })
    |> Map.merge(hit_state(span, ctx))
  end

  # A background block shades a whole day only when it covers the whole day.
  defp shades?(occ, span) do
    occ.background and same_resource?(occ.resource_id, span.resource_id) and
      NaiveDateTime.compare(occ.start, span.start) != :gt and
      NaiveDateTime.compare(occ.end, span.end) != :lt
  end

  defp slot_hit(column, index, col, from, ctx, focus) do
    opts = ctx.opts
    start = at(column.date, from + index * opts.slot_duration)

    span = %{
      start: start,
      end: NaiveDateTime.add(start, opts.select_duration * @minute),
      all_day: false,
      resource_id: column.resource_id
    }

    minute = from + index * opts.slot_duration

    Map.merge(span, %{
      row: index,
      col: col,
      label: "#{long_date(column.date, opts)} #{format_minutes(minute, opts)}",
      focus: focus == {col, index},
      business: business?(column, minute, opts),
      hour_start: rem(minute, 60) == 0,
      slot_end: NaiveDateTime.add(start, opts.slot_duration * @minute)
    })
    |> Map.merge(hit_state(span, ctx))
  end

  defp business?(column, minute, opts) do
    day = Date.day_of_week(column.date)

    opts
    |> business_windows(column.resource_id)
    |> Enum.any?(&(day in &1.days and minute >= &1.from and minute < &1.to))
  end

  # One function decides both what a click would do and how the cell looks beforehand.
  defp hit_state(span, ctx) do
    %{opts: opts, selection: selection, anchor: anchor} = ctx
    picking = opts.selectable != "none"

    enabled =
      not picking or check(span, ctx, edge: if(opts.selectable == "range", do: :start)) == :ok or
        (anchor != nil and range_end_ok?(anchor, span, ctx))

    %{
      disabled: not enabled,
      selected: picking and Enum.any?(selection, &covers?(&1, span)),
      range_start: Enum.any?(selection, &same_start?(&1, span)) and opts.selectable == "range",
      range_end: opts.selectable == "range" and Enum.any?(selection, &range_end?(&1, span, opts)),
      anchor: anchor != nil and same_start?(anchor, span)
    }
  end

  defp range_end_ok?(anchor, span, ctx) do
    anchor.resource_id == span.resource_id and anchor.all_day == span.all_day and
      NaiveDateTime.compare(span.start, anchor.start) != :lt and
      check(join(anchor, span, ctx.opts), ctx, edge: :range) == :ok
  end

  defp range_end?(selected, span, %{range_end: "checkout"}) do
    same_resource?(selected.resource_id, span.resource_id) and
      if(span.all_day, do: selected.end == span.start, else: selected.end == span.end)
  end

  defp range_end?(selected, span, _opts) do
    same_resource?(selected.resource_id, span.resource_id) and selected.end == span.end
  end

  defp covers?(selected, span) do
    same_resource?(selected.resource_id, span.resource_id) and
      NaiveDateTime.compare(span.start, selected.start) != :lt and
      NaiveDateTime.compare(span.start, selected.end) == :lt
  end

  defp same_start?(selected, span) do
    selected.start == span.start and selected.resource_id == span.resource_id
  end

  defp same_span?(a, b), do: a.start == b.start and a.resource_id == b.resource_id

  # One tab stop per grid: the selection if visible, else today, else the first day.
  defp focus_date(ctx, days) do
    candidates =
      Enum.map(ctx.selection, &NaiveDateTime.to_date(&1.start)) ++ [ctx.today, ctx.date]

    Enum.find(candidates, hd(days), &(&1 in days))
  end

  defp focus_slot(ctx, columns, from) do
    col = Enum.find_index(columns, &(&1.date == ctx.today)) || 0
    row = max(div(ctx.opts.scroll_to * 60 - from, ctx.opts.slot_duration), 0)
    {col, row}
  end

  defp hit_span(params, ctx) do
    resource = blank_to_nil(params["resource"])

    case {params["unit"], to_naive(params["start"], ctx.opts.time_zone)} do
      {_unit, nil} ->
        nil

      {"slot", start} ->
        %{
          start: start,
          end: NaiveDateTime.add(start, ctx.opts.select_duration * @minute),
          all_day: false,
          resource_id: resource
        }

      {_day, start} ->
        day = NaiveDateTime.to_date(start)
        %{start: midnight(day), end: day_span(day).end, all_day: true, resource_id: resource}
    end
  end

  defp selection_from(nil), do: []
  defp selection_from(list) when is_list(list), do: Enum.flat_map(list, &selection_from/1)

  defp selection_from(%Date{} = date),
    do: [Map.merge(day_span(date), %{all_day: true, resource_id: nil})]

  defp selection_from({%Date{} = from, %Date{} = to}) do
    [%{start: midnight(from), end: midnight(to), all_day: true, resource_id: nil}]
  end

  defp selection_from(%{} = span) do
    start = span |> field(:start) |> to_naive("Etc/UTC")
    finish = span |> field(:end) |> to_naive("Etc/UTC")
    all_day = match?(%Date{}, field(span, :start)) or field(span, :all_day) == true

    if start && finish,
      do: [
        %{
          start: start,
          end: finish,
          all_day: all_day,
          resource_id: span |> field(:resource_id) |> maybe_string()
        }
      ],
      else: []
  end

  defp selection_from(_other), do: []

  defp public_span(span, opts) do
    convert = if span.all_day, do: &NaiveDateTime.to_date/1, else: & &1

    base = %{
      start: convert.(span.start),
      end: convert.(span.end),
      all_day: span.all_day,
      resource_id: span.resource_id,
      time_zone: opts.time_zone
    }

    if span.all_day,
      do: Map.put(base, :nights, Date.diff(base.end, base.start)),
      else: Map.put(base, :minutes, div(NaiveDateTime.diff(span.end, span.start), @minute))
  end

  defp unit_minutes(%{all_day: true}, _opts), do: @day_minutes
  defp unit_minutes(_occ, opts), do: opts.slot_duration

  # ── labels ───────────────────────────────────────────────────────────────────────────────────

  defp title("month", date, _range, opts) do
    local = in_calendar(date, opts)
    "#{month_name(local, opts)} #{localize_number(local.year, opts)}"
  end

  defp title(view, date, _range, opts) when view in ["day", "resource_day"],
    do: long_date(date, opts)

  defp title(_view, _date, {first, last}, opts) do
    a = in_calendar(first, opts)
    b = last |> Date.add(-1) |> in_calendar(opts)

    cond do
      a.year != b.year ->
        "#{day_month(a, opts)} #{localize_number(a.year, opts)} – #{day_month(b, opts)} #{localize_number(b.year, opts)}"

      a.month != b.month ->
        "#{day_month(a, opts)} – #{day_month(b, opts)} #{localize_number(b.year, opts)}"

      true ->
        "#{localize_number(a.day, opts)} – #{day_month(b, opts)} #{localize_number(b.year, opts)}"
    end
  end

  defp day_month(local, opts),
    do: "#{localize_number(local.day, opts)} #{month_name(local, opts)}"

  defp month_name(local, opts),
    do: Enum.at(opts.labels.months, local.month - 1, to_string(local.month))

  defp long_date(date, opts) do
    local = in_calendar(date, opts)
    weekday = Enum.at(opts.labels.weekdays, Date.day_of_week(date) - 1)
    "#{weekday}, #{day_month(local, opts)} #{localize_number(local.year, opts)}"
  end

  defp weekday_headers(days, opts) do
    Enum.map(days, fn date ->
      %{
        short: Enum.at(opts.labels.weekdays_short, Date.day_of_week(date) - 1),
        long: Enum.at(opts.labels.weekdays, Date.day_of_week(date) - 1)
      }
    end)
  end

  defp day_header(date, ctx) do
    local = in_calendar(date, ctx.opts)

    %{
      date: date,
      weekday: Enum.at(ctx.opts.labels.weekdays_short, Date.day_of_week(date) - 1),
      day: localize_number(local.day, ctx.opts),
      label: long_date(date, ctx.opts),
      today: date == ctx.today
    }
  end

  defp week_number(date) do
    {_year, week} = :calendar.iso_week_number(Date.to_erl(date))
    week
  end

  defp format_minutes(minutes, opts) do
    hour = div(minutes, 60) |> rem(24)
    minute = rem(minutes, 60)

    text =
      if opts.hour12 do
        suffix = if hour < 12, do: opts.labels.am, else: opts.labels.pm
        shown = if rem(hour, 12) == 0, do: 12, else: rem(hour, 12)
        if minute == 0, do: "#{shown} #{suffix}", else: "#{shown}:#{pad(minute)} #{suffix}"
      else
        "#{pad(hour)}:#{pad(minute)}"
      end

    localize_number(text, opts)
  end

  defp event_time(occ, opts) do
    if occ.all_day,
      do: opts.labels.all_day,
      else:
        "#{format_minutes(minute_of_day(occ.start), opts)} – #{format_minutes(minute_of_day(occ.end), opts)}"
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  defp localize_number(value, %{labels: %{digits: [_ | _] = digits}}) do
    value
    |> to_string()
    |> String.replace(~r/[0-9]/, fn digit -> Enum.at(digits, String.to_integer(digit)) end)
  end

  defp localize_number(value, _opts), do: to_string(value)

  defp interpolate(text, count, opts),
    do: String.replace(text, "%{count}", localize_number(count, %{labels: opts}))

  defp resource_title(opts, id) do
    Enum.find_value(opts.resources, fn resource -> resource.id == id && resource.title end)
  end

  # ── small helpers ────────────────────────────────────────────────────────────────────────────

  defp field(%{} = data, key) do
    case Map.fetch(data, key) do
      {:ok, value} -> value
      :error -> Map.get(data, Atom.to_string(key))
    end
  end

  defp field(_data, _key), do: nil

  defp to_date(nil), do: nil
  defp to_date(%Date{} = date), do: Date.convert!(date, Calendar.ISO)
  defp to_date(%NaiveDateTime{} = time), do: time |> NaiveDateTime.to_date() |> to_date()
  defp to_date(%DateTime{} = time), do: time |> DateTime.to_date() |> to_date()

  defp to_date(value) when is_binary(value) do
    # RRULE writes `UNTIL=20261231` or `UNTIL=20261231T235959Z`.
    value = Regex.replace(~r/^(\d{4})(\d{2})(\d{2})(?=T|$)/, value, "\\1-\\2-\\3")

    case Date.from_iso8601(String.slice(value, 0, 10)) do
      {:ok, date} -> date
      _error -> nil
    end
  end

  defp to_date(_other), do: nil

  defp to_naive(nil, _zone), do: nil
  defp to_naive(%Date{} = date, _zone), do: date |> to_date() |> midnight()
  defp to_naive(%NaiveDateTime{} = time, _zone), do: NaiveDateTime.convert!(time, Calendar.ISO)

  defp to_naive(%DateTime{} = time, zone) do
    case DateTime.shift_zone(time, zone) do
      {:ok, shifted} -> DateTime.to_naive(shifted)
      _error -> DateTime.to_naive(time)
    end
  rescue
    _no_database -> DateTime.to_naive(time)
  end

  defp to_naive(value, zone) when is_binary(value) do
    cond do
      date_string?(value) ->
        value |> to_date() |> to_naive(zone)

      match?({:ok, _, _}, DateTime.from_iso8601(value)) ->
        value |> DateTime.from_iso8601() |> elem(1) |> to_naive(zone)

      match?({:ok, _}, NaiveDateTime.from_iso8601(value)) ->
        value |> NaiveDateTime.from_iso8601!() |> NaiveDateTime.truncate(:second)

      true ->
        nil
    end
  end

  defp to_naive(_other, _zone), do: nil

  defp date_string?(value),
    do: is_binary(value) and byte_size(value) == 10 and to_date(value) != nil

  defp current_time(%{now: nil} = opts),
    do: DateTime.utc_now() |> to_naive(opts.time_zone) |> NaiveDateTime.truncate(:second)

  defp current_time(opts), do: to_naive(opts.now, opts.time_zone)

  defp midnight(date), do: NaiveDateTime.new!(date, ~T[00:00:00])
  defp at(date, minutes), do: date |> midnight() |> NaiveDateTime.add(minutes * @minute)
  defp day_span(date), do: %{start: midnight(date), end: at(date, @day_minutes)}

  defp minute_of_day(%{hour: hour, minute: minute}), do: hour * 60 + minute

  defp overlap?(a, b) do
    NaiveDateTime.compare(a.start, b.end) == :lt and NaiveDateTime.compare(b.start, a.end) == :lt
  end

  # An event with no resource belongs to every column; a column with no resource shows every event.
  defp same_resource?(nil, _other), do: true
  defp same_resource?(_other, nil), do: true
  defp same_resource?(a, b), do: a == b

  defp latest(a, b), do: if(NaiveDateTime.compare(a, b) == :lt, do: b, else: a)
  defp earliest(a, b), do: if(NaiveDateTime.compare(a, b) == :gt, do: b, else: a)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp maybe_string(nil), do: nil
  defp maybe_string(value), do: to_string(value)

  defp to_int(nil, default), do: default
  defp to_int(value, _default) when is_integer(value), do: value

  defp to_int(value, default) do
    case Integer.parse(to_string(value)) do
      {int, _rest} -> int
      :error -> default
    end
  end

  # Colors go into a `style` attribute, so only plain CSS color syntax gets through.
  defp safe_color(nil), do: nil

  defp safe_color(color) do
    color = to_string(color)
    if color =~ ~r/^[#a-zA-Z0-9(),.%\s-]{1,64}$/, do: color
  end

  defp iso(%NaiveDateTime{} = time), do: NaiveDateTime.to_iso8601(time)

  defp pct(fraction), do: :erlang.float_to_binary(fraction * 100.0, decimals: 4)

  defp event_style(%{color: nil}), do: ""
  defp event_style(%{color: color}), do: "--fc-event-color: #{color}"

  # ── render ───────────────────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".FullCalendar"
      phx-target={@myself}
      data-part="root"
      data-view={@model.view}
      data-selectable={@options.selectable}
      data-editable={@options.editable}
      data-time-zone={if @settings[:time_zone] == "auto", do: "auto", else: @options.time_zone}
      data-first={Date.to_iso8601(@model.first)}
      data-last={Date.to_iso8601(@model.last)}
      data-anchor={@anchor && iso(@anchor.start)}
      class={["chelekom-full-calendar", @classes[:class]]}
      {@rest}
    >
      <div data-part="toolbar" class={["chelekom-full-calendar__toolbar", @classes[:toolbar_class]]}>
        <div data-part="nav">
          <button
            type="button"
            data-part="previous"
            aria-label={@options.labels.previous}
            phx-click={JS.push("nav", value: %{to: "previous"}, target: @myself, loading: "##{@id}")}
            class={["chelekom-full-calendar__nav-button", @classes[:nav_class]]}
          >‹</button>
          <button
            type="button"
            data-part="today"
            phx-click={JS.push("nav", value: %{to: "today"}, target: @myself, loading: "##{@id}")}
            class={["chelekom-full-calendar__nav-button", @classes[:nav_class]]}
          >{@options.labels.today}</button>
          <button
            type="button"
            data-part="next"
            aria-label={@options.labels.next}
            phx-click={JS.push("nav", value: %{to: "next"}, target: @myself, loading: "##{@id}")}
            class={["chelekom-full-calendar__nav-button", @classes[:nav_class]]}
          >›</button>
        </div>

        <h2
          id={"#{@id}-title"}
          data-part="title"
          aria-live="polite"
          class={["chelekom-full-calendar__title", @classes[:title_class]]}
        >
          {@model.title}
        </h2>

        <div
          :if={length(@options.views) > 1}
          role="group"
          data-part="views"
          aria-label="View"
        >
          <button
            :for={view <- @options.views}
            type="button"
            data-part="view-button"
            data-view={view}
            data-active={view == @model.view}
            aria-pressed={to_string(view == @model.view)}
            phx-click={JS.push("view", value: %{view: view}, target: @myself, loading: "##{@id}")}
            class={["chelekom-full-calendar__view-button", @classes[:view_button_class]]}
          >{Map.get(@options.labels.views, view, view)}</button>
        </div>

        {render_slot(@toolbar_extra)}
      </div>

      <div
        id={"#{@id}-status"}
        role="status"
        data-part="status"
        data-empty={is_nil(@notice)}
        class={["chelekom-full-calendar__status", @classes[:status_class]]}
      >
        <span :if={@notice}>{@notice}</span>
        <button
          :if={@notice}
          type="button"
          data-part="dismiss"
          aria-label={@options.labels.close}
          phx-click={JS.push("dismiss", target: @myself)}
          class={["chelekom-full-calendar__dismiss", @classes[:nav_class]]}
        >×</button>
      </div>

      <div
        id={"#{@id}-view"}
        data-part="view"
        data-view={@model.view}
        aria-labelledby={"#{@id}-title"}
        role="group"
        class={["chelekom-full-calendar__view", @classes[:view_class]]}
      >
        <.month_view :if={@model.view == "month"} {view_assigns(assigns)} />
        <.time_view :if={@model.view in ["week", "day", "resource_day"]} {view_assigns(assigns)} />
        <.timeline_view :if={@model.view == "timeline"} {view_assigns(assigns)} />
        <.list_view :if={@model.view == "list"} {view_assigns(assigns)} />
      </div>

      <.event_popover
        :if={@open}
        occ={@open}
        id={@id}
        myself={@myself}
        options={@options}
        classes={@classes}
        popover_content={@popover_content}
      />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".FullCalendar">
        export default {
          mounted() {
            this.drag = null
            this.view = this.el.dataset.view
            this.renderedAt = Date.now()
            this.onDown = (e) => this.down(e)
            this.onMove = (e) => this.move(e)
            this.onUp = (e) => this.up(e)
            this.onKey = (e) => this.key(e)
            this.el.addEventListener("pointerdown", this.onDown)
            this.el.addEventListener("keydown", this.onKey)
            this.tick = setInterval(() => this.placeNow(), 30000)
            this.scroll()
            this.placeNow()
            if (this.el.dataset.timeZone === "auto") {
              const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
              this.pushEventTo(this.el, "time_zone", {time_zone: zone})
            }
          },
          updated() {
            this.renderedAt = Date.now()
            this.reset()
            if (this.pendingFocus) {
              const cell = this.el.querySelector("[data-hit][data-start^='" + this.pendingFocus + "']")
              this.pendingFocus = null
              if (cell) { cell.setAttribute("tabindex", "0"); cell.focus() }
            }
            if (this.view !== this.el.dataset.view) this.scroll()
            this.view = this.el.dataset.view
            this.placeNow()
          },
          destroyed() {
            clearInterval(this.tick)
            this.stopListening()
          },

          // Hit testing: every droppable cell is a [data-hit] carrying its own ISO start, so the
          // hook never does date math and works for any calendar the server renders.
          hitAt(x, y) {
            return document.elementsFromPoint(x, y)
              .find((node) => node.matches && node.matches("[data-hit]") && this.el.contains(node)) || null
          },
          down(e) {
            if (e.button !== 0 || this.drag) return
            const eventEl = e.target.closest("[data-part=event][data-editable]")
            const resizer = e.target.closest("[data-part=resizer]")
            const hit = this.hitAt(e.clientX, e.clientY)
            let mode = null
            if (eventEl && resizer) mode = "resize"
            else if (eventEl) mode = "move"
            else if (hit && this.el.dataset.selectable === "range" && !hit.hasAttribute("data-disabled")) mode = "select"
            if (!mode || !hit) return
            this.drag = {mode, eventEl, origin: hit, current: hit, x: e.clientX, y: e.clientY, active: false}
            if (e.pointerType === "touch") {
              this.drag.timer = setTimeout(() => this.activate(), 350)
            }
            window.addEventListener("pointermove", this.onMove)
            window.addEventListener("pointerup", this.onUp)
            window.addEventListener("pointercancel", this.onUp)
          },
          activate() {
            const drag = this.drag
            if (!drag || drag.active) return
            drag.active = true
            this.el.setAttribute("data-dragging", drag.mode)
            if (drag.eventEl) {
              drag.eventEl.setAttribute("data-dragging", "")
              drag.eventEl.style.pointerEvents = "none"
            }
          },
          move(e) {
            const drag = this.drag
            if (!drag) return
            if (!drag.active) {
              const far = Math.hypot(e.clientX - drag.x, e.clientY - drag.y) > 5
              if (!far) return
              // A touch that moves before the long press is a scroll, not a drag.
              if (drag.timer) return this.cancel()
              this.activate()
            }
            e.preventDefault()
            this.autoScroll(e.clientY)
            const hit = this.hitAt(e.clientX, e.clientY)
            if (hit) drag.current = hit
            if (drag.mode === "move") {
              drag.eventEl.style.translate = (e.clientX - drag.x) + "px " + (e.clientY - drag.y) + "px"
              this.mark("data-drop-target", [drag.current])
            } else if (drag.mode === "resize") {
              this.mark("data-drop-target", [drag.current])
            } else {
              this.mark("data-selecting", this.between(drag.origin, drag.current))
            }
          },
          up(e) {
            const drag = this.drag
            this.stopListening()
            if (!drag) return
            clearTimeout(drag.timer)
            if (!drag.active) { this.drag = null; return }
            this.swallowClick()
            const target = drag.current
            if (drag.mode === "move") {
              this.pushEventTo(this.el, "drop", {
                key: drag.eventEl.dataset.key,
                from: drag.origin.dataset.start,
                to: target.dataset.start,
                resource: target.dataset.resource || "",
                all_day: target.dataset.allDay === "true"
              })
            } else if (drag.mode === "resize") {
              this.pushEventTo(this.el, "resize", {key: drag.eventEl.dataset.key, to: target.dataset.end})
            } else if (target !== drag.origin) {
              this.pushEventTo(this.el, "span", {
                from: drag.origin.dataset.start,
                to: target.dataset.start,
                resource: drag.origin.dataset.resource || "",
                unit: drag.origin.dataset.unit
              })
            } else {
              this.reset()
            }
            this.drag = null
          },
          // Near the edge of the time grid, dragging scrolls it, so a drop can go anywhere in the day.
          autoScroll(y) {
            const scroller = this.el.querySelector("[data-part=scroller]")
            if (!scroller) return
            const head = scroller.querySelector("[data-part=head]")
            const box = scroller.getBoundingClientRect()
            const top = box.top + (head ? head.offsetHeight : 0)
            if (y < top + 40) scroller.scrollTop -= 16
            else if (y > box.bottom - 40) scroller.scrollTop += 16
          },
          cancel() {
            clearTimeout(this.drag && this.drag.timer)
            this.stopListening()
            this.drag = null
            this.reset()
          },
          // The cells between two hits, in the same grid and for the same resource.
          between(a, b) {
            const [from, to] = [a.dataset.start, b.dataset.start].sort()
            return Array.from(this.el.querySelectorAll("[data-hit][data-grid='" + a.dataset.grid + "']"))
              .filter((n) => (n.dataset.resource || "") === (a.dataset.resource || ""))
              .filter((n) => n.dataset.start >= from && n.dataset.start <= to)
          },
          mark(attr, nodes) {
            this.el.querySelectorAll("[" + attr + "]").forEach((n) => n.removeAttribute(attr))
            nodes.forEach((n) => n.setAttribute(attr, ""))
          },
          // A drag ends with a click on whatever is under the pointer; it is not a pick.
          swallowClick() {
            const stop = (e) => { e.stopPropagation(); e.preventDefault() }
            this.el.addEventListener("click", stop, {capture: true, once: true})
            setTimeout(() => this.el.removeEventListener("click", stop, {capture: true}), 300)
          },
          reset() {
            this.el.removeAttribute("data-dragging")
            this.mark("data-drop-target", [])
            this.mark("data-selecting", [])
            this.el.querySelectorAll("[data-part=event][data-dragging]").forEach((n) => {
              n.removeAttribute("data-dragging")
              n.style.translate = ""
              n.style.pointerEvents = ""
            })
          },
          stopListening() {
            window.removeEventListener("pointermove", this.onMove)
            window.removeEventListener("pointerup", this.onUp)
            window.removeEventListener("pointercancel", this.onUp)
          },

          // Roving focus across a grid's cells by their row and column, the WAI-ARIA grid way.
          key(e) {
            if (e.key === "Escape" && this.drag) return this.cancel()
            const cell = e.target.closest("[data-hit]")
            if (!cell) return
            const row = Number(cell.dataset.row)
            const col = Number(cell.dataset.col)
            const moves = {ArrowLeft: [0, -1], ArrowRight: [0, 1], ArrowUp: [-1, 0], ArrowDown: [1, 0]}
            let next = null
            if (moves[e.key]) {
              const rtl = getComputedStyle(this.el).direction === "rtl"
              const [dr, dc] = moves[e.key]
              next = this.cell(cell.dataset.grid, row + dr, col + (rtl ? -dc : dc))
            } else if (e.key === "Home" || e.key === "End") {
              const row_cells = this.el.querySelectorAll("[data-hit][data-grid='" + cell.dataset.grid + "'][data-row='" + row + "']")
              next = e.key === "Home" ? row_cells[0] : row_cells[row_cells.length - 1]
            } else if (e.key === "PageUp" || e.key === "PageDown") {
              const button = this.el.querySelector(e.key === "PageUp" ? "[data-part=previous]" : "[data-part=next]")
              if (button) { e.preventDefault(); button.click() }
              return
            }
            if (!next && moves[e.key] && cell.dataset.unit === "day") {
              // Off the edge of the grid: page, then land on the day the arrow was heading for.
              const [dr, dc] = moves[e.key]
              const days = dr * 7 + dc * (getComputedStyle(this.el).direction === "rtl" ? -1 : 1)
              const target = new Date(cell.dataset.start.slice(0, 10) + "T00:00:00Z")
              target.setUTCDate(target.getUTCDate() + days)
              this.pendingFocus = target.toISOString().slice(0, 10)
              const button = this.el.querySelector(days < 0 ? "[data-part=previous]" : "[data-part=next]")
              e.preventDefault()
              if (button) button.click()
              return
            }
            if (!next) return
            e.preventDefault()
            cell.setAttribute("tabindex", "-1")
            next.setAttribute("tabindex", "0")
            next.focus()
          },
          cell(grid, row, col) {
            return this.el.querySelector("[data-hit][data-grid='" + grid + "'][data-row='" + row + "'][data-col='" + col + "']")
          },

          // Open the time grid at the working day, below the sticky head.
          scroll() {
            const scroller = this.el.querySelector("[data-part=scroller]")
            const target = this.el.querySelector("[data-scroll-target]")
            if (!scroller || !target) return
            const head = scroller.querySelector("[data-part=head]")
            const offset = target.getBoundingClientRect().top - scroller.getBoundingClientRect().top
            scroller.scrollTop += offset - (head ? head.offsetHeight : 0)
          },
          // The server placed the line when it rendered; between renders it only has to move down.
          placeNow() {
            const minutes = (Date.now() - this.renderedAt) / 60000
            this.el.querySelectorAll("[data-part=now]").forEach((line) => {
              const from = Number(line.dataset.from), to = Number(line.dataset.to)
              const minute = Number(line.dataset.minute) + minutes
              line.hidden = minute >= to
              line.style.setProperty("--fc-top", ((minute - from) / (to - from) * 100).toFixed(4))
            })
          }
        }
      </script>
    </div>
    """
  end

  defp view_assigns(assigns) do
    Map.take(assigns, [:id, :myself, :model, :options, :classes, :event_content, :no_events])
  end

  # ── month ────────────────────────────────────────────────────────────────────────────────────

  defp month_view(assigns) do
    ~H"""
    <div data-part="month" style={"--fc-cols: #{length(@model.weekdays)}"}>
      <div data-part="header-row">
        <span :if={@options.week_numbers} data-part="week-number"></span>
        <div
          :for={weekday <- @model.weekdays}
          data-part="header"
          title={weekday.long}
          class={["chelekom-full-calendar__header", @classes[:header_class]]}
        >
          {weekday.short}
        </div>
      </div>
      <div :for={{row, index} <- Enum.with_index(@model.rows)} data-part="week-wrap">
        <span :if={@options.week_numbers} data-part="week-number">
          {@options.labels.week}{row.number}
        </span>
        <.day_lane
          row={row}
          grid="month"
          id={"#{@id}-w#{index}"}
          numbers
          myself={@myself}
          options={@options}
          classes={@classes}
          event_content={@event_content}
        />
      </div>
    </div>
    """
  end

  # One row of day columns: a month week, a resource's timeline row, or the all-day lane.
  attr :row, :map, required: true
  attr :grid, :string, required: true
  attr :id, :string, required: true
  attr :numbers, :boolean, default: false
  attr :myself, :any, required: true
  attr :options, :map, required: true
  attr :classes, :map, required: true
  attr :event_content, :list, default: []

  defp day_lane(assigns) do
    ~H"""
    <div
      data-part="week"
      class={["chelekom-full-calendar__week", @classes[:week_class]]}
      style={"--fc-cols: #{length(@row.hits)}; --fc-levels: #{max(@row.layout.levels, 1)}"}
    >
      <button
        :for={hit <- @row.hits}
        type="button"
        data-hit
        data-grid={@grid}
        data-unit="day"
        data-row={hit.row}
        data-col={hit.col}
        data-start={iso(hit.start)}
        data-end={iso(hit.end)}
        data-resource={hit.resource_id}
        data-all-day="true"
        data-part="day"
        data-today={hit.today}
        data-outside={hit.outside}
        data-disabled={hit.disabled}
        data-selected={hit.selected}
        data-range-start={hit.range_start}
        data-range-end={hit.range_end}
        data-anchor={hit.anchor}
        data-shaded={hit.shaded}
        data-status={hit.status}
        aria-label={hit.label}
        aria-current={hit.today && "date"}
        aria-disabled={hit.disabled && "true"}
        aria-pressed={@options.selectable != "none" && to_string(hit.selected)}
        tabindex={if hit.focus, do: "0", else: "-1"}
        style={"--fc-col: #{hit.col + 1}"}
        phx-click={!hit.disabled && pick_js(hit, @myself)}
        class={["chelekom-full-calendar__day", @classes[:day_class]]}
      >
        <span :if={hit.info && field(hit.info, :label)} data-part="day-info">
          {field(hit.info, :label)}
        </span>
      </button>

      <%= if @numbers do %>
        <button
          :for={hit <- @row.hits}
          :if={"day" in @options.views}
          type="button"
          data-part="day-number"
          data-today={hit.today}
          data-outside={hit.outside}
          tabindex="-1"
          aria-label={hit.label}
          style={"--fc-col: #{hit.col + 1}"}
          phx-click={
            JS.push("view", value: %{view: "day", date: Date.to_iso8601(hit.date)}, target: @myself)
          }
          class={["chelekom-full-calendar__day-number", @classes[:day_number_class]]}
        >{hit.number}</button>
        <span
          :for={hit <- @row.hits}
          :if={"day" not in @options.views}
          data-part="day-number"
          data-today={hit.today}
          data-outside={hit.outside}
          aria-hidden="true"
          style={"--fc-col: #{hit.col + 1}"}
          class={["chelekom-full-calendar__day-number", @classes[:day_number_class]]}
        >{hit.number}</span>
      <% end %>

      <.event_chip
        :for={seg <- @row.layout.segments}
        occ={seg.event}
        placement="row"
        style={"--fc-col: #{seg.col + 1}; --fc-span: #{seg.span}; --fc-level: #{seg.level}; #{event_style(seg.event)}"}
        cut_start={!seg.starts}
        cut_end={!seg.ends}
        myself={@myself}
        options={@options}
        classes={@classes}
        event_content={@event_content}
      />

      <%= for {col, count} <- @row.layout.more do %>
        <button
          type="button"
          data-part="more"
          aria-expanded="false"
          aria-controls={"#{@id}-more-#{col}"}
          style={"--fc-col: #{col + 1}"}
          phx-click={open_more("#{@id}-more-#{col}")}
          class={["chelekom-full-calendar__more", @classes[:more_class]]}
        >{String.replace(@options.labels.more, "%{count}", localize_number(count, @options))}</button>
        <div
          id={"#{@id}-more-#{col}"}
          role="dialog"
          aria-label={Enum.at(@row.hits, col).label}
          data-part="more-popover"
          hidden
          style={"--fc-col: #{col + 1}"}
          phx-click-away={close_more("#{@id}-more-#{col}")}
          phx-window-keydown={close_more("#{@id}-more-#{col}")}
          phx-key="Escape"
          class={["chelekom-full-calendar__more-popover", @classes[:popover_class]]}
        >
          <div data-part="more-title">{Enum.at(@row.hits, col).label}</div>
          <.event_chip
            :for={occ <- Map.get(@row.more, col, [])}
            occ={occ}
            placement="list"
            style={event_style(occ)}
            myself={@myself}
            options={@options}
            classes={@classes}
            event_content={@event_content}
          />
        </div>
      <% end %>
    </div>
    """
  end

  defp pick_js(hit, myself) do
    JS.push("pick",
      value: %{
        start: iso(hit.start),
        resource: hit.resource_id || "",
        unit: if(hit.all_day, do: "day", else: "slot")
      },
      target: myself
    )
  end

  # The "+N more" list is already in the page; opening it needs no server.
  defp open_more(id) do
    JS.remove_attribute("hidden", to: "##{id}")
    |> JS.set_attribute({"aria-expanded", "true"})
    |> JS.focus_first(to: "##{id}")
  end

  defp close_more(id) do
    JS.set_attribute({"hidden", ""}, to: "##{id}")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "[aria-controls='#{id}']")
  end

  # ── time grid ────────────────────────────────────────────────────────────────────────────────

  defp time_view(assigns) do
    ~H"""
    <div
      data-part="scroller"
      style={"--fc-cols: #{length(@model.columns)}; --fc-slots: #{length(@model.axis)}"}
    >
      <div data-part="head">
        <div data-part="header-row">
          <span data-part="corner"></span>
          <div
            :for={column <- @model.columns}
            data-part="header"
            data-today={column.today}
            data-resource={column.resource_id}
            class={["chelekom-full-calendar__header", @classes[:header_class]]}
          >
            <span :if={column.title} data-part="header-resource">{column.title}</span>
            <span :if={is_nil(column.title) or @model.view != "resource_day"} data-part="header-date">
              {Enum.at(@options.labels.weekdays_short, Date.day_of_week(column.date) - 1)}
              {column.date |> in_calendar(@options) |> Map.fetch!(:day) |> localize_number(@options)}
            </span>
          </div>
        </div>

        <div :if={@options.all_day_slot} data-part="all-day">
          <span data-part="axis" class={["chelekom-full-calendar__axis", @classes[:axis_class]]}>
            {@options.labels.all_day}
          </span>
          <.day_lane
            row={%{hits: @model.all_day_hits, layout: @model.all_day, more: %{}}}
            grid="all-day"
            id={"#{@id}-all-day"}
            myself={@myself}
            options={@options}
            classes={@classes}
            event_content={@event_content}
          />
        </div>
      </div>

      <div data-part="body">
        <div data-part="axis-column">
          <span
            :for={label <- @model.axis}
            data-part="axis"
            class={["chelekom-full-calendar__axis", @classes[:axis_class]]}
          >{label}</span>
        </div>

        <div
          :for={{column, col} <- Enum.with_index(@model.columns)}
          data-part="column"
          data-today={column.today}
          data-resource={column.resource_id}
        >
          <button
            :for={hit <- Enum.at(@model.slots, col)}
            type="button"
            data-hit
            data-grid="slots"
            data-unit="slot"
            data-row={hit.row}
            data-col={hit.col}
            data-start={iso(hit.start)}
            data-end={iso(hit.slot_end)}
            data-resource={hit.resource_id}
            data-all-day="false"
            data-part="slot"
            data-hour={hit.hour_start}
            data-business={hit.business}
            data-disabled={hit.disabled}
            data-selected={hit.selected}
            data-range-start={hit.range_start}
            data-range-end={hit.range_end}
            data-anchor={hit.anchor}
            data-scroll-target={col == 0 and hit.row == @model.scroll_row}
            aria-label={hit.label}
            aria-disabled={hit.disabled && "true"}
            aria-pressed={@options.selectable != "none" && to_string(hit.selected)}
            tabindex={if hit.focus, do: "0", else: "-1"}
            phx-click={!hit.disabled && pick_js(hit, @myself)}
            class={["chelekom-full-calendar__slot", @classes[:slot_class]]}
          ></button>

          <div
            :for={bg <- Enum.at(@model.timed, col).backgrounds}
            data-part="background"
            data-status={bg.status}
            title={bg.title}
            style={"--fc-top: #{pct(bg.top)}; --fc-height: #{pct(bg.height)}; #{event_style(bg)}"}
          >
          </div>

          <.event_chip
            :for={occ <- Enum.at(@model.timed, col).events}
            occ={occ}
            placement="time"
            style={"--fc-top: #{pct(occ.top)}; --fc-height: #{pct(occ.height)}; --fc-left: #{pct(occ.left)}; --fc-width: #{pct(occ.width)}; #{event_style(occ)}"}
            cut_start={occ.cut_start}
            cut_end={occ.cut_end}
            myself={@myself}
            options={@options}
            classes={@classes}
            event_content={@event_content}
          />

          <div
            :if={@model.now && col in @model.now.columns}
            data-part="now"
            data-minute={@model.now.minute}
            data-from={elem(@model.window, 0)}
            data-to={elem(@model.window, 1)}
            aria-hidden="true"
            style={"--fc-top: #{pct(@model.now.top)}"}
            class={["chelekom-full-calendar__now", @classes[:now_class]]}
          >
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── timeline ─────────────────────────────────────────────────────────────────────────────────

  defp timeline_view(assigns) do
    ~H"""
    <div data-part="timeline" style={"--fc-cols: #{length(@model.days)}"}>
      <div data-part="header-row">
        <span data-part="corner"></span>
        <div
          :for={day <- @model.days}
          data-part="header"
          data-today={day.today}
          title={day.label}
          class={["chelekom-full-calendar__header", @classes[:header_class]]}
        >
          <span data-part="header-weekday">{day.weekday}</span>
          <span data-part="header-day">{day.day}</span>
        </div>
      </div>
      <div
        :for={{row, index} <- Enum.with_index(@model.rows)}
        data-part="timeline-row"
        data-resource={row.resource.id}
      >
        <div
          data-part="resource"
          class={["chelekom-full-calendar__resource", @classes[:resource_class]]}
        >
          {row.resource.title}
        </div>
        <.day_lane
          row={row}
          grid="timeline"
          id={"#{@id}-r#{index}"}
          myself={@myself}
          options={@options}
          classes={@classes}
          event_content={@event_content}
        />
      </div>
    </div>
    """
  end

  # ── list ─────────────────────────────────────────────────────────────────────────────────────

  defp list_view(assigns) do
    ~H"""
    <div data-part="list">
      <section
        :for={day <- @model.days}
        data-part="list-day"
        data-today={day.today}
        aria-label={day.label}
        class={["chelekom-full-calendar__list-day", @classes[:list_day_class]]}
      >
        <h3 data-part="list-date">{day.label}</h3>
        <.event_chip
          :for={occ <- day.events}
          occ={occ}
          placement="list"
          style={event_style(occ)}
          myself={@myself}
          options={@options}
          classes={@classes}
          event_content={@event_content}
        />
      </section>
      <div :if={@model.days == []} data-part="empty">
        <%= if @no_events == [] do %>
          {@options.labels.no_events}
        <% else %>
          {render_slot(@no_events)}
        <% end %>
      </div>
    </div>
    """
  end

  # ── events ───────────────────────────────────────────────────────────────────────────────────

  attr :occ, :map, required: true
  attr :placement, :string, required: true
  attr :style, :string, default: nil
  attr :cut_start, :boolean, default: false
  attr :cut_end, :boolean, default: false
  attr :myself, :any, required: true
  attr :options, :map, required: true
  attr :classes, :map, required: true
  attr :event_content, :list, default: []

  defp event_chip(assigns) do
    ~H"""
    <button
      type="button"
      data-part="event"
      data-key={@occ.key}
      data-placement={@placement}
      data-all-day={to_string(@occ.all_day)}
      data-editable={@occ.editable && @placement != "list"}
      data-status={@occ.status}
      data-color={@occ.color}
      data-recurring={@occ.recurring}
      data-cut-start={@cut_start}
      data-cut-end={@cut_end}
      data-resource={@occ.resource_id}
      aria-label={"#{@occ.title}, #{event_time(@occ, @options)}"}
      aria-haspopup={@options.event_popover && "dialog"}
      style={@style}
      phx-click={JS.push("event_click", value: %{key: @occ.key}, target: @myself)}
      class={["chelekom-full-calendar__event", @classes[:event_class]]}
    >
      <%= if @event_content == [] do %>
        <span :if={not @occ.all_day} data-part="event-time">
          {format_minutes(minute_of_day(@occ.start), @options)}
        </span>
        <span data-part="event-title">{@occ.title}</span>
      <% else %>
        {render_slot(@event_content, @occ)}
      <% end %>
      <span
        :if={@occ.editable && @placement != "list" && !@cut_end}
        data-part="resizer"
        aria-hidden="true"
      ></span>
    </button>
    """
  end

  attr :occ, :map, required: true
  attr :id, :string, required: true
  attr :myself, :any, required: true
  attr :options, :map, required: true
  attr :classes, :map, required: true
  attr :popover_content, :list, default: []

  defp event_popover(assigns) do
    ~H"""
    <div
      id={"#{@id}-popover"}
      role="dialog"
      aria-labelledby={"#{@id}-popover-title"}
      data-part="popover"
      data-status={@occ.status}
      phx-click-away={JS.push("close_popover", target: @myself)}
      phx-window-keydown={JS.push("close_popover", target: @myself)}
      phx-key="Escape"
      phx-mounted={JS.focus_first()}
      style={event_style(@occ)}
      class={["chelekom-full-calendar__popover", @classes[:popover_class]]}
    >
      <h3 id={"#{@id}-popover-title"} data-part="popover-title">
        {@occ.title}
      </h3>
      <p data-part="popover-time">
        {long_date(NaiveDateTime.to_date(@occ.start), @options)} · {event_time(@occ, @options)}
      </p>
      <p
        :if={@occ.resource_id && resource_title(@options, @occ.resource_id)}
        data-part="popover-resource"
      >
        {resource_title(@options, @occ.resource_id)}
      </p>
      {render_slot(@popover_content, @occ)}
      <button
        type="button"
        data-part="close"
        aria-label={@options.labels.close}
        phx-click={JS.push("close_popover", target: @myself)}
        class={["chelekom-full-calendar__close", @classes[:nav_class]]}
      >×</button>
    </div>
    """
  end
end
