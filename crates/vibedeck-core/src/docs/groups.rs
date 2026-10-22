//! Grupos de itens (`ItemGroups.swift`): diretórios de ideias/revisões/docs/skills, mover e renomear itens,
//! grupos de regras dentro de tópicos e recibos de desfazer.
//!
//! Skills são referenciadas por `nextSteps` e passos de workflow: ao mover/renomear uma skill as referências
//! `{"kind":"skill","ref":...}` em agents/commands/skills/workflows são reescritas, com rollback dos bytes se
//! algo falhar. Docs vinculados (D4) são movidos como links (o texto relativo é recalculado).

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::str::FromStr;

use serde::Serialize;
use serde_json::Value;

use crate::error::Error;
use crate::json;
use crate::model::{Idea, ReviewGroup, Rule, RuleTopic, Skill};
use crate::paths;
use crate::store::{Store, write_atomic};

use super::error::{DocError, Result};
use super::links::{self, LinkState};
use super::{doc_file, resolve_doc_slug};

/// `ItemConcept`: ideas | reviews | docs | skills.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ItemConcept {
    Ideas,
    Reviews,
    Docs,
    Skills,
}

impl ItemConcept {
    pub const ALL: [ItemConcept; 4] = [
        ItemConcept::Ideas,
        ItemConcept::Reviews,
        ItemConcept::Docs,
        ItemConcept::Skills,
    ];
    pub const NAMES: [&'static str; 4] = ["ideas", "reviews", "docs", "skills"];

    pub fn as_str(self) -> &'static str {
        match self {
            ItemConcept::Ideas => "ideas",
            ItemConcept::Reviews => "reviews",
            ItemConcept::Docs => "docs",
            ItemConcept::Skills => "skills",
        }
    }

    /// `fileExtension`: `md` para docs, `json` nos demais.
    pub fn file_extension(self) -> &'static str {
        if self == ItemConcept::Docs {
            "md"
        } else {
            "json"
        }
    }
}

impl FromStr for ItemConcept {
    type Err = ();
    fn from_str(s: &str) -> std::result::Result<Self, ()> {
        ItemConcept::ALL
            .into_iter()
            .find(|c| c.as_str() == s)
            .ok_or(())
    }
}

/// `ItemDirectory`: só o campo `path`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ItemDirectory {
    pub path: String,
}

/// `ProjectStore.groupPath(of:)`: referência sem o último componente.
pub fn group_path_of(reference: &str) -> String {
    let parts: Vec<&str> = reference.split('/').filter(|p| !p.is_empty()).collect();
    match parts.split_last() {
        Some((_, head)) => head.join("/"),
        None => String::new(),
    }
}

fn last_component(reference: &str) -> &str {
    reference
        .split('/')
        .rfind(|p| !p.is_empty())
        .unwrap_or(reference)
}

pub fn concept_dir(store: &Store, concept: ItemConcept) -> PathBuf {
    store.data_dir().join(concept.as_str())
}

fn contained(store: &Store, concept: ItemConcept, rel: &str) -> Result<PathBuf> {
    Ok(paths::contained(
        &store.data_dir(),
        &concept_dir(store, concept),
        rel,
    )?)
}

/// `validatedRecordURL` do conceito; em docs aceita o link D4 (devolve o caminho do link).
fn record_url(store: &Store, concept: ItemConcept, reference: &str) -> Result<PathBuf> {
    if concept == ItemConcept::Docs {
        return Ok(doc_file(store, reference)?.path().to_path_buf());
    }
    Ok(paths::validated_record_path(
        &store.data_dir(),
        &concept_dir(store, concept),
        reference,
        concept.file_extension(),
    )?)
}

fn relative_item_path(url: &Path, dir: &Path) -> String {
    let base = paths::canonical(dir);
    let path = paths::canonical(url);
    path.strip_prefix(&base)
        .map(|r| {
            r.components()
                .map(|c| c.as_os_str().to_string_lossy().into_owned())
                .collect::<Vec<_>>()
                .join("/")
        })
        .unwrap_or_default()
}

/// Caminho relativo a `base` (lexical, sem canonizar o final).
fn rel_lexical(base: &Path, path: &Path) -> Option<String> {
    path.strip_prefix(base).ok().map(|r| {
        r.components()
            .map(|c| c.as_os_str().to_string_lossy().into_owned())
            .collect::<Vec<_>>()
            .join("/")
    })
}

fn is_hidden(name: &std::ffi::OsStr) -> bool {
    name.to_string_lossy().starts_with('.')
}

// ---- diretórios ------------------------------------------------------------------------------------

/// `listItemDirectories`: nunca desce em symlink nem em ocultos; ordem alfabética.
pub fn list_item_directories(store: &Store, concept: ItemConcept) -> Result<Vec<ItemDirectory>> {
    let dir = concept_dir(store, concept);
    let base = paths::canonical(&dir);
    let mut out = Vec::new();
    let mut stack = vec![base.clone()];
    if !dir.is_dir() {
        return Ok(out);
    }
    while let Some(cur) = stack.pop() {
        let Ok(rd) = fs::read_dir(&cur) else { continue };
        for e in rd.flatten() {
            if is_hidden(&e.file_name()) {
                continue;
            }
            let p = e.path();
            let Ok(m) = fs::symlink_metadata(&p) else {
                continue;
            };
            if m.is_dir() && !m.file_type().is_symlink() {
                if let Some(rel) = rel_lexical(&base, &p) {
                    contained(store, concept, &rel)?;
                    out.push(ItemDirectory { path: rel });
                }
                stack.push(p);
            }
        }
    }
    out.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(out)
}

/// `createItemDirectory`: devolve o caminho normalizado.
pub fn create_item_directory(store: &Store, concept: ItemConcept, path: &str) -> Result<String> {
    let path = paths::normalize_group_path(path, false)?;
    let url = contained(store, concept, &path)?;
    if url.exists() {
        return Err(Error::GroupConflict(path).into());
    }
    fs::create_dir_all(&url).map_err(|e| DocError::io(&url, e))?;
    Ok(path)
}

/// `moveItemDirectory`: `to` é o novo caminho completo (mover e renomear).
pub fn move_item_directory(
    store: &Store,
    concept: ItemConcept,
    from: &str,
    to: &str,
) -> Result<()> {
    move_directory(store, concept, from, to, true)
}

fn move_directory(
    store: &Store,
    concept: ItemConcept,
    from: &str,
    to: &str,
    normalize_destination: bool,
) -> Result<()> {
    paths::normalize_group_path(from, false)?;
    let source = from;
    let normalized = paths::normalize_group_path(to, false)?;
    let target = if normalize_destination {
        normalized.as_str()
    } else {
        to
    };
    if target == source || target.starts_with(&format!("{source}/")) {
        return Err(DocError::invalid_path(to));
    }
    let dir = concept_dir(store, concept);
    let from_url = contained(store, concept, source)?;
    if !from_url.is_dir() {
        return Err(Error::GroupNotFound(from.to_string()).into());
    }
    validate_descendants(store, concept, &from_url)?;
    let to_url = contained(store, concept, target)?;
    let mapping = if concept == ItemConcept::Skills {
        record_slugs(&from_url, &dir, concept.file_extension())
            .into_iter()
            .map(|old| {
                let new = format!("{target}{}", &old[source.len()..]);
                (old, new)
            })
            .collect()
    } else {
        Vec::new()
    };
    rename(store, concept, &from_url, &to_url, &mapping)
}

/// Slugs (caminho relativo a `dir`, sem extensão) dos arquivos regulares sob `under`.
fn record_slugs(under: &Path, dir: &Path, ext: &str) -> Vec<String> {
    let base = paths::canonical(dir);
    let mut out = Vec::new();
    let mut stack = vec![paths::canonical(under)];
    while let Some(cur) = stack.pop() {
        let Ok(rd) = fs::read_dir(&cur) else { continue };
        for e in rd.flatten() {
            if is_hidden(&e.file_name()) {
                continue;
            }
            let p = e.path();
            let Ok(m) = fs::symlink_metadata(&p) else {
                continue;
            };
            if m.file_type().is_symlink() {
                continue;
            }
            if m.is_dir() {
                stack.push(p);
            } else if m.is_file()
                && p.extension()
                    .is_some_and(|x| x.to_string_lossy().eq_ignore_ascii_case(ext))
                && let Some(mut rel) = rel_lexical(&base, &p)
            {
                rel.truncate(rel.len() - ext.len() - 1);
                out.push(rel);
            }
        }
    }
    out.sort();
    out
}

/// Valida todo descendente antes de mexer (inclusive symlinks). Em docs, link D4 saudável ou quebrado vale.
fn validate_descendants(store: &Store, concept: ItemConcept, url: &Path) -> Result<()> {
    let dir = concept_dir(store, concept);
    let base = paths::canonical(&dir);
    let root_c = paths::canonical(store.root());
    let mut stack = vec![url.to_path_buf()];
    while let Some(cur) = stack.pop() {
        let Ok(rd) = fs::read_dir(&cur) else { continue };
        for e in rd.flatten() {
            let p = e.path();
            let Ok(m) = fs::symlink_metadata(&p) else {
                continue;
            };
            if m.file_type().is_symlink() {
                if concept == ItemConcept::Docs
                    && !matches!(links::link_state(&root_c, &p), LinkState::Rejected)
                {
                    continue;
                }
                let rel = rel_lexical(&base, &p).unwrap_or_else(|| relative_item_path(&p, &dir));
                contained(store, concept, &rel)?;
            } else if m.is_dir() {
                stack.push(p);
            }
        }
    }
    Ok(())
}

/// `moveGroupedItem`: move o item para o grupo `destination_group` ("" = raiz). Devolve o novo caminho.
pub fn move_grouped_item(
    store: &Store,
    concept: ItemConcept,
    reference: &str,
    destination_group: &str,
) -> Result<String> {
    let reference = resolve_grouped_reference(store, concept, reference)?;
    let group = paths::normalize_group_path(destination_group, true)?;
    let leaf = last_component(&reference);
    let target = if group.is_empty() {
        leaf.to_string()
    } else {
        format!("{group}/{leaf}")
    };
    if target == reference {
        return Ok(reference);
    }
    let from = record_url(store, concept, &reference)?;
    let to = record_url(store, concept, &target)?;
    rename(
        store,
        concept,
        &from,
        &to,
        &[(reference.clone(), target.clone())],
    )?;
    Ok(target)
}

/// `resolveGroupedReference`.
pub fn resolve_grouped_reference(
    store: &Store,
    concept: ItemConcept,
    reference: &str,
) -> Result<String> {
    Ok(match concept {
        ItemConcept::Ideas => store.resolve::<Idea>(reference)?,
        ItemConcept::Reviews => store.resolve::<ReviewGroup>(reference)?,
        ItemConcept::Skills => store.resolve::<Skill>(reference)?,
        ItemConcept::Docs => return resolve_doc_slug(store, reference),
    })
}

/// `deleteItemDirectory`: grupo não vazio exige `confirmed`. Links de docs somem; as origens ficam.
pub fn delete_item_directory(
    store: &Store,
    concept: ItemConcept,
    path: &str,
    confirmed: bool,
) -> Result<()> {
    paths::normalize_group_path(path, false)?;
    let url = contained(store, concept, path)?;
    if !url.is_dir() {
        return Err(Error::GroupNotFound(path.to_string()).into());
    }
    validate_descendants(store, concept, &url)?;
    let empty = fs::read_dir(&url)
        .map_err(|e| DocError::io(&url, e))?
        .next()
        .is_none();
    if !confirmed && !empty {
        return Err(DocError::GroupConfirmationRequired(path.to_string()));
    }
    fs::remove_dir_all(&url).map_err(|e| DocError::io(&url, e))
}

// ---- mover com referências --------------------------------------------------------------------------

type Update = (PathBuf, Vec<u8>, Vec<u8>);

fn rename(
    store: &Store,
    concept: ItemConcept,
    from: &Path,
    to: &Path,
    mapping: &[(String, String)],
) -> Result<()> {
    if fs::symlink_metadata(to).is_ok() {
        return Err(Error::GroupConflict(to.display().to_string()).into());
    }
    let updates = reference_updates(store, concept, mapping)?;
    let root_c = paths::canonical(store.root());
    let doc_links = if concept == ItemConcept::Docs {
        links::links_under(&root_c, from)
    } else {
        Vec::new()
    };
    if let Some(parent) = to.parent() {
        fs::create_dir_all(parent).map_err(|e| DocError::io(parent, e))?;
    }
    fs::rename(from, to).map_err(|e| DocError::io(from, e))?;
    relink_moved(&root_c, from, to, &doc_links);
    let mut applied: Vec<(PathBuf, Vec<u8>)> = Vec::new();
    let result: Result<()> = (|| {
        for (url, before, after) in &updates {
            let moved = match url.strip_prefix(from) {
                Ok(rest) if rest.as_os_str().is_empty() => to.to_path_buf(),
                Ok(rest) => to.join(rest),
                Err(_) => url.clone(),
            };
            applied.push((moved.clone(), before.clone()));
            write_atomic(&moved, after)?;
        }
        Ok(())
    })();
    if let Err(e) = result {
        for (url, bytes) in applied.iter().rev() {
            let _ = write_atomic(url, bytes);
        }
        if fs::rename(to, from).is_ok() {
            for (old, name) in &doc_links {
                links::relink(&root_c, old, name);
            }
        }
        return Err(e);
    }
    Ok(())
}

fn relink_moved(root_c: &Path, from: &Path, to: &Path, doc_links: &[(PathBuf, String)]) {
    for (old, name) in doc_links {
        let new = match old.strip_prefix(from) {
            Ok(rest) if rest.as_os_str().is_empty() => to.to_path_buf(),
            Ok(rest) => to.join(rest),
            Err(_) => continue,
        };
        links::relink(root_c, &new, name);
    }
}

/// Arquivos JSON (agents, commands, skills, workflows), recursivo, sem ocultos nem symlinks.
fn reference_files(store: &Store) -> Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    for name in ["agents", "commands", "skills", "workflows"] {
        let dir = store.data_dir().join(name);
        if !dir.is_dir() {
            continue;
        }
        paths::contained(&store.data_dir(), &dir, "")?;
        let mut stack = vec![paths::canonical(&dir)];
        while let Some(cur) = stack.pop() {
            let Ok(rd) = fs::read_dir(&cur) else { continue };
            for e in rd.flatten() {
                if is_hidden(&e.file_name()) {
                    continue;
                }
                let p = e.path();
                let Ok(m) = fs::symlink_metadata(&p) else {
                    continue;
                };
                if m.file_type().is_symlink() {
                    continue;
                }
                if m.is_dir() {
                    stack.push(p);
                } else if m.is_file()
                    && p.extension()
                        .is_some_and(|x| x.to_string_lossy().eq_ignore_ascii_case("json"))
                {
                    out.push(p);
                }
            }
        }
    }
    out.sort();
    Ok(out)
}

fn rewrite_refs(store: &Store, value: &Value, paths: &HashMap<&str, &str>) -> Value {
    match value {
        Value::Array(a) => Value::Array(a.iter().map(|v| rewrite_refs(store, v, paths)).collect()),
        Value::Object(o) => {
            let mut object = o.clone();
            if object.get("kind").and_then(Value::as_str) == Some("skill")
                && let Some(r) = object.get("ref").and_then(Value::as_str)
                && let Ok(old) = store.resolve::<Skill>(r)
                && let Some(new) = paths.get(old.as_str())
            {
                object.insert("ref".into(), Value::String((*new).to_string()));
            }
            let keys: Vec<String> = object.keys().cloned().collect();
            for k in keys {
                let v = rewrite_refs(store, &object[&k], paths);
                object.insert(k, v);
            }
            Value::Object(object)
        }
        other => other.clone(),
    }
}

/// Skills são referenciadas por id/título/slug: resolve antes de mover e reescreve só o que identifica um
/// item movido. Devolve `(arquivo, bytes antes, bytes depois)` só dos que mudam.
fn reference_updates(
    store: &Store,
    concept: ItemConcept,
    mapping: &[(String, String)],
) -> Result<Vec<Update>> {
    if concept != ItemConcept::Skills {
        return Ok(Vec::new());
    }
    let map: HashMap<&str, &str> = mapping
        .iter()
        .map(|(a, b)| (a.as_str(), b.as_str()))
        .collect();
    let mut result = Vec::new();
    for file in reference_files(store)? {
        let before = fs::read(&file).map_err(|e| DocError::io(&file, e))?;
        let object: Value = serde_json::from_slice(&before).map_err(|source| Error::Decode {
            path: file.clone(),
            source,
        })?;
        let after = rewrite_refs(store, &object, &map);
        if after != object {
            result.push((file, before, json::to_vdjson(&after).into_bytes()));
        }
    }
    Ok(result)
}

// ---- grupos de regras --------------------------------------------------------------------------------

fn find_rule(store: &Store, reference: &str) -> Result<(String, RuleTopic, usize)> {
    let needle = reference.trim().to_lowercase();
    let mut candidates = Vec::new();
    for rec in store.rule_topics()? {
        for (i, rule) in rec.value.rules.iter().enumerate() {
            candidates.push((rec.slug.clone(), i, rule.id.to_string().to_lowercase()));
        }
    }
    let pick = |slug: &str, i: usize| -> Result<(String, RuleTopic, usize)> {
        let topic = store.load::<RuleTopic>(slug)?;
        Ok((slug.to_string(), topic, i))
    };
    if let Some((slug, i, _)) = candidates.iter().find(|(_, _, id)| *id == needle) {
        return pick(slug, *i);
    }
    let matches: Vec<_> = if needle.chars().count() >= 4 {
        candidates
            .iter()
            .filter(|(_, _, id)| id.starts_with(&needle))
            .collect()
    } else {
        Vec::new()
    };
    match matches.as_slice() {
        [] => Err(DocError::RuleNotFound(reference.to_string())),
        [(slug, i, _)] => pick(slug, *i),
        _ => Err(DocError::AmbiguousRule(reference.to_string())),
    }
}

/// `moveRuleToGroup`: devolve a regra atualizada. `group` vazio = raiz do tópico.
pub fn move_rule_to_group(store: &Store, rule: &str, group: &str) -> Result<Rule> {
    let path = paths::normalize_group_path(group, true)?;
    let (slug, mut topic, index) = find_rule(store, rule)?;
    topic.rules[index].group = if path.is_empty() { None } else { Some(path) };
    store.save::<RuleTopic>(&slug, &topic)?;
    Ok(topic.rules[index].clone())
}

/// `ruleGroupRenamed`: novas regras com o grupo (e subgrupos) trocados.
pub fn rule_group_renamed(rules: &[Rule], from: &str, to: &str) -> Result<Vec<Rule>> {
    paths::normalize_group_path(from, false)?;
    let target = paths::normalize_group_path(to, false)?;
    if target == from || target.starts_with(&format!("{from}/")) {
        return Err(DocError::invalid_path(to));
    }
    let clash = rules.iter().any(|r| {
        let g = r.group.as_deref().unwrap_or("");
        g == target || g.starts_with(&format!("{target}/"))
    });
    if clash {
        return Err(Error::GroupConflict(target).into());
    }
    Ok(rules
        .iter()
        .map(|rule| {
            let mut moved = rule.clone();
            if let Some(g) = &rule.group
                && (g == from || g.starts_with(&format!("{from}/")))
            {
                moved.group = Some(format!("{target}{}", &g[from.len()..]));
            }
            moved
        })
        .collect())
}

/// `renameRuleGroup`.
pub fn rename_rule_group(store: &Store, topic: &str, from: &str, to: &str) -> Result<()> {
    let rec = store.find::<RuleTopic>(topic)?;
    let moved = rule_group_renamed(&rec.value.rules, from, to)?;
    let mut value = rec.value;
    value.rules = moved;
    store.save::<RuleTopic>(&rec.slug, &value)?;
    Ok(())
}

// ---- recibos (desfazer) ------------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct ReferenceChange {
    pub before_path: PathBuf,
    pub after_path: PathBuf,
    pub before: Vec<u8>,
    pub after: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct GroupMoveReceipt {
    pub concept: ItemConcept,
    pub source: String,
    pub destination: String,
    pub is_directory: bool,
    pub references: Vec<ReferenceChange>,
}

fn skill_reference_bytes(store: &Store, concept: ItemConcept) -> Result<Vec<(PathBuf, Vec<u8>)>> {
    if concept != ItemConcept::Skills {
        return Ok(Vec::new());
    }
    reference_files(store)?
        .into_iter()
        .map(|f| {
            let bytes = fs::read(&f).map_err(|e| DocError::io(&f, e))?;
            Ok((f, bytes))
        })
        .collect()
}

/// `moveWithReceipt`: move e guarda só as referências que mudaram, byte a byte, para desfazer.
pub fn move_with_receipt(
    store: &Store,
    concept: ItemConcept,
    reference: &str,
    destination: &str,
    directory: bool,
) -> Result<GroupMoveReceipt> {
    paths::normalize_group_path(reference, false)?;
    let source = if directory {
        reference.to_string()
    } else {
        resolve_grouped_reference(store, concept, reference)?
    };
    let source_url = if directory {
        contained(store, concept, &source)?
    } else {
        record_url(store, concept, &source)?
    };
    let before = skill_reference_bytes(store, concept)?;
    let target = if directory {
        move_item_directory(store, concept, &source, destination)?;
        paths::normalize_group_path(destination, false)?
    } else {
        move_grouped_item(store, concept, &source, destination)?
    };
    let target_url = if directory {
        contained(store, concept, &target)?
    } else {
        record_url(store, concept, &target)?
    };
    let mut changed = Vec::new();
    for (url, bytes) in before {
        let after_path = match url.strip_prefix(&source_url) {
            Ok(rest) if rest.as_os_str().is_empty() => target_url.clone(),
            Ok(rest) => target_url.join(rest),
            Err(_) => url.clone(),
        };
        let after = fs::read(&after_path).map_err(|e| DocError::io(&after_path, e))?;
        if after != bytes {
            changed.push(ReferenceChange {
                before_path: url,
                after_path,
                before: bytes,
                after,
            });
        }
    }
    Ok(GroupMoveReceipt {
        concept,
        source,
        destination: target,
        is_directory: directory,
        references: changed,
    })
}

fn validate_reference_url(store: &Store, url: &Path) -> Result<()> {
    for name in ["agents", "commands", "skills", "workflows"] {
        let dir = store.data_dir().join(name);
        let base = paths::canonical(&dir);
        let norm = paths::lexical_normalize(url);
        if let Ok(rest) = norm.strip_prefix(&base)
            && !rest.as_os_str().is_empty()
        {
            let rel = rest
                .components()
                .map(|c| c.as_os_str().to_string_lossy().into_owned())
                .collect::<Vec<_>>()
                .join("/");
            paths::contained(&store.data_dir(), &dir, &rel)?;
            return Ok(());
        }
    }
    Err(DocError::invalid_path(url.display().to_string()))
}

/// `undoGroupedMove`: nunca sobrescreve edição externa. Devolve o recibo inverso (refazer).
pub fn undo_grouped_move(store: &Store, receipt: &GroupMoveReceipt) -> Result<GroupMoveReceipt> {
    for change in &receipt.references {
        validate_reference_url(store, &change.before_path)?;
        validate_reference_url(store, &change.after_path)?;
        let current =
            fs::read(&change.after_path).map_err(|e| DocError::io(&change.after_path, e))?;
        if current != change.after {
            return Err(Error::GroupConflict(change.after_path.display().to_string()).into());
        }
    }
    if receipt.is_directory {
        move_directory(
            store,
            receipt.concept,
            &receipt.destination,
            &receipt.source,
            false,
        )?;
    } else {
        let from = record_url(store, receipt.concept, &receipt.destination)?;
        let to = record_url(store, receipt.concept, &receipt.source)?;
        rename(
            store,
            receipt.concept,
            &from,
            &to,
            &[(receipt.destination.clone(), receipt.source.clone())],
        )?;
    }
    for change in &receipt.references {
        write_atomic(&change.before_path, &change.before)?;
    }
    Ok(GroupMoveReceipt {
        concept: receipt.concept,
        source: receipt.destination.clone(),
        destination: receipt.source.clone(),
        is_directory: receipt.is_directory,
        references: receipt
            .references
            .iter()
            .map(|c| ReferenceChange {
                before_path: c.after_path.clone(),
                after_path: c.before_path.clone(),
                before: c.after.clone(),
                after: c.before.clone(),
            })
            .collect(),
    })
}
