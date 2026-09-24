[
  chat_branch_picker: [
    name: "chat_branch_picker",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_branch_picker",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/button/",
    args: [type: ["chat_branch_picker"], only: ["chat_branch_picker"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    headless: [
      anatomy: [
        root: [
          element: "div",
          role: "group",
          aria: ["aria-label"],
          data_attributes: ["data-index", "data-count"],
          note: "not rendered with a single version unless `always`",
          required: true
        ],
        parts: [
          previous: [element: "button", aria: ["aria-label"], note: "disabled on the first version"],
          status: [element: "span", aria: ["aria-live", "aria-atomic"], note: ~s|"2 / 3"|],
          next: [element: "button", aria: ["aria-label"], note: "disabled on the last version"]
        ]
      ],
      aria_pattern: [
        pattern: "Group of buttons with a live position",
        keyboard: ["Tab — previous / next", "Enter / Space — switch version"]
      ],
      state_attributes: ["data-index", "data-count"],
      hooks: []
    ]
  ]
]
