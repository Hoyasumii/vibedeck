//! Importação local de agentes, comandos e skills dos provedores (`.claude/*`, `.codex/*`) e descoberta
//! (`discover`) dos que existem na pasta do projeto, usada pelo início guiado.
//!
//! Só lê arquivos: a listagem de skills do Codex por `codex app-server` fica com a área `ai`
//! (`import_skill_files` aplica a lista que ela obtiver).

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use super::error::{ResourceError, Result};
use super::files::{self, Parsed};
use super::persona::{self, Persona};
use crate::model::*;
use crate::{Store, slug};

/// Resultado de uma importação: slugs criados/atualizados e avisos de arquivos que não puderam ser lidos.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ImportResult {
    pub slugs: Vec<String>,
    pub warnings: Vec<String>,
}

/// Um arquivo candidato: o caminho e o que se leu dele (ou o motivo da falha, que vira aviso).
struct Entry {
    path: PathBuf,
    parsed: std::result::Result<Parsed, String>,
}

pub fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .filter(|h| !h.is_empty())
        .map(PathBuf::from)
}

fn sorted_children(dir: &Path, skip_hidden: bool) -> Vec<PathBuf> {
    let Ok(rd) = fs::read_dir(dir) else {
        return vec![];
    };
    let mut v: Vec<PathBuf> = rd
        .filter_map(|e| e.ok())
        .filter(|e| !(skip_hidden && e.file_name().to_string_lossy().starts_with('.')))
        .map(|e| e.path())
        .collect();
    v.sort();
    v
}

/// `subpathsOfDirectory`: caminhos relativos (com `/`) de tudo dentro de `dir`, recursivo, sem seguir symlinks.
fn subpaths(dir: &Path) -> Vec<String> {
    fn walk(base: &Path, rel: &str, out: &mut Vec<String>) {
        let Ok(rd) = fs::read_dir(base) else { return };
        for e in rd.filter_map(|e| e.ok()) {
            let name = e.file_name().to_string_lossy().into_owned();
            let rel_path = if rel.is_empty() {
                name.clone()
            } else {
                format!("{rel}/{name}")
            };
            out.push(rel_path.clone());
            if e.file_type().is_ok_and(|t| t.is_dir()) {
                walk(&e.path(), &rel_path, out);
            }
        }
    }
    let mut out = Vec::new();
    walk(dir, "", &mut out);
    out
}

fn has_ext(path: &Path, ext: &str, lowercase: bool) -> bool {
    path.extension().is_some_and(|e| {
        let e = e.to_string_lossy();
        if lowercase {
            e.to_lowercase() == ext
        } else {
            e == ext
        }
    })
}

fn stem(path: &Path) -> String {
    path.file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn dirs_or(dirs: Option<&[PathBuf]>, defaults: impl FnOnce() -> Vec<PathBuf>) -> Vec<PathBuf> {
    dirs.map(<[PathBuf]>::to_vec).unwrap_or_else(defaults)
}

fn defaults(root: &Path, relative: &str) -> Vec<PathBuf> {
    let mut v = vec![root.join(relative)];
    if let Some(h) = home_dir() {
        v.push(h.join(relative));
    }
    v
}

// ---- coleta de arquivos --------------------------------------------------------------------------

fn claude_agents(dirs: &[PathBuf]) -> Vec<Entry> {
    let mut out = Vec::new();
    for dir in dirs {
        for file in sorted_children(dir, true) {
            if !has_ext(&file, "md", true) {
                continue;
            }
            let Ok(text) = fs::read_to_string(&file) else {
                continue;
            };
            let parsed = files::parse_claude_agent(&text, &stem(&file));
            out.push(Entry {
                path: file,
                parsed: Ok(parsed),
            });
        }
    }
    out
}

fn codex_agents(dirs: &[PathBuf]) -> Vec<Entry> {
    let mut out = Vec::new();
    for dir in dirs {
        for file in sorted_children(dir, false) {
            if !has_ext(&file, "toml", false) {
                continue;
            }
            let parsed = fs::read_to_string(&file)
                .map_err(|e| e.to_string())
                .and_then(|t| {
                    files::parse_codex_agent(&t, &stem(&file)).map_err(|e| e.to_string())
                });
            out.push(Entry { path: file, parsed });
        }
    }
    out
}

/// Comandos (`.claude/commands`, `.codex/prompts`): Markdown recursivo; subpastas viram `ns:nome`.
fn markdown_commands(dirs: &[PathBuf], strict: bool) -> Vec<Entry> {
    let mut out = Vec::new();
    for dir in dirs {
        let mut rels: Vec<String> = subpaths(dir)
            .into_iter()
            .filter(|p| {
                p.to_lowercase().ends_with(".md") && !p.split('/').any(|c| c.starts_with('.'))
            })
            .collect();
        rels.sort();
        for rel in rels {
            let file = dir.join(&rel);
            let name = rel[..rel.len() - 3]
                .split('/')
                .collect::<Vec<_>>()
                .join(":");
            match fs::read_to_string(&file) {
                Ok(text) => out.push(Entry {
                    path: file,
                    parsed: Ok(files::parse_claude_command(&text, &name)),
                }),
                Err(e) if strict => out.push(Entry {
                    path: file,
                    parsed: Err(e.to_string()),
                }),
                Err(_) => {}
            }
        }
    }
    out
}

fn skill_files(files_list: Vec<PathBuf>, strict: bool) -> Vec<Entry> {
    let mut out = Vec::new();
    for file in files_list {
        let fallback = file
            .parent()
            .and_then(|p| p.file_name())
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        match fs::read_to_string(&file) {
            Ok(text) => out.push(Entry {
                parsed: Ok(files::parse_claude_skill(&text, &fallback)),
                path: file,
            }),
            Err(e) if strict => out.push(Entry {
                path: file,
                parsed: Err(e.to_string()),
            }),
            Err(_) => {}
        }
    }
    out
}

fn claude_skills(dirs: &[PathBuf]) -> Vec<Entry> {
    let mut out = Vec::new();
    for dir in dirs {
        let list = sorted_children(dir, true)
            .into_iter()
            .map(|f| f.join("SKILL.md"))
            .collect();
        out.extend(skill_files(list, false));
    }
    out
}

// ---- aplicação -----------------------------------------------------------------------------------

fn record_exists<P: Persona>(store: &Store, slug: &str) -> bool {
    store.dir::<P>().join(format!("{slug}.json")).exists()
}

fn apply<P: Persona>(
    store: &Store,
    provider: AiProvider,
    entries: Vec<Entry>,
    overwrite: bool,
    author: Author,
    result: &mut ImportResult,
) -> Result<()> {
    let mut seen = HashSet::new();
    for entry in entries {
        let parsed = match entry.parsed {
            Ok(p) => p,
            Err(msg) => {
                result
                    .warnings
                    .push(format!("{}: {msg}", entry.path.display()));
                continue;
            }
        };
        let slug = slug::make(&parsed.name);
        if !seen.insert(slug.clone()) {
            continue; // a pasta do projeto vence a do usuário
        }
        let exists = record_exists::<P>(store, &slug);
        if exists && !overwrite {
            continue;
        }
        let source = entry.path.display().to_string();
        match provider {
            AiProvider::Claude => {
                if exists {
                    persona::update::<P>(store, &slug, |f| {
                        *f.summary = parsed.description.clone();
                        *f.model = parsed.model.clone();
                        *f.tools = parsed.tools.clone();
                        *f.prompt = parsed.prompt.clone();
                        if let Some(h) = f.argument_hint.as_deref_mut() {
                            *h = parsed.argument_hint.clone();
                        }
                        if let Some(s) = f.source_path.as_deref_mut() {
                            *s = Some(source.clone());
                        }
                        Ok(())
                    })?;
                } else {
                    let mut value = P::blank(&parsed.name);
                    {
                        let f = value.fields();
                        *f.summary = parsed.description.clone();
                        *f.model = parsed.model.clone();
                        *f.tools = parsed.tools.clone();
                        *f.prompt = parsed.prompt.clone();
                        *f.author = author;
                        *f.tags = vec!["claude-code".to_string()];
                        if let Some(h) = f.argument_hint {
                            *h = parsed.argument_hint.clone();
                        }
                        if let Some(s) = f.source_path {
                            *s = Some(source.clone());
                        }
                    }
                    persona::save(store, &slug, &value)?;
                }
            }
            AiProvider::Codex => {
                let outcome = (|| -> Result<()> {
                    let mut value = store.load::<P>(&slug).ok().unwrap_or_else(|| {
                        let mut v = P::blank(&parsed.name);
                        *v.fields().author = author;
                        v
                    });
                    {
                        let f = value.fields();
                        *f.summary = parsed.description.clone();
                        *f.prompt = parsed.prompt.clone();
                        if let Some(h) = f.argument_hint {
                            *h = parsed.argument_hint.clone();
                        }
                        if let Some(s) = f.source_path {
                            *s = Some(source.clone());
                        }
                        f.provider_settings
                            .get_or_insert_with(Default::default)
                            .insert(
                                "codex".to_string(),
                                ProviderSettings {
                                    model: parsed.model.clone(),
                                    effort: parsed.effort.clone(),
                                },
                            );
                        if !f.tags.iter().any(|t| t == "codex") {
                            f.tags.push("codex".to_string());
                        }
                        *f.updated_at = Timestamp::now();
                    }
                    persona::save(store, &slug, &value)?;
                    Ok(())
                })();
                if let Err(e) = outcome {
                    result.warnings.push(format!("{source}: {e}"));
                    continue;
                }
            }
        }
        result.slugs.push(slug);
    }
    Ok(())
}

// ---- API pública ---------------------------------------------------------------------------------

/// `importAgents`: claude lê `.claude/agents/*.md` (projeto e usuário); codex lê `.codex/agents/*.toml`.
pub fn import_agents(
    store: &Store,
    provider: AiProvider,
    dirs: Option<&[PathBuf]>,
    overwrite: bool,
    author: Author,
) -> Result<ImportResult> {
    let mut result = ImportResult::default();
    let entries = match provider {
        AiProvider::Claude => {
            claude_agents(&dirs_or(dirs, || defaults(store.root(), ".claude/agents")))
        }
        AiProvider::Codex => {
            codex_agents(&dirs_or(dirs, || defaults(store.root(), ".codex/agents")))
        }
    };
    apply::<Agent>(store, provider, entries, overwrite, author, &mut result)?;
    Ok(result)
}

/// `importCommands`: claude lê `.claude/commands/**/*.md`; codex lê `.codex/prompts/**/*.md`.
pub fn import_commands(
    store: &Store,
    provider: AiProvider,
    dirs: Option<&[PathBuf]>,
    overwrite: bool,
    author: Author,
) -> Result<ImportResult> {
    let mut result = ImportResult::default();
    let entries = match provider {
        AiProvider::Claude => markdown_commands(
            &dirs_or(dirs, || defaults(store.root(), ".claude/commands")),
            false,
        ),
        AiProvider::Codex => markdown_commands(
            &dirs_or(dirs, || defaults(store.root(), ".codex/prompts")),
            true,
        ),
    };
    apply::<Command>(store, provider, entries, overwrite, author, &mut result)?;
    Ok(result)
}

/// `importSkills`: claude lê `.claude/skills/<nome>/SKILL.md`. Codex com `dirs` lê `<dir>/*/SKILL.md`; sem
/// `dirs` usa a listagem do `codex app-server` (`ai::codex::skill_paths`).
pub fn import_skills(
    store: &Store,
    provider: AiProvider,
    dirs: Option<&[PathBuf]>,
    overwrite: bool,
    author: Author,
) -> Result<ImportResult> {
    let mut result = ImportResult::default();
    let entries = match (provider, dirs) {
        (AiProvider::Claude, _) => {
            claude_skills(&dirs_or(dirs, || defaults(store.root(), ".claude/skills")))
        }
        (AiProvider::Codex, Some(dirs)) => {
            let list = dirs
                .iter()
                .flat_map(|d| sorted_children(d, false))
                .map(|f| f.join("SKILL.md"))
                .collect();
            skill_files(list, true)
        }
        (AiProvider::Codex, None) => {
            // Listagem pelo `codex app-server` (skills do projeto primeiro, desativadas fora).
            let (files, warnings) = crate::ai::codex::skill_paths(store.root())
                .map_err(|e| ResourceError::Unavailable(e.to_string()))?;
            result.warnings.extend(warnings);
            skill_files(files, true)
        }
    };
    apply::<Skill>(store, provider, entries, overwrite, author, &mut result)?;
    Ok(result)
}

/// Importa, com a semântica do Codex, os `SKILL.md` já listados (ex.: pelo `codex app-server`).
pub fn import_skill_files(
    store: &Store,
    files: Vec<PathBuf>,
    overwrite: bool,
    author: Author,
) -> Result<ImportResult> {
    let mut result = ImportResult::default();
    apply::<Skill>(
        store,
        AiProvider::Codex,
        skill_files(files, true),
        overwrite,
        author,
        &mut result,
    )?;
    Ok(result)
}

// ---- descoberta ----------------------------------------------------------------------------------

/// Um recurso existente na pasta do projeto, pronto para ser cadastrado.
#[derive(Debug, Clone, PartialEq)]
pub struct Discovered {
    pub kind: NextStepKind,
    pub provider: AiProvider,
    /// Arquivo de origem (`.claude/agents/x.md`, `.claude/skills/x/SKILL.md`, `.codex/prompts/x.md`...).
    pub origin: PathBuf,
    pub name: String,
    pub slug: String,
    /// Já existe `.vibedeck/<tipo>/<slug>.json`.
    pub registered: bool,
}

/// Varre `<root>/.claude/{agents,commands,skills}`, `<root>/.codex/prompts` e `<root>/.codex/agents`.
/// Não exige `vibedeck.json` nem toca o disco. Ordem: tipo (agentes, comandos, skills), provedor, caminho.
pub fn discover(root: &Path) -> Vec<Discovered> {
    let data = root.join(crate::store::DATA_DIR);
    let mut out = Vec::new();
    let mut add = |kind: NextStepKind, provider: AiProvider, entries: Vec<Entry>, dir: &str| {
        for e in entries {
            let Ok(p) = e.parsed else { continue };
            let slug = slug::make(&p.name);
            let registered = data.join(dir).join(format!("{slug}.json")).exists();
            out.push(Discovered {
                kind,
                provider,
                origin: e.path,
                name: p.name,
                slug,
                registered,
            });
        }
    };
    let claude = |rel: &str| vec![root.join(rel)];
    add(
        NextStepKind::Agent,
        AiProvider::Claude,
        claude_agents(&claude(".claude/agents")),
        "agents",
    );
    add(
        NextStepKind::Agent,
        AiProvider::Codex,
        codex_agents(&claude(".codex/agents")),
        "agents",
    );
    add(
        NextStepKind::Command,
        AiProvider::Claude,
        markdown_commands(&claude(".claude/commands"), false),
        "commands",
    );
    add(
        NextStepKind::Command,
        AiProvider::Codex,
        markdown_commands(&claude(".codex/prompts"), false),
        "commands",
    );
    add(
        NextStepKind::Skill,
        AiProvider::Claude,
        claude_skills(&claude(".claude/skills")),
        "skills",
    );
    out
}

/// Cadastra exatamente os itens descobertos (os já cadastrados só mudam com `overwrite`), com a mesma
/// semântica dos `import_*` do provedor de cada item.
pub fn import_discovered(
    store: &Store,
    items: &[Discovered],
    overwrite: bool,
    author: Author,
) -> Result<ImportResult> {
    let mut result = ImportResult::default();
    for kind in [
        NextStepKind::Agent,
        NextStepKind::Command,
        NextStepKind::Skill,
    ] {
        for provider in [AiProvider::Claude, AiProvider::Codex] {
            let group: Vec<&Discovered> = items
                .iter()
                .filter(|d| d.kind == kind && d.provider == provider)
                .collect();
            if group.is_empty() {
                continue;
            }
            let entries = group.into_iter().filter_map(reread).collect::<Vec<_>>();
            match kind {
                NextStepKind::Agent => {
                    apply::<Agent>(store, provider, entries, overwrite, author, &mut result)?
                }
                NextStepKind::Command => {
                    apply::<Command>(store, provider, entries, overwrite, author, &mut result)?
                }
                NextStepKind::Skill => {
                    apply::<Skill>(store, provider, entries, overwrite, author, &mut result)?
                }
            }
        }
    }
    Ok(result)
}

fn reread(d: &Discovered) -> Option<Entry> {
    let text = fs::read_to_string(&d.origin).ok()?;
    let base = stem(&d.origin);
    let parsed = match (d.kind, d.provider) {
        (NextStepKind::Agent, AiProvider::Claude) => Ok(files::parse_claude_agent(&text, &base)),
        (NextStepKind::Agent, AiProvider::Codex) => {
            files::parse_codex_agent(&text, &base).map_err(|e| e.to_string())
        }
        (NextStepKind::Command, _) => Ok(files::parse_claude_command(&text, &d.name)),
        (NextStepKind::Skill, _) => {
            let folder = d
                .origin
                .parent()
                .and_then(|p| p.file_name())
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            Ok(files::parse_claude_skill(&text, &folder))
        }
    };
    Some(Entry {
        path: d.origin.clone(),
        parsed,
    })
}
