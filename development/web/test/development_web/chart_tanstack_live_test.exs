defmodule DevelopmentWeb.ChartTanstackLiveTest do
  @moduledoc """
  The `chart` component over the TanStack engine (`--lib tanstack`) at `/showcase/headless/chart`.

  The engine is vendored under the `ChartTanstack` hook beside the default ECharts `Chart`, so the
  point of these tests is that NOTHING in the server contract changes with the engine: the same
  ignored surface, the same `data-*` channel, the same `chelekom:chart` push — only the option's
  vocabulary differs.
  """
  use DevelopmentWeb.ConnCase
  import Phoenix.LiveViewTest

  @path "/showcase/headless/chart"

  defp query(html, selector), do: html |> LazyHTML.from_document() |> LazyHTML.query(selector)

  defp attrs(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)

  defp tanstack_surfaces(html), do: query(html, ~s([data-part=surface][phx-hook="ChartTanstack"]))

  describe "the showcase cards" do
    test "render every TanStack example on the engine's hook", %{conn: conn} do
      {:ok, _view, html} = live(conn, @path)

      ids = html |> tanstack_surfaces() |> LazyHTML.attribute("id")

      for card <- ~w(bars time grouped stack ranking scatter donut radar heatmap) do
        assert Enum.any?(ids, &String.ends_with?(&1, "-ts-#{card}-surface")),
               "no TanStack #{card} chart rendered"
      end
    end

    test "keep the engine-independent contract: ignored surface, data-* channel, labelled", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, @path)
      surfaces = tanstack_surfaces(html)

      # Nine cards plus the live demo; the checks below would pass vacuously on none.
      assert Enum.count(surfaces) == 10

      assert Enum.all?(LazyHTML.attribute(surfaces, "phx-update"), &(&1 == "ignore"))

      for {id, root_id} <-
            Enum.zip(
              LazyHTML.attribute(surfaces, "id"),
              LazyHTML.attribute(surfaces, "data-root-id")
            ) do
        assert id == "#{root_id}-surface"
      end

      # The engine moves this onto the SVG it renders; the server still has to supply it.
      assert length(LazyHTML.attribute(surfaces, "aria-label")) == Enum.count(surfaces)
    end

    test "ship the option as TanStack's grammar in data-option", %{conn: conn} do
      {:ok, _view, html} = live(conn, @path)

      [raw] = attrs(html, ~s([id$="-ts-donut-surface"]), "data-option")
      option = Jason.decode!(raw)

      assert [%{"mark" => "polar", "marks" => [arc]}] = option["marks"]
      assert arc["mark"] == "radialArc"
      assert arc["pie"] == %{"value" => "visits", "gapAngle" => 0.02}
      assert arc["innerRadius"] == "58%"

      # The pie transform reserves `source` for lineage on every slice; a category field by that
      # name would silently color every slice the same.
      refute Enum.any?(arc["data"], &Map.has_key?(&1, "source"))
    end

    test "name the --lib in the copy-paste snippet, never the harness-only hook", %{conn: conn} do
      {:ok, _view, html} = live(conn, @path)

      snippets =
        html
        |> query("pre code")
        |> Enum.map(&LazyHTML.text/1)
        |> Enum.filter(&(&1 =~ "--lib tanstack"))

      assert length(snippets) == 9

      for snippet <- snippets do
        assert snippet =~
                 ~r/\A<%!-- mix mishka.ui.gen.headless chart --lib tanstack --%>\n<.chart/

        # In the app the engine installs under the plain `Chart` hook.
        refute snippet =~ "ChartTanstack"
      end
    end
  end

  describe "server-driven" do
    test "pushing new data travels as chelekom:chart, not as a re-rendered option", %{conn: conn} do
      {:ok, view, html} = live(conn, @path)

      [before] = attrs(html, ~s([id$="-ts-demo-live-surface"]), "data-option")
      [root_id] = attrs(html, ~s([id$="-ts-demo-live-surface"]), "data-root-id")

      html = view |> element(~s([id$="-ts-demo-shuffle"])) |> render_click()

      assert_push_event(view, "chelekom:chart", %{id: ^root_id, option: option})
      assert [%{mark: "barY", data: rows} | _] = option.marks
      assert length(rows) == 6

      assert attrs(html, ~s([id$="-ts-demo-live-surface"]), "data-option") == [before],
             "the same change must not also re-render data-option, or the chart redraws twice"
    end

    test "a clicked point reaches the server with its values", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)

      # The surface carries no phx-target; the hook pushes to its component, which the demo's
      # button (same component) routes to.
      html =
        view
        |> element(~s([id$="-ts-demo-shuffle"]))
        |> render_hook("point-clicked", %{"x" => "Mar", "y" => 901, "datumIndex" => 2})

      clicked = html |> query(~s([id$="-ts-demo-clicked"])) |> LazyHTML.text()
      assert clicked =~ "Mar"
      assert clicked =~ "901"
    end
  end
end
