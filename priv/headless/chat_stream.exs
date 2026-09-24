[
  chat_stream: [
    name: "chat_stream",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_stream",
    spec_url: "https://www.w3.org/TR/wai-aria-1.2/#aria-busy",
    args: [type: ["chat_stream"], only: ["chat_stream"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    scripts: [
      %{
        module: "ChatStream",
        type: "file",
        file: "chat_stream.js",
        imports: "import ChatStream from \"./chat_stream.js\";"
      }
    ],
    headless: [
      anatomy: [
        root: [
          element: "span",
          data_attributes: ["data-done"],
          note: "the live wrapper; receives data-done when the stream finishes",
          required: true
        ],
        parts: [
          text: [
            element: "span",
            data_attributes: ["data-root-id", "data-text", "data-smooth"],
            note:
              "carries the ChatStream hook + phx-update=\"ignore\"; id is <root id>-text. Text " <>
                "is appended with textContent, never innerHTML"
          ],
          caret: [element: "span", aria: ["aria-hidden"], note: "rendered until done"]
        ]
      ],
      aria_pattern: [
        pattern: "Streaming text inside a busy log",
        keyboard: [
          "None — pair it with chat_message (aria-busy) inside chat_thread (role=log) so the " <>
            "finished answer is announced once"
        ]
      ],
      state_attributes: ["data-done"],
      hooks: ["ChatStream"]
    ]
  ]
]
