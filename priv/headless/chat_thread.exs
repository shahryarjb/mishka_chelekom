[
  chat_thread: [
    name: "chat_thread",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_thread",
    spec_url: "https://www.w3.org/TR/wai-aria-1.2/#log",
    args: [type: ["chat_thread"], only: ["chat_thread"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    scripts: [
      %{
        module: "ChatThread",
        type: "file",
        file: "chat_thread.js",
        imports: "import ChatThread from \"./chat_thread.js\";"
      }
    ],
    headless: [
      anatomy: [
        root: [
          element: "div",
          data_attributes: ["data-running", "data-auto-scroll", "data-on-top", "data-at-bottom"],
          note:
            "carries the ChatThread hook; receives data-at-bottom (sticky) while the viewport is " <>
              "scrolled to the end",
          required: true
        ],
        parts: [
          viewport: [
            element: "div",
            role: "region",
            aria: ["aria-label"],
            note: "the scroll container; focusable so the keyboard can scroll it"
          ],
          messages: [
            element: "div",
            role: "log",
            aria: ["aria-live", "aria-relevant", "aria-busy"],
            note: ~s|id is <root id>-messages; phx-update="stream" when `stream` is set|
          ],
          empty: [element: "div", note: "shown only while messages has no children (:has rule)"],
          "scroll-button": [
            element: "button",
            aria: ["aria-label"],
            note: "`hidden` (sticky) while at the bottom; click scrolls to the latest message"
          ],
          footer: [element: "div", note: "pinned below the viewport — the composer"]
        ]
      ],
      aria_pattern: [
        pattern: "Log (role=log) inside a labelled scroll region",
        keyboard: [
          "Tab — focus the viewport, then Arrow keys / Page Up / Page Down / Home / End scroll it",
          "Scrolling up stops following new content; returning to the end follows again"
        ]
      ],
      state_attributes: ["data-running", "data-at-bottom"],
      hooks: ["ChatThread"]
    ]
  ]
]
