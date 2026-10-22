//! `tag` (CLI) e `set_tags` (MCP): substitui as tags de um registro; lista vazia remove.

use super::{ProjectError, Result, markdown};
use crate::model::{Agent, Command, Idea, ReviewGroup, RuleTopic, Skill, Timestamp, Workflow};
use crate::store::{Store, Stored};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TagKind {
    Doc,
    ReviewGroup,
    RuleTopic,
    Idea,
    Agent,
    Command,
    Skill,
    Workflow,
    Stack,
    Pattern,
}

impl TagKind {
    /// Nomes do CLI: `doc review rules idea agent command skill workflow stack pattern`.
    pub fn from_cli(text: &str) -> Option<TagKind> {
        Some(match text {
            "doc" => TagKind::Doc,
            "review" => TagKind::ReviewGroup,
            "rules" => TagKind::RuleTopic,
            "idea" => TagKind::Idea,
            "agent" => TagKind::Agent,
            "command" => TagKind::Command,
            "skill" => TagKind::Skill,
            "workflow" => TagKind::Workflow,
            "stack" => TagKind::Stack,
            "pattern" => TagKind::Pattern,
            _ => return None,
        })
    }

    /// Nomes do MCP: `doc review_group rule_topic idea agent command skill workflow stack pattern`.
    pub fn from_mcp(text: &str) -> Option<TagKind> {
        match text {
            "review_group" => Some(TagKind::ReviewGroup),
            "rule_topic" => Some(TagKind::RuleTopic),
            "review" | "rules" => None,
            other => Self::from_cli(other),
        }
    }
}

/// Objetos com `tags` e, em alguns, `updatedAt` (o Swift atualiza `updatedAt` ao salvar).
fn retag<T: Stored>(
    store: &Store,
    reference: &str,
    tags: &[String],
    set: impl FnOnce(&mut T, &[String]),
) -> Result<()> {
    let mut record = store.find::<T>(reference)?;
    set(&mut record.value, tags);
    store.save::<T>(&record.slug, &record.value)?;
    Ok(())
}

pub fn set_tags(store: &Store, kind: TagKind, reference: &str, tags: &[String]) -> Result<()> {
    match kind {
        TagKind::Doc => markdown::set_doc_tags(store, reference, tags)?,
        TagKind::ReviewGroup => retag::<ReviewGroup>(store, reference, tags, |g, t| {
            g.tags = t.to_vec();
        })?,
        TagKind::RuleTopic => retag::<RuleTopic>(store, reference, tags, |g, t| {
            g.tags = t.to_vec();
        })?,
        TagKind::Idea => retag::<Idea>(store, reference, tags, |g, t| {
            g.tags = t.to_vec();
            g.updated_at = Timestamp::now();
        })?,
        TagKind::Agent => retag::<Agent>(store, reference, tags, |g, t| {
            g.tags = t.to_vec();
            g.updated_at = Timestamp::now();
        })?,
        TagKind::Command => retag::<Command>(store, reference, tags, |g, t| {
            g.tags = t.to_vec();
            g.updated_at = Timestamp::now();
        })?,
        TagKind::Skill => retag::<Skill>(store, reference, tags, |g, t| {
            g.tags = t.to_vec();
            g.updated_at = Timestamp::now();
        })?,
        TagKind::Workflow => retag::<Workflow>(store, reference, tags, |g, t| {
            g.tags = t.to_vec();
            g.updated_at = Timestamp::now();
        })?,
        TagKind::Stack => {
            let mut project = store.project()?;
            let i = stack_index(reference, &project)?;
            project.stack[i].tags = tags.to_vec();
            store.save_project(&project)?;
        }
        TagKind::Pattern => {
            let mut project = store.project()?;
            let i = pattern_index(reference, &project)?;
            project.patterns[i].tags = tags.to_vec();
            store.save_project(&project)?;
        }
    }
    Ok(())
}

/// Texto de saída: `Tags removidas.` ou `Tags: a, b`.
pub fn message(tags: &[String]) -> String {
    if tags.is_empty() {
        "Tags removidas.".into()
    } else {
        format!("Tags: {}", tags.join(", "))
    }
}

fn trim_blank(s: &str) -> &str {
    s.trim_matches([' ', '\t'])
}

/// `stackIndex`: ícone exato, depois nome (sem caixa), depois prefixo único do ícone.
fn stack_index(reference: &str, project: &crate::model::Project) -> Result<usize> {
    let key = trim_blank(reference);
    let stack = &project.stack;
    if let Some(i) = stack.iter().position(|s| s.icon == key) {
        return Ok(i);
    }
    if let Some(i) = stack
        .iter()
        .position(|s| s.name.to_lowercase() == key.to_lowercase())
    {
        return Ok(i);
    }
    let prefixed: Vec<usize> = (0..stack.len())
        .filter(|&i| {
            stack[i]
                .icon
                .to_lowercase()
                .starts_with(&key.to_lowercase())
        })
        .collect();
    if prefixed.len() == 1 && !key.is_empty() {
        return Ok(prefixed[0]);
    }
    Err(ProjectError::StackItemNotFound(reference.to_string()))
}

/// `patternIndex` sem o passo do catálogo embutido (apelidos do catálogo ficam com a área de padrões):
/// id exato, nome (sem caixa), prefixo único do id.
fn pattern_index(reference: &str, project: &crate::model::Project) -> Result<usize> {
    let key = reference.trim_matches(|c: char| c.is_whitespace());
    let patterns = &project.patterns;
    if let Some(i) = patterns.iter().position(|p| p.id == key) {
        return Ok(i);
    }
    if let Some(i) = patterns
        .iter()
        .position(|p| p.name.to_lowercase() == key.to_lowercase())
    {
        return Ok(i);
    }
    let prefixed: Vec<usize> = (0..patterns.len())
        .filter(|&i| {
            patterns[i]
                .id
                .to_lowercase()
                .starts_with(&key.to_lowercase())
        })
        .collect();
    if prefixed.len() == 1 && !key.is_empty() {
        return Ok(prefixed[0]);
    }
    Err(ProjectError::PatternNotFound(reference.to_string()))
}
