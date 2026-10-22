//! Cliente do servidor MCP do Skill Icons (JSON-RPC sem estado sobre HTTP): o catálogo e os badges vêm
//! dele, nunca de URLs escritas à mão.

use std::collections::BTreeMap;
use std::time::Duration;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::{Result, StackError, trim_ws};
use crate::slug;

/// Variável de ambiente que troca o endpoint (testes e ambientes sem acesso à rede pública).
pub const ENDPOINT_ENV: &str = "VIBEDECK_SKILL_ICONS_URL";
pub const DEFAULT_ENDPOINT: &str = "https://skill-icons.alanreisanjo.workers.dev/mcp";
pub const CATEGORIES: [&str; 18] = [
    "language",
    "frontend",
    "backend",
    "database",
    "cloud",
    "devops",
    "tooling",
    "testing",
    "observability",
    "auth",
    "ide",
    "ai",
    "design",
    "game",
    "payments",
    "os",
    "social",
    "productivity",
];
/// Tamanho do catálogo completo (uma chamada).
pub const CATALOG_LIMIT: i64 = 631;
const TIMEOUT: Duration = Duration::from_secs(20);

/// Ícone do catálogo do Skill Icons, como o `skill_icons_search` devolve.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "SkillIconWire")]
pub struct SkillIcon {
    pub id: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    /// Tem variantes dark e light.
    pub themed: bool,
    pub aliases: Vec<String>,
}

#[derive(Deserialize)]
struct SkillIconWire {
    id: String,
    name: Option<String>,
    category: Option<String>,
    themed: Option<bool>,
    aliases: Option<Vec<String>>,
}

impl From<SkillIconWire> for SkillIcon {
    fn from(w: SkillIconWire) -> Self {
        SkillIcon {
            name: w.name.unwrap_or_else(|| w.id.clone()),
            id: w.id,
            category: w.category,
            themed: w.themed.unwrap_or(false),
            aliases: w.aliases.unwrap_or_default(),
        }
    }
}

impl SkillIcon {
    fn names(&self) -> impl Iterator<Item = &String> {
        std::iter::once(&self.id)
            .chain(std::iter::once(&self.name))
            .chain(self.aliases.iter())
    }

    /// `text` nomeia este ícone: id, nome da marca ou alias (sem caixa nem acentos).
    pub fn matches_exactly(&self, text: &str) -> bool {
        let key = normalize(text);
        self.names().any(|n| normalize(n) == key)
    }

    /// `text` é parte do id, do nome ou de um alias.
    pub fn matches_containing(&self, text: &str) -> bool {
        let key = normalize(text);
        key.is_empty() || self.names().any(|n| normalize(n).contains(&key))
    }
}

fn normalize(s: &str) -> String {
    slug::fold(s)
        .chars()
        .filter(|c| c.is_alphabetic() || c.is_numeric() || *c == '+' || *c == '#')
        .collect()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SkillIconTheme {
    Dark,
    Light,
}

impl SkillIconTheme {
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "dark" => Some(Self::Dark),
            "light" => Some(Self::Light),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Dark => "dark",
            Self::Light => "light",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SkillBadgeUnknown {
    pub name: String,
    #[serde(default)]
    pub suggestions: Vec<String>,
}

/// O que `skill_icons_badge` devolve: a URL da imagem mais Markdown/HTML prontos para colar.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "SkillBadgeWire")]
pub struct SkillBadge {
    pub url: String,
    pub markdown: String,
    pub html: String,
    pub icons: Vec<String>,
    pub unknown: Vec<SkillBadgeUnknown>,
}

#[derive(Deserialize)]
struct SkillBadgeWire {
    url: String,
    markdown: Option<String>,
    html: Option<String>,
    icons: Option<Vec<String>>,
    unknown: Option<Vec<SkillBadgeUnknown>>,
}

impl From<SkillBadgeWire> for SkillBadge {
    fn from(w: SkillBadgeWire) -> Self {
        SkillBadge {
            markdown: w.markdown.unwrap_or_else(|| format!("![Stack]({})", w.url)),
            html: w
                .html
                .unwrap_or_else(|| format!("<img src=\"{}\" />", w.url)),
            icons: w.icons.unwrap_or_default(),
            unknown: w.unknown.unwrap_or_default(),
            url: w.url,
        }
    }
}

/// O servidor do Skill Icons; um trait para os testes trocarem a rede por um falso.
pub trait SkillIconsApi {
    fn search(
        &self,
        query: Option<&str>,
        category: Option<&str>,
        limit: Option<i64>,
    ) -> Result<Vec<SkillIcon>>;

    fn badge(
        &self,
        icons: &[String],
        theme: Option<SkillIconTheme>,
        per_line: Option<i64>,
    ) -> Result<SkillBadge>;

    /// O catálogo inteiro (uma chamada).
    fn catalog(&self) -> Result<Vec<SkillIcon>> {
        self.search(None, None, Some(CATALOG_LIMIT))
    }
}

/// Cliente HTTP real (com timeout de 20 s).
#[derive(Debug, Clone)]
pub struct SkillIcons {
    pub endpoint: String,
}

impl Default for SkillIcons {
    /// Endpoint de `VIBEDECK_SKILL_ICONS_URL`, se definido e não vazio; senão o worker público.
    fn default() -> Self {
        let endpoint = std::env::var(ENDPOINT_ENV)
            .ok()
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_ENDPOINT.to_string());
        SkillIcons { endpoint }
    }
}

impl SkillIcons {
    pub fn new(endpoint: impl Into<String>) -> Self {
        SkillIcons {
            endpoint: endpoint.into(),
        }
    }

    fn call_tool(&self, name: &str, arguments: Value) -> Result<String> {
        let unavailable = |e: String| StackError::SkillIconsUnavailable(e);
        let mut builder = ureq::Agent::config_builder()
            .timeout_global(Some(TIMEOUT))
            .http_status_as_error(false);
        if self.endpoint.starts_with("http://") {
            builder = builder.proxy(None);
        }
        let agent: ureq::Agent = builder.build().into();
        let body = json!({
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        });
        let mut response = agent
            .post(&self.endpoint)
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream")
            .send_json(&body)
            .map_err(|e| unavailable(e.to_string()))?;
        let status = response.status().as_u16();
        if !(200..300).contains(&status) {
            return Err(unavailable(format!("HTTP {status} em {name}.")));
        }
        response
            .body_mut()
            .read_to_string()
            .map_err(|e| unavailable(e.to_string()))
    }
}

impl SkillIconsApi for SkillIcons {
    fn search(
        &self,
        query: Option<&str>,
        category: Option<&str>,
        limit: Option<i64>,
    ) -> Result<Vec<SkillIcon>> {
        let mut args = serde_json::Map::new();
        if let Some(q) = query.filter(|s| !s.is_empty()) {
            args.insert("query".into(), json!(q));
        }
        if let Some(c) = category.filter(|s| !s.is_empty()) {
            args.insert("category".into(), json!(c));
        }
        if let Some(l) = limit {
            args.insert("limit".into(), json!(l));
        }
        #[derive(Deserialize)]
        struct Found {
            icons: Vec<SkillIcon>,
        }
        let text = self.call_tool("skill_icons_search", Value::Object(args))?;
        Ok(decode_tool_text::<Found>(&text)?.icons)
    }

    fn badge(
        &self,
        icons: &[String],
        theme: Option<SkillIconTheme>,
        per_line: Option<i64>,
    ) -> Result<SkillBadge> {
        let mut args = serde_json::Map::new();
        args.insert("icons".into(), json!(icons));
        if let Some(t) = theme {
            args.insert("theme".into(), json!(t.as_str()));
        }
        if let Some(p) = per_line {
            args.insert("perLine".into(), json!(p));
        }
        let text = self.call_tool("skill_icons_badge", Value::Object(args))?;
        decode_tool_text(&text)
    }
}

/// Abre a resposta JSON-RPC de `tools/call` (JSON puro ou um evento SSE `data:`) e decodifica o JSON
/// dentro do primeiro conteúdo de texto.
pub fn decode_tool_text<T: DeserializeOwned>(response: &str) -> Result<T> {
    let unexpected =
        || StackError::SkillIconsUnavailable("resposta inesperada do servidor.".into());
    let mut payload = response;
    if !response.starts_with('{')
        && let Some(line) = response.split('\n').rfind(|l| l.starts_with("data:"))
    {
        payload = trim_ws(&line[5..]);
    }
    #[derive(Deserialize)]
    struct Content {
        #[serde(rename = "type")]
        kind: String,
        text: Option<String>,
    }
    #[derive(Deserialize)]
    struct CallResult {
        content: Vec<Content>,
        #[serde(rename = "isError")]
        is_error: Option<bool>,
    }
    #[derive(Deserialize)]
    struct Failure {
        message: String,
    }
    #[derive(Deserialize)]
    struct Envelope {
        result: Option<CallResult>,
        error: Option<Failure>,
    }
    let envelope: Envelope = serde_json::from_str(payload).map_err(|_| unexpected())?;
    if let Some(error) = envelope.error {
        return Err(StackError::SkillIconsUnavailable(error.message));
    }
    let text = envelope
        .result
        .as_ref()
        .and_then(|r| {
            r.content
                .iter()
                .find(|c| c.kind == "text")
                .and_then(|c| c.text.clone())
        })
        .ok_or_else(|| StackError::SkillIconsUnavailable("resposta sem conteúdo.".into()))?;
    if envelope.result.and_then(|r| r.is_error) == Some(true) {
        return Err(StackError::SkillIconsUnavailable(text));
    }
    serde_json::from_str(&text).map_err(|_| unexpected())
}

/// Resolve ids, nomes de marca ou aliases ("k8s", "Next.js") no catálogo, em ordem e sem repetir.
/// Falha com `UnknownStackIcons` (e sugestões) se algum nome não casar com nada.
pub fn resolve(refs: &[String], catalog: &[SkillIcon]) -> Result<Vec<SkillIcon>> {
    let mut resolved: Vec<SkillIcon> = Vec::new();
    let mut unknown: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for reference in refs.iter().map(|r| trim_ws(r)).filter(|r| !r.is_empty()) {
        let found = catalog
            .iter()
            .find(|i| i.id == reference)
            .or_else(|| catalog.iter().find(|i| i.matches_exactly(reference)));
        match found {
            Some(icon) => {
                if !resolved.iter().any(|r| r.id == icon.id) {
                    resolved.push(icon.clone());
                }
            }
            None => {
                let suggestions = catalog
                    .iter()
                    .filter(|i| i.matches_containing(reference))
                    .take(5)
                    .map(|i| i.id.clone())
                    .collect();
                unknown.insert(reference.to_string(), suggestions);
            }
        }
    }
    if unknown.is_empty() {
        Ok(resolved)
    } else {
        Err(StackError::UnknownStackIcons(unknown))
    }
}

impl SkillIcons {
    /// Ver [`resolve`].
    pub fn resolve(refs: &[String], catalog: &[SkillIcon]) -> Result<Vec<SkillIcon>> {
        resolve(refs, catalog)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Vec<SkillIcon> {
        let mk = |id: &str, name: &str, cat: &str, aliases: &[&str]| SkillIcon {
            id: id.into(),
            name: name.into(),
            category: Some(cat.into()),
            themed: false,
            aliases: aliases.iter().map(|s| s.to_string()).collect(),
        };
        vec![
            mk("swift", "Swift", "language", &[]),
            mk("kubernetes", "Kubernetes", "devops", &["k8s"]),
            mk("nextjs", "Next.js", "frontend", &["next"]),
            mk("postgresql", "PostgreSQL", "database", &["postgres"]),
        ]
    }

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn resolve_aceita_ids_nomes_e_aliases() {
        let icons = resolve(&s(&["k8s", "Next.js", "swift", "kubernetes"]), &fixture()).unwrap();
        let ids: Vec<_> = icons.iter().map(|i| i.id.as_str()).collect();
        assert_eq!(ids, ["kubernetes", "nextjs", "swift"]);
        match resolve(&s(&["swift", "post"]), &fixture()).unwrap_err() {
            StackError::UnknownStackIcons(m) => {
                assert_eq!(m.len(), 1);
                assert_eq!(m["post"], ["postgresql"]);
            }
            e => panic!("{e}"),
        }
    }

    #[test]
    fn decodifica_respostas_do_servidor() {
        let plain = r#"{"result":{"content":[{"type":"text","text":"{\"total\":1,\"icons\":[{\"id\":\"swift\",\"name\":\"Swift\",\"category\":\"language\",\"themed\":false,\"aliases\":[]}]}"}]},"jsonrpc":"2.0","id":1}"#;
        #[derive(Debug, Deserialize)]
        struct R {
            icons: Vec<SkillIcon>,
        }
        assert_eq!(
            decode_tool_text::<R>(plain).unwrap().icons,
            vec![fixture()[0].clone()]
        );
        let sse = format!("event: message\ndata: {plain}\n\n");
        assert_eq!(decode_tool_text::<R>(&sse).unwrap().icons.len(), 1);
        let error =
            r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}"#;
        assert_eq!(
            decode_tool_text::<R>(error).unwrap_err().to_string(),
            "Skill Icons indisponível: Method not found"
        );
        assert_eq!(
            decode_tool_text::<R>("lixo").unwrap_err().to_string(),
            "Skill Icons indisponível: resposta inesperada do servidor."
        );
        let is_error = r#"{"result":{"isError":true,"content":[{"type":"text","text":"falhou"}]}}"#;
        assert_eq!(
            decode_tool_text::<R>(is_error).unwrap_err().to_string(),
            "Skill Icons indisponível: falhou"
        );
        let empty = r#"{"result":{"content":[]}}"#;
        assert_eq!(
            decode_tool_text::<R>(empty).unwrap_err().to_string(),
            "Skill Icons indisponível: resposta sem conteúdo."
        );
    }

    #[test]
    fn badge_e_icone_tem_defaults() {
        let b: SkillBadge = serde_json::from_str(r#"{"url":"https://x/i"}"#).unwrap();
        assert_eq!(b.markdown, "![Stack](https://x/i)");
        assert_eq!(b.html, "<img src=\"https://x/i\" />");
        assert!(b.icons.is_empty() && b.unknown.is_empty());
        let i: SkillIcon = serde_json::from_str(r#"{"id":"a"}"#).unwrap();
        assert_eq!((i.name.as_str(), i.themed), ("a", false));
        // category ausente é omitida; aliases e themed sempre saem
        let v = serde_json::to_value(&i).unwrap();
        assert_eq!(v, json!({"id":"a","name":"a","themed":false,"aliases":[]}));
    }

    #[test]
    fn busca_por_trecho() {
        let f = fixture();
        assert!(f[3].matches_containing("postg"));
        assert!(f[3].matches_containing(""));
        assert!(f[2].matches_exactly("NEXT.JS"));
        assert!(!f[2].matches_exactly("nex"));
    }
}
