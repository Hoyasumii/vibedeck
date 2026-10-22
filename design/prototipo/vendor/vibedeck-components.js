/* @ds-bundle: {"format":4,"namespace":"VibeDeck","components":[{"name":"Logo"},{"name":"Button"},{"name":"SegmentedControl"},{"name":"FilterChip"},{"name":"TypeBadge"},{"name":"AuthorTag"},{"name":"SidebarItem"},{"name":"SidebarSection"},{"name":"TreeFolder"},{"name":"UsageMeter"},{"name":"Tab"},{"name":"ReviewItem"},{"name":"Composer"},{"name":"InspectorGroup"},{"name":"RecentProject"},{"name":"SeverityBadge"},{"name":"TestChip"},{"name":"RuleRow"},{"name":"StatusPill"},{"name":"StepCard"},{"name":"NextStepRow"},{"name":"ChatBubble"},{"name":"ActionCard"},{"name":"StackCard"},{"name":"PatternCard"},{"name":"Icon"}]} */
(function () {
  var React = window.React;
  var h = React.createElement;

  function cx() {
    var out = [];
    for (var i = 0; i < arguments.length; i++) if (arguments[i]) out.push(arguments[i]);
    return out.join(" ");
  }

  /* Icons: 16px grid, 1.6 stroke, round caps — drawn for VibeDeck. */
  var ICONS = {
    fix: [["path", { d: "M10.6 2.6a3 3 0 0 0-3 3.9L2.9 11.2a1.4 1.4 0 0 0 2 2l4.7-4.7a3 3 0 0 0 3.8-3l-1.9 1.9-1.8-.4-.4-1.8z" }]],
    change: [["path", { d: "M10.8 2.7l2.5 2.5-7.6 7.6-3.1.6.6-3.1z" }], ["path", { d: "M9.3 4.2l2.5 2.5" }]],
    remove: [["path", { d: "M2.8 4.5h10.4" }], ["path", { d: "M6.3 4.5V2.8h3.4v1.7" }], ["path", { d: "M4.3 4.5l.7 8.7h6l.7-8.7" }]],
    disable: [["circle", { cx: 8, cy: 8, r: 5.6 }], ["path", { d: "M4.1 4.1l7.8 7.8" }]],
    hide: [["path", { d: "M1.8 8s2.3-4.2 6.2-4.2S14.2 8 14.2 8 11.9 12.2 8 12.2 1.8 8 1.8 8z" }], ["circle", { cx: 8, cy: 8, r: 1.8 }], ["path", { d: "M2.6 13.4L13.4 2.6" }]],
    note: [["path", { d: "M3 3.5h10v7H7.2L4 13v-2.5H3z" }]],
    folder: [["path", { d: "M2 4.6A1.6 1.6 0 0 1 3.6 3h2.9l1.6 1.6h4.3A1.6 1.6 0 0 1 14 6.2v5.2a1.6 1.6 0 0 1-1.6 1.6H3.6A1.6 1.6 0 0 1 2 11.4z" }]],
    link: [["path", { d: "M6.9 9.1a2.6 2.6 0 0 0 3.7 0l2-2a2.6 2.6 0 0 0-3.7-3.7l-.6.6" }], ["path", { d: "M9.1 6.9a2.6 2.6 0 0 0-3.7 0l-2 2a2.6 2.6 0 0 0 3.7 3.7l.6-.6" }]],
    review: [["circle", { cx: 3.6, cy: 4.6, r: 1.6 }], ["circle", { cx: 3.6, cy: 11.4, r: 1.6 }], ["path", { d: "M7 4.6h6.4" }], ["path", { d: "M7 11.4h6.4" }]],
    doc: [["path", { d: "M4 2.5h5l3 3v8H4z" }], ["path", { d: "M9 2.5v3h3" }], ["path", { d: "M6 9h4" }], ["path", { d: "M6 11.3h4" }]],
    all: [["rect", { x: 2.6, y: 2.6, width: 4.2, height: 4.2, rx: 1 }], ["rect", { x: 9.2, y: 2.6, width: 4.2, height: 4.2, rx: 1 }], ["rect", { x: 2.6, y: 9.2, width: 4.2, height: 4.2, rx: 1 }], ["rect", { x: 9.2, y: 9.2, width: 4.2, height: 4.2, rx: 1 }]],
    plus: [["path", { d: "M8 3v10" }], ["path", { d: "M3 8h10" }]],
    minus: [["path", { d: "M4 8h8" }]],
    check: [["path", { d: "M3.5 8.4l2.9 2.9 6.1-6.6" }]],
    close: [["path", { d: "M4.5 4.5l7 7" }], ["path", { d: "M11.5 4.5l-7 7" }]],
    updown: [["path", { d: "M5.4 6.2L8 3.6l2.6 2.6" }], ["path", { d: "M5.4 9.8L8 12.4l2.6-2.6" }]],
    chevron: [["path", { d: "M6 4l4 4-4 4" }]],
    arrow: [["path", { d: "M3 8h10" }], ["path", { d: "M9.5 4.5L13 8l-3.5 3.5" }]],
    send: [["path", { d: "M8 13V3.5" }], ["path", { d: "M4 7.5l4-4 4 4" }]],
    more: [["circle", { cx: 3.8, cy: 8, r: .9 }], ["circle", { cx: 8, cy: 8, r: .9 }], ["circle", { cx: 12.2, cy: 8, r: .9 }]],
    search: [["circle", { cx: 7, cy: 7, r: 4.2 }], ["path", { d: "M10.2 10.2l3.3 3.3" }]],
    play: [["path", { d: "M5 3.4v9.2l7.4-4.6z" }]],
    stop: [["rect", { x: 4, y: 4, width: 8, height: 8, rx: 1.4 }]],
    attach: [["path", { d: "M10.6 5.6L6.2 10a1.4 1.4 0 0 0 2 2l4.9-4.9a2.8 2.8 0 0 0-4-4L4.2 8a4.2 4.2 0 0 0 6 6l3.3-3.3" }]],
    copy: [["rect", { x: 5.2, y: 5.2, width: 8, height: 8, rx: 1.5 }], ["path", { d: "M3 10.6V4a1 1 0 0 1 1-1h6.6" }]],
    tag: [["path", { d: "M2.5 2.5h5l6 6-5 5-6-6z" }], ["circle", { cx: 5.4, cy: 5.4, r: .9 }]],
    clock: [["circle", { cx: 8, cy: 8, r: 5.8 }], ["path", { d: "M8 5v3.2l2 1.3" }]],
    warn: [["path", { d: "M8 2.5l6 10.5H2z" }], ["path", { d: "M8 6.6v3" }], ["path", { d: "M8 11.5v.1" }]],
    help: [["circle", { cx: 8, cy: 8, r: 5.8 }], ["path", { d: "M6.4 6.4a1.7 1.7 0 1 1 2.4 1.6c-.5.3-.8.6-.8 1.2" }], ["path", { d: "M8 11.2v.1" }]],
    archive: [["rect", { x: 2.5, y: 3, width: 11, height: 3, rx: 1 }], ["path", { d: "M3.5 6v6.5h9V6" }], ["path", { d: "M6.5 8.6h3" }]],
    seal: [["circle", { cx: 8, cy: 8, r: 5.8 }], ["path", { d: "M5.5 8.2l1.8 1.8 3.2-3.5" }]],
    inspector: [["rect", { x: 2, y: 3, width: 12, height: 10, rx: 2 }], ["path", { d: "M10 3v10" }]],
    kit: [["path", { d: "M2.5 5L8 2.5 13.5 5v6L8 13.5 2.5 11z" }], ["path", { d: "M2.5 5L8 7.5 13.5 5" }], ["path", { d: "M8 7.5v6" }]],
    flow: [["path", { d: "M2.5 4.2h7a2.9 2.9 0 0 1 0 5.8H5.8" }], ["path", { d: "M7.8 8l-2 2 2 2" }]],
    /* sidebar */
    stack: [["path", { d: "M8 2.5l5.5 2.8L8 8.1 2.5 5.3z" }], ["path", { d: "M2.5 8l5.5 2.8L13.5 8" }], ["path", { d: "M2.5 10.7l5.5 2.8 5.5-2.8" }]],
    pattern: [["path", { d: "M2.5 5.5L8 2.5l5.5 3z" }], ["path", { d: "M4.2 7.4v4.6" }], ["path", { d: "M8 7.4v4.6" }], ["path", { d: "M11.8 7.4v4.6" }], ["path", { d: "M2.5 13.5h11" }]],
    claude: [["rect", { x: 2.8, y: 5.2, width: 8, height: 8, rx: 1.5 }], ["path", { d: "M5.6 2.8h6.1a1.5 1.5 0 0 1 1.5 1.5v6.1" }]],
    graph: [["circle", { cx: 4, cy: 4.2, r: 1.7 }], ["circle", { cx: 12, cy: 6, r: 1.7 }], ["circle", { cx: 6, cy: 12, r: 1.7 }], ["path", { d: "M5.6 4.6l4.7 1" }], ["path", { d: "M4.4 5.9l1.2 4.4" }], ["path", { d: "M10.7 7.2l-3.5 3.6" }]],
    terminal: [["rect", { x: 2, y: 3, width: 12, height: 10, rx: 2 }], ["path", { d: "M5 6.6l2 1.6-2 1.6" }], ["path", { d: "M8.6 10.4h2.8" }]],
    rule: [["path", { d: "M8 2l5 1.8v4c0 3-2.2 5.2-5 6.2-2.8-1-5-3.2-5-6.2v-4z" }], ["path", { d: "M5.8 8.1l1.6 1.6 3-3.2" }]],
    must: [["path", { d: "M8 2l5 1.8v4c0 3-2.2 5.2-5 6.2-2.8-1-5-3.2-5-6.2v-4z" }], ["path", { d: "M8 5.2v3.3" }], ["path", { d: "M8 10.7v.1" }]],
    should: [["path", { d: "M8 2l5 1.8v4c0 3-2.2 5.2-5 6.2-2.8-1-5-3.2-5-6.2v-4z" }]],
    scope: [["circle", { cx: 8, cy: 8, r: 5 }], ["circle", { cx: 8, cy: 8, r: 1.8 }], ["path", { d: "M8 1.5v1.8" }], ["path", { d: "M8 12.7v1.8" }], ["path", { d: "M1.5 8h1.8" }], ["path", { d: "M12.7 8h1.8" }]],
    globe: [["circle", { cx: 8, cy: 8, r: 5.8 }], ["path", { d: "M2.2 8h11.6" }], ["path", { d: "M8 2.2c1.8 1.6 2.6 3.6 2.6 5.8S9.8 12.2 8 13.8C6.2 12.2 5.4 10.2 5.4 8S6.2 3.8 8 2.2z" }]],
    idea: [["path", { d: "M5.6 10.4a4 4 0 1 1 4.8 0v1.1H5.6z" }], ["path", { d: "M6.2 13.6h3.6" }]],
    agent: [["rect", { x: 2, y: 2.5, width: 12, height: 11, rx: 2 }], ["circle", { cx: 8, cy: 6.8, r: 1.8 }], ["path", { d: "M5 11.5a3 3 0 0 1 6 0" }]],
    command: [["path", { d: "M6 6H4.6A1.6 1.6 0 1 1 6 4.6v6.8A1.6 1.6 0 1 1 4.6 10h6.8A1.6 1.6 0 1 1 10 11.4V4.6A1.6 1.6 0 1 1 11.4 6z" }]],
    skill: [["path", { d: "M2.8 13.2l7.6-7.6" }], ["path", { d: "M12 2v2.6" }], ["path", { d: "M10.7 3.3h2.6" }], ["path", { d: "M13.4 7.2v1.6" }], ["path", { d: "M12.6 8h1.6" }]],
    workflow: [["rect", { x: 2, y: 2.5, width: 4, height: 4, rx: 1 }], ["rect", { x: 10, y: 2.5, width: 4, height: 4, rx: 1 }], ["rect", { x: 6, y: 9.5, width: 4, height: 4, rx: 1 }], ["path", { d: "M6 4.5h4" }], ["path", { d: "M4 6.5v2A1.5 1.5 0 0 0 5.5 10H6" }], ["path", { d: "M12 6.5v2A1.5 1.5 0 0 1 10.5 10H10" }]],
    script: [["circle", { cx: 8, cy: 8, r: 2.2 }], ["path", { d: "M8 2v1.8" }], ["path", { d: "M8 12.2V14" }], ["path", { d: "M2 8h1.8" }], ["path", { d: "M12.2 8H14" }], ["path", { d: "M3.8 3.8l1.3 1.3" }], ["path", { d: "M10.9 10.9l1.3 1.3" }], ["path", { d: "M3.8 12.2l1.3-1.3" }], ["path", { d: "M10.9 5.1l1.3-1.3" }]],
    manual: [["path", { d: "M5.6 8.4V4.2a1 1 0 0 1 2 0v3.4" }], ["path", { d: "M7.6 7V3.2a1 1 0 0 1 2 0V7" }], ["path", { d: "M9.6 7V4.4a1 1 0 0 1 2 0v4.9a4.3 4.3 0 0 1-4.3 4.3h-.5a3.4 3.4 0 0 1-2.9-1.6L2.4 9.6a1 1 0 0 1 1.7-1l1.5 1.6" }]],
    ai: [["path", { d: "M8 2.2l1.4 3.9 3.9 1.4-3.9 1.4L8 12.8 6.6 8.9 2.7 7.5l3.9-1.4z" }]],
    human: [["circle", { cx: 8, cy: 5.4, r: 2.6 }], ["path", { d: "M3.2 13.6a4.8 4.8 0 0 1 9.6 0" }]]
  };

  function Icon(props) {
    var name = props.name, size = props.size || 16;
    var parts = ICONS[name] || [];
    return h("svg", {
      className: cx("vd-icon", props.className), width: size, height: size, viewBox: "0 0 16 16",
      fill: "none", stroke: "currentColor", strokeWidth: 1.6, strokeLinecap: "round", strokeLinejoin: "round",
      "aria-hidden": props.label ? undefined : true, role: props.label ? "img" : undefined, "aria-label": props.label
    }, parts.map(function (p, i) { return h(p[0], Object.assign({ key: i }, p[1])); }));
  }

  /* The mark: two cards fanned into a V. Front card = human (brand), back card = AI. */
  var MARK_BACK = "M44.20 12.79 L43.74 12.63 L43.26 12.51 L42.78 12.44 L42.29 12.42 L41.80 12.45 L41.31 12.53 L40.84 12.65 L40.38 12.82 L39.93 13.04 L39.52 13.29 L39.12 13.59 L38.76 13.92 L38.44 14.29 L38.15 14.68 L37.90 15.11 L37.69 15.55 L33.62 25.64 L40.33 42.24 L40.38 42.38 L40.54 42.84 L40.62 43.13 L40.74 43.60 L40.79 43.89 L40.86 44.38 L40.89 44.67 L40.91 45.16 L40.90 45.46 L40.87 45.95 L40.84 46.24 L40.77 46.72 L40.71 47.01 L40.58 47.49 L40.50 47.77 L40.33 48.23 L40.21 48.50 L40.00 48.94 L39.86 49.20 L39.60 49.62 L39.44 49.86 L39.14 50.25 L38.95 50.48 L38.62 50.84 L38.41 51.05 L38.04 51.37 L37.81 51.56 L37.42 51.85 L37.17 52.01 L36.75 52.26 L36.49 52.39 L36.32 52.47 L36.70 52.49 L37.19 52.46 L37.67 52.38 L38.15 52.26 L38.61 52.09 L39.05 51.88 L39.47 51.62 L39.86 51.33 L40.22 50.99 L40.55 50.63 L40.84 50.23 L41.08 49.81 L41.29 49.36 L52.53 21.55 L52.69 21.08 L52.81 20.61 L52.87 20.12 L52.89 19.63 L52.86 19.14 L52.79 18.65 L52.66 18.18 L52.50 17.72 L52.28 17.28 L52.03 16.86 L51.73 16.47 L51.40 16.11 L51.03 15.78 L50.63 15.49 L50.21 15.24 L49.77 15.04 Z";
  var MARK_FRONT = "M19.80 12.79 L14.23 15.04 L13.79 15.24 L13.37 15.49 L12.97 15.78 L12.60 16.11 L12.27 16.47 L11.97 16.86 L11.72 17.28 L11.50 17.72 L11.34 18.18 L11.21 18.65 L11.14 19.14 L11.11 19.63 L11.13 20.12 L11.19 20.61 L11.31 21.08 L11.47 21.55 L22.71 49.36 L22.92 49.81 L23.16 50.23 L23.45 50.63 L23.78 50.99 L24.14 51.33 L24.53 51.62 L24.95 51.88 L25.39 52.09 L25.85 52.26 L26.33 52.38 L26.81 52.46 L27.30 52.49 L27.79 52.47 L28.28 52.40 L28.76 52.29 L29.22 52.12 L34.78 49.88 L35.23 49.67 L35.65 49.42 L36.05 49.13 L36.41 48.81 L36.75 48.45 L37.04 48.05 L37.30 47.64 L37.51 47.19 L37.68 46.73 L37.80 46.26 L37.88 45.77 L37.91 45.28 L37.89 44.79 L37.82 44.31 L37.71 43.83 L37.54 43.37 L26.31 15.55 L26.10 15.11 L25.85 14.68 L25.56 14.29 L25.24 13.92 L24.88 13.59 L24.48 13.29 L24.07 13.04 L23.62 12.82 L23.16 12.65 L22.69 12.53 L22.20 12.45 L21.71 12.42 L21.22 12.44 L20.74 12.51 L20.26 12.63 Z";

  function Logo(props) {
    var variant = props.variant || "mark", size = props.size || 32;
    var mono = props.tone === "mono";
    var mark = h("svg", { className: "vd-logo-mark", width: size, height: size, viewBox: "0 0 64 64", "aria-hidden": variant === "lockup" ? true : undefined, role: variant === "lockup" ? undefined : "img", "aria-label": variant === "lockup" ? undefined : "VibeDeck" },
      h("path", { d: MARK_BACK, className: mono ? "vd-logo-mono" : "vd-logo-ai" }),
      h("path", { d: MARK_FRONT, className: mono ? "vd-logo-mono" : "vd-logo-human" }));
    if (variant === "mark") return mark;
    return h("span", { className: "vd-logo-lockup", style: { fontSize: Math.round(size * 0.69) + "px" }, role: "img", "aria-label": "VibeDeck" }, mark, h("span", { className: "vd-logo-word", "aria-hidden": true }, "VibeDeck"));
  }

  function Button(props) {
    var variant = props.variant || "secondary", size = props.size || "md";
    var rest = Object.assign({}, props);
    delete rest.variant; delete rest.size; delete rest.icon; delete rest.className; delete rest.children;
    return h("button", Object.assign({ type: "button" }, rest, { className: cx("vd-btn", "vd-btn-" + variant, "vd-btn-" + size, props.className) }),
      props.icon ? h(Icon, { name: props.icon, size: size === "lg" ? 18 : 15 }) : null,
      props.children ? h("span", null, props.children) : null);
  }

  function SegmentedControl(props) {
    var opts = props.options || [];
    var st = React.useState(props.defaultValue || (opts[0] && opts[0].value));
    var value = props.value !== undefined ? props.value : st[0];
    return h("div", { className: "vd-seg", role: "tablist", "aria-label": props.label },
      opts.map(function (o) {
        var on = o.value === value;
        return h("button", { key: o.value, type: "button", role: "tab", "aria-selected": on, className: cx("vd-seg-item", on && "is-on"),
          onClick: function () { st[1](o.value); if (props.onChange) props.onChange(o.value); } }, o.label);
      }));
  }

  function FilterChip(props) {
    var st = React.useState(!!props.defaultSelected);
    var on = props.selected !== undefined ? props.selected : st[0];
    return h("button", { type: "button", "aria-pressed": on, className: cx("vd-chip", on && "is-on", props.tone && "vd-tone-" + props.tone),
      onClick: function () { st[1](!on); if (props.onToggle) props.onToggle(!on); } },
      props.icon ? h(Icon, { name: props.icon, size: 15 }) : null,
      h("span", null, props.label),
      props.count ? h("span", { className: "vd-chip-count" }, props.count) : null);
  }

  var TYPE_LABEL = { fix: "Corrigir", change: "Alterar", remove: "Remover", disable: "Inativar", hide: "Ocultar", note: "Nota" };

  function TypeBadge(props) {
    var t = props.type || "fix";
    return h("span", { className: cx("vd-badge", "vd-tone-" + t) }, h(Icon, { name: t, size: 13 }), h("span", null, props.label || TYPE_LABEL[t]));
  }

  function AuthorTag(props) {
    var a = props.author === "ai" ? "ai" : "human";
    return h("span", { className: cx("vd-author", "vd-author-" + a) }, h(Icon, { name: a, size: 12 }), h("span", null, props.label || (a === "ai" ? "IA" : "Humano")));
  }

  function SidebarItem(props) {
    var depth = props.depth || 0;
    return h("button", { type: "button", className: cx("vd-side", props.selected && "is-on", props.muted && "is-muted"), "aria-current": props.selected ? "page" : undefined,
      style: depth ? { paddingLeft: 12 + depth * 16 } : undefined },
      h(Icon, { name: props.icon || "review", size: 16 }),
      h("span", { className: "vd-side-label" }, props.label),
      props.count ? h("span", { className: "vd-side-count" }, props.count) : null);
  }

  function renderTreeItem(it, i, depth) {
    if (it.folder) return h(TreeFolder, Object.assign({ key: i }, it, { depth: depth }));
    return h(SidebarItem, Object.assign({ key: i }, it, { depth: depth }));
  }

  function TreeFolder(props) {
    var st = React.useState(props.defaultExpanded !== false);
    var open = st[0], depth = props.depth || 0;
    return h("div", { className: "vd-tree" },
      h("button", { type: "button", className: "vd-side vd-tree-head", "aria-expanded": open, style: { paddingLeft: 12 + depth * 16 }, onClick: function () { st[1](!open); } },
        h(Icon, { name: "chevron", size: 12, className: cx("vd-chev", open && "is-open") }),
        h(Icon, { name: "folder", size: 16 }),
        h("span", { className: "vd-side-label" }, props.label),
        props.count ? h("span", { className: "vd-side-count" }, props.count) : null),
      open ? h("div", { role: "group" }, (props.items || []).map(function (it, i) { return renderTreeItem(it, i, depth + 1); })) : null);
  }

  function SidebarSection(props) {
    var st = React.useState(props.defaultExpanded !== false);
    var open = props.expanded !== undefined ? props.expanded : st[0];
    var items = props.items || [];
    return h("section", { className: "vd-sec" },
      h("div", { className: cx("vd-sec-head", props.selected && "is-on") },
        h("button", { type: "button", className: "vd-sec-toggle", "aria-expanded": open, onClick: function () { st[1](!open); } },
          h(Icon, { name: props.icon || "doc", size: 16 }),
          h("span", { className: "vd-side-label" }, props.label),
          props.count !== undefined ? h("span", { className: "vd-side-count" }, props.count) : null,
          h(Icon, { name: "chevron", size: 12, className: cx("vd-chev", open && "is-open") })),
        h("button", { type: "button", className: "vd-sec-add", "aria-label": "Adicionar em " + props.label }, h(Icon, { name: "plus", size: 14 }))),
      open && items.length ? h("div", { className: "vd-sec-items" }, items.map(function (it, i) { return renderTreeItem(it, i, (it.depth || 0) + 1); })) : null);
  }

  function UsageMeter(props) {
    var v = Math.max(0, Math.min(1, props.value || 0)), pct = Math.round(v * 100);
    return h("div", { className: "vd-meter" },
      h("div", { className: "vd-meter-row" }, h("span", null, props.label), h("span", { className: "vd-meter-detail" }, props.detail || pct + "%")),
      h("div", { className: "vd-meter-track", role: "meter", "aria-valuemin": 0, "aria-valuemax": 100, "aria-valuenow": pct, "aria-label": props.label },
        h("div", { className: cx("vd-meter-fill", v >= 0.8 && "is-high"), style: { width: pct + "%" } })));
  }

  function Tab(props) {
    return h("div", { className: cx("vd-tab", props.selected && "is-on") },
      h("button", { type: "button", className: "vd-tab-main", "aria-current": props.selected ? "page" : undefined },
        h(Icon, { name: props.icon || "doc", size: 14 }), h("span", { className: "vd-tab-label" }, props.label)),
      h("button", { type: "button", className: "vd-tab-close", "aria-label": "Fechar aba " + props.label }, h(Icon, { name: "close", size: 12 })));
  }

  function ReviewItem(props) {
    var st = React.useState(!!props.defaultDone);
    var done = props.done !== undefined ? props.done : st[0];
    return h("div", { className: cx("vd-review", done && "is-done", props.selected && "is-selected") },
      h("button", { type: "button", className: "vd-check", role: "checkbox", "aria-checked": done, "aria-label": done ? "Reabrir" : "Concluir",
        onClick: function () { st[1](!done); if (props.onToggle) props.onToggle(!done); } }, done ? h(Icon, { name: "check", size: 12 }) : null),
      h("div", { className: "vd-review-body" },
        h("div", { className: "vd-review-title" }, props.title),
        props.where ? h("div", { className: "vd-review-where" }, props.where) : null,
        h("div", { className: "vd-review-meta" },
          h(TypeBadge, { type: props.type || "fix" }),
          props.status === "doing" ? h("span", { className: "vd-badge vd-tone-change" }, h(Icon, { name: "clock", size: 12 }), h("span", null, "Em andamento")) : null,
          props.priority === "high" ? h("span", { className: "vd-badge vd-tone-fix" }, h("span", null, "Alta")) : null,
          props.rules ? h("span", { className: "vd-badge vd-tone-neutral" }, h(Icon, { name: "rule", size: 12 }), h("span", null, props.rules === 1 ? "1 regra" : props.rules + " regras")) : null,
          props.author ? h(AuthorTag, { author: props.author }) : null)),
      props.resolve && !done ?h(Button, { variant: "quiet", icon: "ai", className: "vd-review-resolve" }, "Resolver") : null);
  }

  function Composer(props) {
    var t = props.type || "fix";
    return h("form", { className: "vd-composer", onSubmit: function (e) { e.preventDefault(); } },
      h("button", { type: "button", className: cx("vd-composer-type", "vd-tone-" + t) }, h(Icon, { name: t, size: 15 }), h("span", null, TYPE_LABEL[t]), h(Icon, { name: "updown", size: 12 })),
      h("input", { className: "vd-composer-input", placeholder: props.placeholder || "Novo ponto de revisão…", "aria-label": props.placeholder || "Novo ponto de revisão", defaultValue: props.defaultValue }),
      h("button", { type: "submit", className: "vd-composer-add", "aria-label": "Adicionar" }, h(Icon, { name: "plus", size: 15 })));
  }

  function InspectorGroup(props) {
    return h("section", { className: "vd-insp" },
      props.title ? h("h4", { className: "vd-insp-title" }, props.title) : null,
      h("dl", { className: "vd-insp-list" }, (props.rows || []).map(function (r, i) {
        return h("div", { key: i, className: "vd-insp-row" },
          h("dt", null, r.label),
          r.toggle !== undefined
            ? h("dd", null, h("span", { className: cx("vd-switch", r.toggle && "is-on"), role: "switch", "aria-checked": !!r.toggle, "aria-label": r.label }))
            : h("dd", { className: cx(r.mono && "is-mono", !r.value && "is-empty") }, r.value || r.placeholder || "—", r.picker ? h(Icon, { name: "updown", size: 13 }) : null));
      })));
  }

  function RecentProject(props) {
    return h("button", { type: "button", className: "vd-recent" },
      h("span", { className: "vd-recent-icon" }, h(Icon, { name: "folder", size: 18 })),
      h("span", { className: "vd-recent-text" }, h("span", { className: "vd-recent-name" }, props.name), h("span", { className: "vd-recent-path" }, props.path)));
  }

  /* Regras */
  var SEVERITY = { must: { label: "Obrigatória", icon: "must" }, should: { label: "Recomendada", icon: "should" } };

  function SeverityBadge(props) {
    var s = props.severity === "should" ? "should" : "must";
    return h("span", { className: cx("vd-badge", "vd-sev-" + s) }, h(Icon, { name: SEVERITY[s].icon, size: 13 }), h("span", null, props.label || SEVERITY[s].label));
  }

  var TEST = { script: ["script", "Script"], manual: ["manual", "Manual"], stale: ["warn", "Desatualizado"], none: ["minus", "Sem teste"] };
  var RESULT = { pass: ["check", "Aprovada"], fail: ["close", "Reprovada"], na: ["minus", "Não aplicável"], pending: ["clock", "Pendente"], running: ["clock", "Executando"] };

  function TestChip(props) {
    var m = TEST[props.mode] ? props.mode : "none";
    var r = RESULT[props.result] ? props.result : null;
    return h("span", { className: "vd-test" },
      h("span", { className: cx("vd-badge", "vd-test-" + m) }, h(Icon, { name: TEST[m][0], size: 12 }), h("span", null, TEST[m][1])),
      r ? h("span", { className: cx("vd-badge", "vd-res-" + r) }, h(Icon, { name: RESULT[r][0], size: 12 }), h("span", null, props.resultLabel || RESULT[r][1])) : null);
  }

  function RuleRow(props) {
    var s = props.severity === "should" ? "should" : "must";
    return h("div", { className: cx("vd-rule", props.selected && "is-selected") },
      h("button", { type: "button", className: cx("vd-rule-sev", "vd-sev-" + s), "aria-label": "Severidade: " + SEVERITY[s].label }, h(Icon, { name: SEVERITY[s].icon, size: 16 })),
      h("div", { className: "vd-rule-body" },
        h("div", { className: "vd-rule-text" }, props.text),
        props.detail ? h("div", { className: "vd-rule-detail" }, props.detail) : null,
        h("div", { className: "vd-review-meta" },
          h(SeverityBadge, { severity: s }),
          h(TestChip, { mode: props.test, result: props.result }),
          props.author === "ai" ? h(AuthorTag, { author: "ai" }) : null,
          props.id ? h("span", { className: "vd-id" }, props.id) : null)));
  }

  /* Ideias */
  var IDEA = {
    "new": ["idea", "Nova", "neutral"], exploring: ["search", "Explorando", "change"], approved: ["check", "Aprovada", "done"],
    discarded: ["archive", "Descartada", "neutral"], implemented: ["seal", "Implementada", "done"]
  };

  function StatusPill(props) {
    var s = IDEA[props.status] ? props.status : "new", d = IDEA[s];
    var inner = [h(Icon, { key: "i", name: d[0], size: 13 }), h("span", { key: "l" }, d[1])];
    if (props.picker) return h("button", { type: "button", className: cx("vd-badge", "vd-status", "vd-tone-" + d[2]), "aria-label": "Status: " + d[1] }, inner, h(Icon, { name: "updown", size: 12 }));
    return h("span", { className: cx("vd-badge", "vd-tone-" + d[2]) }, inner);
  }

  /* Agentes, comandos, skills, workflows */
  var KIND = { agent: ["agent", "Agente"], command: ["command", "Comando"], skill: ["skill", "Skill"] };

  function StepCard(props) {
    var k = KIND[props.kind] ? props.kind : "agent";
    var trans = props.transitions || [];
    return h("article", { className: cx("vd-step", props.selected && "is-selected") },
      h("header", { className: "vd-step-head" },
        h("span", { className: "vd-step-num" }, props.index),
        h("span", { className: "vd-step-kind", title: KIND[k][1] }, h(Icon, { name: KIND[k][0], size: 16 })),
        h("span", { className: "vd-step-title" }, props.title),
        props.start ? h("span", { className: "vd-step-start" }, "Início") : null,
        props.id ? h("span", { className: "vd-id" }, props.id) : null,
        h("button", { type: "button", className: "vd-icon-btn", "aria-label": "Opções da etapa " + props.title }, h(Icon, { name: "more", size: 14 }))),
      props.note ? h("p", { className: "vd-step-note" }, props.note) : null,
      h("ul", { className: "vd-step-trans" }, trans.length ? trans.map(function (t, i) {
        var op = t.kind === "else" ? "senão" : t.kind === "if" ? "se" : "=";
        return h("li", { key: i, className: "vd-trans" },
          h("span", { className: cx("vd-trans-op", t.kind === "else" && "is-else") }, op),
          t.when ? h("span", { className: "vd-trans-when" }, t.when) : null,
          h(Icon, { name: "arrow", size: 13 }),
          h("span", { className: cx("vd-trans-to", t.back && "is-back") }, t.to));
      }) : h("li", { className: "vd-trans is-empty" }, "Sem transições: o workflow termina aqui.")),
      props.maxVisits ? h("div", { className: "vd-step-foot" }, "Máx. vezes: " + props.maxVisits) : null);
  }

  function NextStepRow(props) {
    var k = KIND[props.kind] ? props.kind : "agent";
    return h("div", { className: "vd-next" },
      h("span", { className: "vd-next-icon", title: KIND[k][1] }, h(Icon, { name: KIND[k][0], size: 16 })),
      h("div", { className: "vd-next-body" }, h("div", { className: "vd-next-title" }, props.title), props.note ? h("div", { className: "vd-next-note" }, props.note) : null),
      h("button", { type: "button", className: "vd-icon-btn", "aria-label": "Abrir " + props.title }, h(Icon, { name: "arrow", size: 14 })));
  }

  /* Chat de IA */
  function ChatBubble(props) {
    var role = props.role || "assistant", body = props.text || props.children;
    if (role === "tool") return h("button", { type: "button", className: "vd-toolline", "aria-expanded": false },
      h(Icon, { name: "chevron", size: 12, className: "vd-chev" }),
      h("span", { className: "vd-toolline-name" }, props.tool || "Ferramenta"),
      h("span", { className: "vd-toolline-detail" }, body));
    return h("div", { className: cx("vd-bubble", "vd-bubble-" + role) },
      role === "assistant" ? h("span", { className: "vd-bubble-avatar", "aria-hidden": true }, h(Icon, { name: "ai", size: 14 })) : null,
      h("div", { className: "vd-bubble-body" }, body));
  }

  var ACTION = {
    permission: { icon: "should", title: "Permissão", actions: [["Negar", "quiet"], ["Sempre", "secondary"], ["Permitir", "primary"]] },
    plan: { icon: "flow", title: "Plano", actions: [["Rejeitar", "quiet"], ["Pedir mudanças", "secondary"], ["Aprovar", "primary"]] },
    question: { icon: "help", title: "Pergunta", actions: [["Não responder", "quiet"], ["Responder", "primary"]] }
  };

  function ActionCard(props) {
    var k = ACTION[props.kind] ? props.kind : "permission", def = ACTION[k];
    var actions = props.actions || def.actions.map(function (a) { return { label: a[0], variant: a[1] }; });
    var title = props.title || def.title;
    return h("section", { className: "vd-action", "aria-label": title },
      h("header", { className: "vd-action-head" }, h(Icon, { name: def.icon, size: 15 }), h("span", null, title)),
      props.detail ? h("div", { className: "vd-action-detail" }, props.detail) : null,
      props.code ? h("pre", { className: "vd-action-code" }, props.code) : null,
      h("div", { className: "vd-action-buttons" }, actions.map(function (a, i) { return h(Button, { key: i, variant: a.variant || "secondary" }, a.label); })));
  }

  /* Stack e padrões */
  function tagsRow(tags, author) {
    if (!(tags && tags.length) && author !== "ai") return null;
    return h("div", { className: "vd-tags" },
      (tags || []).map(function (t) { return h("span", { key: t, className: "vd-tag" }, "#" + t); }),
      author === "ai" ? h(AuthorTag, { author: "ai" }) : null);
  }

  function StackCard(props) {
    var initials = (props.name || "?").replace(/[^A-Za-z0-9]/g, "").slice(0, 2);
    return h("article", { className: "vd-card vd-stack" },
      props.iconSrc
        ? h("img", { className: "vd-stack-icon", src: props.iconSrc, alt: "", width: 40, height: 40 })
        : h("span", { className: "vd-stack-icon is-placeholder", role: "img", "aria-label": "Ícone de " + props.name }, initials),
      h("div", { className: "vd-card-name" }, props.name),
      props.category ? h("div", { className: "vd-card-cat" }, props.category) : null,
      props.note ? h("p", { className: "vd-card-note" }, props.note) : null,
      tagsRow(props.tags, props.author));
  }

  function PatternCard(props) {
    return h("article", { className: "vd-card vd-pattern" },
      h("header", { className: "vd-pattern-head" },
        h("span", { className: "vd-pattern-icon" }, h(Icon, { name: "pattern", size: 16 })),
        h("div", null, h("div", { className: "vd-card-name" }, props.name), props.category ? h("div", { className: "vd-card-cat" }, props.category) : null)),
      props.summary ? h("p", { className: "vd-card-note" }, props.summary) : null,
      props.note ? h("p", { className: "vd-pattern-note" }, h(Icon, { name: "note", size: 13 }), h("span", null, props.note)) : null,
      h("footer", { className: "vd-pattern-foot" },
        h("span", { className: "vd-pattern-scope" }, h(Icon, { name: props.scope ? "scope" : "globe", size: 13 }), h("span", null, props.scope || "Projeto inteiro")),
        props.rules ? h("button", { type: "button", className: "vd-link" }, props.rules === 1 ? "1 regra" : props.rules + " regras") : null),
      tagsRow(props.tags, props.author));
  }

  window.VibeDeck = Object.assign(window.VibeDeck || {}, {
    Logo: Logo, Button: Button, SegmentedControl: SegmentedControl, FilterChip: FilterChip, TypeBadge: TypeBadge,
    AuthorTag: AuthorTag, SidebarItem: SidebarItem, SidebarSection: SidebarSection, TreeFolder: TreeFolder,
    UsageMeter: UsageMeter, Tab: Tab, ReviewItem: ReviewItem, Composer: Composer,
    InspectorGroup: InspectorGroup, RecentProject: RecentProject, SeverityBadge: SeverityBadge, TestChip: TestChip,
    RuleRow: RuleRow, StatusPill: StatusPill, StepCard: StepCard, NextStepRow: NextStepRow, ChatBubble: ChatBubble,
    ActionCard: ActionCard, StackCard: StackCard, PatternCard: PatternCard, Icon: Icon
  });
})();
