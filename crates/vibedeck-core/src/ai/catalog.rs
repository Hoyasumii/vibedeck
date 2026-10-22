//! `ai_catalog` / `ai catalog` (AICatalog.swift): índice paginado sem prompts.

use serde::Serialize;

use super::{AiError, Result};
use crate::store::Store;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct CatalogItem {
    #[serde(rename = "ref")]
    pub reference: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub paths: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CatalogPage {
    pub items: Vec<CatalogItem>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_offset: Option<usize>,
    pub total: usize,
}

pub const KINDS: &str = "agents, commands, skills, workflows ou rules";

pub fn catalog(store: &Store, kind: &str, offset: i64, limit: i64) -> Result<CatalogPage> {
    if offset < 0 || !(1..=100).contains(&limit) {
        return Err(AiError::InvalidRange);
    }
    let item = |reference: String, title: &str, summary: &Option<String>, paths| CatalogItem {
        reference,
        title: title.to_string(),
        summary: summary.clone(),
        paths,
    };
    let mut all: Vec<CatalogItem> = match kind {
        "agents" => store
            .agents()?
            .into_iter()
            .map(|r| item(r.slug, &r.value.title, &r.value.summary, None))
            .collect(),
        "commands" => store
            .commands()?
            .into_iter()
            .map(|r| item(r.slug, &r.value.title, &r.value.summary, None))
            .collect(),
        "skills" => store
            .skills()?
            .into_iter()
            .map(|r| item(r.slug, &r.value.title, &r.value.summary, None))
            .collect(),
        "workflows" => store
            .workflows()?
            .into_iter()
            .map(|r| item(r.slug, &r.value.title, &r.value.summary, None))
            .collect(),
        "rules" => store
            .rule_topics()?
            .into_iter()
            .map(|r| {
                item(
                    r.slug,
                    &r.value.title,
                    &r.value.description,
                    Some(r.value.paths.clone()),
                )
            })
            .collect(),
        _ => {
            return Err(AiError::DiscoverFailed(format!(
                "Catálogo inválido: use {KINDS}."
            )));
        }
    };
    all.sort_by(|a, b| a.reference.cmp(&b.reference));
    let offset = offset as usize;
    if offset > all.len() {
        return Err(AiError::InvalidRange);
    }
    let total = all.len();
    let items: Vec<CatalogItem> = all.into_iter().skip(offset).take(limit as usize).collect();
    let end = offset + items.len();
    Ok(CatalogPage {
        items,
        next_offset: (end < total).then_some(end),
        total,
    })
}
