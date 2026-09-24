[
  chat_message: [
    name: "chat_message",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_message",
    spec_url: "https://www.w3.org/TR/wai-aria-1.2/#article",
    args: [type: ["chat_message"], only: ["chat_message"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    headless: [
      anatomy: [
        root: [
          element: "div",
          role: "article",
          aria: ["aria-label", "aria-busy"],
          data_attributes: ["data-role", "data-status", "data-last"],
          note: "one turn; data-role is user | assistant | system | tool",
          required: true
        ],
        parts: [
          avatar: [element: "div", note: "optional avatar / role icon"],
          body: [element: "div", note: "wraps everything beside the avatar"],
          header: [element: "div", note: "only when a name or timestamp is given"],
          name: [element: "span"],
          time: [element: "time", note: "datetime attribute carries the ISO8601 value"],
          content: [element: "div", note: "the message itself"],
          caret: [element: "span", aria: ["aria-hidden"], note: "only while streaming/pending"],
          attachments: [element: "div"],
          error: [element: "div", role: "alert", note: "only when status is error"],
          footer: [element: "div", note: "the actions slot"]
        ]
      ],
      aria_pattern: [
        pattern: "Article (role=article) with an accessible name, inside a log",
        keyboard: ["None — the message itself is static; its actions are ordinary buttons"]
      ],
      state_attributes: ["data-role", "data-status", "data-last"],
      hooks: []
    ]
  ]
]
