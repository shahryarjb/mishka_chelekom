# full_calendar (headless)

A scheduler in one `Phoenix.LiveComponent`. It shows month, week, day, list, resource-day and timeline views. It handles selection (single, multiple, range), booking rules, drag-and-drop, resizing and recurring events. The grid is laid out on the server. A colocated hook adds the pointer and keyboard gestures a server cannot handle. The pattern is the WAI-ARIA grid, with roving focus over days and slots.

## Generate

```bash
mix mishka.ui.gen.headless full_calendar
```

This generates `lib/<app>_web/components/headless/full_calendar.ex`: one file with no JS to wire up. The hook is a `Phoenix.LiveView.ColocatedHook` (LiveView ≥ 1.1). A Phoenix 1.8 app already imports `phoenix-colocated/<app>` in `app.js` and runs the `:phoenix_live_view` compiler. The layout rules come with `mishka_chelekom_headless.css`.

Render it through the wrapper or directly:

```heex
<.full_calendar id="calendar" events={@events} />
<.live_component module={MyAppWeb.Components.Headless.FullCalendar} id="calendar" events={@events} />
```

## The contract

The component owns only what is on screen: the view, the date, and the pick in progress. **Your LiveView owns the data.** The component reports and your LiveView decides:

```elixir
alias MyAppWeb.Components.Headless.FullCalendar

def handle_info({FullCalendar, "calendar", :dates_set, %{start: from, end: to}}, socket),
  do: {:noreply, assign(socket, :events, Bookings.between(from, to))}

def handle_info({FullCalendar, "calendar", :select, span}, socket),
  do: {:noreply, assign(socket, :pending, span)}

def handle_info({FullCalendar, "calendar", :event_drop, change}, socket) do
  {:ok, _} = Bookings.move(change.id, change.start, change.end, change.resource_id)
  {:noreply, assign(socket, :events, Bookings.between(...))}
end

def handle_info({FullCalendar, _id, _other, _payload}, socket), do: {:noreply, socket}
```

| message | payload |
|---|---|
| `:dates_set` | `%{view, start, end}`: the visible range, with `end` exclusive. Sent on the first connected render and on every change, so you can load lazily |
| `:select` | a span (`single` or `range`), a list of spans (`multiple`), or `nil` |
| `:select_rejected` | `%{reason}`: one of `:past`, `:unavailable`, `:overlap`, `:outside_hours`, `:no_check_in`, `:no_check_out`, `:min_nights`, `:max_nights`, `:min_duration`, `:max_duration`, `:max_selections` |
| `:date_click` | a span, sent when `selectable="none"` |
| `:event_click` | `%{id, key, event, recurring}`, where `event` is your original map or struct |
| `:event_drop` / `:event_resize` | the click payload plus the new span and `previous` (the old span) |

A **span** looks like this:

- `%{start, end, all_day, resource_id, time_zone}`, plus `nights` for all-day spans or `minutes` for timed ones.
- All-day spans carry `Date`s and timed spans carry `NaiveDateTime`s in `time_zone`.
- `end` is always exclusive.

If you do not save a drop, the event renders where it was, so reverting costs nothing. Setting `notify={false}` silences every message.

You can drive the calendar from the server:

- `FullCalendar.navigate(id, date)`;
- `FullCalendar.change_view(id, view)`;
- `FullCalendar.clear_selection(id)` (call it after saving a booking);
- or pass `view`, `date` and `selection` again. They are adopted only when they change, so the calendar still pages on its own.

## Events

Events are maps or structs, with atom or string keys:

| key | |
|---|---|
| `id`, `title` | required / shown |
| `start`, `end` | `Date`, `NaiveDateTime`, `DateTime` (shifted to `time_zone`) or ISO 8601 strings. A missing `end` means one day (all-day) or `default_duration` minutes |
| `all_day` | inferred from a `Date` start |
| `resource_id` | the room, doctor or agent it belongs to |
| `color` | lands in `--fc-event-color` and `data-color` |
| `status` | lands in `data-status`, e.g. `pending` |
| `display` | `"background"` shades time and blocks picks instead of rendering an event |
| `editable` | per-event override of `editable` |
| `recurrence` | `"FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10"` or `%{freq: :weekly, interval: 1, by_day: [1, 3], count: 10, until: ~D[...], exdates: [...]}` (DAILY, WEEKLY, MONTHLY, YEARLY). Only the visible range is expanded, and each occurrence's key is `"id@start"` |

## Options

Every option can be left out. `preset` fills in defaults for a use case, and anything you set wins.

| option | default | |
|---|---|---|
| `preset` | — | `hotel`, `doctor`, `viewing`, `planner` |
| `view` / `views` | `month` / month, week, day, list | plus `resource_day` and `timeline` |
| `selectable` | `none` | `single`, `multiple`, `range` |
| `range_end` | `inclusive` | `checkout`: the second day is the morning the stay ends |
| `editable` | `false` | drag to move, drag the edge to resize |
| `resources` / `resource_id` | `[]` / — | columns or rows; `resource_id` scopes the plain views to one resource |
| `hours`, `slot_duration`, `select_duration`, `scroll_to` | `0..24`, 30, one slot, 8 | the time grid |
| `business_hours` | — | `%{days: [1..5], hours: 9..17}`, a list of those, or per resource |
| `select_constraint` | — | `"business_hours"` |
| `min`, `max`, `disabled_dates`, `disabled_weekdays`, `allow_past`, `min_notice` | | availability |
| `select_overlap` / `event_overlap` | `true` | whether picks and drops may cover other events |
| `min_nights`, `max_nights`, `min_duration`, `max_duration`, `max_selections` | | lengths |
| `day_info` | `%{}` | `%{date => %{label: "$120", status: "check_in_only"}}` |
| `day_max_events`, `fixed_weeks`, `week_numbers`, `all_day_slot`, `now_indicator` | 3, true, false, true, true | layout |
| `first_day_of_week`, `hidden_weekdays`, `hour12` | 1, `[]`, false | |
| `calendar`, `labels`, `time_zone`, `now` | `Calendar.ISO`, English, `Etc/UTC`, now | see below |

## Recipes

```heex
<%!-- Hotel: one room's availability; the timeline shows every room --%>
<.full_calendar id="stay" preset="hotel" resources={@rooms} resource_id={@room}
  events={@bookings} day_info={@prices} min_nights={2} />

<%!-- Clinic: a column per doctor, 15 minute rows, 30 minute appointments --%>
<.full_calendar id="clinic" preset="doctor" resources={@doctors} events={@appointments}
  select_duration={30} />

<%!-- House viewing: up to three proposed slots --%>
<.full_calendar id="viewing" preset="viewing" events={@viewings} max_selections={3} />

<%!-- Planner: drag, resize, custom popover content --%>
<.full_calendar id="plans" preset="planner" events={@plans}>
  <:popover_content :let={occ}>
    <button phx-click="delete" phx-value-id={occ.id}>Delete</button>
  </:popover_content>
</.full_calendar>
```

Slots:

- `:event_content` replaces what an event shows;
- `:popover_content` adds to the event popover;
- `:toolbar_extra` adds to the toolbar;
- `:no_events` is the empty list view.

Each receives the occurrence (`id`, `title`, `start`, `end`, `all_day`, `resource_id`, `source`).

## Calendars, languages, time zones

The grid only uses `Date` functions that every `Calendar` implementation provides, so a non-Gregorian calendar is an option, not a rewrite. For Shamsi (Jalali):

```heex
<.full_calendar id="fa" calendar={Jalaali.Calendar} first_day_of_week={6} dir="rtl"
  labels={%{
    months: ~w(فروردین اردیبهشت خرداد تیر مرداد شهریور مهر آبان آذر دی بهمن اسفند),
    weekdays: ~w(دوشنبه سه‌شنبه چهارشنبه پنجشنبه جمعه شنبه یکشنبه),
    weekdays_short: ~w(د س چ پ ج ش ی),
    digits: ~w(۰ ۱ ۲ ۳ ۴ ۵ ۶ ۷ ۸ ۹),
    today: "امروز"
  }} />
```

Month names and weekday names are listed in calendar order, with weekdays Monday first. Everything on the wire stays ISO 8601, so the hook never does calendar math. RTL comes from `dir`: the grid uses logical CSS properties and the arrow keys follow the reading direction.

`time_zone="Europe/Berlin"` shows `DateTime` events in that zone. `time_zone="auto"` asks the browser. Both need a time zone database (`tz` or `tzdata`); unknown zones fall back to UTC.

## Anatomy and state

The root is `div.chelekom-full-calendar` with `data-view`, `data-selectable`, `data-editable` and, while dragging, `data-dragging`. Parts carry `data-part`:

- `toolbar`, `previous`, `today`, `next`, `title`, `view-button`, `status`, `view`, `header`;
- `week` (any row of day columns), `day`, `day-number`, `slot`, `axis`;
- `event`, `resizer`, `more`, `more-popover`, `popover`;
- `list-day`, `resource`, `now`;
- structural parts (targeted with `data-part` only): `scroller`, `head`, `body`, `column`, `all-day`, `timeline-row`, `background`.

State attributes:

- `data-selected`, `data-disabled` (a rule would refuse it), `data-range-start`, `data-range-end`;
- `data-anchor` (the first click of a range), `data-today`, `data-outside`, `data-business`, `data-shaded`;
- `data-status`, `data-cut-start` / `data-cut-end` (a bar continues into the next row);
- `data-drop-target` and `data-selecting` (set by the hook while dragging).

Layout knobs are CSS custom properties: `--fc-slot-height`, `--fc-row-min-height`, `--fc-lane-min-height`, `--fc-axis-width`, `--fc-scroll-height`, `--fc-resource-width`, `--fc-day-min-width`, `--fc-head-background`.

Every part takes a `*_class` attribute: `class`, `toolbar_class`, `title_class`, `nav_class`, `view_button_class`, `view_class`, `header_class`, `week_class`, `day_class`, `day_number_class`, `slot_class`, `axis_class`, `event_class`, `more_class`, `popover_class`, `list_day_class`, `resource_class`, `now_class` and `status_class`.

## Keyboard

- Arrow keys move between days or slots and page past the edge.
- Home and End go to the ends of the row.
- PageUp and PageDown move to the previous or next period.
- Enter or Space picks the focused cell or opens the focused event.
- Escape closes a popover or cancels a drag.

Only one cell per grid is in the tab order.

## Testing

Everything is server state, so `Phoenix.LiveViewTest` covers it:

- use `render_click` on `[data-part=day][data-start='2026-03-12T00:00:00']`;
- use `render_hook(view |> element("#calendar"), "drop", %{key:, from:, to:})` for what the hook would send;
- use `assert_receive` on the messages, with a test LiveView that forwards them.

The pure parts are public: `options/2`, `weeks/2`, `visible_range/3`, `occurrences/3`, `recurrence/1`, `day_row/3`, `time_layout/1` and `check/3`.
