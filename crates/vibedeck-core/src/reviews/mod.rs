//! Revisões: grupos e itens de revisão (`.vibedeck/reviews/*.json`).
//!
//! CLI e MCP chamam as mesmas funções daqui. Submódulos:
//! - [`gate`]: o gate de conclusão (item com regras só vai a `done` com check aprovado);
//! - [`resolve`] e [`discover`]: a parte do "Resolver"/"Descubra" que não depende de provider de IA.

pub mod discover;
pub mod gate;
pub mod resolve;

use serde::Serialize;

use crate::error::{Error, Result};
use crate::model::*;
use crate::store::{Record, Store};

/// Erros da área. Os de `Core` repassam o erro tipado do core; as mensagens espelham o Swift.
#[derive(Debug, thiserror::Error)]
pub enum ReviewError {
    #[error(transparent)]
    Core(#[from] Error),
    #[error(
        "O item não pode ser concluído sem passar pelas regras:\n{}\nUse rules_for / submit_rule_check (ou `vibedeck rules check`) com o id do item.",
        bullets(.0)
    )]
    RulesNotVerified(Vec<String>),
    #[error("Kind desconhecido '{kind}'. Disponíveis: {}", available.join(", "))]
    UnknownKind {
        kind: String,
        available: Vec<String>,
    },
    #[error("Status inválido: {0}")]
    InvalidStatus(String),
}

impl ReviewError {
    /// Erros que o MCP devolve como `invalidParams` (no Swift, `MCPError.invalidParams`).
    pub fn is_invalid_params(&self) -> bool {
        matches!(
            self,
            ReviewError::UnknownKind { .. } | ReviewError::InvalidStatus(_)
        )
    }
}

fn bullets(lines: &[String]) -> String {
    lines
        .iter()
        .map(|l| format!("- {l}"))
        .collect::<Vec<_>>()
        .join("\n")
}

pub type ReviewResult<T> = std::result::Result<T, ReviewError>;

/// `ReviewStatus(rawValue:)`.
pub fn parse_status(s: &str) -> Option<ReviewStatus> {
    Some(match s {
        "open" => ReviewStatus::Open,
        "in_progress" => ReviewStatus::InProgress,
        "done" => ReviewStatus::Done,
        "wontfix" => ReviewStatus::Wontfix,
        _ => return None,
    })
}

pub fn status_name(s: ReviewStatus) -> &'static str {
    match s {
        ReviewStatus::Open => "open",
        ReviewStatus::InProgress => "in_progress",
        ReviewStatus::Done => "done",
        ReviewStatus::Wontfix => "wontfix",
    }
}

/// `ReviewPriority(rawValue:)`.
pub fn parse_priority(s: &str) -> Option<ReviewPriority> {
    Some(match s {
        "low" => ReviewPriority::Low,
        "normal" => ReviewPriority::Normal,
        "high" => ReviewPriority::High,
        _ => return None,
    })
}

pub const STATUSES: [&str; 4] = ["open", "in_progress", "done", "wontfix"];
pub const PRIORITIES: [&str; 3] = ["low", "normal", "high"];

/// Itens ainda não fechados (`done`/`wontfix` não contam).
pub fn open_count(group: &ReviewGroup) -> usize {
    group.items.iter().filter(|i| !i.status.is_closed()).count()
}

/// Caminho de diretório de um slug (`a/b/c` -> `a/b`; sem barra -> vazio).
pub fn group_path_of(slug: &str) -> String {
    let parts: Vec<&str> = slug.split('/').filter(|p| !p.is_empty()).collect();
    match parts.split_last() {
        Some((_, head)) => head.join("/"),
        None => String::new(),
    }
}

/// Linha de `list_review_groups` (MCP).
#[derive(Debug, Serialize)]
pub struct GroupRow {
    pub group: String,
    pub slug: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub tags: Vec<String>,
    pub open: usize,
    pub total: usize,
}

/// Linha de `list_review_items` / `review list --json` e resultado de `add_review_item`.
#[derive(Debug, Serialize)]
pub struct ItemRow {
    pub group: String,
    pub item: ReviewItem,
}

pub fn list_groups(store: &Store) -> Result<Vec<Record<ReviewGroup>>> {
    store.review_groups()
}

pub fn group_rows(store: &Store) -> Result<Vec<GroupRow>> {
    Ok(list_groups(store)?
        .into_iter()
        .map(|r| GroupRow {
            group: group_path_of(&r.slug),
            open: open_count(&r.value),
            total: r.value.items.len(),
            slug: r.slug,
            title: r.value.title,
            description: r.value.description,
            tags: r.value.tags,
        })
        .collect())
}

/// `GroupedRecord(slug, group)` do CLI: o grupo mais `slug` e `group` (caminho do diretório).
pub fn grouped_json(record: &Record<ReviewGroup>) -> Result<serde_json::Value> {
    let mut value = serde_json::to_value(&record.value).map_err(Error::Encode)?;
    if let Some(map) = value.as_object_mut() {
        map.insert("slug".into(), record.slug.clone().into());
        map.insert("group".into(), group_path_of(&record.slug).into());
    }
    Ok(value)
}

/// Itens por grupo (ordem dos grupos da listagem), filtrados por grupo/status/kind.
pub fn list_items(
    store: &Store,
    group: Option<&str>,
    status: Option<ReviewStatus>,
    kind: Option<&str>,
) -> Result<Vec<ItemRow>> {
    let mut groups = list_groups(store)?;
    if let Some(g) = group {
        let slug = store.resolve::<ReviewGroup>(g)?;
        groups.retain(|r| r.slug == slug);
    }
    let mut rows = Vec::new();
    for g in groups {
        for item in g.value.items {
            if status.is_none_or(|s| item.status == s) && kind.is_none_or(|k| item.kind == k) {
                rows.push(ItemRow {
                    group: g.slug.clone(),
                    item,
                });
            }
        }
    }
    Ok(rows)
}

/// Cria um grupo com slug único (título aparado; `reference` com `/` define o caminho).
pub fn create_group(
    store: &Store,
    title: &str,
    description: Option<String>,
    tags: Vec<String>,
    reference: Option<&str>,
) -> Result<Record<ReviewGroup>> {
    let title = title.trim();
    if title.is_empty() {
        return Err(Error::InvalidName);
    }
    let mut group = ReviewGroup::new(title);
    group.description = description;
    group.tags = tags;
    store.create(&group, reference)
}

/// Acha um item por id completo ou prefixo único (>= 4) em todos os grupos.
/// Devolve `(slug do grupo, grupo, índice)`.
pub fn find_item(store: &Store, reference: &str) -> Result<(String, ReviewGroup, usize)> {
    let needle = reference.to_lowercase();
    let mut matches: Vec<(String, ReviewGroup, usize)> = Vec::new();
    for rec in list_groups(store)? {
        for (i, item) in rec.value.items.iter().enumerate() {
            let id = item.id.to_string().to_lowercase();
            if id == needle {
                return Ok((rec.slug, rec.value, i));
            }
            if needle.chars().count() >= 4 && id.starts_with(&needle) {
                matches.push((rec.slug.clone(), rec.value.clone(), i));
            }
        }
    }
    match matches.len() {
        0 => Err(Error::ItemNotFound(reference.to_string())),
        1 => Ok(matches.remove(0)),
        _ => Err(Error::AmbiguousItem(reference.to_string())),
    }
}

/// Adiciona o item ao grupo (criado na hora se `group_ref` não resolve).
pub fn add_item_to_group(
    store: &Store,
    item: ReviewItem,
    group_ref: &str,
) -> Result<(String, ReviewItem)> {
    let slug = match store.resolve::<ReviewGroup>(group_ref) {
        Ok(s) => s,
        Err(Error::GroupNotFound(_)) => {
            let reference = group_ref.contains('/').then_some(group_ref);
            create_group(store, group_ref, None, vec![], reference)?.slug
        }
        Err(e) => return Err(e),
    };
    let mut group = store.load::<ReviewGroup>(&slug)?;
    group.items.push(item.clone());
    store.save(&slug, &group)?;
    Ok((slug, item))
}

/// Aplica `change` ao item e carimba `updatedAt`. Se `change` falha, nada é gravado.
pub fn update_item<F>(store: &Store, reference: &str, change: F) -> ReviewResult<ReviewItem>
where
    F: FnOnce(&mut ReviewItem) -> ReviewResult<()>,
{
    let (slug, mut group, index) = find_item(store, reference)?;
    change(&mut group.items[index])?;
    group.items[index].updated_at = Timestamp::now();
    store.save(&slug, &group)?;
    Ok(group.items.remove(index))
}

pub fn delete_item(store: &Store, reference: &str) -> Result<()> {
    let (slug, mut group, index) = find_item(store, reference)?;
    group.items.remove(index);
    store.save(&slug, &group)?;
    Ok(())
}

fn check_kind(store: &Store, kind: &str) -> ReviewResult<()> {
    let kinds: Vec<String> = store
        .project()?
        .review_kinds
        .into_iter()
        .map(|k| k.id)
        .collect();
    if kinds.iter().any(|k| k == kind) {
        Ok(())
    } else {
        Err(ReviewError::UnknownKind {
            kind: kind.to_string(),
            available: kinds,
        })
    }
}

fn resolve_topics(store: &Store, refs: &[String]) -> Result<Vec<String>> {
    refs.iter().map(|r| store.resolve::<RuleTopic>(r)).collect()
}

/// Dados de um item novo (referências de regras ainda não resolvidas).
#[derive(Debug, Clone)]
pub struct NewItem {
    pub kind: String,
    pub title: String,
    pub details: Option<String>,
    pub priority: ReviewPriority,
    pub target: ReviewTarget,
    pub rules: Vec<String>,
    pub author: Author,
}

/// `review add` / `add_review_item`: valida o kind, resolve as regras e grava (cria o grupo se preciso).
pub fn add_item(
    store: &Store,
    new: NewItem,
    group_ref: &str,
) -> ReviewResult<(String, ReviewItem)> {
    check_kind(store, &new.kind)?;
    let mut item = ReviewItem::new(new.kind, new.title);
    item.details = new.details;
    item.priority = new.priority;
    item.target = (!new.target.is_empty()).then_some(new.target);
    item.rules = resolve_topics(store, &new.rules)?;
    item.author = new.author;
    Ok(add_item_to_group(store, item, group_ref)?)
}

/// Mudanças de `review set` / `update_review_item`.
#[derive(Debug, Clone, Default)]
pub struct ItemUpdate {
    /// Substitui os tópicos (referências); `None` = não mexe. `Some(vec![])` limpa.
    pub rules: Option<Vec<String>>,
    /// Nome do status (`open|in_progress|done|wontfix`); inválido = `InvalidStatus`.
    pub status: Option<String>,
    pub priority: Option<ReviewPriority>,
    pub kind: Option<String>,
    pub title: Option<String>,
    pub details: Option<String>,
    /// `--force`: conclui sem o gate.
    pub force: bool,
}

/// Mesma sequência do Swift (write parcial possível): regras gravadas ANTES do gate e do resto; gate
/// quando o status é `done` (e sem `force`); kind validado; depois o restante num único `update_item`.
pub fn apply_update(
    store: &Store,
    reference: &str,
    change: ItemUpdate,
) -> ReviewResult<ReviewItem> {
    if let Some(refs) = &change.rules {
        let slugs = resolve_topics(store, refs)?;
        update_item(store, reference, |i| {
            i.rules = slugs;
            Ok(())
        })?;
    }
    if change.status.as_deref() == Some("done") && !change.force {
        gate::ensure_verified(store, reference)?;
    }
    if let Some(kind) = &change.kind {
        check_kind(store, kind)?;
    }
    update_item(store, reference, |item| {
        if let Some(s) = &change.status {
            item.status = parse_status(s).ok_or_else(|| ReviewError::InvalidStatus(s.clone()))?;
        }
        if let Some(p) = change.priority {
            item.priority = p;
        }
        if let Some(k) = &change.kind {
            item.kind = k.clone();
        }
        if let Some(t) = &change.title {
            item.title = t.clone();
        }
        if let Some(d) = &change.details {
            item.details = Some(d.clone());
        }
        Ok(())
    })
}
