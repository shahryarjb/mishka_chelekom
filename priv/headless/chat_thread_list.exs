[
  chat_thread_list: [
    name: "chat_thread_list",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_thread_list",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/landmarks/examples/navigation.html",
    args: [type: ["chat_thread_list"], only: ["chat_thread_list"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    headless: [
      anatomy: [
        root: [element: "nav", aria: ["aria-label"], required: true],
        parts: [
          new: [element: "a | button", note: "new chat: a link (navigate/patch) or on_new"],
          list: [element: "ul"],
          item: [element: "li", data_attributes: ["data-active"]],
          link: [
            element: "a | button",
            aria: ["aria-current"],
            note: "a link when the thread has a URL, else a button sending on_select"
          ],
          title: [element: "span"],
          meta: [element: "span"],
          archive: [element: "button", aria: ["aria-label"], note: "only with on_archive"],
          delete: [element: "button", aria: ["aria-label"], note: "only with on_delete"],
          empty: [element: "div", note: "only when there are no threads"]
        ]
      ],
      aria_pattern: [
        pattern: "Navigation landmark with a list of links",
        keyboard: ["Tab — move between conversations and their actions", "Enter — open"]
      ],
      state_attributes: ["data-active"],
      hooks: []
    ]
  ]
]
