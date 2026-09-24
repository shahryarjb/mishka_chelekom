[
  full_calendar: [
    name: "full_calendar",
    category: "data display",
    doc_url: "https://mishka.tools/chelekom/docs/headless/full_calendar",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/grid/",
    args: [type: ["full_calendar"], only: ["full_calendar"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    # The hook is colocated in the template (`Phoenix.LiveView.ColocatedHook`, LiveView 1.1+):
    # Phoenix 1.8 apps already import `phoenix-colocated/<app>`, so there is nothing to wire.
    scripts: [],
    headless: [
      anatomy: [
        root: [
          element: "div",
          role: "none",
          aria: [],
          data_attributes: [
            "data-view",
            "data-selectable",
            "data-editable",
            "data-time-zone",
            "data-first",
            "data-last",
            "data-anchor",
            "data-dragging"
          ],
          note:
            "a `Phoenix.LiveComponent`: it keeps the view, the date and the selection, lays " <>
              "everything out on the server and tells the parent LiveView what happened; the " <>
              "colocated hook only drags, resizes, moves focus and scrolls",
          required: true
        ],
        parts: [
          toolbar: [element: "div", note: "previous / today / next, the title and the views"],
          previous: [element: "button", aria: ["aria-label"]],
          today: [element: "button"],
          next: [element: "button", aria: ["aria-label"]],
          title: [element: "h2", aria: ["aria-live"], note: "announces the period as it changes"],
          "view-button": [
            element: "button",
            aria: ["aria-pressed"],
            data_attributes: ["data-view", "data-active"]
          ],
          status: [
            element: "div",
            role: "status",
            data_attributes: ["data-empty"],
            note: "why a pick was refused — \"Choose at least 2 nights\""
          ],
          view: [element: "div", role: "group", data_attributes: ["data-view"]],
          header: [element: "div", data_attributes: ["data-today", "data-resource"]],
          week: [
            element: "div",
            note:
              "a row of day columns — a month week, the all-day lane, a resource's timeline " <>
                "row; `--fc-cols` / `--fc-levels` size its grid"
          ],
          day: [
            element: "button",
            aria: ["aria-label", "aria-current", "aria-disabled", "aria-pressed"],
            data_attributes: [
              "data-start",
              "data-end",
              "data-resource",
              "data-today",
              "data-outside",
              "data-disabled",
              "data-selected",
              "data-range-start",
              "data-range-end",
              "data-anchor",
              "data-shaded",
              "data-status"
            ],
            note:
              "a whole day to pick; disabled when a rule would refuse it, so the grid shows " <>
                "what can be booked before anyone clicks"
          ],
          "day-number": [element: "button", note: "jumps to that day's view"],
          slot: [
            element: "button",
            aria: ["aria-label", "aria-disabled", "aria-pressed"],
            data_attributes: [
              "data-start",
              "data-end",
              "data-resource",
              "data-business",
              "data-hour",
              "data-disabled",
              "data-selected"
            ],
            note: "one row of the time grid"
          ],
          axis: [element: "span", note: "the time labels"],
          event: [
            element: "button",
            aria: ["aria-label", "aria-haspopup"],
            data_attributes: [
              "data-key",
              "data-placement",
              "data-all-day",
              "data-editable",
              "data-status",
              "data-color",
              "data-recurring",
              "data-cut-start",
              "data-cut-end",
              "data-dragging"
            ],
            note: "`--fc-event-color` carries the event's own color"
          ],
          resizer: [element: "span", note: "the edge a pointer drags to resize"],
          more: [element: "button", aria: ["aria-expanded", "aria-controls"]],
          "more-popover": [
            element: "div",
            role: "dialog",
            note: "opened and closed with JS commands alone"
          ],
          popover: [element: "div", role: "dialog", aria: ["aria-labelledby"]],
          "list-day": [element: "section", aria: ["aria-label"], data_attributes: ["data-today"]],
          resource: [element: "div", note: "a resource's name at the start of its timeline row"],
          now: [element: "div", note: "the current time, moved by the hook between renders"]
        ]
      ],
      aria_pattern: [
        pattern: "Grid",
        keyboard: [
          "Arrow keys — move between days or time slots (and page past the edge)",
          "Home / End — first / last cell of the row",
          "PageUp / PageDown — previous / next period",
          "Enter / Space — pick the focused day or slot, or open the focused event",
          "Escape — close a popover, cancel a drag"
        ]
      ],
      state_attributes: [
        "data-selected",
        "data-disabled",
        "data-today",
        "data-outside",
        "data-range-start",
        "data-range-end",
        "data-anchor",
        "data-business",
        "data-dragging",
        "data-drop-target",
        "data-selecting"
      ],
      hooks: [".FullCalendar"]
    ]
  ]
]
