[
  chat_attachment: [
    name: "chat_attachment",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_attachment",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/",
    args: [type: ["chat_attachment"], only: ["chat_attachment"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    headless: [
      anatomy: [
        root: [
          element: "div",
          aria: ["aria-busy"],
          data_attributes: ["data-kind", "data-status"],
          note:
            "data-kind is image | pdf | document | audio | video | archive | code | file, from " <>
              "the MIME type or the extension",
          required: true
        ],
        parts: [
          thumbnail: [element: "img", note: "decorative (alt=\"\") — the name carries the meaning"],
          icon: [element: "span", aria: ["aria-hidden"], note: "when there is no thumbnail"],
          name: [element: "a | span", note: "a link (new tab) when href is given"],
          meta: [element: "span", note: ~s|human size, "1.2 MB"|],
          progress: [element: "progress", aria: ["aria-label"], note: "while uploading"],
          remove: [element: "button", aria: ["aria-label"], note: "sends on_remove with phx-value-ref"]
        ]
      ],
      aria_pattern: [
        pattern: "Static item with an optional labelled remove button",
        keyboard: ["Tab — focus the name link / remove button"]
      ],
      state_attributes: ["data-kind", "data-status"],
      hooks: []
    ]
  ]
]
