[
  chat_suggestions: [
    name: "chat_suggestions",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_suggestions",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/button/",
    args: [type: ["chat_suggestions"], only: ["chat_suggestions"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    headless: [
      anatomy: [
        root: [element: "div", role: "group", aria: ["aria-label"], required: true],
        parts: [
          suggestion: [
            element: "button",
            data_attributes: ["data-prompt"],
            note: "sends on_select with phx-value-prompt"
          ],
          title: [element: "span", note: "the title, or the prompt itself"],
          description: [element: "span"]
        ]
      ],
      aria_pattern: [
        pattern: "Group of buttons",
        keyboard: ["Tab — move between suggestions", "Enter / Space — send it"]
      ],
      state_attributes: [],
      hooks: []
    ]
  ]
]
