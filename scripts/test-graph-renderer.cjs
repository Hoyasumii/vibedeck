// Exercise the offline renderer against the real graph without a browser or network.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {performance} = require('node:perf_hooks');
const root = path.resolve(__dirname, '..');
const graph = JSON.parse(fs.readFileSync(process.argv[2] || path.join(root, 'graphify-out/graph.json'), 'utf8'));
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.attrs = {}; this.events = {}; this.textContent = ''; this.value = ''; }
  append(child) { this.children.push(child); }
  replaceChildren() { this.children = []; }
  setAttribute(name, value) { this.attrs[name] = String(value); }
  addEventListener(name, callback) { this.events[name] = callback; }
  fire(name, extra = {}) { this.events[name]?.({target:this,preventDefault(){},...extra}); }
  set innerHTML(_) { throw Error('Untrusted HTML insertion'); }
}
const elements = new Map(['graph-data','graph','details','results','status','search','overview','zoom-in','zoom-out','center'].map(id => [id,new Element(id)]));
elements.get('graph-data').textContent = JSON.stringify(graph);
const document = {
  getElementById: id => elements.get(id),
  createElement: tag => new Element(tag),
  createElementNS: (_,tag) => new Element(tag)
};
const context = vm.createContext({document, fetch(){throw Error('Unexpected network access');}});
const code = fs.readFileSync(path.join(root,'Sources/VibeDeckCore/GraphResources/graph.js'),'utf8');
const started = performance.now();
vm.runInContext(code,context,{timeout:10000});
function count(tag) { return elements.get('graph').children.filter(e => e.tag === tag).length; }
function text(node) { return node.textContent + node.children.map(text).join(' '); }
assert(graph.nodes.length > 5000, 'This validation uses the real large project graph');
assert(count('g') <= 180 && count('g') > 0);
assert(count('line') <= 300);
assert(text(elements.get('status')).includes('comunidades'));
assert(text(elements.get('details')).includes('INFERRED'));
const communities = elements.get('results').children.length;
elements.get('results').children[0].fire('click');
assert(count('g') <= 180);
assert(text(elements.get('status')).includes('Comunidade'));
const search = elements.get('search');
search.value = graph.nodes[0].id; search.fire('input');
assert(elements.get('results').children.length > 0 && elements.get('results').children.length <= 100);
elements.get('results').children[0].fire('click');
assert(text(elements.get('details')).includes(graph.nodes[0].id));
assert(count('g') <= 180 && count('line') <= 300);
const viewport = elements.get('graph').attrs.viewBox;
elements.get('zoom-in').fire('click');
assert.notEqual(elements.get('graph').attrs.viewBox, viewport);
elements.get('center').fire('click'); assert.equal(elements.get('graph').attrs.viewBox,viewport);
elements.get('graph').fire('keydown',{key:'ArrowRight'}); assert.notEqual(elements.get('graph').attrs.viewBox,viewport);
search.value = 'no-node-with-this-name-1234567'; search.fire('input');
assert.equal(elements.get('results').children.length,0);
search.value = ''; search.fire('input'); assert.equal(elements.get('results').children.length,communities);
assert(count('g') <= 180 && count('line') <= 300);
console.log(`Renderer passed: ${graph.nodes.length} nodes, ${communities} communities, bounded SVG, search, inspection, zoom, keyboard and reset; ${(performance.now()-started).toFixed(1)} ms.`);
