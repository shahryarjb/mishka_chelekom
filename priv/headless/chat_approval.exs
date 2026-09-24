[
  chat_approval: [
    name: "chat_approval",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_approval",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/radio/",
    args: [type: ["chat_approval"], only: ["chat_approval"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    headless: [
      anatomy: [
        root: [
          element: "form",
          data_attributes: ["data-status"],
          note: "data-status is pending | approved | denied | answered",
          required: true
        ],
        parts: [
          fieldset: [
            element: "fieldset",
            aria: ["aria-describedby"],
            note: "disabled once decided"
          ],
          title: [element: "legend", note: "the question — the fieldset's accessible name"],
          description: [element: "p", note: "id is <id>-description"],
          options: [element: "div", note: "only with :option slots"],
          option: [element: "label", note: "one per :option"],
          "option-input": [element: "input", note: "radio, or checkbox with multiple"],
          "option-label": [element: "span"],
          "option-description": [element: "span"],
          custom: [element: "input", aria: ["aria-label"], note: "free-text answer (allow_custom)"],
          actions: [element: "div"],
          approve: [element: "button", note: "type=submit"],
          deny: [element: "button", note: "sends on_deny; only when on_deny is set"]
        ]
      ],
      aria_pattern: [
        pattern: "Form: fieldset + legend with native radio buttons or checkboxes",
        keyboard: [
          "Arrow keys — move between radio options",
          "Space — toggle a checkbox option",
          "Enter — submit (approve)"
        ]
      ],
      state_attributes: ["data-status"],
      hooks: []
    ]
  ]
]
