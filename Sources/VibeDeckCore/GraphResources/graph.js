'use strict';
// Offline renderer: replaces the generated vis-network CDN page with bounded SVG views.
const graph = JSON.parse(document.getElementById('graph-data').textContent);
const nodes = graph.nodes, links = graph.links || graph.edges || [];
const index = new Map(nodes.map(n => [n.id, n]));
const communities = new Map();
const groupKey = n => String(n.community ?? 'sem-comunidade');
for (const n of nodes) {
  const key = groupKey(n);
  if (!communities.has(key)) communities.set(key, []);
  communities.get(key).push(n);
}
const byId = id => document.getElementById(id);
const svg = byId('graph'), details = byId('details'), results = byId('results');
const NS = 'http://www.w3.org/2000/svg';
let viewport = [0, 0, 1000, 700], selected = null;
const LIMIT = 180, EDGE_LIMIT = 300;
function el(tag, text, parent) {
  const child = document.createElement(tag);
  if (text != null) child.textContent = text;
  if (parent) parent.append(child);
  return child;
}
function svgEl(tag, attrs, parent) {
  const child = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) child.setAttribute(k, String(v));
  if (parent) parent.append(child);
  return child;
}
function setViewport() { svg.setAttribute('viewBox', viewport.join(' ')); }
function center() { viewport = [0, 0, 1000, 700]; setViewport(); }
function zoom(factor) {
  const [x, y, w, h] = viewport;
  const next = Math.min(4000, Math.max(100, w * factor));
  viewport = [x + (w - next) / 2, y + (h - next * .7) / 2, next, next * .7];
  setViewport();
}
function draw(items, edges, activate, description) {
  svg.replaceChildren();
  const defs = svgEl('defs', {}, svg);
  const marker = svgEl('marker', {id:'arrow', viewBox:'0 0 10 10', refX:16, refY:5, markerWidth:6, markerHeight:6, orient:'auto-start-reverse'}, defs);
  svgEl('path', {d:'M 0 0 L 10 5 L 0 10 z', fill:'currentColor'}, marker);
  const shown = items.slice(0, LIMIT);
  const positions = new Map(shown.map((n, i) => {
    const angle = i * 2 * Math.PI / Math.max(1, shown.length);
    const radius = shown.length > 1 ? 285 : 0;
    return [n.id, [500 + radius * Math.cos(angle), 350 + radius * Math.sin(angle)]];
  }));
  const visibleEdges = edges.filter(e => positions.has(e.source) && positions.has(e.target));
  for (const e of visibleEdges.slice(0, EDGE_LIMIT)) {
    const [x1,y1] = positions.get(e.source), [x2,y2] = positions.get(e.target);
    const kind = String(e.confidence || e._origin || 'EXTRACTED');
    const line = svgEl('line', {x1,y1,x2,y2,stroke:'currentColor','stroke-opacity':.3,'stroke-dasharray':kind === 'INFERRED' ? '8 4' : kind === 'AMBIGUOUS' ? '2 4' : '', 'marker-end':graph.directed || e.directed ? 'url(#arrow)' : ''}, svg);
    svgEl('title', {}, line).textContent = `${e.source} → ${e.target}: ${e.relation || 'relação'} (${kind})`;
  }
  for (const n of shown) {
    const [x,y] = positions.get(n.id);
    const g = svgEl('g', {tabindex:0,role:'button','aria-label':n.label || n.id,transform:`translate(${x} ${y})`}, svg);
    svgEl('circle', {r:9,fill:'currentColor'}, g);
    svgEl('text', {x:12,y:4,'font-size':11,fill:'currentColor'}, g).textContent = String(n.label || n.id).slice(0,34);
    g.addEventListener('click', () => activate(n));
    g.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); activate(n); } });
  }
  byId('status').textContent = `${description} · ${shown.length}/${items.length} nós · ${Math.min(visibleEdges.length, EDGE_LIMIT)}/${visibleEdges.length} relações. Limite: ${LIMIT} nós por vista.`;
  center();
}
function overview() {
  selected = null; details.replaceChildren();
  el('p', 'Selecione uma comunidade ou busque um nó. EXTRACTED: estrutural; INFERRED: inferida; AMBIGUOUS: ambígua. As setas indicam direção em grafos direcionados.', details);
  const groups = [...communities].map(([id, members]) => ({id,label:`${members[0].community_name || id} (${members.length})`}));
  const edges = [], seen = new Set();
  for (const e of links) {
    const a = index.get(e.source), b = index.get(e.target);
    if (!a || !b || groupKey(a) === groupKey(b)) continue;
    const key = `${groupKey(a)}:${groupKey(b)}`;
    if (!seen.has(key)) { seen.add(key); edges.push({source:groupKey(a),target:groupKey(b),confidence:e.confidence,relation:e.relation}); }
  }
  groups.sort((a,b) => communities.get(b.id).length - communities.get(a.id).length);
  draw(groups, edges, n => showCommunity(n.id), `Visão geral: ${communities.size} comunidades`);
  results.replaceChildren();
  for (const group of groups) {
    const button = el('button', group.label, results);
    button.addEventListener('click', () => showCommunity(group.id));
  }
}
function showCommunity(id) {
  const members = communities.get(id) || [];
  draw(members, links, inspect, `Comunidade ${id}`);
  details.replaceChildren(); el('h2', `Comunidade ${id}`, details);
  el('p', `${members.length} nós. Use a busca para encontrar nós além do limite da vista.`, details);
}
function inspect(n) {
  selected = n;
  const neighbors = new Set([n.id]);
  for (const e of links) { if (e.source === n.id) neighbors.add(e.target); if (e.target === n.id) neighbors.add(e.source); }
  const neighborhood = [n, ...[...neighbors].filter(id => id !== n.id).map(id => index.get(id)).filter(Boolean)];
  draw(neighborhood, links, inspect, `Vizinhança de ${n.label || n.id}`);
  details.replaceChildren(); el('h2', n.label || n.id, details);
  for (const key of ['id','source_file','source_location','_origin','confidence','community_name']) {
    if (n[key] != null) el('p', `${key}: ${n[key]}`, details);
  }
  if (n.vibedeck_source_available) {
    const link = el('a', 'Abrir origem no Finder', details);
    link.href = `vibedeck-source://node/${encodeURIComponent(n.id)}`;
  } else el('p', 'Origem ausente, removida ou fora do projeto.', details);
  const related = links.filter(e => e.source === n.id || e.target === n.id);
  const list = el('ul', null, details);
  for (const e of related.slice(0, EDGE_LIMIT)) {
    const other = index.get(e.source === n.id ? e.target : e.source);
    const item = el('li', null, list);
    const button = el('button', `${graph.directed || e.directed ? (e.source === n.id ? '→' : '←') : '—'} ${other?.label || other?.id || '?'} · ${e.relation || 'relação'} · ${e.confidence || 'não informada'} · origem: ${e._origin || 'não informada'}${e.confidence_score != null ? ' · confiança: ' + e.confidence_score : ''}${e.source_file ? ' · ' + e.source_file : ''}`, item);
    button.addEventListener('click', () => { if (other) inspect(other); });
  }
  if (related.length > EDGE_LIMIT) el('p', `Mostrando ${EDGE_LIMIT}/${related.length} relações.`, details);
}
byId('search').addEventListener('input', e => {
  const q = e.target.value.trim().toLocaleLowerCase();
  if (!q) { overview(); return; }
  results.replaceChildren();
  const matches = nodes.filter(n => [n.label,n.id,n.source_file,n.community_name].some(v => String(v || '').toLocaleLowerCase().includes(q)));
  byId('status').textContent = `${matches.length} resultados; mostrando até 100. Refine a busca para ver outros nós.`;
  for (const n of matches.slice(0,100)) {
    const button = el('button', `${n.label || n.id} · ${n.source_file || ''}`, results);
    button.addEventListener('click', () => inspect(n));
  }
});
byId('overview').addEventListener('click', overview);
byId('zoom-in').addEventListener('click', () => zoom(.8));
byId('zoom-out').addEventListener('click', () => zoom(1.25));
byId('center').addEventListener('click', center);
svg.addEventListener('keydown', e => {
  const delta = viewport[2] * .08;
  if (e.key === 'ArrowLeft') viewport[0] -= delta;
  else if (e.key === 'ArrowRight') viewport[0] += delta;
  else if (e.key === 'ArrowUp') viewport[1] -= delta;
  else if (e.key === 'ArrowDown') viewport[1] += delta;
  else return;
  e.preventDefault(); setViewport();
});
overview();
