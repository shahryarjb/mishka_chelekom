[
  chat_composer: [
    name: "chat_composer",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_composer",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/",
    args: [type: ["chat_composer"], only: ["chat_composer"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    scripts: [
      %{
        module: "ChatComposer",
        type: "file",
        file: "chat_composer.js",
        imports: "import ChatComposer from \"./chat_composer.js\";"
      }
    ],
    headless: [
      anatomy: [
        root: [
          element: "form",
          data_attributes: [
            "data-submit-mode",
            "data-running",
            "data-disabled",
            "data-empty",
            "data-on-cancel",
            "data-clear-on-submit"
          ],
          note: "carries the ChatComposer hook; data-empty (sticky) while the box is blank",
          required: true
        ],
        parts: [
          attachments: [element: "div", note: "pending attachments above the textarea"],
          input: [
            element: "textarea",
            aria: ["aria-label"],
            data_attributes: ["data-min-rows", "data-max-rows"],
            note: "id is <root id>-input; grows between min and max rows, then scrolls"
          ],
          actions: [element: "div", note: "the :leading slot, then stop or send"],
          send: [
            element: "button",
            aria: ["aria-label"],
            note: "type=submit; disabled (sticky) while blank, running or disabled"
          ],
          cancel: [
            element: "button",
            aria: ["aria-label"],
            note: "rendered instead of send while running, when on_cancel is set"
          ]
        ]
      ],
      aria_pattern: [
        pattern: "Form with a labelled multi-line textbox",
        keyboard: [
          "Enter — send (submit_mode enter); Shift+Enter — newline",
          "Ctrl/Cmd+Enter — send (submit_mode ctrl_enter)",
          "Escape — stop the running answer (on_cancel)",
          "Enter never sends while an IME is composing"
        ]
      ],
      state_attributes: ["data-running", "data-disabled", "data-empty"],
      hooks: ["ChatComposer"]
    ]
  ]
]
