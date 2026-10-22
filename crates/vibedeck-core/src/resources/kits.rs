//! Catálogo de kits embutido (`assets/kits/`) e instalação (`addKitItems`).
//!
//! Os itens instalados são registros comuns do projeto (agentes, comandos, skills e workflows).

use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

use super::error::{ResourceError, Result};
use super::persona::{self, NewPersona};
use crate::model::*;
use crate::{Error, Store, slug};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum KitItemKind {
    Agent,
    Command,
    Skill,
    Workflow,
}

impl KitItemKind {
    pub const ALL: [KitItemKind; 4] = [Self::Agent, Self::Command, Self::Skill, Self::Workflow];

    pub fn title(self) -> &'static str {
        match self {
            Self::Agent => "Agente",
            Self::Command => "Comando",
            Self::Skill => "Skill",
            Self::Workflow => "Workflow",
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Agent => "agent",
            Self::Command => "command",
            Self::Skill => "skill",
            Self::Workflow => "workflow",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KitCatalogItem {
    pub id: String,
    pub kind: KitItemKind,
    pub title: String,
    pub summary: String,
    pub prompt: String,
    pub next_steps: Vec<NextStep>,
    pub steps: Vec<WorkflowStep>,
}

impl KitCatalogItem {
    /// Ids do catálogo de que este item depende (alvos dos próximos passos e das etapas), ordenados.
    pub fn dependencies(&self) -> Vec<String> {
        let mut deps: Vec<String> = self
            .next_steps
            .iter()
            .map(|s| s.r#ref.clone())
            .chain(self.steps.iter().map(|s| s.r#ref.clone()))
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();
        deps.sort();
        deps
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CatalogKit {
    pub id: String,
    pub title: String,
    pub summary: String,
    pub items: Vec<KitCatalogItem>,
}

/// Item como está em `assets/kits/<kit>.json`: o prompt ainda sem a orientação comum.
#[derive(Deserialize)]
struct RawItem {
    kind: KitItemKind,
    title: String,
    summary: String,
    prompt: String,
    #[serde(default)]
    steps: Vec<WorkflowStep>,
}

#[derive(Deserialize)]
struct RawKit {
    id: String,
    title: String,
    summary: String,
    items: Vec<RawItem>,
}

const GUIDANCE: &str = include_str!("../../assets/kits/guidance.txt");
/// `AIPromptPolicy.instructions` (cópia; a área `ai` é a dona do texto original).
const POLICY: &str = include_str!("../../assets/kits/policy.txt");
const KIT_FILES: [&str; 2] = [
    include_str!("../../assets/kits/manutencao.json"),
    include_str!("../../assets/kits/novas-ferramentas.json"),
];

/// Os kits embutidos, na ordem do catálogo.
pub fn kits() -> &'static [CatalogKit] {
    static KITS: OnceLock<Vec<CatalogKit>> = OnceLock::new();
    KITS.get_or_init(|| {
        KIT_FILES
            .iter()
            .map(|text| {
                let raw: RawKit = serde_json::from_str(text).expect("assets/kits/*.json válidos");
                CatalogKit {
                    items: raw
                        .items
                        .into_iter()
                        .map(|i| KitCatalogItem {
                            id: format!("{}:{}", raw.id, i.kind.as_str()),
                            kind: i.kind,
                            title: i.title,
                            summary: i.summary,
                            prompt: format!("{}\n\n{GUIDANCE}\n\n{POLICY}", i.prompt),
                            next_steps: vec![],
                            steps: i.steps,
                        })
                        .collect(),
                    id: raw.id,
                    title: raw.title,
                    summary: raw.summary,
                }
            })
            .collect()
    })
}

/// Ids de kits selecionam todos os seus itens; ids de itens selecionam só o item (ordem do catálogo).
pub fn selection(refs: &[String]) -> Result<Vec<&'static KitCatalogItem>> {
    let all: Vec<&KitCatalogItem> = kits().iter().flat_map(|k| &k.items).collect();
    let mut ids: HashSet<&str> = HashSet::new();
    for r in refs {
        if let Some(kit) = kits().iter().find(|k| &k.id == r) {
            ids.extend(kit.items.iter().map(|i| i.id.as_str()));
        } else if all.iter().any(|i| &i.id == r) {
            ids.insert(r.as_str());
        } else {
            return Err(ResourceError::InvalidKitSelection(r.clone()));
        }
    }
    Ok(all
        .into_iter()
        .filter(|i| ids.contains(i.id.as_str()))
        .collect())
}

/// Dependências da seleção que ficaram de fora dela, ordenadas.
pub fn missing_dependencies(refs: &[String]) -> Result<Vec<String>> {
    let items = selection(refs)?;
    let ids: HashSet<&str> = items.iter().map(|i| i.id.as_str()).collect();
    let mut missing: Vec<String> = items
        .iter()
        .flat_map(|i| i.dependencies())
        .filter(|d| !ids.contains(d.as_str()))
        .collect::<HashSet<_>>()
        .into_iter()
        .collect();
    missing.sort();
    Ok(missing)
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InstalledKitItem {
    #[serde(rename = "catalogID")]
    pub catalog_id: String,
    pub kind: KitItemKind,
    pub slug: String,
}

fn delete_installed(store: &Store, item: &InstalledKitItem) {
    let _ = match item.kind {
        KitItemKind::Agent => store.delete_agent(&item.slug),
        KitItemKind::Command => store.delete_command(&item.slug),
        KitItemKind::Skill => store.delete_skill(&item.slug),
        KitItemKind::Workflow => store.delete_workflow(&item.slug),
    };
}

/// Valida toda a seleção antes de gravar. As referências são remapeadas para os slugs recém-criados, mesmo
/// quando já existe uma cópia anterior do kit; em caso de erro, desfaz só as criações desta operação.
pub fn add_kit_items(
    store: &Store,
    refs: &[String],
    author: Author,
) -> Result<Vec<InstalledKitItem>> {
    let items = selection(refs)?;
    if items.is_empty() {
        return Err(ResourceError::InvalidKitSelection("nenhum item".into()));
    }
    let missing = missing_dependencies(refs)?;
    if !missing.is_empty() {
        return Err(ResourceError::MissingKitDependencies(missing));
    }
    let mut created: Vec<InstalledKitItem> = Vec::new();
    match install(store, &items, author, &mut created) {
        Ok(()) => Ok(created),
        Err(e) => {
            for item in created.iter().rev() {
                delete_installed(store, item);
            }
            Err(e)
        }
    }
}

fn install(
    store: &Store,
    items: &[&KitCatalogItem],
    author: Author,
    created: &mut Vec<InstalledKitItem>,
) -> Result<()> {
    for item in items {
        let base = NewPersona {
            title: item.title.clone(),
            summary: Some(item.summary.clone()),
            prompt: item.prompt.clone(),
            tags: vec!["kit".into()],
            author,
            ..NewPersona::default()
        };
        let slug = match item.kind {
            KitItemKind::Agent => persona::create::<Agent>(store, base)?.slug,
            KitItemKind::Command => {
                persona::create::<Command>(
                    store,
                    NewPersona {
                        argument_hint: Some("<objetivo>".into()),
                        ..base
                    },
                )?
                .slug
            }
            KitItemKind::Skill => persona::create::<Skill>(store, base)?.slug,
            KitItemKind::Workflow => create_workflow(store, item, author)?,
        };
        created.push(InstalledKitItem {
            catalog_id: item.id.clone(),
            kind: item.kind,
            slug,
        });
    }
    let mapping: HashMap<&str, &str> = created
        .iter()
        .map(|c| (c.catalog_id.as_str(), c.slug.as_str()))
        .collect();
    let target = |r: &str| -> Result<String> {
        mapping
            .get(r)
            .map(|s| s.to_string())
            .ok_or_else(|| ResourceError::MissingKitDependencies(vec![r.to_string()]))
    };
    for (item, installed) in items.iter().zip(created.iter()) {
        let next = item
            .next_steps
            .iter()
            .map(|s| {
                Ok(NextStep {
                    kind: s.kind,
                    r#ref: target(&s.r#ref)?,
                    note: s.note.clone(),
                })
            })
            .collect::<Result<Vec<_>>>()?;
        match item.kind {
            KitItemKind::Agent if !next.is_empty() => {
                persona::update::<Agent>(store, &installed.slug, |f| {
                    *f.next_steps = next.clone();
                    Ok(())
                })?;
            }
            KitItemKind::Command if !next.is_empty() => {
                persona::update::<Command>(store, &installed.slug, |f| {
                    *f.next_steps = next.clone();
                    Ok(())
                })?;
            }
            KitItemKind::Skill if !next.is_empty() => {
                persona::update::<Skill>(store, &installed.slug, |f| {
                    *f.next_steps = next.clone();
                    Ok(())
                })?;
            }
            KitItemKind::Workflow => {
                let steps = item
                    .steps
                    .iter()
                    .map(|s| {
                        let mut s = s.clone();
                        s.r#ref = target(&s.r#ref)?;
                        Ok(s)
                    })
                    .collect::<Result<Vec<_>>>()?;
                let mut w = store.load::<Workflow>(&installed.slug)?;
                w.steps = steps;
                w.updated_at = Timestamp::now();
                store.ensure_directories()?;
                store.save::<Workflow>(&installed.slug, &w)?;
            }
            _ => {}
        }
    }
    Ok(())
}

/// `createWorkflow(title:summary:input:maxSteps:tags:author:)` do kit.
fn create_workflow(store: &Store, item: &KitCatalogItem, author: Author) -> Result<String> {
    let title = item.title.trim();
    if title.is_empty() {
        return Err(Error::InvalidName.into());
    }
    let mut w = Workflow::new(title);
    w.summary = Some(item.summary.clone());
    w.input = Some("<objetivo e critérios de aceite>".into());
    w.max_steps = Some(10);
    w.tags = vec!["kit".into()];
    w.author = author;
    let slug = slug::unique(&slug::make(title), &store.dir::<Workflow>(), "json");
    store.ensure_directories()?;
    store.save::<Workflow>(&slug, &w)?;
    Ok(slug)
}
