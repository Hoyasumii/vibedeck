//! Grafo do projeto: lê `graphify-out/graph.json` (node-link do graphify) e gera o `graph.html` offline.
//! Os atributos do grafo são sempre dados; nunca viram HTML nem script.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use super::{ProjectError, Result};
use crate::json;
use crate::store;

/// Recursos estáticos do visualizador (copiados de `Sources/VibeDeckCore/GraphResources`).
const GRAPH_JS: &str = include_str!("../../assets/graph/graph.js");
const GRAPH_CSS: &str = include_str!("../../assets/graph/graph.css");

pub const MAX_BYTES: u64 = 64 * 1024 * 1024;

fn too_big() -> ProjectError {
    ProjectError::Graph("O grafo excede 64 MB. Gere um grafo de uma pasta menor.".into())
}

#[derive(Debug, Clone, PartialEq)]
pub struct Graph {
    pub value: Value,
    pub nodes: Vec<Value>,
    pub links: Vec<Value>,
}

impl Graph {
    pub fn from_bytes(data: &[u8]) -> Result<Graph> {
        if data.len() as u64 > MAX_BYTES {
            return Err(too_big());
        }
        let Ok(mut value) = serde_json::from_slice::<Value>(data) else {
            return Err(ProjectError::Graph(
                "JSON inválido. Gere novamente o grafo.".into(),
            ));
        };
        // O Swift lê todo número como Double: inteiros viram inteiros, `1.0` vira `1`.
        normalize_numbers(&mut value);
        let incompatible = || {
            ProjectError::Graph(
                "Formato incompatível: esperado JSON node-link do graphify com nodes e links/edges."
                    .into(),
            )
        };
        let nodes = value
            .get("nodes")
            .and_then(Value::as_array)
            .ok_or_else(incompatible)?
            .clone();
        let links = value
            .get("links")
            .or_else(|| value.get("edges"))
            .and_then(Value::as_array)
            .ok_or_else(incompatible)?
            .clone();
        let ids: Vec<&str> = nodes
            .iter()
            .filter_map(|n| n.get("id").and_then(Value::as_str))
            .collect();
        let known: HashSet<&str> = ids.iter().copied().collect();
        let endpoint =
            |l: &Value, key: &str| known.contains(l.get(key).and_then(Value::as_str).unwrap_or(""));
        if ids.len() != nodes.len()
            || known.len() != nodes.len()
            || !links
                .iter()
                .all(|l| endpoint(l, "source") && endpoint(l, "target"))
        {
            return Err(ProjectError::Graph(
                "Grafo inválido: IDs repetidos ou relações sem origem/destino. Gere novamente."
                    .into(),
            ));
        }
        Ok(Graph {
            value,
            nodes,
            links,
        })
    }

    pub fn path(root: &Path) -> PathBuf {
        root.join("graphify-out").join("graph.json")
    }

    pub fn load(root: &Path) -> Result<Graph> {
        let path = Self::path(root);
        let meta = fs::metadata(&path).map_err(|_| {
            ProjectError::Graph(
                "graphify-out/graph.json não encontrado. Gere o grafo com o graphify.".into(),
            )
        })?;
        if meta.len() > MAX_BYTES {
            return Err(too_big());
        }
        let data = fs::read(&path).map_err(|e| crate::Error::io(&path, e))?;
        Self::from_bytes(&data)
    }
}

fn normalize_numbers(value: &mut Value) {
    match value {
        Value::Number(n) => {
            if let Some(f) = n.as_f64()
                && f.is_finite()
                && f.fract() == 0.0
                && f.abs() < 9.0e15
            {
                *value = Value::from(f as i64);
            }
        }
        Value::Array(a) => a.iter_mut().for_each(normalize_numbers),
        Value::Object(o) => o.values_mut().for_each(normalize_numbers),
        _ => {}
    }
}

/// `ProjectGraph.sourceURL`: o arquivo de origem de um nó, só se for regular e ficar dentro da raiz
/// (symlinks resolvidos; `..` e caminhos absolutos fora da raiz são recusados).
pub fn source_path(path: &str, root: &Path) -> Option<PathBuf> {
    if path.is_empty() || path.contains('\0') {
        return None;
    }
    let base = fs::canonicalize(root).ok()?;
    let candidate = if path.starts_with('/') {
        PathBuf::from(path)
    } else {
        base.join(path)
    };
    let resolved = fs::canonicalize(candidate).ok()?;
    (resolved != base && resolved.starts_with(&base) && resolved.is_file()).then_some(resolved)
}

/// `GraphHTML.render`.
pub fn render(graph: &Graph, root: &Path) -> Vec<u8> {
    let mut object: Map<String, Value> = graph.value.as_object().cloned().unwrap_or_default();
    let nodes: Vec<Value> = graph
        .nodes
        .iter()
        .map(|node| {
            let mut value = node.as_object().cloned().unwrap_or_default();
            let source = node
                .get("source_file")
                .and_then(Value::as_str)
                .unwrap_or("");
            value.insert(
                "vibedeck_source_available".into(),
                Value::Bool(source_path(source, root).is_some()),
            );
            Value::Object(value)
        })
        .collect();
    object.insert("nodes".into(), Value::Array(nodes));
    object.insert("links".into(), Value::Array(graph.links.clone()));
    // Rótulos controlados pelo grafo não podem fechar o elemento <script>.
    let data = json::to_vdjson(&Value::Object(object))
        .replace('<', "\\u003c")
        .replace('>', "\\u003e")
        .replace('&', "\\u0026");
    let nonce = uuid::Uuid::new_v4().to_string().to_uppercase();
    let html = format!(
        "<!doctype html><html lang=\"pt-BR\"><head><meta charset=\"utf-8\">\n\
<meta name=\"vibedeck-graph-renderer\" content=\"1\">\n\
<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'nonce-{nonce}'; style-src 'nonce-{nonce}'; img-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\">\n\
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Grafo do projeto</title>\n\
<style nonce=\"{nonce}\">{style}</style></head><body>\n\
<header><label for=\"search\">Buscar nós</label><input id=\"search\" type=\"search\" placeholder=\"Nome, arquivo ou comunidade\">\n\
<button id=\"overview\">Visão geral</button><button id=\"zoom-in\" aria-label=\"Aumentar zoom\">+</button>\n\
<button id=\"zoom-out\" aria-label=\"Diminuir zoom\">−</button><button id=\"center\">Centralizar</button></header>\n\
<div id=\"status\" role=\"status\" aria-live=\"polite\"></div>\n\
<main><svg id=\"graph\" tabindex=\"0\" role=\"group\" aria-label=\"Grafo: navegue com as setas e selecione com Enter\"></svg>\n\
<aside><section id=\"details\" aria-label=\"Inspeção do nó\"></section><section id=\"results\" aria-label=\"Resultados e comunidades\"></section></aside></main>\n\
<script id=\"graph-data\" type=\"application/json\" nonce=\"{nonce}\">{data}</script>\n\
<script nonce=\"{nonce}\">{script}</script></body></html>",
        style = GRAPH_CSS,
        script = GRAPH_JS,
    );
    html.into_bytes()
}

/// `GraphHTML.write`: grava (de forma atômica) em `output`.
pub fn write(graph: &Graph, root: &Path, output: &Path) -> Result<()> {
    store::write_atomic(output, &render(graph, root))?;
    Ok(())
}

/// `graph export` / `export_graph`: lê `graphify-out/graph.json` e sobrescreve `graphify-out/graph.html`.
pub fn export(root: &Path) -> Result<&'static str> {
    let graph = Graph::load(root)?;
    write(&graph, root, &root.join("graphify-out").join("graph.html"))?;
    Ok(EXPORTED_MESSAGE)
}

pub const EXPORTED_MESSAGE: &str = "Visualização offline exportada em graphify-out/graph.html";
