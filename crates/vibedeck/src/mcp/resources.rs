//! Recursos MCP (`vibedeck://…`), como `resources()`/`read(_:)` do servidor Swift.
//!
//! Recursos não pesam no catálogo de tools de cada sessão; por isso stack, padrões e logs ficam aqui.

use super::server::{INVALID_PARAMS, ResourceProvider, RpcError};
use super::tool::ToolCtx;
use crate::mcp::args::Args;
use serde_json::{Value, json};
use std::path::{Path, PathBuf};
use vibedeck_core::ideas::IdeaStatusExt;
use vibedeck_core::model::{Agent, Command, Idea, ReviewGroup, RuleTopic, Skill, Workflow};
use vibedeck_core::{Store, docs, reviews};

pub struct ProjectResources {
    root: PathBuf,
}

impl ProjectResources {
    pub fn new(root: PathBuf) -> Self {
        ProjectResources { root }
    }

    fn store(&self) -> Result<Store, RpcError> {
        Store::open(&self.root).map_err(internal)
    }
}

fn internal(e: impl std::fmt::Display) -> RpcError {
    RpcError::new(super::server::INTERNAL_ERROR, e.to_string())
}

fn item(name: &str, uri: String, description: Option<&str>, mime: &str) -> Value {
    let mut v = json!({"name": name, "uri": uri, "mimeType": mime});
    if let Some(d) = description {
        v["description"] = json!(d);
    }
    v
}

fn text(uri: &str, mime: &str, text: String) -> Value {
    json!({"uri": uri, "mimeType": mime, "text": text})
}

/// Arquivo cru do registro (como `String(contentsOf: store.<tipo>URL(slug))`); o slug passa pela
/// validação de caminho do store, então `..` e afins são recusados.
fn raw_record<T: vibedeck_core::store::Stored>(
    store: &Store,
    slug: &str,
) -> Result<String, RpcError> {
    let path = store.record_path::<T>(slug).map_err(internal)?;
    read(&path)
}

fn read(path: &Path) -> Result<String, RpcError> {
    std::fs::read_to_string(path).map_err(|e| internal(format!("{}: {e}", path.display())))
}

/// Resultado de uma tool de leitura reaproveitado como conteúdo (mesmo JSON da tool).
fn tool_text(root: &Path, name: &str) -> Result<String, RpcError> {
    let tools = super::tools::all();
    let tool = tools
        .iter()
        .find(|t| t.name == name)
        .ok_or_else(|| internal(format!("tool ausente: {name}")))?;
    let ctx = ToolCtx {
        root: root.to_path_buf(),
    };
    (tool.handler)(&ctx, &Args(serde_json::Map::new())).map_err(internal)
}

impl ResourceProvider for ProjectResources {
    fn list(&self) -> Result<Vec<Value>, RpcError> {
        let store = self.store()?;
        let mut list = super::tools::project::resources();
        // Ordem do Swift: project, stack, patterns, logs, crashes, depois os dinâmicos.
        list.insert(
            1,
            item(
                "Stack",
                "vibedeck://stack".into(),
                Some("Tecnologias de destaque do projeto"),
                "application/json",
            ),
        );
        list.insert(
            2,
            item(
                "Padrões",
                "vibedeck://patterns".into(),
                Some("Padrões de projeto que o código deve seguir"),
                "application/json",
            ),
        );
        for d in docs::list_docs(&store).map_err(internal)? {
            list.push(item(
                &d.title,
                format!("vibedeck://docs/{}", d.slug),
                None,
                "text/markdown",
            ));
        }
        let json = "application/json";
        for r in store.list::<ReviewGroup>().map_err(internal)? {
            let open = format!("{} aberto(s)", reviews::open_count(&r.value));
            list.push(item(
                &format!("Revisão: {}", r.value.title),
                format!("vibedeck://reviews/{}", r.slug),
                Some(&open),
                json,
            ));
        }
        for r in store.list::<RuleTopic>().map_err(internal)? {
            let count = format!("{} regra(s)", r.value.rules.len());
            list.push(item(
                &format!("Regras: {}", r.value.title),
                format!("vibedeck://rules/{}", r.slug),
                Some(&count),
                json,
            ));
        }
        for r in store.list::<Idea>().map_err(internal)? {
            list.push(item(
                &format!("Ideia: {}", r.value.title),
                format!("vibedeck://ideas/{}", r.slug),
                Some(r.value.status.label()),
                json,
            ));
        }
        for r in store.list::<Agent>().map_err(internal)? {
            list.push(item(
                &format!("Agente: {}", r.value.title),
                format!("vibedeck://agents/{}", r.slug),
                r.value.model.as_deref(),
                json,
            ));
        }
        for r in store.list::<Command>().map_err(internal)? {
            list.push(item(
                &format!("Comando: {}", r.value.title),
                format!("vibedeck://commands/{}", r.slug),
                r.value.summary.as_deref(),
                json,
            ));
        }
        for r in store.list::<Skill>().map_err(internal)? {
            list.push(item(
                &format!("Skill: {}", r.value.title),
                format!("vibedeck://skills/{}", r.slug),
                r.value.summary.as_deref(),
                json,
            ));
        }
        for r in store.list::<Workflow>().map_err(internal)? {
            list.push(item(
                &format!("Workflow: {}", r.value.title),
                format!("vibedeck://workflows/{}", r.slug),
                r.value.summary.as_deref(),
                json,
            ));
        }
        Ok(list)
    }

    fn read(&self, uri: &str) -> Result<Value, RpcError> {
        if let Some(result) = super::tools::project::read_resource(&self.root, uri) {
            return result.map_err(internal);
        }
        let json = "application/json";
        if uri == "vibedeck://patterns" {
            return Ok(text(uri, json, tool_text(&self.root, "list_patterns")?));
        }
        if uri == "vibedeck://stack" {
            let store = self.store()?;
            let stack = store.project().map_err(internal)?.stack;
            let body = super::tool::json_text(&stack).map_err(internal)?;
            return Ok(text(uri, json, body));
        }
        let store = self.store()?;
        if let Some(slug) = uri.strip_prefix("vibedeck://docs/") {
            let body = docs::read_doc(&store, slug).map_err(internal)?;
            return Ok(text(uri, "text/markdown", body));
        }
        let body = if let Some(s) = uri.strip_prefix("vibedeck://reviews/") {
            raw_record::<ReviewGroup>(&store, s)?
        } else if let Some(s) = uri.strip_prefix("vibedeck://rules/") {
            raw_record::<RuleTopic>(&store, s)?
        } else if let Some(s) = uri.strip_prefix("vibedeck://ideas/") {
            raw_record::<Idea>(&store, s)?
        } else if let Some(s) = uri.strip_prefix("vibedeck://agents/") {
            raw_record::<Agent>(&store, s)?
        } else if let Some(s) = uri.strip_prefix("vibedeck://commands/") {
            raw_record::<Command>(&store, s)?
        } else if let Some(s) = uri.strip_prefix("vibedeck://skills/") {
            raw_record::<Skill>(&store, s)?
        } else if let Some(s) = uri.strip_prefix("vibedeck://workflows/") {
            raw_record::<Workflow>(&store, s)?
        } else {
            return Err(RpcError::new(
                INVALID_PARAMS,
                format!("Invalid params: URI desconhecida: {uri}"),
            ));
        };
        Ok(text(uri, json, body))
    }
}
