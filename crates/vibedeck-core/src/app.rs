//! Superfície do app macOS (`vibedeck mcp --app`): escrita genérica de registros com lixeira, projeto, anexos,
//! status de verificação, ideias como pedido de implementação, recibos de reorganização e a revisão que o
//! app consulta para saber se algo mudou fora dele.
//!
//! Nada aqui é novo domínio: cada função valida contra o modelo tipado e delega ao módulo da área.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

use crate::ai::reorganize::{self, Receipt};
use crate::ai::usage::{UsageRecord, UsageStore};
use crate::docs::{self, DocFile, attachments};
use crate::ideas;
use crate::model::{
    Agent, AiProvider, Command, Idea, Project, ReviewGroup, RuleTopic, Skill, Workflow,
    WorkflowRun, WorkflowStepCheckpoint,
};
use crate::rules;
use crate::stack::{SkillIcons, StackService};
use crate::store::{DATA_DIR, PROJECT_FILE, Store, Stored, write_atomic};
use crate::time;
use crate::workflows::{self, restart_from_beginning};

/// Erro com a mensagem final, em português, que a tool devolve.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppError(pub String);

pub type Result<T> = std::result::Result<T, AppError>;

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

fn err(e: impl std::fmt::Display) -> AppError {
    AppError(e.to_string())
}

fn bad(message: impl Into<String>) -> AppError {
    AppError(message.into())
}

// ---- registros -----------------------------------------------------------------------------------

/// Conceitos que o app grava inteiros.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordKind {
    Reviews,
    Rules,
    Ideas,
    Agents,
    Commands,
    Skills,
    Workflows,
}

impl RecordKind {
    pub const NAMES: [&'static str; 7] = [
        "reviews",
        "rules",
        "ideas",
        "agents",
        "commands",
        "skills",
        "workflows",
    ];

    pub fn parse(raw: &str) -> Result<Self> {
        Ok(match raw {
            "reviews" => Self::Reviews,
            "rules" => Self::Rules,
            "ideas" => Self::Ideas,
            "agents" => Self::Agents,
            "commands" => Self::Commands,
            "skills" => Self::Skills,
            "workflows" => Self::Workflows,
            other => {
                return Err(bad(format!(
                    "Tipo de registro inválido: {other}. Use {}.",
                    Self::NAMES.join(", ")
                )));
            }
        })
    }
}

fn put_typed<T: Stored>(store: &Store, slug: &str, record: &str) -> Result<()> {
    let value: T = serde_json::from_str(record)
        .map_err(|e| bad(format!("Registro inválido para {}: {e}", T::DIR)))?;
    store.save(slug, &value).map_err(err)?;
    Ok(())
}

/// Grava o registro inteiro: valida contra o modelo tipado, cria subpastas do slug e escreve de forma
/// atômica. Preserva `author`, ids e datas do registro (nada é forçado a `ai`).
pub fn put_record(store: &Store, kind: RecordKind, slug: &str, record: &str) -> Result<()> {
    match kind {
        RecordKind::Reviews => put_typed::<ReviewGroup>(store, slug, record),
        RecordKind::Rules => put_typed::<RuleTopic>(store, slug, record),
        RecordKind::Ideas => put_typed::<Idea>(store, slug, record),
        RecordKind::Agents => put_typed::<Agent>(store, slug, record),
        RecordKind::Commands => put_typed::<Command>(store, slug, record),
        RecordKind::Skills => put_typed::<Skill>(store, slug, record),
        RecordKind::Workflows => put_typed::<Workflow>(store, slug, record),
    }
}

/// Copia `bytes` para `.vibedeck/.trash/<carimbo>/<rel>` (nunca sobrescreve uma cópia anterior).
fn trash_bytes(store: &Store, rel: &str, bytes: &[u8]) -> Result<PathBuf> {
    let stamp = time::now().format("%Y%m%dT%H%M%S%3fZ").to_string();
    let base = store.data_dir().join(".trash");
    let mut dir = base.join(&stamp);
    let mut n = 1;
    while dir.join(rel).exists() {
        n += 1;
        dir = base.join(format!("{stamp}-{n}"));
    }
    let target = dir.join(rel);
    write_atomic(&target, bytes).map_err(err)?;
    Ok(target)
}

fn trash_typed<T: Stored>(store: &Store, slug: &str) -> Result<()> {
    let path = store.record_path::<T>(slug).map_err(err)?;
    if !path.exists() {
        return Err(err(T::not_found(slug)));
    }
    let bytes = fs::read(&path).map_err(err)?;
    trash_bytes(store, &format!("{}/{slug}.json", T::DIR), &bytes)?;
    Ok(())
}

/// Tira o registro do projeto, deixando a cópia em `.vibedeck/.trash/<carimbo>/`. Para `rules`, as ideias e os
/// padrões que apontavam para o tópico são soltos (`rules::delete_topic`).
pub fn delete_record(store: &Store, kind: RecordKind, slug: &str) -> Result<()> {
    match kind {
        RecordKind::Reviews => {
            trash_typed::<ReviewGroup>(store, slug)?;
            store.delete::<ReviewGroup>(slug).map_err(err)
        }
        RecordKind::Rules => {
            trash_typed::<RuleTopic>(store, slug)?;
            rules::delete_topic(store, slug).map_err(err)
        }
        RecordKind::Ideas => {
            trash_typed::<Idea>(store, slug)?;
            store.delete::<Idea>(slug).map_err(err)
        }
        RecordKind::Agents => {
            trash_typed::<Agent>(store, slug)?;
            store.delete::<Agent>(slug).map_err(err)
        }
        RecordKind::Commands => {
            trash_typed::<Command>(store, slug)?;
            store.delete::<Command>(slug).map_err(err)
        }
        RecordKind::Skills => {
            trash_typed::<Skill>(store, slug)?;
            store.delete::<Skill>(slug).map_err(err)
        }
        RecordKind::Workflows => {
            trash_typed::<Workflow>(store, slug)?;
            store.delete::<Workflow>(slug).map_err(err)
        }
    }
}

/// Grava `vibedeck.json` inteiro. Se a stack mudou, o bloco de badge do README.md é regravado (como a área
/// stack). Devolve um aviso quando o README não pôde ser atualizado; o projeto já está salvo.
pub fn put_project(store: &Store, project: &str) -> Result<Option<String>> {
    let new: Project = serde_json::from_str(project)
        .map_err(|e| bad(format!("Projeto inválido (vibedeck.json): {e}")))?;
    let stack_changed = !store.project().is_ok_and(|old| old.stack == new.stack);
    store.save_project(&new).map_err(err)?;
    if !stack_changed {
        return Ok(None);
    }
    let api = SkillIcons::default();
    Ok(StackService::new(store, &api).sync_readme())
}

// ---- docs, anexos ----------------------------------------------------------------------------------

/// Apaga um doc comum (cópia em `.trash`) ou, em doc vinculado, só o vínculo. Devolve o slug.
pub fn delete_doc(store: &Store, reference: &str) -> Result<String> {
    let slug = docs::resolve_doc_slug(store, reference).map_err(err)?;
    match docs::doc_file(store, &slug).map_err(err)? {
        DocFile::Regular(path) => {
            let bytes = fs::read(&path).map_err(err)?;
            trash_bytes(store, &format!("docs/{slug}.md"), &bytes)?;
            docs::delete_doc(store, &slug).map_err(err)?;
        }
        DocFile::Linked { .. } | DocFile::Broken { .. } => {
            docs::unlink_doc(store, &slug).map_err(err)?;
        }
    }
    Ok(slug)
}

/// Grava `data` como anexo de `owner` (o doc ou a ideia) e devolve o link Markdown.
pub fn import_attachment(store: &Store, owner: &str, name: &str, data: &[u8]) -> Result<String> {
    attachments::import_attachment_data(store, data, name, owner).map_err(err)
}

/// Base64 padrão (com ou sem `=`), como o `Data` do Swift.
pub fn decode_base64(text: &str) -> Result<Vec<u8>> {
    reorganize::decode_base64(text).ok_or_else(|| bad("data_base64 não é base64 válido."))
}

// ---- execuções de workflow -------------------------------------------------------------------------

pub fn run_checkpoint(
    store: &Store,
    reference: &str,
    step: &str,
    verdict: Option<&str>,
    output: &str,
    completed: bool,
) -> Result<String> {
    let reference = workflows::resolve_run_ref(store, reference).map_err(err)?;
    workflows::checkpoint_run(
        store,
        &reference,
        WorkflowStepCheckpoint {
            step: step.to_string(),
            verdict: verdict.map(str::to_string),
            output: output.to_string(),
            completed,
        },
    )
    .map_err(err)?;
    Ok(reference)
}

/// Reinício explícito: novo ciclo desde a primeira etapa, mantendo o histórico e fechando as perguntas.
pub fn run_restart(store: &Store, reference: &str) -> Result<(String, WorkflowRun)> {
    let reference = workflows::resolve_run_ref(store, reference).map_err(err)?;
    let mut run = workflows::load_run(store, &reference).map_err(err)?;
    let flow = workflows::load_workflow(store, &run.workflow).map_err(err)?;
    restart_from_beginning(&mut run, &flow).map_err(err)?;
    workflows::save_run(store, &run, &reference).map_err(err)?;
    Ok((reference, run))
}

pub fn run_resume(store: &Store, reference: &str) -> Result<(String, WorkflowRun)> {
    let reference = workflows::resolve_run_ref(store, reference).map_err(err)?;
    let run = workflows::resume_run(store, &reference).map_err(err)?;
    Ok((reference, run))
}

// ---- regras ------------------------------------------------------------------------------------------

/// Selo "regras verificadas" de um item de revisão.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct VerificationStatus {
    /// Vazio = verificado.
    pub problems: Vec<String>,
    pub required_topics: Vec<String>,
}

pub fn rule_verification_status(store: &Store, review_item: &str) -> Result<VerificationStatus> {
    let item = rules::find_review_item(store, review_item).map_err(err)?;
    let problems = rules::verification_problems(store, &item).map_err(err)?;
    let required_topics = rules::required_topics(store, &item)
        .map_err(err)?
        .into_iter()
        .map(|t| t.slug)
        .collect();
    Ok(VerificationStatus {
        problems,
        required_topics,
    })
}

/// Solta ideias e padrões promovidos para um tópico que não existe mais (apagado fora do app).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Released {
    pub ideas: Vec<String>,
    pub patterns: Vec<String>,
}

pub fn release_orphaned(store: &Store) -> Result<Released> {
    Ok(Released {
        ideas: store.release_orphaned_ideas().map_err(err)?,
        patterns: store.release_orphaned_patterns().map_err(err)?,
    })
}

// ---- ideias ------------------------------------------------------------------------------------------

/// Resultado de `idea_implement`.
#[derive(Debug, Clone, Serialize)]
pub struct IdeaImplementation {
    /// Tópico de regras promovido da ideia.
    pub topic: String,
    /// `<workflow>/<execução>`, só quando um workflow foi pedido.
    pub run_ref: Option<String>,
    pub prompt: String,
    pub run: Option<WorkflowRun>,
}

fn run_of_idea(
    store: &Store,
    idea: &Idea,
    workflow: &str,
) -> Result<Option<(String, WorkflowRun)>> {
    let input = ideas::workflow_input(idea);
    Ok(workflows::list_runs(store, Some(workflow))
        .map_err(err)?
        .into_iter()
        .find(|r| r.run.input.as_deref() == Some(input.as_str()))
        .map(|r| (r.reference, r.run)))
}

/// Execução do workflow ligada a esta ideia (a que tem a entrada estável da ideia), se houver.
pub fn idea_run(
    store: &Store,
    idea: &str,
    workflow: &str,
) -> Result<Option<(String, WorkflowRun)>> {
    let slug = store.resolve::<Idea>(idea).map_err(err)?;
    let idea = store.load::<Idea>(&slug).map_err(err)?;
    let workflow = workflows::resolve_workflow_slug(store, workflow).map_err(err)?;
    run_of_idea(store, &idea, &workflow)
}

/// "Implementar": confere elegibilidade e dependências, promove a ideia para um tópico e, com `workflow`,
/// cria/retoma (ou reinicia, com `restart`) a execução ligada à ideia.
pub fn idea_implement(
    store: &Store,
    reference: &str,
    workflow: Option<&str>,
    restart: bool,
    provider: Option<AiProvider>,
    skipping_paths: &HashSet<String>,
) -> Result<IdeaImplementation> {
    let record = store.implementable_idea(reference).map_err(err)?;
    let provider = provider.unwrap_or(AiProvider::Claude);
    let target = match workflow {
        Some(w) => {
            let slug = workflows::resolve_workflow_slug(store, w).map_err(err)?;
            let flow = workflows::load_workflow(store, &slug).map_err(err)?;
            if flow.steps.is_empty() {
                return Err(bad("o workflow não tem etapas."));
            }
            let previous = run_of_idea(store, &record.value, &slug)?;
            if let Some((_, run)) = &previous
                && run.provider != provider
            {
                return Err(bad(
                    "a execução pertence a outro provedor. Selecione o mesmo provedor antes de continuar.",
                ));
            }
            Some((slug, flow, previous))
        }
        None => None,
    };
    let topic = store
        .promote_idea(&record.slug, skipping_paths)
        .map_err(err)?;
    let (run_ref, run) = match target {
        None => (None, None),
        Some((_, flow, Some((reference, mut run)))) => {
            if restart {
                restart_from_beginning(&mut run, &flow).map_err(err)?;
                workflows::save_run(store, &run, &reference).map_err(err)?;
            } else {
                run = workflows::resume_run(store, &reference).map_err(err)?;
            }
            (Some(reference), Some(run))
        }
        Some((slug, _, None)) => {
            let (reference, run, _) = workflows::start_run(
                store,
                &slug,
                Some(&ideas::workflow_input(&record.value)),
                None,
                Some(provider),
            )
            .map_err(err)?;
            (Some(reference), Some(run))
        }
    };
    Ok(IdeaImplementation {
        prompt: ideas::implementation_prompt(&record.slug, &record.value, Some(&topic)),
        topic,
        run_ref,
        run,
    })
}

// ---- reorganização e uso de IA ------------------------------------------------------------------

/// Desfaz (`forward = false`) ou refaz um recibo de `reorganize_apply`, dado como JSON.
pub fn reorganize_restore(store: &Store, receipt: &str, forward: bool) -> Result<()> {
    let receipt: Receipt = serde_json::from_str(receipt)
        .map_err(|e| bad(format!("Recibo de reorganização inválido: {e}")))?;
    reorganize::restore(store, &receipt, forward).map_err(err)
}

/// Grava um `UsageRecord` (consumo de um turno de IA do app) no armazenamento local de uso.
pub fn ai_usage_record(store: &Store, record: &str) -> Result<String> {
    let record: UsageRecord =
        serde_json::from_str(record).map_err(|e| bad(format!("Registro de uso inválido: {e}")))?;
    UsageStore::for_root(store.root())
        .save(&record)
        .map_err(err)?;
    Ok(record.id.to_string())
}

// ---- revisão -----------------------------------------------------------------------------------------

/// Nome de arquivo que não é dado do projeto (temporário de escrita atômica).
fn is_transient(name: &str) -> bool {
    name.starts_with('.') && name.ends_with(".tmp")
}

/// Hash (hex) de caminho, tamanho e mtime de `vibedeck.json` e de tudo em `.vibedeck/` (menos a lixeira e
/// temporários). Muda quando algo muda; igual enquanto nada muda.
pub fn revision(root: &Path) -> String {
    let mut hasher = Sha256::new();
    let mut feed = |label: &str, path: &Path| {
        if let Ok(meta) = fs::symlink_metadata(path) {
            let nanos = meta
                .modified()
                .ok()
                .and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok())
                .map_or(0, |d| d.as_nanos());
            hasher.update(label.as_bytes());
            hasher.update(b"\0");
            hasher.update(meta.len().to_le_bytes());
            hasher.update(nanos.to_le_bytes());
        }
    };
    feed(PROJECT_FILE, &root.join(PROJECT_FILE));
    let data = root.join(DATA_DIR);
    let walker = WalkDir::new(&data)
        .sort_by_file_name()
        .into_iter()
        .filter_entry(|e| {
            let name = e.file_name().to_string_lossy();
            !(e.depth() == 1 && name == ".trash") && !is_transient(&name)
        });
    // O diretório `.vibedeck` em si muda ao criar/apagar a lixeira, que não é dado do projeto.
    for entry in walker.flatten().filter(|e| e.depth() > 0) {
        if let Ok(rel) = entry.path().strip_prefix(&data) {
            feed(&rel.to_string_lossy(), entry.path());
        }
    }
    hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
