defmodule DevelopmentWeb.Showcase.ChartTanstackDemo do
  @moduledoc """
  The TanStack engine driven from the server: a live `push_event` update and a click round-trip.

  In a real app you generate the engine with `mix mishka.ui.gen.headless chart --lib tanstack` and
  it installs as `chart.js` under the `Chart` hook. The harness vendors it beside the default
  ECharts engine under `ChartTanstack`, which is what the `hook` attr is for.

  The option is assigned ONCE (`:initial`) and never re-rendered: new data travels as a push, so
  the ignored surface is not also patched with a fresh `data-option` for the same change. TanStack
  reconciles the new scene by key, so the bars animate to their new heights.
  """
  use DevelopmentWeb, :live_component

  import DevelopmentWeb.Components.Headless.Chart

  @months ~w(Jan Feb Mar Apr May Jun)
  @start [820, 932, 901, 1234, 1290, 1330]

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:initial, fn -> option(@start) end)
     |> assign_new(:pushes, fn -> 0 end)
     |> assign_new(:clicked, fn -> nil end)}
  end

  @impl true
  def handle_event("shuffle", _params, socket) do
    values = Enum.map(@months, fn _ -> Enum.random(400..1600) end)

    {:noreply,
     socket
     |> assign(pushes: socket.assigns.pushes + 1)
     |> push_event("chelekom:chart", %{id: chart_id(socket.assigns.id), option: option(values)})}
  end

  # The engine's payload: `x`/`y` are the point's values, `datum` the row it came from.
  def handle_event("point-clicked", params, socket) do
    {:noreply, assign(socket, clicked: %{month: params["x"], revenue: params["y"]})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex flex-wrap items-center gap-3">
        <button
          id={"#{@id}-shuffle"}
          type="button"
          phx-click="shuffle"
          phx-target={@myself}
          class="rounded-md border border-[var(--c-base-300)] bg-[var(--c-base-100)] px-3 py-1.5 text-sm font-medium hover:bg-[var(--c-base-200)]"
        >
          Push new data
        </button>
        <span class="text-xs text-[var(--c-base-content)]/60">
          pushes: <strong>{@pushes}</strong>
        </span>
        <span id={"#{@id}-clicked"} class="text-xs text-[var(--c-base-content)]/60">
          <%= if @clicked do %>
            server got a click: <strong>{@clicked.month}</strong>
            → <strong>{@clicked.revenue}</strong>
          <% else %>
            click a bar (or focus the chart and press Enter)
          <% end %>
        </span>
      </div>

      <.chart
        id={chart_id(@id)}
        hook="ChartTanstack"
        option={@initial}
        height="16rem"
        on_click="point-clicked"
        aria_label="Monthly revenue, updated live from the server"
        class="w-full"
      />
    </div>
    """
  end

  defp chart_id(id), do: "#{id}-live"

  defp option(values) do
    %{
      marks: [
        %{
          mark: "barY",
          data: Enum.zip_with(@months, values, &%{month: &1, revenue: &2}),
          x: "month",
          y: "revenue",
          radius: 4
        },
        %{mark: "ruleY", data: [0]}
      ],
      scales: %{
        x: %{scale: "band", padding: 0.2},
        y: %{
          scale: "linear",
          domain: [0, 1600],
          grid: true,
          axis: %{ticks: %{format: "chelekom:compact"}}
        }
      },
      tooltip: true
    }
  end
end
