// Chart — headless charting engine (TanStack Charts, the framework-agnostic grammar-of-graphics
// core). One hook, `Chart`, drives every engine; this file is the TanStack build. The generator
// installs exactly one engine file as `chart.js`.
//
// The hook lives on [data-part="surface"], NOT on the component root. The surface is
// `phx-update="ignore"` because TanStack owns that subtree (an <svg> it reconciles), and LiveView
// merges ONLY `data-*` on an ignored element. Every live knob is a `data-*` and the whole chart
// spec rides in on data-option. See chart_echarts.js for the full element/data-* contract; the
// engines are interchangeable behind one <.chart> markup.
//
// TanStack Charts is a GRAMMAR, not a config object: a chart is a list of marks built by calling
// factories (`barY(rows, {x: "month", y: "sales"})`) and scales are factories too. A function
// cannot cross the LiveView wire, so the option is the same grammar spelled as data and this file
// turns it back into calls. Everything that is already plain data (channels as field names,
// paints, axis/grid/legend options, focus modes, …) is passed through untouched, so the TanStack
// docs apply as written:
//
//   %{
//     marks: [
//       %{mark: "barY", data: rows, x: "month", y: "sales", color: "region", layout: "group"},
//       %{mark: "ruleY", data: [0]}
//     ],
//     scales: %{
//       x: %{scale: "band", padding: 0.2},
//       y: %{scale: "linear", nice: true, grid: true,
//            axis: %{ticks: %{format: "chelekom:compact"}}}
//     },
//     color: %{legend: %{label: "Region", placement: "bottom"}},
//     tooltip: true,
//     focus: "group-x"
//   }
//
// What is translated (and only this — anything else goes to TanStack as-is):
//   mark: "<name>"        | the factory, from a whitelist (MARKS / POLAR_MARKS below). `data` is
//                         | its first argument; the rest of the map is its options
//   mark: "polar"         | a polar container: its own `marks`, `scales` (angle/radius) and
//                         | `guides` (%{guide: "radialGrid" | "angleGrid", …})
//   pie: %{value: …}      | on a radialArc — runs the `pie` transform over `data` first
//   layout: "stack" | "group" | %{type: "stack", …}  | the stack()/group() layouts
//   curve: "monotone" …   | a d3-shape curve by name (CURVES below)
//   scale: "linear" …     | a scale factory by name (SCALES below); `domain`, `padding`, `base`,
//                         | `exponent`, `constant` configure it. Temporal scales ("time"/"utc")
//                         | parse their channel's ISO strings into Dates for you
//   "50%" (polar lengths) | innerRadius/outerRadius/cornerRadius/padRadius as a share of the radius
//   "chelekom:*"          | formatter sentinels, anywhere; "chelekom:fade" as an area `fill`
//   color.legend          | true or a map -> colorLegend(); `gradient: true` ->
//                         | colorGradientLegend()
//   tooltip               | true or a map -> the built-in DOM tooltip extension, portaled out of
//                         | the clipped surface unless `portal: false`
//
// Missing x/y scales are inferred from the data (band for bar categories, point for other
// categories, utc for ISO dates, linear for numbers), so the smallest useful chart is just marks.
//
// Theming is pure CSS: the palette is `var(--chart-N, <fallback>)` and text/axis/grid read
// `--chart-text` / `--chart-axis` / `--chart-grid`, so a light/dark toggle re-colors the SVG with
// no JavaScript and no redraw. The tooltip reads TanStack's own `--ts-chart-tooltip-*` properties.
//
// Server -> client live updates: `push_event("chelekom:chart", %{id:, option:})`. TanStack diffs
// the new scene against the old one by key, so a push animates (with `svgAnimation`) instead of
// redrawing from scratch. `merge` is accepted for API parity; a TanStack option is always whole.

import {
  areaX,
  areaY,
  arrow,
  bandX,
  bandY,
  barX,
  barY,
  boxX,
  boxY,
  cell,
  colorGradientLegend,
  colorLegend,
  colorLegendItems,
  crosshair,
  d3Curve,
  defineChart,
  differenceX,
  differenceY,
  dot,
  frame,
  group,
  hexagon,
  lineX,
  lineY,
  link,
  rect,
  ruleX,
  ruleY,
  stack,
  text,
  tickX,
  tickY,
  vector,
  waffleX,
  waffleY,
} from "@tanstack/charts";
import { mountChart } from "@tanstack/charts/dom";
import { tooltip } from "@tanstack/charts/tooltip";
import { portal } from "@tanstack/charts/tooltip/portal";
import {
  angleGrid,
  pie,
  polar,
  radialArc,
  radialArea,
  radialBarAngle,
  radialBarRadius,
  radialDot,
  radialGrid,
  radialLine,
  radialRule,
  radialText,
} from "@tanstack/charts/polar";
import { scaleBand } from "@tanstack/charts/scales/band";
import { scaleLinear } from "@tanstack/charts/scales/linear";
import { scaleOrdinal } from "@tanstack/charts/scales/ordinal";
import { scalePoint } from "@tanstack/charts/scales/point";
import {
  scaleLinear as d3ScaleLinear,
  scaleLog,
  scalePow,
  scaleQuantile,
  scaleQuantize,
  scaleSqrt,
  scaleSymlog,
  scaleThreshold,
  scaleTime,
  scaleUtc,
} from "d3-scale";
import {
  curveBasis,
  curveBumpX,
  curveBumpY,
  curveCardinal,
  curveCardinalClosed,
  curveCatmullRom,
  curveCatmullRomClosed,
  curveLinear,
  curveLinearClosed,
  curveMonotoneX,
  curveMonotoneY,
  curveNatural,
  curveStep,
  curveStepAfter,
  curveStepBefore,
} from "d3-shape";
// Developer-owned, created once by the generator and never regenerated. See its header.
import userConfig from "./chart_extensions.js";

const FADE = "chelekom:fade";

// Built-in fallback palette, used only when neither the CSS custom properties --chart-1..8 nor the
// developer palette in chart_extensions.js are set. Legible on both light and dark backgrounds.
const DEFAULT_PALETTE = [
  "#3b82f6",
  "#22c55e",
  "#f59e0b",
  "#ef4444",
  "#8b5cf6",
  "#14b8a6",
  "#ec4899",
  "#64748b",
];

// Only these factories are reachable from the server. A whitelist, not `import *` + lookup: the
// option is data, and data must never be able to name an arbitrary export to call.
const MARKS = {
  areaX,
  areaY,
  arrow,
  bandX,
  bandY,
  barX,
  barY,
  boxX,
  boxY,
  cell,
  differenceX,
  differenceY,
  dot,
  hexagon,
  lineX,
  lineY,
  link,
  rect,
  ruleX,
  ruleY,
  text,
  tickX,
  tickY,
  vector,
  waffleX,
  waffleY,
};

// Marks that take only options (no data argument).
const DATALESS_MARKS = { crosshair, frame };

const POLAR_MARKS = {
  radialArc,
  radialArea,
  radialBarAngle,
  radialBarRadius,
  radialDot,
  radialLine,
  radialRule,
  radialText,
};

const POLAR_GUIDES = { angleGrid, radialGrid };

const CURVES = {
  basis: curveBasis,
  bumpX: curveBumpX,
  bumpY: curveBumpY,
  cardinal: curveCardinal,
  cardinalClosed: curveCardinalClosed,
  catmullRom: curveCatmullRom,
  catmullRomClosed: curveCatmullRomClosed,
  linear: curveLinear,
  linearClosed: curveLinearClosed,
  monotone: curveMonotoneX,
  monotoneX: curveMonotoneX,
  monotoneY: curveMonotoneY,
  natural: curveNatural,
  step: curveStep,
  stepAfter: curveStepAfter,
  stepBefore: curveStepBefore,
};

// Positional scales. The compact TanStack scales cover the common cases; d3-scale covers time,
// log, power and friends. A function of `spec` so band/point padding etc. apply before domain
// inference, exactly as the TanStack docs recommend (`() => scaleBand().padding(0.2)`).
const SCALES = {
  linear: () => scaleLinear(),
  band: (s) => bandLike(scaleBand(), s),
  point: (s) => bandLike(scalePoint(), s),
  ordinal: () => scaleOrdinal(),
  time: () => scaleTime(),
  utc: () => scaleUtc(),
  log: (s) => (s.base != null ? scaleLog().base(s.base) : scaleLog()),
  pow: (s) => (s.exponent != null ? scalePow().exponent(s.exponent) : scalePow()),
  sqrt: () => scaleSqrt(),
  symlog: (s) => (s.constant != null ? scaleSymlog().constant(s.constant) : scaleSymlog()),
};

// Color scales. Omit `scale` for the built-in categorical palette; name one for continuous or
// stepped color (heatmaps, choropleths). d3's linear scale interpolates color strings.
const COLOR_SCALES = {
  ordinal: () => scaleOrdinal(),
  linear: () => d3ScaleLinear(),
  sqrt: () => scaleSqrt(),
  log: () => scaleLog(),
  quantize: () => scaleQuantize(),
  quantile: () => scaleQuantile(),
  threshold: () => scaleThreshold(),
};

const TEMPORAL = new Set(["time", "utc"]);

// Spec keys this file consumes; never forwarded to TanStack.
const SCALE_KEYS = [
  "scale",
  "domain",
  "padding",
  "paddingInner",
  "paddingOuter",
  "align",
  "round",
  "base",
  "exponent",
  "constant",
];

const POLAR_LENGTHS = ["innerRadius", "outerRadius", "cornerRadius", "padRadius"];

// ---- pure helpers -------------------------------------------------------------------------------

// The series palette as CSS: `var(--chart-N, <fallback>)`. Unlike the canvas engines, the SVG
// TanStack renders resolves var() itself, so the palette follows a theme toggle with no redraw.
// Fallbacks: the developer palette, else the built-in one.
export function resolvePalette(_el) {
  const fallback =
    Array.isArray(userConfig?.palette) && userConfig.palette.length
      ? userConfig.palette
      : DEFAULT_PALETTE;
  return fallback.map((color, i) => (i < 8 ? `var(--chart-${i + 1}, ${color})` : color));
}

// Axis / grid / label colors, as CSS too: a --chart-* property defined only under a dark theme
// still applies the moment the theme flips. `currentColor` is TanStack's own default, so an app
// that defines none of them inherits its text color in light and dark mode.
function resolveTheme(el, spec) {
  return {
    foreground: "var(--chart-text, currentColor)",
    muted: "var(--chart-axis, var(--chart-text, currentColor))",
    grid: "var(--chart-grid, currentColor)",
    background: "transparent",
    palette: resolvePalette(el),
    ...(spec || {}),
  };
}

// A JSON option string may be malformed if the server built it wrong; treat that as an empty chart
// rather than throwing, so one bad chart cannot break the whole page.
export function safeParse(raw) {
  if (raw == null || raw === "") return {};
  try {
    return JSON.parse(raw);
  } catch (_e) {
    return {};
  }
}

// "chelekom:currency:USD" etc. -> a real function. A function cannot cross the LiveView wire, so the
// server sends a string and we swap the function in here. Extend via chart_extensions.js. Returns
// null for anything that is not a known formatter sentinel (e.g. "chelekom:fade", handled elsewhere).
export function intlFormatter(token) {
  const [ns, kind, arg] = token.split(":");
  if (ns !== "chelekom") return null;

  const custom = userConfig?.formatters?.[kind];
  if (typeof custom === "function") return (v) => custom(v, arg);

  switch (kind) {
    case "number":
      return (v) => new Intl.NumberFormat().format(v);
    case "compact":
      return (v) => new Intl.NumberFormat(undefined, { notation: "compact" }).format(v);
    case "percent":
      return (v) =>
        new Intl.NumberFormat(undefined, { style: "percent", maximumFractionDigits: 1 }).format(v);
    case "currency":
      return (v) =>
        new Intl.NumberFormat(undefined, { style: "currency", currency: arg || "USD" }).format(v);
    default:
      return null;
  }
}

function isSentinel(value) {
  return typeof value === "string" && value.startsWith("chelekom:") && value !== FADE;
}

// Walk a plain options subtree and replace formatter sentinels with real functions. TanStack's
// value formatters (axis ticks, legend labels, polar grid labels) all take the value first, which
// is exactly the shape intlFormatter returns. `data` is never walked: it is the user's rows.
function resolveSentinels(node) {
  if (Array.isArray(node)) return node.map(resolveSentinels);
  if (node && typeof node === "object") {
    const out = {};
    for (const [k, v] of Object.entries(node)) out[k] = k === "data" ? v : resolveSentinels(v);
    return out;
  }
  if (isSentinel(node)) return intlFormatter(node) || node;
  return node;
}

function omit(object, keys) {
  const out = {};
  for (const [k, v] of Object.entries(object || {})) if (!keys.includes(k)) out[k] = v;
  return out;
}

function bandLike(scale, s) {
  if (s.padding != null) scale.padding(s.padding);
  if (s.paddingInner != null && scale.paddingInner) scale.paddingInner(s.paddingInner);
  if (s.paddingOuter != null && scale.paddingOuter) scale.paddingOuter(s.paddingOuter);
  if (s.align != null) scale.align(s.align);
  if (s.round != null) scale.round(s.round);
  return scale;
}

function isPaint(value) {
  return typeof value === "string" && /^(#|rgb|hsl|oklch|oklab|lab|lch|color|var\()/i.test(value);
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}([T ][\d:.]+(Z|[+-]\d{2}:?\d{2})?)?$/;

function toDate(value) {
  if (value instanceof Date || value == null) return value;
  if (typeof value === "string" || typeof value === "number") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? value : date;
  }
  return value;
}

// ---- scales -------------------------------------------------------------------------------------

// A named scale spec -> TanStack's ChartPositionScaleOptions. With a `domain` the scale is an
// instance (fixed, application-owned domain); without one it is a factory (domain inferred from the
// marks). `nice`, `grid`, `axis`, `reverse`, `side`, `channel`, `viewport`, `wrap`, `range` ride
// through untouched.
function buildScale(spec) {
  if (spec === null || spec === false) return null;
  if (spec === undefined) return undefined;
  const s = typeof spec === "string" ? { scale: spec } : spec;
  const name = s.scale || "linear";
  const make = SCALES[name];
  if (!make) {
    console.warn(`[chart] unknown scale "${name}", using linear`);
    return buildScale({ ...s, scale: "linear" });
  }

  const rest = resolveSentinels(omit(s, SCALE_KEYS));
  if (Array.isArray(s.domain)) {
    const domain = TEMPORAL.has(name) ? s.domain.map(toDate) : s.domain;
    return { ...rest, scale: make(s).domain(domain) };
  }
  return { ...rest, scale: () => make(s) };
}

function scaleKind(spec) {
  if (spec == null || spec === false) return null;
  return typeof spec === "string" ? spec : spec.scale || "linear";
}

// Collect the raw values a set of marks feeds into one positional axis, for inference.
function channelValues(marks, axis) {
  const values = [];
  for (const m of marks) {
    if (!m || m.mark === "polar" || !Array.isArray(m.data)) continue;
    if ((m[`${axis}Scale`] || axis) !== axis) continue;
    const field = m[axis] ?? m[`${axis}1`];
    if (typeof field === "string") {
      for (const row of m.data) if (row && row[field] != null) values.push(row[field]);
    } else if (field == null && m.mark === (axis === "x" ? "ruleX" : "ruleY")) {
      for (const v of m.data) if (typeof v !== "object") values.push(v);
    }
  }
  return values;
}

// The scale TanStack requires but the option left out. A bar's categorical axis is a band; other
// categories are points (lines and dots sit ON the category, not in a band); ISO dates are utc;
// numbers are linear. Everything polar-only needs no Cartesian scales at all.
function inferScale(marks, axis) {
  const cartesian = marks.filter((m) => m && m.mark !== "polar");
  if (cartesian.length === 0) return null;

  const values = channelValues(cartesian, axis);
  if (values.length === 0) {
    // No field to look at (e.g. `lineY([3, 1, 4])` plots against the index): linear, unless no
    // mark positions on this axis at all — a lone ruleY needs no x — or only decorations do.
    const other = axis === "x" ? "ruleY" : "ruleX";
    const needed = cartesian.some((m) => ![other, "frame", "crosshair"].includes(m.mark));
    return needed ? { scale: "linear", nice: true } : null;
  }
  if (values.every((v) => typeof v === "number")) {
    return { scale: "linear", nice: true, ...(axis === "y" ? { grid: true } : {}) };
  }
  if (values.every((v) => typeof v === "string" && ISO_DATE.test(v))) return { scale: "utc" };

  const categoricalBar = cartesian.some((m) => m.mark === (axis === "x" ? "barY" : "barX"));
  return categoricalBar ? { scale: "band", padding: 0.2 } : { scale: "point", padding: 0.4 };
}

// ---- marks --------------------------------------------------------------------------------------

function buildLayout(layout) {
  if (!layout || typeof layout === "function") return layout;
  const spec = typeof layout === "string" ? { type: layout } : layout;
  const opts = omit(spec, ["type"]);
  if (spec.type === "stack") return stack(opts);
  if (spec.type === "group") return group(opts);
  return layout;
}

// A polar length as a share of the resolved radius: "58%" -> ({radius}) => radius * 0.58. The
// native form is a pixel number or a function; the percentage is the portable, JSON-safe one.
function polarLength(value) {
  if (typeof value === "string" && value.trim().endsWith("%")) {
    const ratio = parseFloat(value) / 100;
    if (Number.isFinite(ratio)) return ({ radius }) => radius * ratio;
  }
  return value;
}

// Parse the temporal channels of one mark into Dates, so a `%{date: "2026-01-01"}` row works on a
// "utc"/"time" axis without the server having to know JavaScript has a Date type.
function parseTemporal(data, opts, temporalScales) {
  if (!Array.isArray(data) || temporalScales.size === 0) return data;
  const fields = [];
  for (const axis of ["x", "y"]) {
    if (!temporalScales.has(opts[`${axis}Scale`] || axis)) continue;
    for (const channel of [axis, `${axis}1`, `${axis}2`]) {
      if (typeof opts[channel] === "string") fields.push(opts[channel]);
    }
  }
  if (fields.length === 0) return data;
  return data.map((row) => {
    if (!row || typeof row !== "object") return toDate(row);
    const out = { ...row };
    for (const f of fields) out[f] = toDate(out[f]);
    return out;
  });
}

// A value formatter applied to a text mark's `text` channel: %{mark: "text", text: "sales",
// format: "chelekom:compact"}. `format` is ours; TanStack's text mark has no such option.
function formattedText(opts, format) {
  const fn = isSentinel(format) && intlFormatter(format);
  if (!fn) return opts;
  const channel = opts.text;
  if (typeof channel === "string") return { ...opts, text: (d) => fn(d?.[channel]) };
  if (channel == null) return { ...opts, text: (d) => fn(d) };
  return opts;
}

class Builder {
  constructor(el, temporalScales) {
    this.el = el;
    this.temporalScales = temporalScales;
    this.gradients = [];
    this.fades = 0;
  }

  // "chelekom:fade" as an area fill -> a top-to-transparent gradient of the series color. The
  // color is the mark's own `stroke` if it is a literal paint, else the mark's slot in the palette.
  fade(opts, index) {
    const palette = resolvePalette(this.el);
    const base = isPaint(opts.stroke) ? opts.stroke : palette[index % palette.length];
    // Local to this chart: the host's `idPrefix` scopes both the gradient and the url(#…) to it.
    const id = `chelekom-fade-${this.fades++}`;
    this.gradients.push({
      id,
      y1: 0,
      y2: 1,
      stops: [
        { offset: 0, color: base, opacity: 0.38 },
        { offset: 1, color: base, opacity: 0 },
      ],
    });
    return `url(#${id})`;
  }

  mark(spec, index, polarContext = false) {
    if (!spec || typeof spec !== "object") return null;
    const name = spec.mark;

    if (name === "polar") return this.polar(spec);

    if (DATALESS_MARKS[name]) return DATALESS_MARKS[name](resolveSentinels(omit(spec, ["mark"])));

    const factory = polarContext ? POLAR_MARKS[name] : MARKS[name];
    if (!factory) {
      const where = polarContext ? "inside polar" : "at the top level";
      console.warn(`[chart] unknown mark "${name}" ${where}; skipped`);
      return null;
    }

    const opts = formattedText(
      resolveSentinels(omit(spec, ["mark", "data", "pie", "format"])),
      spec.format,
    );

    if (opts.layout) opts.layout = buildLayout(opts.layout);
    if (typeof opts.curve === "string") {
      const curve = CURVES[opts.curve];
      if (curve) opts.curve = polarContext ? curve : d3Curve(curve);
      else delete opts.curve;
    }
    if (polarContext) for (const k of POLAR_LENGTHS) if (k in opts) opts[k] = polarLength(opts[k]);
    if (opts.fill === FADE) opts.fill = this.fade(spec, index);

    let data = Array.isArray(spec.data) ? spec.data : [];
    if (spec.pie) data = pie(data, spec.pie);
    if (!polarContext) data = parseTemporal(data, opts, this.temporalScales);

    return factory(data, opts);
  }

  polar(spec) {
    const marks = (spec.marks || []).map((m, i) => this.mark(m, i, true)).filter(Boolean);
    const guides = (spec.guides || [])
      .map((g) => {
        const make = g && POLAR_GUIDES[g.guide];
        if (!make) console.warn(`[chart] unknown polar guide "${g && g.guide}"; skipped`);
        return make ? make(resolveSentinels(omit(g, ["guide"]))) : null;
      })
      .filter(Boolean);

    const scales = { angle: null, radius: null };
    for (const [id, s] of Object.entries(spec.scales || {})) {
      const built = buildScale(s);
      if (built && Array.isArray(built.range)) built.range = built.range.map(polarLength);
      scales[id] = built ?? null;
    }

    const rest = resolveSentinels(omit(spec, ["mark", "marks", "guides", "scales"]));
    return polar({ ...rest, marks, guides, scales });
  }
}

// ---- the whole option ---------------------------------------------------------------------------

function buildColor(spec) {
  if (!spec) return undefined;
  const out = resolveSentinels(omit(spec, ["scale", "legend"]));
  if (typeof spec.scale === "string") {
    const make = COLOR_SCALES[spec.scale];
    if (make) out.scale = make;
  }
  if (spec.legend) {
    const l = spec.legend === true ? {} : resolveSentinels(spec.legend);
    const { gradient, items, ...legend } = l;
    out.legend = gradient
      ? colorGradientLegend(legend)
      : colorLegend({ ...legend, ...(items ? { items: colorLegendItems(items) } : {}) });
  }
  return out;
}

// Tooltip items keep TanStack's shape; a sentinel `text` becomes a function of the item's own
// value: %{channel: "y", label: "Revenue", text: "chelekom:currency:USD"}.
function buildTooltipItem(item) {
  if (!item || typeof item !== "object" || !isSentinel(item.text)) return item;
  const fn = intlFormatter(item.text);
  if (!fn) return omit(item, ["text"]);
  let pick;
  if (item.field) pick = (p) => p.datum?.[item.field];
  else if (item.channel === "x") pick = (p) => p.xValue;
  else if (item.channel === "group") pick = (p) => p.groupLabel;
  else pick = (p) => p.yValue;
  return { ...item, text: (point) => fn(pick(point)) };
}

// Without explicit items TanStack titles each row with the axis label, or the bare channel name
// ("x", "y") when the axis has none. Name the rows after the first mark's fields instead, so
// `tooltip: true` reads "month  Jun / revenue  1,330" rather than "x  Jun / y  1,330". A field
// behind `color` gets its own row too — for a heatmap it IS the value — except under grouped
// focus, where each series is already a row of its own.
function defaultTooltipItems(marks, scales, focus) {
  const polarMark = marks.find((m) => m && m.mark === "polar");
  if (polarMark) return defaultPolarItems(polarMark.marks || []);

  const first = marks.find((m) => m && typeof m.x === "string" && typeof m.y === "string");
  if (!first) return undefined;
  const label = (axis) => {
    const title = scales?.[axis]?.axis?.label;
    return (typeof title === "object" ? title?.text : title) ?? first[axis];
  };
  const items = [
    { channel: "x", label: label("x") },
    { channel: "y", label: label("y") },
  ];
  const color = first.color;
  const grouped = typeof focus === "string" && focus.startsWith("group");
  if (typeof color === "string" && color !== first.x && color !== first.y && !grouped) {
    items.push({ field: color, label: color });
  }
  return items;
}

// A polar point's x/y are an angle in radians and a radius in pixels — true, but useless to a
// reader. A pie slice reads as "category, value, share"; a radar vertex as its angle/radius fields.
function defaultPolarItems(marks) {
  const slices = marks.find((m) => m && m.pie && typeof m.pie.value === "string");
  if (slices) {
    const name = [slices.color, slices.key, slices.z].find((f) => typeof f === "string");
    const share = intlFormatter("chelekom:percent");
    return [
      ...(name ? [{ field: name, label: name }] : []),
      { field: slices.pie.value, label: slices.pie.value },
      { id: "share", label: "share", text: (p) => share(p.datum?.fraction) },
    ];
  }

  const radial = marks.find(
    (m) => m && typeof m.angle === "string" && typeof m.radius === "string",
  );
  if (!radial) return undefined;
  return [
    { field: radial.angle, label: radial.angle },
    { field: radial.radius, label: radial.radius },
  ];
}

// The surface clips its overflow (so a chart never forces a page scrollbar), which would also clip
// a tooltip near an edge. TanStack's portal lifts the tooltip into the browser top layer while it
// stays a DOM descendant of the chart, so it escapes the clip and keeps inheriting chart CSS. On by
// default; `portal: false` keeps it inside the box, a map passes portal options through.
function buildPortal(spec) {
  if (spec === false) return undefined;
  if (spec && typeof spec === "object") return { ...spec, use: portal };
  return portal;
}

function buildTooltip(spec, marks, scales, focus) {
  if (!spec) return undefined;
  const s = spec === true ? {} : spec;
  const out = resolveSentinels(omit(s, ["items", "portal"]));
  const items = Array.isArray(s.items) ? s.items : defaultTooltipItems(marks, scales, focus);
  if (items) out.items = items.map(buildTooltipItem);
  const lifted = buildPortal(s.portal);
  if (lifted) out.portal = lifted;
  return { ...out, use: tooltip };
}

const OPTION_KEYS = ["marks", "scales", "color", "theme", "tooltip", "gradients"];

export function buildDefinition(el, option) {
  const specMarks = Array.isArray(option.marks) ? option.marks : [];
  const scaleSpecs = { ...(option.scales || {}) };
  for (const axis of ["x", "y"]) {
    if (!(axis in scaleSpecs)) scaleSpecs[axis] = inferScale(specMarks, axis);
  }

  const temporal = new Set(
    Object.entries(scaleSpecs)
      .filter(([, s]) => TEMPORAL.has(scaleKind(s)))
      .map(([id]) => id),
  );

  const builder = new Builder(el, temporal);
  const marks = specMarks.map((m, i) => builder.mark(m, i)).filter(Boolean);

  const scales = {};
  for (const [id, s] of Object.entries(scaleSpecs)) scales[id] = buildScale(s) ?? null;

  const defaults = {};
  const animate = userConfig?.tanstack?.animate;
  if (animate !== false && option.svgAnimation === undefined) defaults.svgAnimation = true;

  const definition = {
    ...defaults,
    ...resolveSentinels(omit(option, OPTION_KEYS)),
    marks,
    scales,
    theme: resolveTheme(el, option.theme),
  };

  const gradients = [...(option.gradients || []), ...builder.gradients];
  if (gradients.length) definition.gradients = gradients;

  const color = buildColor(option.color);
  if (color) definition.color = color;

  const tip = buildTooltip(
    option.tooltip ?? userConfig?.tanstack?.tooltip,
    specMarks,
    option.scales,
    option.focus,
  );
  if (tip) definition.tooltip = tip;

  return defineChart(definition);
}

const EMPTY = () => defineChart({ marks: [], scales: { x: null, y: null } });

function clickPayload(point) {
  return {
    key: point.key,
    markId: point.markId,
    group: point.group,
    datumIndex: point.datumIndex,
    x: point.xValue,
    y: point.yValue,
    datum: point.datum,
  };
}

// ---- hook ---------------------------------------------------------------------------------------

const Chart = {
  mounted() {
    const el = this.el;
    this.rootId = el.getAttribute("data-root-id");
    this.onClick = el.getAttribute("data-on-click");
    this.domOption = el.getAttribute("data-option");
    this.raw = this.domOption;

    // TanStack's SVG is itself the accessible, keyboard-navigable chart (role, name, focusable
    // points). Left on the surface, role="img" would make that interactive content presentational
    // to a screen reader — so the name moves onto the SVG and the wrapper steps aside. Safe on an
    // ignored element: LiveView never patches its non-data attributes back.
    this.ariaLabel = el.getAttribute("aria-label") || "Chart";
    el.removeAttribute("role");
    el.removeAttribute("aria-label");

    try {
      this.host = mountChart(el, this.hostOptions(this.raw));
    } catch (error) {
      this.fail(error);
      this.host = mountChart(el, { ...this.hostOptions(null), definition: EMPTY() });
    }

    this.ref = this.handleEvent("chelekom:chart", (payload) => {
      if (!payload || (payload.id && payload.id !== this.rootId)) return;
      if (payload.option != null) {
        this.raw = payload.option;
        this.render();
      }
      // The host measures its own container (ResizeObserver); a forced resize is a re-render.
      else if (payload.resize) this.render();
    });
  },

  // Only data-* survive on an ignored element, so a server re-assign of `option` lands on
  // data-option. Re-apply only when it actually changed, so unrelated patches do not thrash.
  updated() {
    const next = this.el.getAttribute("data-option");
    if (next !== this.domOption) {
      this.domOption = next;
      this.raw = next;
      this.render();
    }
  },

  destroyed() {
    if (this.ref) this.removeHandleEvent(this.ref);
    // destroy() disconnects TanStack's resize/font listeners, cancels animation frames and removes
    // its tooltip; without it they outlive every LiveView navigation.
    if (this.host) this.host.destroy();
    this.host = null;
  },

  // A spec TanStack rejects (while building it, or while compiling its scene) renders an empty
  // chart and logs, instead of taking the page down.
  render() {
    if (!this.host) return;
    try {
      this.host.update(this.hostOptions(this.raw));
    } catch (error) {
      this.fail(error);
      this.host.update({ ...this.hostOptions(null), definition: EMPTY() });
    }
  },

  fail(error) {
    console.error(`[chart] #${this.rootId}: invalid TanStack option`, error);
  },

  // Parse (if a string) and build a fresh definition; its identity is TanStack's update boundary.
  hostOptions(raw) {
    const option = typeof raw === "string" ? safeParse(raw) : raw || {};
    const definition = buildDefinition(this.el, option);

    const options = { definition, ariaLabel: this.ariaLabel, idPrefix: this.rootId };
    if (this.onClick) {
      options.onSelect = (point) => {
        if (point) this.pushEventTo(this.el, this.onClick, clickPayload(point));
      };
    }
    return options;
  },
};

export default Chart;
