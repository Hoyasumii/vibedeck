//! `status` (CLI) e `get_project` (MCP): resumos do projeto.

use serde::Serialize;

use super::{Result, markdown};
use crate::model::{
    Agent, Command, Idea, IdeaStatus, Project, ReviewGroup, RuleTopic, Skill, Workflow,
};
use crate::store::Store;

#[derive(Debug, Clone, Serialize)]
pub struct GroupSummary {
    pub slug: String,
    pub title: String,
    pub open: usize,
    pub total: usize,
}

/// Objeto `--json` de `status` (chaves em camelCase; o emissor VDJSON ordena).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    pub root: String,
    pub project: Project,
    pub docs: Vec<String>,
    pub groups: Vec<GroupSummary>,
    pub rule_topics: Vec<String>,
    pub ideas: Vec<String>,
    pub agents: Vec<String>,
    pub commands: Vec<String>,
    pub skills: Vec<String>,
    pub workflows: Vec<String>,
}

/// Resumo mais as contagens que só o texto usa.
#[derive(Debug, Clone)]
pub struct Status {
    pub summary: Summary,
    pub rule_count: usize,
    pub open_ideas: usize,
}

pub fn open_count(group: &ReviewGroup) -> usize {
    group.items.iter().filter(|i| !i.status.is_closed()).count()
}

pub fn status(store: &Store) -> Result<Status> {
    let project = store.project()?;
    let docs = markdown::list_docs(store)?;
    let groups = store.list::<ReviewGroup>()?;
    let topics = store.list::<RuleTopic>()?;
    let ideas = store.list::<Idea>()?;
    let rule_count = topics.iter().map(|t| t.value.rules.len()).sum();
    let open_ideas = ideas
        .iter()
        .filter(|i| !matches!(i.value.status, IdeaStatus::Discarded | IdeaStatus::Done))
        .count();
    let summary = Summary {
        root: store.root().display().to_string(),
        project,
        docs: docs.into_iter().map(|d| d.slug).collect(),
        groups: groups
            .iter()
            .map(|g| GroupSummary {
                slug: g.slug.clone(),
                title: g.value.title.clone(),
                open: open_count(&g.value),
                total: g.value.items.len(),
            })
            .collect(),
        rule_topics: topics.into_iter().map(|t| t.slug).collect(),
        ideas: ideas.into_iter().map(|i| i.slug).collect(),
        agents: store.list::<Agent>()?.into_iter().map(|r| r.slug).collect(),
        commands: store
            .list::<Command>()?
            .into_iter()
            .map(|r| r.slug)
            .collect(),
        skills: store.list::<Skill>()?.into_iter().map(|r| r.slug).collect(),
        workflows: store
            .list::<Workflow>()?
            .into_iter()
            .map(|r| r.slug)
            .collect(),
    };
    Ok(Status {
        summary,
        rule_count,
        open_ideas,
    })
}

impl Status {
    /// Linhas da saída de texto (cada uma vira um `println`; a segunda linha em branco é "\nLinks: …").
    pub fn text_lines(&self) -> Vec<String> {
        let s = &self.summary;
        let p = &s.project;
        let mut out = vec![format!("{} — {}", p.name, s.root)];
        if let Some(d) = &p.description {
            out.push(d.clone());
        }
        if !p.stack.is_empty() {
            let names: Vec<&str> = p.stack.iter().map(|i| i.name.as_str()).collect();
            out.push(format!("Stack: {}", names.join(", ")));
        }
        if !p.patterns.is_empty() {
            let names: Vec<&str> = p.patterns.iter().map(|i| i.name.as_str()).collect();
            out.push(format!("Padrões: {}", names.join(", ")));
        }
        out.push(format!(
            "\nLinks: {}  Docs: {}  Grupos de revisão: {}",
            p.links.len(),
            s.docs.len(),
            s.groups.len()
        ));
        for g in &s.groups {
            out.push(format!(
                "  • {} [{}] — {} aberto(s) de {}",
                g.title, g.slug, g.open, g.total
            ));
        }
        out.push(format!(
            "Tópicos de regras: {} ({} regra(s))  Ideias: {} ({} abertas)  Agentes: {}  Comandos: {}  Skills: {}  Workflows: {}",
            s.rule_topics.len(),
            self.rule_count,
            s.ideas.len(),
            self.open_ideas,
            s.agents.len(),
            s.commands.len(),
            s.skills.len(),
            s.workflows.len()
        ));
        out
    }
}

/// Resultado da tool `get_project`: `open`/`total` são TEXTO (como o `[String: String]` do Swift).
#[derive(Debug, Clone, Serialize)]
pub struct Overview {
    pub root: String,
    pub project: Project,
    pub docs: Vec<String>,
    pub groups: Vec<OverviewGroup>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OverviewGroup {
    pub slug: String,
    pub title: String,
    pub open: String,
    pub total: String,
}

pub fn overview(store: &Store) -> Result<Overview> {
    let groups = store
        .list::<ReviewGroup>()?
        .into_iter()
        .map(|g| OverviewGroup {
            open: open_count(&g.value).to_string(),
            total: g.value.items.len().to_string(),
            slug: g.slug,
            title: g.value.title,
        })
        .collect();
    let project = store.project()?;
    let docs = markdown::list_docs(store)?
        .into_iter()
        .map(|d| d.slug)
        .collect();
    Ok(Overview {
        root: store.root().display().to_string(),
        project,
        docs,
        groups,
    })
}
