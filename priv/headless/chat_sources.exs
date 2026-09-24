[
  chat_sources: [
    name: "chat_sources",
    category: "chat",
    doc_url: "https://mishka.tools/chelekom/docs/headless/chat_sources",
    spec_url: "https://www.w3.org/WAI/ARIA/apg/patterns/landmarks/",
    args: [type: ["chat_sources"], only: ["chat_sources"], helpers: [], module: ""],
    optional: [],
    necessary: [],
    required: false,
    precompile: false,
    headless: [
      anatomy: [
        root: [element: "section", aria: ["aria-label"], required: true],
        parts: [
          label: [
            element: "span",
            aria: ["aria-hidden"],
            note: "the visible heading (the root carries the accessible name)"
          ],
          list: [element: "ol"],
          source: [element: "li", data_attributes: ["data-index"]],
          link: [element: "a", note: "target=_blank rel=noopener noreferrer"],
          index: [element: "span", note: "1-based, matching [1] markers in the answer"],
          favicon: [element: "img", note: "decorative (alt=\"\")"],
          title: [element: "span", note: "page title, or the domain"],
          domain: [element: "span", note: "derived from href when not given"]
        ]
      ],
      aria_pattern: [
        pattern: "Labelled section with an ordered list of links",
        keyboard: ["Tab — move between sources", "Enter — open in a new tab"]
      ],
      state_attributes: [],
      hooks: []
    ]
  ]
]
