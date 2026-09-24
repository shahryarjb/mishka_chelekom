[
  chat_reasoning: [
    name: "chat_reasoning",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_reasoning",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/",
    args: [type: ["chat_reasoning"], only: ["chat_reasoning"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    scripts: [
      %{
        module: "ChatReasoning",
        type: "file",
        file: "chat_reasoning.js",
        imports: "import ChatReasoning from \"./chat_reasoning.js\";"
      }
    ],
    headless: [
      anatomy: [
        root: [
          element: "details",
          aria: ["aria-busy"],
          data_attributes: ["data-status"],
          note:
            "carries the ChatReasoning hook: opens while streaming, closes when done, unless the " <>
              "reader toggled it",
          required: true
        ],
        parts: [
          trigger: [element: "summary", note: "the native disclosure button"],
          icon: [element: "span", aria: ["aria-hidden"]],
          label: [
            element: "span",
            role: "status",
            data_attributes: ["data-status"],
            note: ~s|"Thinking" while streaming, "Thought for N seconds" when done|
          ],
          content: [element: "div", note: "reasoning prose, then the steps"],
          steps: [element: "ol"],
          step: [
            element: "li",
            aria: ["aria-current"],
            data_attributes: ["data-status"],
            note: "aria-current=step on the active one"
          ],
          "step-label": [element: "a | span", note: "a link (new tab) when href is given"],
          "step-detail": [element: "span"]
        ]
      ],
      aria_pattern: [
        pattern: "Disclosure (native details/summary)",
        keyboard: ["Tab — focus the summary", "Enter / Space — expand or collapse"]
      ],
      state_attributes: ["data-status"],
      hooks: ["ChatReasoning"]
    ]
  ]
]
