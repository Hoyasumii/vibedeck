//! Agentes, comandos e skills: mesmo formato, mesmas operações (criar, editar, próximos passos).
//!
//! `Persona` abstrai os três tipos; as funções genéricas valem para todos e os wrappers por tipo ficam em
//! `mod.rs`. Espelha `createAgent/updateAgent/addNextStep...` de `ProjectStore.swift`.

use serde_json::{Map, Value};

use super::error::{ResourceError, Result};
use crate::model::*;
use crate::store::{Record, Stored};
use crate::{Error, Store};

/// Acesso mutável aos campos comuns; `argument_hint` só existe em comandos e `source_path` só em skills.
pub struct Fields<'a> {
    pub title: &'a mut String,
    pub summary: &'a mut Option<String>,
    pub model: &'a mut Option<String>,
    pub provider_settings: &'a mut Option<ProviderSettingsMap>,
    pub tools: &'a mut Vec<String>,
    pub prompt: &'a mut String,
    pub next_steps: &'a mut Vec<NextStep>,
    pub tags: &'a mut Vec<String>,
    pub author: &'a mut Author,
    pub updated_at: &'a mut Timestamp,
    pub argument_hint: Option<&'a mut Option<String>>,
    pub source_path: Option<&'a mut Option<String>>,
}

/// Visão somente leitura dos campos comuns.
pub struct View<'a> {
    pub title: &'a str,
    pub summary: Option<&'a str>,
    pub argument_hint: Option<&'a str>,
    pub model: Option<&'a str>,
    pub tools: &'a [String],
    pub prompt: &'a str,
    pub next_steps: &'a [NextStep],
    pub tags: &'a [String],
}

pub trait Persona: Stored + Clone {
    const KIND: NextStepKind;
    fn blank(title: &str) -> Self;
    fn fields(&mut self) -> Fields<'_>;
    fn view(&self) -> View<'_>;
    fn next_steps(&self) -> &[NextStep] {
        self.view().next_steps
    }
}

// Uma implementação por tipo: `argument_hint` e `source_path` só existem em alguns.
impl Persona for Agent {
    const KIND: NextStepKind = NextStepKind::Agent;
    fn blank(title: &str) -> Self {
        Agent::new(title)
    }
    fn fields(&mut self) -> Fields<'_> {
        Fields {
            title: &mut self.title,
            summary: &mut self.summary,
            model: &mut self.model,
            provider_settings: &mut self.provider_settings,
            tools: &mut self.tools,
            prompt: &mut self.prompt,
            next_steps: &mut self.next_steps,
            tags: &mut self.tags,
            author: &mut self.author,
            updated_at: &mut self.updated_at,
            argument_hint: None,
            source_path: None,
        }
    }
    fn view(&self) -> View<'_> {
        View {
            title: &self.title,
            summary: self.summary.as_deref(),
            argument_hint: None,
            model: self.model.as_deref(),
            tools: &self.tools,
            prompt: &self.prompt,
            next_steps: &self.next_steps,
            tags: &self.tags,
        }
    }
}

impl Persona for Command {
    const KIND: NextStepKind = NextStepKind::Command;
    fn blank(title: &str) -> Self {
        Command::new(title)
    }
    fn fields(&mut self) -> Fields<'_> {
        Fields {
            title: &mut self.title,
            summary: &mut self.summary,
            model: &mut self.model,
            provider_settings: &mut self.provider_settings,
            tools: &mut self.tools,
            prompt: &mut self.prompt,
            next_steps: &mut self.next_steps,
            tags: &mut self.tags,
            author: &mut self.author,
            updated_at: &mut self.updated_at,
            argument_hint: Some(&mut self.argument_hint),
            source_path: None,
        }
    }
    fn view(&self) -> View<'_> {
        View {
            title: &self.title,
            summary: self.summary.as_deref(),
            argument_hint: self.argument_hint.as_deref(),
            model: self.model.as_deref(),
            tools: &self.tools,
            prompt: &self.prompt,
            next_steps: &self.next_steps,
            tags: &self.tags,
        }
    }
}

impl Persona for Skill {
    const KIND: NextStepKind = NextStepKind::Skill;
    fn blank(title: &str) -> Self {
        Skill::new(title)
    }
    fn fields(&mut self) -> Fields<'_> {
        Fields {
            title: &mut self.title,
            summary: &mut self.summary,
            model: &mut self.model,
            provider_settings: &mut self.provider_settings,
            tools: &mut self.tools,
            prompt: &mut self.prompt,
            next_steps: &mut self.next_steps,
            tags: &mut self.tags,
            author: &mut self.author,
            updated_at: &mut self.updated_at,
            argument_hint: None,
            source_path: Some(&mut self.source_path),
        }
    }
    fn view(&self) -> View<'_> {
        View {
            title: &self.title,
            summary: self.summary.as_deref(),
            argument_hint: None,
            model: self.model.as_deref(),
            tools: &self.tools,
            prompt: &self.prompt,
            next_steps: &self.next_steps,
            tags: &self.tags,
        }
    }
}

/// Dados de criação (`createAgent(title:summary:model:tools:prompt:tags:author:)` e variantes).
#[derive(Debug, Clone, Default)]
pub struct NewPersona {
    pub title: String,
    pub summary: Option<String>,
    pub argument_hint: Option<String>,
    pub model: Option<String>,
    pub tools: Vec<String>,
    pub prompt: String,
    pub tags: Vec<String>,
    pub author: Author,
    /// Só skills: caminho completo `grupo/slug`.
    pub reference: Option<String>,
}

/// Grava garantindo as pastas do projeto (`ensureDirectories`).
pub fn save<P: Persona>(store: &Store, slug: &str, value: &P) -> Result<bool> {
    store.ensure_directories()?;
    Ok(store.save::<P>(slug, value)?)
}

pub fn create<P: Persona>(store: &Store, new: NewPersona) -> Result<Record<P>> {
    let title = new.title.trim().to_string();
    if title.is_empty() {
        return Err(Error::InvalidName.into());
    }
    let mut value = P::blank(&title);
    {
        let f = value.fields();
        *f.summary = new.summary;
        *f.model = new.model;
        *f.tools = new.tools;
        *f.prompt = new.prompt;
        *f.tags = new.tags;
        *f.author = new.author;
        if let Some(hint) = f.argument_hint {
            *hint = new.argument_hint;
        }
    }
    let reference = if P::KIND == NextStepKind::Skill {
        new.reference.as_deref()
    } else {
        None
    };
    let slug = store.new_slug::<P>(&title, reference)?;
    save(store, &slug, &value)?;
    Ok(Record { slug, value })
}

/// Resolve `reference` (slug, id/prefixo, título), aplica `change`, atualiza `updatedAt` e grava.
pub fn update<P: Persona>(
    store: &Store,
    reference: &str,
    change: impl FnOnce(&mut Fields<'_>) -> Result<()>,
) -> Result<Record<P>> {
    let slug = store.resolve::<P>(reference)?;
    let mut value = store.load::<P>(&slug)?;
    {
        let mut f = value.fields();
        change(&mut f)?;
        *f.updated_at = Timestamp::now();
    }
    save(store, &slug, &value)?;
    Ok(Record { slug, value })
}

fn kind_noun(kind: NextStepKind) -> &'static str {
    match kind {
        NextStepKind::Agent => "um agente",
        NextStepKind::Command => "um comando",
        NextStepKind::Skill => "uma skill",
    }
}

/// Slug de um agente, comando ou skill existente do VibeDeck.
pub fn resolve_step_target(store: &Store, kind: NextStepKind, target: &str) -> Result<String> {
    Ok(match kind {
        NextStepKind::Agent => store.resolve::<Agent>(target)?,
        NextStepKind::Command => store.resolve::<Command>(target)?,
        NextStepKind::Skill => store.resolve::<Skill>(target)?,
    })
}

/// `addNextStep`: o alvo precisa existir e não pode ser o próprio dono; duplicata `(kind, ref)` é ignorada.
pub fn add_next_step<P: Persona>(
    store: &Store,
    reference: &str,
    kind: NextStepKind,
    target: &str,
    note: Option<&str>,
) -> Result<Record<P>> {
    let from = store.resolve::<P>(reference)?;
    let stored = resolve_step_target(store, kind, target)?;
    if kind == P::KIND && stored == from {
        return Err(ResourceError::InvalidNextStep(format!(
            "{} não pode ser o próximo passo de si mesmo.",
            kind_noun(kind)
        )));
    }
    let note = note.map(|n| n.trim().to_string()).filter(|n| !n.is_empty());
    update::<P>(store, &from, |f| {
        if !f
            .next_steps
            .iter()
            .any(|s| s.kind == kind && s.r#ref == stored)
        {
            f.next_steps.push(NextStep {
                kind,
                r#ref: stored.clone(),
                note: note.clone(),
            });
        }
        Ok(())
    })
}

/// `unnext`: remove os passos cujo `ref` está em {texto dado, slugs resolvidos de agente/comando/skill}.
pub fn remove_next_step<P: Persona>(
    store: &Store,
    reference: &str,
    target: &str,
) -> Result<Record<P>> {
    let mut targets = vec![target.to_string()];
    if let Ok(s) = store.resolve::<Agent>(target) {
        targets.push(s);
    }
    if let Ok(s) = store.resolve::<Command>(target) {
        targets.push(s);
    }
    if let Ok(s) = store.resolve::<Skill>(target) {
        targets.push(s);
    }
    update::<P>(store, reference, |f| {
        f.next_steps.retain(|s| !targets.contains(&s.r#ref));
        Ok(())
    })
}

/// `''` ou só espaços viram `None` (`nonEmptyOrNil`).
pub fn non_empty_or_nil(s: &str) -> Option<String> {
    (!s.trim().is_empty()).then(|| s.to_string())
}

/// Edição por provedor (`--provider`): `model`/`effort` vão para `providerSettings[provedor]`; sem provedor,
/// `--model` altera o `model` legado.
pub fn set_provider_or_model(
    f: &mut Fields<'_>,
    provider: Option<&str>,
    model: Option<&str>,
    effort: Option<&str>,
) {
    if let Some(provider) = provider {
        let all = f.provider_settings.get_or_insert_with(Default::default);
        let settings = all.entry(provider.to_string()).or_default();
        if let Some(m) = model {
            settings.model = non_empty_or_nil(m);
        }
        if let Some(e) = effort {
            settings.effort = non_empty_or_nil(e);
        }
    } else if let Some(m) = model {
        *f.model = non_empty_or_nil(m);
    }
}

/// Registro como objeto JSON + `slug` (`SlugAnd`).
pub fn with_slug<T: serde::Serialize>(slug: &str, value: &T) -> Value {
    let mut v = serde_json::to_value(value).unwrap_or(Value::Null);
    if let Value::Object(m) = &mut v {
        m.insert("slug".into(), Value::String(slug.to_string()));
    }
    v
}

/// Registro + `slug` + `group` (`GroupedRecord`, skills).
pub fn with_slug_and_group<T: serde::Serialize>(slug: &str, value: &T) -> Value {
    let mut v = with_slug(slug, value);
    if let Value::Object(m) = &mut v {
        m.insert("group".into(), Value::String(group_path(slug)));
    }
    v
}

/// `ProjectStore.groupPath(of:)`: tudo antes do último componente.
pub fn group_path(slug: &str) -> String {
    let parts: Vec<&str> = slug.split('/').filter(|p| !p.is_empty()).collect();
    match parts.split_last() {
        Some((_, rest)) => rest.join("/"),
        None => String::new(),
    }
}

/// Linhas resumidas de `list_agents|list_commands|list_skills` (MCP).
pub fn mcp_row<P: Persona>(slug: &str, value: &P) -> Value {
    let v = value.view();
    let mut m = Map::new();
    if P::KIND == NextStepKind::Skill {
        m.insert("group".into(), Value::String(group_path(slug)));
    }
    m.insert("slug".into(), Value::String(slug.to_string()));
    m.insert("title".into(), Value::String(v.title.to_string()));
    if P::KIND == NextStepKind::Command
        && let Some(h) = v.argument_hint
    {
        m.insert("argumentHint".into(), Value::String(h.to_string()));
    }
    if P::KIND == NextStepKind::Skill
        && let Some(s) = v.summary
    {
        m.insert("summary".into(), Value::String(s.to_string()));
    }
    if let Some(model) = v.model {
        m.insert("model".into(), Value::String(model.to_string()));
    }
    m.insert("tags".into(), serde_json::json!(v.tags));
    m.insert(
        "nextSteps".into(),
        serde_json::to_value(v.next_steps).unwrap_or(Value::Null),
    );
    Value::Object(m)
}
