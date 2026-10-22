//! Comandos CLI — Workflows (`workflows`) e execuções (`runs`).
//!
//! Porta de `Workflows` e `Runs` de `CLI.swift` (cli.md §2.17, §2.18). Os dois grupos têm `list` como
//! subcomando padrão: as opções do `list` valem também no nível do grupo.

use std::io::Read;

use clap::{Args, Subcommand, ValueEnum};
use vibedeck_core::model::{AiProvider, Author, NextStepKind, WorkflowRunStatus};
use vibedeck_core::project::links::hashtags;
use vibedeck_core::workflows::{
    self as wf, RunAction, WorkflowError, WorkflowQuestionDraft, kind_str, status_str,
};

use super::output::print_json;
use super::{CliError, Context};

impl From<WorkflowError> for CliError {
    fn from(e: WorkflowError) -> Self {
        CliError::new(e.to_string())
    }
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Workflows do VibeDeck: etapas (agentes, comandos e skills) e transições condicionais que orquestram um fluxo inteiro.
    Workflows(WorkflowsArgs),
    /// Execuções de workflows: estado em disco, uma etapa por subagente, veredito decide a transição, perguntas sobem ao orquestrador.
    Runs(RunsArgs),
}

pub fn run(command: Command, ctx: &Context) -> Result<i32, CliError> {
    match command {
        Command::Workflows(a) => run_workflows(a, ctx),
        Command::Runs(a) => run_runs(a, ctx),
    }
}

// ---- argumentos -------------------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum KindArg {
    Agent,
    Command,
    Skill,
}

impl From<KindArg> for NextStepKind {
    fn from(k: KindArg) -> Self {
        match k {
            KindArg::Agent => NextStepKind::Agent,
            KindArg::Command => NextStepKind::Command,
            KindArg::Skill => NextStepKind::Skill,
        }
    }
}

#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum StatusArg {
    Running,
    Waiting,
    Done,
    Stopped,
}

impl From<StatusArg> for WorkflowRunStatus {
    fn from(s: StatusArg) -> Self {
        match s {
            StatusArg::Running => WorkflowRunStatus::Running,
            StatusArg::Waiting => WorkflowRunStatus::Waiting,
            StatusArg::Done => WorkflowRunStatus::Done,
            StatusArg::Stopped => WorkflowRunStatus::Stopped,
        }
    }
}

#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum ProviderArg {
    Claude,
    Codex,
}

impl From<ProviderArg> for AiProvider {
    fn from(p: ProviderArg) -> Self {
        match p {
            ProviderArg::Claude => AiProvider::Claude,
            ProviderArg::Codex => AiProvider::Codex,
        }
    }
}

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct WorkflowsArgs {
    #[command(subcommand)]
    pub command: Option<WorkflowsCommand>,
    #[command(flatten)]
    pub list: WorkflowsListArgs,
}

#[derive(Args, Debug, Default)]
pub struct WorkflowsListArgs {
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum WorkflowsCommand {
    /// Lista os workflows.
    List(WorkflowsListArgs),
    /// Mostra um workflow.
    Show {
        workflow: String,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Cria um workflow vazio e imprime o slug.
    New {
        title: String,
        #[arg(long)]
        summary: Option<String>,
        /// O que pedir ao iniciar (ex.: <número do PR>).
        #[arg(long)]
        input: Option<String>,
        /// Limite de etapas executadas (padrão: 25).
        #[arg(long, allow_negative_numbers = true)]
        max_steps: Option<i64>,
        #[arg(long, num_args = 1..)]
        tags: Vec<String>,
        /// Marca o workflow como criado por IA.
        #[arg(long)]
        ai: bool,
    },
    /// Altera título, resumo, entrada ou limite de etapas.
    Set {
        workflow: String,
        #[arg(long)]
        title: Option<String>,
        #[arg(long)]
        summary: Option<String>,
        #[arg(long)]
        input: Option<String>,
        /// Limite de etapas executadas (0 volta ao padrão).
        #[arg(long, allow_negative_numbers = true)]
        max_steps: Option<i64>,
    },
    /// Adiciona uma etapa (agente, comando ou skill do VibeDeck). A primeira etapa é o início.
    Step {
        workflow: String,
        /// Agente, comando ou skill do VibeDeck (slug, id ou título).
        target: String,
        #[arg(long, value_enum, default_value = "agent")]
        kind: KindArg,
        /// Instrução extra da etapa ($ARGUMENTS para comandos).
        #[arg(long)]
        note: Option<String>,
        /// Máximo de vezes que a etapa roda por ciclo de uma execução.
        #[arg(long, allow_negative_numbers = true)]
        max_visits: Option<i64>,
    },
    /// Remove uma etapa (e as transições que apontam para ela).
    Unstep {
        workflow: String,
        /// Id ou posição (1, 2, …) da etapa.
        step: String,
    },
    /// Move uma etapa para outra posição (1 = início).
    Move {
        workflow: String,
        /// Id ou posição da etapa.
        step: String,
        /// Nova posição (1, 2, …).
        #[arg(allow_negative_numbers = true)]
        position: i64,
    },
    /// Define quantas vezes uma etapa pode rodar por ciclo de uma execução (0 remove o limite).
    Visits {
        workflow: String,
        /// Id ou posição da etapa.
        step: String,
        /// Máximo de vezes (0 = sem limite).
        #[arg(allow_negative_numbers = true)]
        max: i64,
    },
    /// Adiciona uma transição entre etapas (pode voltar). --verdict casa a última linha do resultado; --when é uma condição; sem nenhum é o "senão".
    Route {
        workflow: String,
        /// Etapa de origem (id ou posição).
        from: String,
        /// Etapa de destino (id ou posição).
        to: String,
        /// Veredito (última linha do resultado da etapa, ex.: APROVADO) que leva a esta transição.
        #[arg(long)]
        verdict: Option<String>,
        /// Condição em linguagem natural sobre o resultado da etapa.
        #[arg(long)]
        when: Option<String>,
    },
    /// Remove uma transição de uma etapa (pela posição mostrada em `show`).
    Unroute {
        workflow: String,
        /// Etapa de origem (id ou posição).
        from: String,
        /// Posição da transição (1, 2, …).
        #[arg(allow_negative_numbers = true)]
        index: i64,
    },
    /// Imprime o JSON do workflow (etapas, transições e regras de execução) para orquestrar a IA.
    Flow {
        workflow: String,
        /// Entrada desta execução (sem ela, a IA pede a entrada ao usuário).
        #[arg(long)]
        input: Option<String>,
        /// Imprime o prompt completo (instrução + JSON) em vez de só o JSON.
        #[arg(long)]
        prompt: bool,
    },
}

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct RunsArgs {
    #[command(subcommand)]
    pub command: Option<RunsCommand>,
    #[command(flatten)]
    pub list: RunsListArgs,
}

#[derive(Args, Debug, Default)]
pub struct RunsListArgs {
    /// Só as execuções deste workflow.
    #[arg(long)]
    pub workflow: Option<String>,
    /// running, waiting, done ou stopped.
    #[arg(long, value_enum)]
    pub status: Option<StatusArg>,
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

const EXEC_HELP: &str = "<workflow>/<execução>, nome da execução ou id.";

#[derive(Subcommand, Debug)]
pub enum RunsCommand {
    /// Lista as execuções.
    List(RunsListArgs),
    /// Mostra uma execução.
    Show {
        #[arg(help = EXEC_HELP)]
        execution: String,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Inicia (ou retoma, com a mesma entrada) uma execução e imprime a próxima ação.
    Start {
        workflow: String,
        /// Provedor da nova execução: claude ou codex.
        #[arg(long, value_enum)]
        provider: Option<ProviderArg>,
        /// Entrada da execução (a execução recebe o nome dela).
        #[arg(long)]
        input: Option<String>,
        /// Etapa por onde começar (libera mais uma volta numa execução parada).
        #[arg(long)]
        from: Option<String>,
        /// Imprime o prompt do orquestrador em vez da ação.
        #[arg(long)]
        prompt: bool,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Próxima ação do orquestrador: run-step, ask, decide, done ou stop.
    Next {
        #[arg(help = EXEC_HELP)]
        execution: String,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Imprime o prompt da etapa atual (é o que o subagente da etapa segue).
    Step {
        #[arg(help = EXEC_HELP)]
        execution: String,
    },
    /// Registra o veredito da etapa atual e imprime a próxima ação.
    Record {
        #[arg(help = EXEC_HELP)]
        execution: String,
        /// Última linha do resultado da etapa.
        #[arg(long)]
        verdict: Option<String>,
        /// Resumo de 1 a 3 linhas do que a etapa fez.
        #[arg(long)]
        summary: Option<String>,
        /// Etapa escolhida ao avaliar as condições (resposta a `decide`).
        #[arg(long)]
        to: Option<String>,
        /// Nenhuma condição vale (resposta a `decide`): segue o senão ou termina.
        #[arg(long = "nenhuma")]
        none_holds: bool,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Grava perguntas da etapa atual (JSON no stdin: [{question, context, options: [{label, description}], multiple}]); a execução espera as respostas.
    Ask {
        #[arg(help = EXEC_HELP)]
        execution: String,
    },
    /// Lista as perguntas de uma execução.
    Questions {
        #[arg(help = EXEC_HELP)]
        execution: String,
        /// Só as abertas.
        #[arg(long)]
        open: bool,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Grava a resposta a uma pergunta e imprime a próxima ação.
    Answer {
        #[arg(help = EXEC_HELP)]
        execution: String,
        /// Número da pergunta.
        #[arg(allow_negative_numbers = true)]
        number: i64,
        /// Resposta (opção escolhida, várias separadas por "; ", ou texto livre).
        answer: String,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Para uma execução.
    Stop {
        #[arg(help = EXEC_HELP)]
        execution: String,
        /// Motivo.
        #[arg(long)]
        reason: Option<String>,
    },
    /// Apaga a execução e a pasta dela (artefatos das etapas).
    Delete {
        #[arg(help = EXEC_HELP)]
        execution: String,
    },
    /// Imprime o prompt do orquestrador de uma execução existente (para continuá-la num chat).
    Orchestrate {
        #[arg(help = EXEC_HELP)]
        execution: String,
    },
}

// ---- helpers ----------------------------------------------------------------------------------------

/// Texto não vazio (depois de aparar) é mantido como veio; em branco vira `None` (`nonEmptyOrNil`).
fn non_empty_or_none(s: String) -> Option<String> {
    if s.trim().is_empty() { None } else { Some(s) }
}

/// Como os subagentes devem chamar este CLI: caminho absoluto se rodou por caminho, senão `vibedeck`.
fn cli_invocation() -> String {
    let arg0 = std::env::args().next().unwrap_or_else(|| "vibedeck".into());
    if !arg0.contains('/') {
        return "vibedeck".into();
    }
    let path = std::path::PathBuf::from(&arg0);
    let abs = if path.is_absolute() {
        path
    } else {
        std::env::current_dir()
            .map(|d| d.join(&path))
            .unwrap_or(path)
    };
    vibedeck_core::paths::lexical_normalize(&abs)
        .to_string_lossy()
        .into_owned()
}

fn print_action(action: &RunAction, json: bool) -> Result<i32, CliError> {
    if json {
        print_json(action)?;
        return Ok(0);
    }
    println!(
        "{}\t{}\t{}",
        action.action.as_str(),
        action.step.as_deref().unwrap_or("-"),
        action.reason
    );
    for c in action.candidates.iter().flatten() {
        println!("  {} → {}", c.label(), c.to);
    }
    for q in action.questions.iter().flatten() {
        println!("  {}. [{}] {}", q.number, q.step, q.question);
    }
    Ok(0)
}

// ---- workflows --------------------------------------------------------------------------------------

fn run_workflows(args: WorkflowsArgs, ctx: &Context) -> Result<i32, CliError> {
    let cmd = args.command.unwrap_or(WorkflowsCommand::List(args.list));
    let store = ctx.store()?;
    match cmd {
        WorkflowsCommand::List(a) => {
            let list = wf::list_workflows(&store)?;
            if a.json {
                let values: Vec<_> = list.iter().map(|r| &r.value).collect();
                print_json(&values)?;
            } else {
                for r in &list {
                    println!(
                        "{}\t{}  → {} etapa(s){}",
                        r.slug,
                        r.value.title,
                        r.value.steps.len(),
                        hashtags(&r.value.tags)
                    );
                }
            }
        }
        WorkflowsCommand::Show { workflow, json } => {
            let slug = wf::resolve_workflow_slug(&store, &workflow)?;
            let w = wf::load_workflow(&store, &slug)?;
            if json {
                print_json(&w)?;
                return Ok(0);
            }
            println!(
                "{} — até {} etapa(s) por execução",
                w.title,
                w.max_steps
                    .unwrap_or(vibedeck_core::model::DEFAULT_MAX_STEPS)
            );
            if let Some(d) = &w.summary {
                println!("{d}");
            }
            if let Some(i) = &w.input {
                println!("Entrada: {i}");
            }
            for (n, step) in w.steps.iter().enumerate() {
                let visits = step
                    .max_visits
                    .map(|v| format!("  (até {v}x)"))
                    .unwrap_or_default();
                let note = step
                    .note
                    .as_ref()
                    .map(|n| format!(" — {n}"))
                    .unwrap_or_default();
                println!(
                    "\n{}. {} [{}] {}{}{visits}{note}",
                    n + 1,
                    step.id,
                    kind_str(step.kind),
                    step.r#ref,
                    if n == 0 { "  (início)" } else { "" },
                );
                for (i, t) in step.transitions.iter().enumerate() {
                    println!("   {}. {} → {}", i + 1, t.label(), t.to);
                }
                if step.transitions.is_empty() {
                    println!("   → fim");
                }
            }
        }
        WorkflowsCommand::New {
            title,
            summary,
            input,
            max_steps,
            tags,
            ai,
        } => {
            let rec = wf::create_workflow(
                &store,
                &title,
                summary,
                input,
                max_steps,
                tags,
                if ai { Author::Ai } else { Author::Human },
            )?;
            println!("{}", rec.slug);
        }
        WorkflowsCommand::Set {
            workflow,
            title,
            summary,
            input,
            max_steps,
        } => {
            let rec = wf::update_workflow(&store, &workflow, |w| {
                if let Some(t) = title {
                    w.title = t;
                }
                if let Some(s) = summary {
                    w.summary = non_empty_or_none(s);
                }
                if let Some(i) = input {
                    w.input = non_empty_or_none(i);
                }
                if let Some(m) = max_steps {
                    w.max_steps = (m > 0).then_some(m);
                }
                Ok(())
            })?;
            println!("{}\t{}", rec.slug, rec.value.title);
        }
        WorkflowsCommand::Step {
            workflow,
            target,
            kind,
            note,
            max_visits,
        } => {
            let (rec, step) =
                wf::add_workflow_step(&store, &workflow, kind.into(), &target, note.as_deref())?;
            if let Some(v) = max_visits {
                wf::set_workflow_step_max_visits(&store, &rec.slug, &step, Some(v))?;
            }
            println!("{}\t{}", rec.slug, step);
        }
        WorkflowsCommand::Visits {
            workflow,
            step,
            max,
        } => {
            let rec = wf::set_workflow_step_max_visits(&store, &workflow, &step, Some(max))?;
            let limit = if max > 0 {
                format!("até {max}x")
            } else {
                "sem limite".to_string()
            };
            println!("{}\t{step}: {limit}", rec.slug);
        }
        WorkflowsCommand::Unstep { workflow, step } => {
            let rec = wf::remove_workflow_step(&store, &workflow, &step)?;
            println!("{}\t{} etapa(s)", rec.slug, rec.value.steps.len());
        }
        WorkflowsCommand::Move {
            workflow,
            step,
            position,
        } => {
            let rec = wf::move_workflow_step(&store, &workflow, &step, position)?;
            let ids: Vec<&str> = rec.value.steps.iter().map(|s| s.id.as_str()).collect();
            println!("{}\t{}", rec.slug, ids.join(" → "));
        }
        WorkflowsCommand::Route {
            workflow,
            from,
            to,
            verdict,
            when,
        } => {
            let rec = wf::add_workflow_transition(
                &store,
                &workflow,
                &from,
                &to,
                when.as_deref(),
                verdict.as_deref(),
            )?;
            let step = &rec.value.steps[rec.value.step_index(&from).unwrap_or(0)];
            println!(
                "{}\t{}: {} transição(ões)",
                rec.slug,
                step.id,
                step.transitions.len()
            );
        }
        WorkflowsCommand::Unroute {
            workflow,
            from,
            index,
        } => {
            wf::remove_workflow_transition(&store, &workflow, &from, index)?;
        }
        WorkflowsCommand::Flow {
            workflow,
            input,
            prompt,
        } => {
            let plan = wf::workflow_plan(&store, &workflow, input.as_deref())?;
            let text = if prompt { plan.prompt() } else { plan.json() };
            println!("{}", text.map_err(|e| CliError::new(e.to_string()))?);
        }
    }
    Ok(0)
}

// ---- runs -------------------------------------------------------------------------------------------

fn run_runs(args: RunsArgs, ctx: &Context) -> Result<i32, CliError> {
    let cmd = args.command.unwrap_or(RunsCommand::List(args.list));
    let store = ctx.store()?;
    match cmd {
        RunsCommand::List(a) => {
            let status: Option<WorkflowRunStatus> = a.status.map(Into::into);
            let runs: Vec<_> = wf::list_runs(&store, a.workflow.as_deref())?
                .into_iter()
                .filter(|r| status.is_none_or(|s| r.run.status == s))
                .collect();
            if a.json {
                let rows: Vec<_> = runs
                    .iter()
                    .map(|r| serde_json::json!({"ref": r.reference, "run": r.run}))
                    .collect();
                print_json(&rows)?;
            } else {
                for r in &runs {
                    let open = r.run.open_questions().len();
                    println!(
                        "{}\t{}\t{}\t{} etapa(s){}",
                        r.reference,
                        status_str(r.run.status),
                        r.run.current.as_deref().unwrap_or("-"),
                        r.run.history.len(),
                        if open == 0 {
                            String::new()
                        } else {
                            format!("  ❓{open}")
                        }
                    );
                }
            }
        }
        RunsCommand::Show { execution, json } => {
            let reference = wf::resolve_run_ref(&store, &execution)?;
            let r = wf::load_run(&store, &reference)?;
            if json {
                print_json(&r)?;
                return Ok(0);
            }
            println!(
                "{reference} — {}{}",
                status_str(r.status),
                r.input
                    .as_ref()
                    .map(|i| format!(" — entrada: {i}"))
                    .unwrap_or_default()
            );
            if let Some(reason) = &r.reason {
                println!("{reason}");
            }
            for (n, e) in r.history.iter().enumerate() {
                println!(
                    "{}. [c{}] {} → {}{}{}",
                    n + 1,
                    e.cycle,
                    e.step,
                    e.verdict.as_deref().unwrap_or("—"),
                    e.next
                        .as_ref()
                        .map(|x| format!(" ⇒ {x}"))
                        .unwrap_or_else(|| " ⇒ fim".to_string()),
                    e.summary
                        .as_ref()
                        .map(|s| format!("  · {s}"))
                        .unwrap_or_default()
                );
            }
            if let Some(current) = &r.current
                && !r.is_finished()
            {
                println!("Próxima: {current}");
            }
            for q in &r.questions {
                println!(
                    "❓ {}. [{}] {}{}",
                    q.number,
                    q.step,
                    q.question,
                    q.answer
                        .as_ref()
                        .map(|a| format!(" → {a}"))
                        .unwrap_or_else(|| "  (aberta)".to_string())
                );
            }
        }
        RunsCommand::Start {
            workflow,
            provider,
            input,
            from,
            prompt,
            json,
        } => {
            let (reference, run, action) = wf::start_run(
                &store,
                &workflow,
                input.as_deref(),
                from.as_deref(),
                provider.map(Into::into),
            )?;
            if prompt {
                let slug = wf::resolve_workflow_slug(&store, &workflow)?;
                let w = wf::load_workflow(&store, &slug)?;
                println!(
                    "{}",
                    wf::orchestrator_prompt(
                        &reference,
                        &w.title,
                        input.as_deref(),
                        &cli_invocation(),
                        run.provider
                    )
                );
                return Ok(0);
            }
            return print_action(&action, json);
        }
        RunsCommand::Next { execution, json } => {
            return print_action(&wf::next_run_action(&store, &execution)?, json);
        }
        RunsCommand::Step { execution } => {
            println!(
                "{}",
                wf::run_step_prompt(&store, &execution, &cli_invocation())?
            );
        }
        RunsCommand::Record {
            execution,
            verdict,
            summary,
            to,
            none_holds,
            json,
        } => {
            let action = wf::record_run(
                &store,
                &execution,
                verdict.as_deref(),
                summary.as_deref(),
                to.as_deref(),
                none_holds,
            )?;
            return print_action(&action, json);
        }
        RunsCommand::Ask { execution } => {
            let mut text = String::new();
            std::io::stdin()
                .read_to_string(&mut text)
                .map_err(|e| CliError::new(e.to_string()))?;
            let drafts: Vec<WorkflowQuestionDraft> =
                match serde_json::from_str::<Vec<WorkflowQuestionDraft>>(&text) {
                    Ok(list) => list,
                    Err(_) => vec![
                        serde_json::from_str::<WorkflowQuestionDraft>(&text).map_err(|e| {
                            CliError::new(format!("JSON de perguntas inválido: {e}"))
                        })?,
                    ],
                };
            let added = wf::ask_run(&store, &execution, &drafts)?;
            let numbers: Vec<String> = added.iter().map(|q| q.number.to_string()).collect();
            println!(
                "Pergunta(s) gravada(s): {}. Termine com a última linha: PERGUNTA",
                numbers.join(", ")
            );
        }
        RunsCommand::Questions {
            execution,
            open,
            json,
        } => {
            let reference = wf::resolve_run_ref(&store, &execution)?;
            let r = wf::load_run(&store, &reference)?;
            let list: Vec<_> = r
                .questions
                .iter()
                .filter(|q| !open || q.is_open())
                .collect();
            if json {
                print_json(&list)?;
                return Ok(0);
            }
            for q in list {
                println!(
                    "{}. [{}] {}{}",
                    q.number,
                    q.step,
                    q.question,
                    q.answer
                        .as_ref()
                        .map(|a| format!(" → {a}"))
                        .unwrap_or_default()
                );
                for o in &q.options {
                    println!(
                        "   - {}{}",
                        o.label,
                        o.description
                            .as_ref()
                            .map(|d| format!(": {d}"))
                            .unwrap_or_default()
                    );
                }
            }
        }
        RunsCommand::Answer {
            execution,
            number,
            answer,
            json,
        } => {
            return print_action(&wf::answer_run(&store, &execution, number, &answer)?, json);
        }
        RunsCommand::Stop { execution, reason } => {
            let r = wf::stop_run(&store, &execution, reason.as_deref())?;
            println!("{execution}\t{}", status_str(r.status));
        }
        RunsCommand::Delete { execution } => {
            wf::delete_run(&store, &execution)?;
        }
        RunsCommand::Orchestrate { execution } => {
            let reference = wf::resolve_run_ref(&store, &execution)?;
            let r = wf::load_run(&store, &reference)?;
            let title = wf::load_workflow(&store, &r.workflow)
                .map(|w| w.title)
                .unwrap_or_else(|_| r.workflow.clone());
            println!(
                "{}",
                wf::orchestrator_prompt(
                    &reference,
                    &title,
                    r.input.as_deref(),
                    &cli_invocation(),
                    r.provider
                )
            );
        }
    }
    Ok(0)
}
