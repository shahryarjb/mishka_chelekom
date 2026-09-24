[
  chat_tool_call: [
    name: "chat_tool_call",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_tool_call",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/",
    args: [type: ["chat_tool_call"], only: ["chat_tool_call"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    headless: [
      anatomy: [
        root: [
          element: "details",
          aria: ["aria-busy"],
          data_attributes: ["data-status", "data-tool"],
          note:
            "data-status is pending | running | success | error | awaiting_approval | cancelled",
          required: true
        ],
        parts: [
          trigger: [element: "summary"],
          icon: [element: "span", aria: ["aria-hidden"]],
          name: [element: "span", note: "the tool's name"],
          label: [element: "span", note: "a human description of the call"],
          status: [element: "span", data_attributes: ["data-status"], note: "status as text"],
          duration: [element: "span", note: ~s|"320 ms" / "1.4 s"|],
          content: [element: "div"],
          args: [element: "div", note: "pretty JSON in pre > code"],
          result: [element: "div", note: "the :result slot, or the output attr as pretty JSON"],
          heading: [element: "span", note: "the Arguments / Result headings"]
        ]
      ],
      aria_pattern: [
        pattern: "Disclosure (native details/summary)",
        keyboard: ["Tab — focus the summary", "Enter / Space — expand or collapse"]
      ],
      state_attributes: ["data-status"],
      hooks: []
    ]
  ]
]
