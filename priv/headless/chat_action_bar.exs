[
  chat_action_bar: [
    name: "chat_action_bar",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_action_bar",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/button/",
    args: [type: ["chat_action_bar"], only: ["chat_action_bar"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    scripts: [
      %{
        module: "ChatActionBar",
        type: "file",
        file: "chat_action_bar.js",
        imports: "import ChatActionBar from \"./chat_action_bar.js\";"
      }
    ],
    headless: [
      anatomy: [
        root: [
          element: "div",
          role: "group",
          aria: ["aria-label"],
          data_attributes: [
            "data-autohide",
            "data-copy-text",
            "data-copy-from",
            "data-copied",
            "data-copied-label",
            "data-copied-duration"
          ],
          note: "carries the ChatActionBar hook only when it can copy (id + copy/copy_from)",
          required: true
        ],
        parts: [
          copy: [
            element: "button",
            aria: ["aria-label"],
            data_attributes: ["data-copied"],
            note: "data-copied (sticky) for copied_duration ms after a copy"
          ],
          "copy-status": [
            element: "span",
            role: "status",
            aria: ["aria-live"],
            note: "visually hidden; announces the copied label"
          ],
          action: [
            element: "button",
            aria: ["aria-label", "aria-pressed"],
            data_attributes: ["data-action", "data-pressed"],
            note: "one per :action slot; aria-pressed when `pressed` is given (feedback toggles)"
          ]
        ]
      ],
      aria_pattern: [
        pattern: "Group of buttons (toggle buttons for feedback)",
        keyboard: [
          "Tab — move between the actions",
          "Enter / Space — activate; a hidden (autohide) bar becomes visible while focused"
        ]
      ],
      state_attributes: ["data-autohide", "data-copied", "data-pressed"],
      hooks: ["ChatActionBar"]
    ]
  ]
]
