[
  chat_typing_indicator: [
    name: "chat_typing_indicator",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_typing_indicator",
    spec_url: "https://www.w3.org/TR/wai-aria-1.2/#status",
    args: [
      type: ["chat_typing_indicator"],
      only: ["chat_typing_indicator"],
      helpers: [],
      module: ""
    ],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    headless: [
      anatomy: [
        root: [
          element: "div",
          role: "status",
          aria: ["aria-live"],
          note: "announces the label once, politely",
          required: true
        ],
        parts: [
          dot: [
            element: "span",
            aria: ["aria-hidden"],
            data_attributes: ["data-index"],
            note: "carries --index (0-based) for staggered animation"
          ],
          label: [element: "span", note: "screen-reader only unless show_label"]
        ]
      ],
      aria_pattern: [
        pattern: "Status (role=status, polite)",
        keyboard: ["None — not interactive"]
      ],
      state_attributes: [],
      hooks: []
    ]
  ]
]
