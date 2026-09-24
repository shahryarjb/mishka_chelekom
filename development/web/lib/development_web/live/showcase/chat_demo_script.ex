defmodule DevelopmentWeb.Showcase.ChatDemoScript do
  @moduledoc """
  The pretend model behind `/showcase/chat`.

  It exists so the chat components can be exercised end to end — thinking, a tool call, a
  streamed answer with sources, an approval — without an API key. Everything here is pure: the
  LiveView owns the timers and the socket, this module only decides what the "model" says.
  """

  @type reply :: %{
          steps: [map()],
          tool: map(),
          sources: [map()],
          text: String.t(),
          approval: nil | map()
        }

  @suggestions [
    %{
      prompt: "Which flavor should we launch this summer?",
      title: "Summer launch",
      description: "pick a hero flavor"
    },
    %{
      prompt: "Find a waffle cone supplier",
      title: "Cone suppliers",
      description: "search the web"
    },
    %{
      prompt: "Delete the old build directory",
      title: "Clean the build",
      description: "asks before it acts"
    }
  ]

  @doc "Starter prompts for the empty thread."
  @spec suggestions() :: [map()]
  def suggestions, do: @suggestions

  @doc "Follow-up prompts offered under a finished answer."
  @spec follow_ups(prompt :: String.t()) :: [map()]
  def follow_ups(prompt) do
    if String.contains?(String.downcase(prompt), "supplier"),
      do: [
        %{prompt: "Compare their prices per 1,000 cones"},
        %{prompt: "Which one ships fastest?"}
      ],
      else: [
        %{prompt: "Which flavors sell best in winter?"},
        %{prompt: "Compare gelato and soft serve margins"}
      ]
  end

  @doc """
  What the model does for `prompt`. `attempt` (1-based) varies the wording, so regenerating an
  answer produces a visibly different branch.
  """
  @spec reply(prompt :: String.t(), attempt :: pos_integer()) :: reply()
  def reply(prompt, attempt \\ 1) do
    down = String.downcase(prompt)

    cond do
      String.contains?(down, ["delete", "remove", "rm "]) -> destructive(attempt)
      String.contains?(down, ["supplier", "cone", "search", "find"]) -> search(attempt)
      true -> general(prompt, attempt)
    end
  end

  @doc "Split an answer into the chunks the fake model streams (words, keeping their spaces)."
  @spec tokens(text :: String.t()) :: [String.t()]
  def tokens(text), do: Regex.split(~r/(?<=\s)/u, text, trim: true)

  defp search(attempt) do
    %{
      steps: [
        %{label: "Planning the search", status: "done"},
        %{label: "best waffle cone supplier", detail: "query", status: "done"},
        %{label: "Reading the top results", detail: "3 pages", status: "done"}
      ],
      tool: %{
        name: "web_search",
        label: "Searched the web",
        args: %{"query" => "best waffle cone supplier", "limit" => 3}
      },
      sources: [
        %{href: "https://joycone.com/fs_products/waffle-cones/", title: "Joy Cone"},
        %{href: "https://www.webstaurantstore.com/", title: "WebstaurantStore"},
        %{href: "https://www.thekonery.com/", title: "The Konery"}
      ],
      text:
        Enum.at(
          [
            "Joy Cone is the safest pick: they bake waffle cones in bulk and ship nationally [1]. " <>
              "WebstaurantStore is cheaper per case but slower to restock [2], and The Konery " <>
              "makes premium gluten-free cones if you want a specialty line [3].",
            "For volume, go with Joy Cone [1]. If price matters most, WebstaurantStore undercuts " <>
              "them by about 12% per case [2]. The Konery is the boutique option [3]."
          ],
          rem(attempt - 1, 2)
        ),
      approval: nil
    }
  end

  defp destructive(_attempt) do
    %{
      steps: [
        %{label: "Locating build/", detail: "412 files", status: "done"},
        %{label: "Checking nothing else depends on it", status: "done"}
      ],
      tool: %{name: "shell", label: "rm -rf build/", args: %{"command" => "rm -rf build/"}},
      sources: [],
      text:
        "Done — build/ is gone (412 files, 38 MB). The next `mix assets.deploy` recreates it.",
      approval: %{
        title: "Run `rm -rf build/`?",
        description: "This permanently deletes 412 files in build/."
      }
    }
  end

  defp general(prompt, attempt) do
    openers = [
      "Pistachio. Its sales are up 23% this month and its margin beats vanilla by 8 points.",
      "I'd launch pistachio — it is your fastest-growing flavor, up 23% month over month."
    ]

    %{
      steps: [
        %{label: "Reading flavor briefs", status: "done"},
        %{label: "Comparing tasting notes", detail: "6 flavors", status: "done"},
        %{label: "Writing the answer", status: "done"}
      ],
      tool: %{
        name: "sales_report",
        label: "Queried last month's sales",
        args: %{"metric" => "units", "period" => "30d", "question" => prompt}
      },
      sources: [],
      text:
        Enum.at(openers, rem(attempt - 1, 2)) <>
          "\n\nStone-fruit flavors are trending in the same range, so peach makes a strong " <>
          "runner-up. Keep both near the front of the freezer through August.",
      approval: nil
    }
  end
end
