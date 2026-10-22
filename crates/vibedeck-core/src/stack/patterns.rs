//! Padrões do projeto: `patterns` em `vibedeck.json` + o tópico de regras que cada um cria em `rules/`
//! (com `sourcePattern` apontando de volta), para o `rules_for` cobrar.

use std::collections::BTreeSet;

use super::catalog::{PatternCatalog, PatternTemplate};
use super::{Result, StackError, trim_non_empty, update_project};
use crate::error::Error;
use crate::model::{Author, ProjectPattern, Rule, RuleTopic};
use crate::slug;
use crate::store::{Record, Store};

/// Descrição do tópico de regras do padrão: o que ele é, mais a nota do projeto.
pub fn pattern_topic_description(pattern: &ProjectPattern) -> String {
    let mut parts: Vec<String> = Vec::new();
    if let Some(s) = pattern.summary.as_deref().and_then(trim_non_empty) {
        parts.push(s);
    }
    if let Some(n) = pattern.note.as_deref().and_then(trim_non_empty) {
        parts.push(format!("No projeto: {n}"));
    }
    if parts.is_empty() {
        format!("Padrão de projeto {}.", pattern.name)
    } else {
        parts.join("\n\n")
    }
}

fn clean_paths(paths: Option<&[String]>) -> Option<Vec<String>> {
    paths.map(|p| p.iter().filter_map(|s| trim_non_empty(s)).collect())
}

impl Store {
    /// Índice do padrão que `reference` nomeia: id exato, nome (sem caixa), catálogo, prefixo único do id.
    pub fn pattern_index(&self, reference: &str, patterns: &[ProjectPattern]) -> Result<usize> {
        let key = reference.trim();
        if let Some(i) = patterns.iter().position(|p| p.id == key) {
            return Ok(i);
        }
        let lower = key.to_lowercase();
        if let Some(i) = patterns.iter().position(|p| p.name.to_lowercase() == lower) {
            return Ok(i);
        }
        if let Some(t) = PatternCatalog::find(key)
            && let Some(i) = patterns.iter().position(|p| p.id == t.id)
        {
            return Ok(i);
        }
        let prefixed: Vec<usize> = (0..patterns.len())
            .filter(|&i| patterns[i].id.to_lowercase().starts_with(&lower))
            .collect();
        if prefixed.len() == 1 && !key.is_empty() {
            return Ok(prefixed[0]);
        }
        Err(StackError::PatternNotFound(reference.to_string()))
    }

    /// O tópico de regras que impõe o padrão, se ainda existe.
    pub fn pattern_topic(&self, pattern: &ProjectPattern) -> Option<Record<RuleTopic>> {
        let reference = pattern.topic.as_deref()?;
        self.find::<RuleTopic>(reference).ok()
    }

    fn update_topic(&self, reference: &str, change: impl FnOnce(&mut RuleTopic)) -> Result<()> {
        let mut rec = self.find::<RuleTopic>(reference)?;
        change(&mut rec.value);
        self.save_rule_topic(&rec.slug, &rec.value)?;
        Ok(())
    }

    /// Adiciona padrões do catálogo (ids, nomes ou aliases; qualquer desconhecido recusa tudo). Cada novo ganha
    /// seu tópico de regras, com escopo `paths` (vazio = projeto inteiro). Os existentes mantêm o lugar; uma
    /// nota/paths dada substitui a deles.
    pub fn add_patterns(
        &self,
        refs: &[String],
        note: Option<&str>,
        paths: Option<&[String]>,
        author: Author,
    ) -> Result<Vec<ProjectPattern>> {
        let templates = PatternCatalog::resolve(refs)?;
        templates
            .into_iter()
            .map(|t| self.add_template(t, note, paths, author))
            .collect()
    }

    fn add_template(
        &self,
        t: &PatternTemplate,
        note: Option<&str>,
        paths: Option<&[String]>,
        author: Author,
    ) -> Result<ProjectPattern> {
        let pattern = ProjectPattern {
            id: t.id.clone(),
            name: t.name.clone(),
            category: Some(t.category.clone()),
            summary: Some(t.summary.clone()),
            note: None,
            topic: None,
            tags: vec![],
            author,
        };
        let rules = t
            .rules
            .iter()
            .map(|r| {
                let mut rule = Rule::new(r.text.clone());
                rule.details = r.details.clone();
                rule.severity = r.severity;
                rule.author = author;
                rule
            })
            .collect();
        self.add_pattern(pattern, rules, note, paths)
    }

    /// Adiciona um padrão do próprio projeto, com uma regra `must` por entrada de `rules`.
    pub fn add_custom_pattern(
        &self,
        name: &str,
        summary: Option<&str>,
        rules: &[String],
        note: Option<&str>,
        paths: Option<&[String]>,
        author: Author,
    ) -> Result<ProjectPattern> {
        let name = trim_non_empty(name).ok_or(Error::InvalidName)?;
        let base = slug::make(&name);
        if base.is_empty() {
            return Err(Error::InvalidName.into());
        }
        let taken: BTreeSet<String> = self.project()?.patterns.into_iter().map(|p| p.id).collect();
        let mut id = base.clone();
        let mut n = 2;
        while taken.contains(&id) || PatternCatalog::all().iter().any(|t| t.id == id) {
            id = format!("{base}-{n}");
            n += 1;
        }
        let pattern = ProjectPattern {
            id,
            name,
            category: Some("custom".into()),
            summary: summary.and_then(trim_non_empty),
            note: None,
            topic: None,
            tags: vec![],
            author,
        };
        let rules = rules
            .iter()
            .filter_map(|r| trim_non_empty(r))
            .map(|text| {
                let mut rule = Rule::new(text);
                rule.author = author;
                rule
            })
            .collect();
        self.add_pattern(pattern, rules, note, paths)
    }

    fn add_pattern(
        &self,
        new: ProjectPattern,
        rules: Vec<Rule>,
        note: Option<&str>,
        paths: Option<&[String]>,
    ) -> Result<ProjectPattern> {
        let note = note.map(str::trim);
        let paths = clean_paths(paths);
        if let Some(existing) = self
            .project()?
            .patterns
            .into_iter()
            .find(|p| p.id == new.id)
        {
            let mut existing = existing;
            if let Some(note) = note {
                existing = self.set_pattern_note(&existing.id, Some(note))?;
            }
            if let Some(paths) = &paths {
                existing = self.set_pattern_paths(&existing.id, paths)?;
            }
            return Ok(existing);
        }
        let mut pattern = new;
        pattern.note = note.and_then(trim_non_empty);
        let mut topic = RuleTopic::new(format!("Padrão: {}", pattern.name));
        topic.description = Some(pattern_topic_description(&pattern));
        topic.tags = vec!["padrao".into()];
        topic.paths = paths.unwrap_or_default();
        topic.rules = rules;
        topic.source_pattern = Some(pattern.id.clone());
        let created = self.create(&topic, None)?;
        pattern.topic = Some(created.slug);
        update_project(self, |project| {
            project.patterns.push(pattern.clone());
            Ok(())
        })?;
        Ok(pattern)
    }

    /// Remove os padrões que `refs` nomeiam e apaga seus tópicos. Falha (sem remover nada) se algum é desconhecido.
    pub fn remove_patterns(&self, refs: &[String]) -> Result<Vec<ProjectPattern>> {
        let mut removed = Vec::new();
        update_project(self, |project| {
            let mut indices = BTreeSet::new();
            for r in refs {
                indices.insert(self.pattern_index(r, &project.patterns)?);
            }
            removed = indices
                .iter()
                .map(|&i| project.patterns[i].clone())
                .collect();
            let old = std::mem::take(&mut project.patterns);
            project.patterns = old
                .into_iter()
                .enumerate()
                .filter(|(i, _)| !indices.contains(i))
                .map(|(_, p)| p)
                .collect();
            Ok(())
        })?;
        for pattern in &removed {
            if let Some(rec) = self.pattern_topic(pattern) {
                self.delete_rule_topic(&rec.slug)?;
            }
        }
        Ok(removed)
    }

    /// Define (ou, com `None`/vazio, apaga) a nota do padrão e renova a descrição do tópico.
    pub fn set_pattern_note(&self, reference: &str, note: Option<&str>) -> Result<ProjectPattern> {
        let mut pattern = None;
        update_project(self, |project| {
            let i = self.pattern_index(reference, &project.patterns)?;
            project.patterns[i].note = note.and_then(trim_non_empty);
            pattern = Some(project.patterns[i].clone());
            Ok(())
        })?;
        let pattern = pattern.expect("padrão definido");
        if let Some(rec) = self.pattern_topic(&pattern) {
            let description = pattern_topic_description(&pattern);
            self.update_topic(&rec.slug, |t| t.description = Some(description))?;
        }
        Ok(pattern)
    }

    /// Substitui as tags do padrão (vazio remove).
    pub fn set_pattern_tags(&self, reference: &str, tags: &[String]) -> Result<ProjectPattern> {
        let mut pattern = None;
        update_project(self, |project| {
            let i = self.pattern_index(reference, &project.patterns)?;
            project.patterns[i].tags = tags.to_vec();
            pattern = Some(project.patterns[i].clone());
            Ok(())
        })?;
        Ok(pattern.expect("padrão definido"))
    }

    /// Restringe o tópico do padrão a `paths` (globs; vazio = projeto inteiro). O tópico é a fonte dos paths.
    pub fn set_pattern_paths(&self, reference: &str, paths: &[String]) -> Result<ProjectPattern> {
        let patterns = self.project()?.patterns;
        let pattern = patterns[self.pattern_index(reference, &patterns)?].clone();
        let Some(rec) = self.pattern_topic(&pattern) else {
            return Err(Error::TopicNotFound(
                pattern.topic.clone().unwrap_or_else(|| pattern.id.clone()),
            )
            .into());
        };
        let cleaned: Vec<String> = paths.iter().filter_map(|p| trim_non_empty(p)).collect();
        self.update_topic(&rec.slug, |t| t.paths = cleaned)?;
        Ok(pattern)
    }

    /// Move o padrão para `position` (a partir de 0, limitada ao intervalo).
    pub fn move_pattern(&self, reference: &str, position: i64) -> Result<()> {
        update_project(self, |project| {
            let i = self.pattern_index(reference, &project.patterns)?;
            let item = project.patterns.remove(i);
            let at = position.clamp(0, project.patterns.len() as i64) as usize;
            project.patterns.insert(at, item);
            Ok(())
        })?;
        Ok(())
    }

    /// Descarta padrões cujo tópico de regras já não existe (sem regras nada os cobra). Idempotente.
    /// Devolve os ids removidos. Quem apaga um tópico de regras deve chamar isto depois.
    pub fn release_orphaned_patterns(&self) -> Result<Vec<String>> {
        let Ok(project) = self.project() else {
            return Ok(vec![]);
        };
        if project.patterns.is_empty() {
            return Ok(vec![]);
        }
        let orphaned: Vec<String> = project
            .patterns
            .iter()
            .filter(|p| self.pattern_topic(p).is_none())
            .map(|p| p.id.clone())
            .collect();
        if orphaned.is_empty() {
            return Ok(vec![]);
        }
        update_project(self, |project| {
            project.patterns.retain(|p| !orphaned.contains(&p.id));
            Ok(())
        })?;
        Ok(orphaned)
    }
}
