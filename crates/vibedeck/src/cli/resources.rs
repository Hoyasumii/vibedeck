//! Comandos CLI — agentes, comandos, skills e kits.
//!
//! `agents`, `commands` e `skills` têm os mesmos subcomandos (`list` é o padrão: as opções dele valem no
//! nível do grupo); `kits` tem `list` e `add`. A lógica fica em `vibedeck_core::resources`.

use std::path::PathBuf;

use clap::{Args, Subcommand};
use vibedeck_core::Store;
use vibedeck_core::model::{Agent, AiProvider, Author, Command as Cmd, NextStepKind, Skill};
use vibedeck_core::project::links::hashtags;
use vibedeck_core::resources::{
    self, NewPersona, Persona, flow_for, group_path, import_agents, import_commands, import_skills,
    kits, persona::View, with_slug_and_group,
};

use super::output::print_json;
use super::{CliError, Context};

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Agentes do VibeDeck (nome, modelo, prompt) e os próximos passos que formam um fluxo.
    Agents(AgentsArgs),
    /// Comandos do VibeDeck (prompt no formato de slash command) e os próximos passos que formam um fluxo.
    Commands(CommandsArgs),
    /// Skills do VibeDeck (instruções no formato do SKILL.md) e os próximos passos que formam um fluxo.
    Skills(SkillsArgs),
    /// Kits pré-definidos de agentes, comandos, skills e workflows.
    Kits(KitsArgs),
}

pub fn run(command: Command, ctx: &Context) -> Result<i32, CliError> {
    match command {
        Command::Agents(a) => run_agents(a, ctx)?,
        Command::Commands(a) => run_commands(a, ctx)?,
        Command::Skills(a) => run_skills(a, ctx)?,
        Command::Kits(a) => run_kits(a, ctx)?,
    }
    Ok(0)
}

fn err(e: impl std::fmt::Display) -> CliError {
    CliError::new(e.to_string())
}

// ---- argumentos compartilhados --------------------------------------------------------------------

#[derive(Args, Debug)]
pub struct ShowArgs {
    /// Slug, id (ou prefixo >= 4) ou título.
    pub reference: String,
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Debug)]
pub struct NextArgs {
    /// Item de origem (slug, id ou título).
    pub reference: String,
    /// Agente, comando ou skill do VibeDeck (slug, id ou título).
    pub target: String,
    #[arg(long, default_value = "agent", value_parser = ["agent", "command", "skill"])]
    pub kind: String,
    #[arg(long)]
    pub note: Option<String>,
}

#[derive(Args, Debug)]
pub struct UnnextArgs {
    /// Item de origem (slug, id ou título).
    pub reference: String,
    /// Passo a remover (slug, id ou título do agente/comando/skill).
    pub target: String,
}

#[derive(Args, Debug)]
pub struct FlowArgs {
    /// Slug, id ou título.
    pub reference: String,
}

#[derive(Args, Debug)]
pub struct ImportArgs {
    /// Provedor: claude ou codex.
    #[arg(long, default_value = "claude", value_parser = ["claude", "codex"])]
    pub provider: String,
    /// Sobrescreve itens já existentes.
    #[arg(long)]
    pub overwrite: bool,
    /// Diretório com os arquivos a importar (substitui os padrões).
    #[arg(long)]
    pub dir: Option<PathBuf>,
    /// Marca os itens como criados por IA.
    #[arg(long)]
    pub ai: bool,
}

#[derive(Args, Debug)]
pub struct ListArgs {
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Debug)]
pub struct NewCommon {
    /// Título (vira o slug).
    pub title: String,
    #[arg(long)]
    pub model: Option<String>,
    #[arg(long)]
    pub summary: Option<String>,
    #[arg(long, default_value = "")]
    pub prompt: String,
    #[arg(long, num_args = 1..)]
    pub tools: Vec<String>,
    #[arg(long, num_args = 1..)]
    pub tags: Vec<String>,
    /// Marca o item como criado por IA.
    #[arg(long)]
    pub ai: bool,
}

#[derive(Args, Debug)]
pub struct SetCommon {
    /// Slug, id ou título.
    pub reference: String,
    #[arg(long)]
    pub title: Option<String>,
    #[arg(long)]
    pub model: Option<String>,
    #[arg(long, value_parser = ["claude", "codex"])]
    pub provider: Option<String>,
    #[arg(long)]
    pub effort: Option<String>,
    #[arg(long)]
    pub summary: Option<String>,
    #[arg(long)]
    pub prompt: Option<String>,
}

// ---- agents -----------------------------------------------------------------------------------------

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct AgentsArgs {
    #[command(subcommand)]
    pub command: Option<AgentsCmd>,
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum AgentsCmd {
    /// Lista os agentes.
    List(ListArgs),
    /// Mostra um agente.
    Show(ShowArgs),
    /// Cria um agente e imprime o slug.
    New(NewAgent),
    /// Edita campos do agente.
    Set(SetAgent),
    /// Adiciona um próximo passo (agente, comando ou skill do VibeDeck) ao agente.
    Next(NextArgs),
    /// Remove um próximo passo do agente.
    Unnext(UnnextArgs),
    /// Imprime o JSON do fluxo (agente + próximos passos) para orquestrar a IA em um prompt.
    Flow(FlowArgs),
    /// Importa agentes do Claude Code (.claude/agents do projeto e do usuário).
    Import(ImportArgs),
}

#[derive(Args, Debug)]
pub struct NewAgent {
    #[command(flatten)]
    pub common: NewCommon,
}

#[derive(Args, Debug)]
pub struct SetAgent {
    #[command(flatten)]
    pub common: SetCommon,
}

// ---- commands ---------------------------------------------------------------------------------------

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct CommandsArgs {
    #[command(subcommand)]
    pub command: Option<CommandsCmd>,
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum CommandsCmd {
    /// Lista os comandos.
    List(ListArgs),
    /// Mostra um comando.
    Show(ShowArgs),
    /// Cria um comando e imprime o slug.
    New(NewCommand),
    /// Edita campos do comando.
    Set(SetCommand),
    /// Adiciona um próximo passo (agente, comando ou skill do VibeDeck) ao comando.
    Next(NextArgs),
    /// Remove um próximo passo do comando.
    Unnext(UnnextArgs),
    /// Imprime o JSON do fluxo (comando + próximos passos) para orquestrar a IA em um prompt.
    Flow(FlowArgs),
    /// Importa comandos do Claude Code (.claude/commands do projeto e do usuário).
    Import(ImportArgs),
}

#[derive(Args, Debug)]
pub struct NewCommand {
    #[command(flatten)]
    pub common: NewCommon,
    /// O que vai em $ARGUMENTS (ex.: "<mensagem>").
    #[arg(long)]
    pub argument_hint: Option<String>,
}

#[derive(Args, Debug)]
pub struct SetCommand {
    #[command(flatten)]
    pub common: SetCommon,
    #[arg(long)]
    pub argument_hint: Option<String>,
}

// ---- skills -----------------------------------------------------------------------------------------

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct SkillsArgs {
    #[command(subcommand)]
    pub command: Option<SkillsCmd>,
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum SkillsCmd {
    /// Lista as skills.
    List(ListArgs),
    /// Mostra uma skill.
    Show(ShowArgs),
    /// Cria uma skill e imprime o slug.
    New(NewSkill),
    /// Edita campos da skill.
    Set(SetAgent),
    /// Adiciona um próximo passo (agente, comando ou skill do VibeDeck) à skill.
    Next(NextArgs),
    /// Remove um próximo passo da skill.
    Unnext(UnnextArgs),
    /// Imprime o JSON do fluxo (skill + próximos passos) para orquestrar a IA em um prompt.
    Flow(FlowArgs),
    /// Importa skills do Claude Code (.claude/skills/<nome>/SKILL.md do projeto e do usuário).
    Import(ImportArgs),
}

#[derive(Args, Debug)]
pub struct NewSkill {
    #[command(flatten)]
    pub common: NewCommon,
    /// Caminho completo grupo/slug.
    #[arg(long)]
    pub reference: Option<String>,
}

// ---- kits -------------------------------------------------------------------------------------------

#[derive(Args, Debug)]
pub struct KitsArgs {
    #[command(subcommand)]
    pub command: KitsCmd,
}

#[derive(Subcommand, Debug)]
pub enum KitsCmd {
    /// Consulta os conteúdos e as dependências do catálogo, sem adicionar itens.
    List {
        /// Saída em JSON.
        #[arg(long)]
        json: bool,
    },
    /// Adiciona a seleção explícita do catálogo; exige selecionar todas as dependências.
    Add {
        /// Ids de kits completos ou de itens (consulte kits list).
        items: Vec<String>,
        /// Marca os itens como criados por IA.
        #[arg(long)]
        ai: bool,
        /// Saída em JSON.
        #[arg(long)]
        json: bool,
    },
}

// ---- execução comum ---------------------------------------------------------------------------------

fn author(ai: bool) -> Author {
    if ai { Author::Ai } else { Author::Human }
}

fn provider_of(s: &str) -> AiProvider {
    if s == "codex" {
        AiProvider::Codex
    } else {
        AiProvider::Claude
    }
}

fn kind_of(s: &str) -> NextStepKind {
    match s {
        "command" => NextStepKind::Command,
        "skill" => NextStepKind::Skill,
        _ => NextStepKind::Agent,
    }
}

fn list_line<P: Persona>(slug: &str, value: &P) -> String {
    let v = value.view();
    let hint = if P::KIND == NextStepKind::Command {
        v.argument_hint.map(|h| format!(" {h}")).unwrap_or_default()
    } else {
        String::new()
    };
    format!(
        "{slug}\t{}{hint}  [{}]  → {} passo(s){}",
        v.title,
        v.model.unwrap_or("herdado"),
        v.next_steps.len(),
        hashtags(v.tags)
    )
}

fn show_text<P: Persona>(v: View<'_>) {
    println!("{} — modelo: {}", v.title, v.model.unwrap_or("herdado"));
    if let Some(s) = v.summary {
        println!("{s}");
    }
    if P::KIND == NextStepKind::Command
        && let Some(h) = v.argument_hint
    {
        println!("Argumentos: {h}");
    }
    if !v.tools.is_empty() {
        println!("Ferramentas: {}", v.tools.join(", "));
    }
    println!("\n{}\n", v.prompt);
    for step in v.next_steps {
        let kind = match step.kind {
            NextStepKind::Agent => "agent",
            NextStepKind::Command => "command",
            NextStepKind::Skill => "skill",
        };
        let note = step
            .note
            .as_ref()
            .map(|n| format!(" — {n}"))
            .unwrap_or_default();
        println!("→ [{kind}] {}{note}", step.r#ref);
    }
}

fn do_list<P: Persona>(store: &Store, json: bool) -> Result<(), CliError> {
    let records = store.list::<P>().map_err(err)?;
    if json {
        if P::KIND == NextStepKind::Skill {
            let rows: Vec<_> = records
                .iter()
                .map(|r| with_slug_and_group(&r.slug, &r.value))
                .collect();
            return print_json(&rows);
        }
        let rows: Vec<&P> = records.iter().map(|r| &r.value).collect();
        return print_json(&rows);
    }
    for r in &records {
        println!("{}", list_line(&r.slug, &r.value));
    }
    Ok(())
}

fn do_show<P: Persona>(store: &Store, a: ShowArgs) -> Result<(), CliError> {
    let slug = store.resolve::<P>(&a.reference).map_err(err)?;
    let value = store.load::<P>(&slug).map_err(err)?;
    if a.json {
        return print_json(&value);
    }
    show_text::<P>(value.view());
    Ok(())
}

fn new_persona(
    c: NewCommon,
    argument_hint: Option<String>,
    reference: Option<String>,
) -> NewPersona {
    NewPersona {
        title: c.title,
        summary: c.summary,
        argument_hint,
        model: c.model,
        tools: c.tools,
        prompt: c.prompt,
        tags: c.tags,
        author: author(c.ai),
        reference,
    }
}

fn do_new<P: Persona>(store: &Store, new: NewPersona) -> Result<(), CliError> {
    let rec = resources::create::<P>(store, new).map_err(err)?;
    println!("{}", rec.slug);
    Ok(())
}

fn do_set<P: Persona>(
    store: &Store,
    c: SetCommon,
    argument_hint: Option<String>,
) -> Result<(), CliError> {
    let rec = resources::update::<P>(store, &c.reference, |f| {
        if let Some(t) = &c.title {
            *f.title = t.clone();
        }
        resources::set_provider_or_model(
            f,
            c.provider.as_deref(),
            c.model.as_deref(),
            c.effort.as_deref(),
        );
        if let Some(s) = &c.summary {
            *f.summary = resources::persona::non_empty_or_nil(s);
        }
        if let (Some(h), Some(slot)) = (&argument_hint, f.argument_hint.as_deref_mut()) {
            *slot = resources::persona::non_empty_or_nil(h);
        }
        if let Some(p) = &c.prompt {
            *f.prompt = p.clone();
        }
        Ok(())
    })
    .map_err(err)?;
    println!("{}\t{}", rec.slug, rec.value.view().title);
    Ok(())
}

fn do_next<P: Persona>(store: &Store, a: NextArgs) -> Result<(), CliError> {
    let rec = resources::add_next_step::<P>(
        store,
        &a.reference,
        kind_of(&a.kind),
        &a.target,
        a.note.as_deref(),
    )
    .map_err(err)?;
    println!(
        "{}\t{} passo(s)",
        rec.slug,
        rec.value.view().next_steps.len()
    );
    Ok(())
}

fn do_unnext<P: Persona>(store: &Store, a: UnnextArgs) -> Result<(), CliError> {
    resources::remove_next_step::<P>(store, &a.reference, &a.target).map_err(err)?;
    Ok(())
}

fn do_flow<P: Persona>(store: &Store, a: FlowArgs) -> Result<(), CliError> {
    let json = flow_for(store, P::KIND, &a.reference).map_err(err)?;
    println!("{json}");
    Ok(())
}

type Importer = fn(
    &Store,
    AiProvider,
    Option<&[PathBuf]>,
    bool,
    Author,
) -> resources::Result<resources::ImportResult>;

fn do_import(store: &Store, a: ImportArgs, importer: Importer) -> Result<(), CliError> {
    let dirs = a.dir.map(|d| vec![d]);
    let result = importer(
        store,
        provider_of(&a.provider),
        dirs.as_deref(),
        a.overwrite,
        author(a.ai),
    )
    .map_err(err)?;
    for w in &result.warnings {
        eprintln!("{w}");
    }
    for s in &result.slugs {
        println!("{s}");
    }
    if result.slugs.is_empty() {
        println!("Nada para importar.");
    }
    Ok(())
}

fn run_agents(a: AgentsArgs, ctx: &Context) -> Result<(), CliError> {
    let store = ctx.store()?;
    match a
        .command
        .unwrap_or(AgentsCmd::List(ListArgs { json: a.json }))
    {
        AgentsCmd::List(l) => do_list::<Agent>(&store, l.json),
        AgentsCmd::Show(s) => do_show::<Agent>(&store, s),
        AgentsCmd::New(n) => do_new::<Agent>(&store, new_persona(n.common, None, None)),
        AgentsCmd::Set(s) => do_set::<Agent>(&store, s.common, None),
        AgentsCmd::Next(n) => do_next::<Agent>(&store, n),
        AgentsCmd::Unnext(u) => do_unnext::<Agent>(&store, u),
        AgentsCmd::Flow(f) => do_flow::<Agent>(&store, f),
        AgentsCmd::Import(i) => do_import(&store, i, import_agents),
    }
}

fn run_commands(a: CommandsArgs, ctx: &Context) -> Result<(), CliError> {
    let store = ctx.store()?;
    match a
        .command
        .unwrap_or(CommandsCmd::List(ListArgs { json: a.json }))
    {
        CommandsCmd::List(l) => do_list::<Cmd>(&store, l.json),
        CommandsCmd::Show(s) => do_show::<Cmd>(&store, s),
        CommandsCmd::New(n) => do_new::<Cmd>(&store, new_persona(n.common, n.argument_hint, None)),
        CommandsCmd::Set(s) => do_set::<Cmd>(&store, s.common, s.argument_hint),
        CommandsCmd::Next(n) => do_next::<Cmd>(&store, n),
        CommandsCmd::Unnext(u) => do_unnext::<Cmd>(&store, u),
        CommandsCmd::Flow(f) => do_flow::<Cmd>(&store, f),
        CommandsCmd::Import(i) => do_import(&store, i, import_commands),
    }
}

fn run_skills(a: SkillsArgs, ctx: &Context) -> Result<(), CliError> {
    let store = ctx.store()?;
    match a
        .command
        .unwrap_or(SkillsCmd::List(ListArgs { json: a.json }))
    {
        SkillsCmd::List(l) => do_list::<Skill>(&store, l.json),
        SkillsCmd::Show(s) => do_show::<Skill>(&store, s),
        SkillsCmd::New(n) => do_new::<Skill>(&store, new_persona(n.common, None, n.reference)),
        SkillsCmd::Set(s) => do_set::<Skill>(&store, s.common, None),
        SkillsCmd::Next(n) => do_next::<Skill>(&store, n),
        SkillsCmd::Unnext(u) => do_unnext::<Skill>(&store, u),
        SkillsCmd::Flow(f) => do_flow::<Skill>(&store, f),
        SkillsCmd::Import(i) => do_import(&store, i, import_skills),
    }
}

fn run_kits(a: KitsArgs, ctx: &Context) -> Result<(), CliError> {
    match a.command {
        KitsCmd::List { json } => {
            if json {
                return print_json(&kits());
            }
            for kit in kits() {
                println!("{} · {} — {}", kit.id, kit.title, kit.summary);
                for item in &kit.items {
                    println!("  {} · {}: {}", item.id, item.kind.title(), item.title);
                }
            }
            Ok(())
        }
        KitsCmd::Add { items, ai, json } => {
            let store = ctx.store()?;
            let added = resources::add_kit_items(&store, &items, author(ai)).map_err(err)?;
            if json {
                return print_json(&added);
            }
            for item in &added {
                println!("{}: {}", item.kind.title(), item.slug);
            }
            Ok(())
        }
    }
}

// `group_path` é reexportado para quem monta saídas de skills fora deste módulo.
#[allow(dead_code)]
fn _group(slug: &str) -> String {
    group_path(slug)
}
