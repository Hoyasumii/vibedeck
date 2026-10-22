//! Comandos CLI — Projeto: init, status, links, coleção Claude (claude items), tags, grafo (export), logs.
//!
//! A área declara seus comandos de primeiro nível em `Command` e os executa em `run`.

use std::path::PathBuf;

use clap::{Args, Subcommand};
use vibedeck_core::model::ClaudeItemKind;
use vibedeck_core::project::{self, ProjectError, claude, graph, links, logs, tags};

use super::output::print_json;
use super::{CliError, Context};

const TAG_KINDS: [&str; 10] = [
    "doc", "review", "rules", "idea", "agent", "command", "skill", "workflow", "stack", "pattern",
];
const LOG_LEVELS: [&str; 5] = ["debug", "info", "warning", "error", "crash"];

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Cria vibedeck.json e .vibedeck/ no diretório.
    Init(InitArgs),
    /// Resumo do projeto.
    Status(StatusArgs),
    /// Exporta a visualização local do grafo, sem consumir IA.
    Graph(GraphArgs),
    /// Links do projeto.
    Links(Box<LinksArgs>),
    /// Coleção de artefatos e docs do Claude deste projeto.
    Claude(Box<ClaudeArgs>),
    /// Define as tags de um doc, grupo de revisão, tópico de regras, ideia, agente, comando, skill, workflow, tecnologia da stack ou padrão (sem tags: remove todas).
    Tag(TagArgs),
    /// Logs de erros, falhas e crashes do app, do CLI e do MCP (ficam fora do projeto).
    Logs(Box<LogsArgs>),
}

impl From<ProjectError> for CliError {
    fn from(e: ProjectError) -> Self {
        CliError::new(e.to_string())
    }
}

pub fn run(command: Command, ctx: &Context) -> Result<i32, CliError> {
    match command {
        Command::Init(a) => init(a, ctx)?,
        Command::Status(a) => status(a, ctx)?,
        Command::Graph(a) => match a.command {
            GraphCommand::Export => {
                let root = ctx.root()?;
                println!("{}", graph::export(&root)?);
            }
        },
        Command::Links(a) => run_links(*a, ctx)?,
        Command::Claude(a) => run_claude(*a, ctx)?,
        Command::Tag(a) => run_tag(a, ctx)?,
        Command::Logs(a) => run_logs(*a, ctx)?,
    }
    Ok(0)
}

// ---- init / status ----------------------------------------------------------------------------------

#[derive(Args, Debug)]
pub struct InitArgs {
    /// Diretório (padrão: atual).
    directory: Option<PathBuf>,
    /// Nome do projeto (padrão: nome da pasta).
    #[arg(long)]
    name: Option<String>,
    /// Descrição.
    #[arg(long)]
    description: Option<String>,
}

fn init(a: InitArgs, ctx: &Context) -> Result<(), CliError> {
    let dir = match a.directory {
        Some(d) => expand_tilde(d),
        None => ctx.start_dir()?,
    };
    // Como `ProjectStore.initialize`: o guia (AGENTS.md/guide.md) nasce junto com o projeto.
    let store = project::init_with(&dir, a.name.as_deref(), a.description.as_deref(), |store| {
        vibedeck_core::ai::guide::write_agents_guide(store).map_err(|e| match e {
            vibedeck_core::ai::AiError::Core(core) => core,
            other => vibedeck_core::Error::Io {
                path: store.data_dir(),
                source: std::io::Error::other(other.to_string()),
            },
        })
    })?;
    println!("Projeto criado em {}", store.root().display());
    Ok(())
}

fn expand_tilde(p: PathBuf) -> PathBuf {
    let s = p.to_string_lossy();
    if let Some(rest) = s.strip_prefix("~/").or((s == "~").then_some(""))
        && let Some(home) = std::env::var_os("HOME")
    {
        return PathBuf::from(home).join(rest);
    }
    p
}

#[derive(Args, Debug)]
pub struct StatusArgs {
    /// Saída JSON.
    #[arg(long)]
    json: bool,
}

fn status(a: StatusArgs, ctx: &Context) -> Result<(), CliError> {
    let st = project::status::status(&ctx.store()?)?;
    if a.json {
        return print_json(&st.summary);
    }
    for line in st.text_lines() {
        println!("{line}");
    }
    Ok(())
}

// ---- graph ------------------------------------------------------------------------------------------

#[derive(Args, Debug)]
pub struct GraphArgs {
    #[command(subcommand)]
    command: GraphCommand,
}

#[derive(Subcommand, Debug)]
pub enum GraphCommand {
    /// Substitui graph.html pela visualização offline segura do VibeDeck.
    Export,
}

// ---- links ------------------------------------------------------------------------------------------

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct LinksArgs {
    #[command(subcommand)]
    command: Option<LinksCommand>,
    #[command(flatten)]
    list: LinksList,
}

#[derive(Args, Debug)]
pub struct LinksList {
    /// Saída JSON.
    #[arg(long)]
    json: bool,
}

#[derive(Subcommand, Debug)]
pub enum LinksCommand {
    /// Lista os links.
    List(LinksList),
    /// Adiciona um link e imprime o id.
    Add {
        url: String,
        #[arg(long)]
        title: Option<String>,
        #[arg(long, num_args = 1..)]
        tags: Vec<String>,
    },
    /// Remove links pelo id ou prefixo do id.
    Remove {
        /// Id ou prefixo do id.
        id: String,
    },
}

fn run_links(a: LinksArgs, ctx: &Context) -> Result<(), CliError> {
    let command = a.command.unwrap_or(LinksCommand::List(a.list));
    let store = ctx.store()?;
    match command {
        LinksCommand::List(l) => {
            let all = links::list(&store)?;
            if l.json {
                return print_json(&all);
            }
            for link in all {
                println!(
                    "{}  {}  {}{}",
                    links::id8(&link.id),
                    link.title,
                    link.url,
                    links::hashtags(&link.tags)
                );
            }
        }
        LinksCommand::Add { url, title, tags } => {
            let link = links::add(&store, &url, title.as_deref(), tags)?;
            println!("{}", link.id);
        }
        LinksCommand::Remove { id } => {
            links::remove(&store, &id)?;
        }
    }
    Ok(())
}

// ---- claude -----------------------------------------------------------------------------------------

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct ClaudeArgs {
    #[command(subcommand)]
    command: Option<ClaudeCommand>,
    #[command(flatten)]
    list: ClaudeList,
}

#[derive(Args, Debug)]
pub struct ClaudeList {
    /// Saída JSON.
    #[arg(long)]
    json: bool,
    /// Filtrar por artifact ou doc.
    #[arg(long, value_parser = ["artifact", "doc"])]
    kind: Option<String>,
}

#[derive(Subcommand, Debug)]
pub enum ClaudeCommand {
    /// Lista os itens da coleção.
    List(ClaudeList),
    /// Adiciona um item (só claude.ai) e imprime o id.
    Add {
        url: String,
        /// Tipo escolhido pelo usuário: artifact ou doc.
        #[arg(long, value_parser = ["artifact", "doc"])]
        kind: String,
        #[arg(long)]
        title: Option<String>,
        #[arg(long, num_args = 1..)]
        tags: Vec<String>,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Remove um item.
    Remove {
        /// Id, prefixo (pelo menos 4 caracteres) ou título.
        id: String,
    },
}

fn kind_of(text: &str) -> ClaudeItemKind {
    claude::parse_kind(text).unwrap_or(ClaudeItemKind::Artifact)
}

/// Equivalente em pt-BR ao `Date.formatted()` do Foundation (determinístico, em UTC).
fn format_added(item: &vibedeck_core::model::ClaudeItem) -> String {
    item.added_at.0.format("%d/%m/%Y %H:%M").to_string()
}

fn run_claude(a: ClaudeArgs, ctx: &Context) -> Result<(), CliError> {
    let command = a.command.unwrap_or(ClaudeCommand::List(a.list));
    let store = ctx.store()?;
    match command {
        ClaudeCommand::List(l) => {
            let items = claude::list(&store, l.kind.as_deref().map(kind_of))?;
            if l.json {
                return print_json(&items);
            }
            for item in items {
                println!(
                    "{}  [{}] {}  {}  {}{}",
                    links::id8(&item.id),
                    claude::kind_title(item.kind),
                    item.title,
                    item.url,
                    format_added(&item),
                    links::hashtags(&item.tags)
                );
            }
        }
        ClaudeCommand::Add {
            url,
            kind,
            title,
            tags,
            json,
        } => {
            let item = claude::add(&store, &url, kind_of(&kind), title.as_deref(), tags)?;
            if json {
                return print_json(&item);
            }
            println!("{}", item.id);
        }
        ClaudeCommand::Remove { id } => claude::remove(&store, &id)?,
    }
    Ok(())
}

// ---- tag --------------------------------------------------------------------------------------------

#[derive(Args, Debug)]
pub struct TagArgs {
    /// doc, review, rules, idea, agent, command, skill, workflow, stack ou pattern.
    #[arg(value_parser = TAG_KINDS)]
    kind: String,
    /// Slug, id ou título.
    reference: String,
    /// Tags (substituem as atuais).
    tags: Vec<String>,
}

fn run_tag(a: TagArgs, ctx: &Context) -> Result<(), CliError> {
    let store = ctx.store()?;
    let kind = tags::TagKind::from_cli(&a.kind)
        .ok_or_else(|| CliError::new(ProjectError::InvalidTagKind(a.kind.clone()).to_string()))?;
    tags::set_tags(&store, kind, &a.reference, &a.tags)?;
    println!("{}", tags::message(&a.tags));
    Ok(())
}

// ---- logs -------------------------------------------------------------------------------------------

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct LogsArgs {
    #[command(subcommand)]
    command: Option<LogsCommand>,
    #[command(flatten)]
    list: LogsList,
}

#[derive(Args, Debug)]
pub struct LogsFilter {
    /// Período: 30m, 24h, 7d.
    #[arg(long, default_value = "24h")]
    since: String,
    /// Nível mínimo: debug, info, warning, error ou crash.
    #[arg(long, default_value = "warning", value_parser = LOG_LEVELS)]
    level: String,
    /// Componentes: app, cli, mcp, core, rules, ai, hook.
    #[arg(long, num_args = 1..)]
    component: Vec<String>,
    /// Inclui todos os projetos (padrão: só o projeto atual, se houver).
    #[arg(long)]
    all_projects: bool,
    /// Texto a procurar no evento, na mensagem ou no contexto.
    #[arg(long)]
    search: Option<String>,
    /// Id de correlação da ação.
    #[arg(long)]
    action: Option<String>,
    /// Máximo de entradas.
    #[arg(long, default_value_t = 100, allow_negative_numbers = true)]
    limit: i64,
}

impl LogsFilter {
    fn filter(&self, ctx: &Context) -> Result<logs::LogFilter, CliError> {
        let project = if self.all_projects {
            None
        } else {
            ctx.root().ok().map(|r| r.to_string_lossy().into_owned())
        };
        Ok(logs::LogFilter {
            since: Some(logs::LogFilter::parse_since(
                &self.since,
                vibedeck_core::time::now(),
            )?),
            min_level: logs::LogFilter::parse_level(&self.level)?,
            components: logs::LogFilter::parse_components(&self.component)?,
            project,
            search: self.search.clone(),
            action: self.action.clone(),
            limit: self.limit,
        })
    }
}

#[derive(Args, Debug)]
pub struct LogsList {
    #[command(flatten)]
    filter: LogsFilter,
    /// Saída JSON.
    #[arg(long)]
    json: bool,
}

#[derive(Subcommand, Debug)]
pub enum LogsCommand {
    /// Lista as entradas mais recentes primeiro.
    List(LogsList),
    /// Relatório em texto, do mais antigo ao mais novo, para colar numa issue.
    Report(LogsReport),
    /// Crashes e encerramentos inesperados do app registrados.
    Crashes {
        /// Período: 30m, 24h, 7d.
        #[arg(long, default_value = "14d")]
        since: String,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Mostra a pasta dos logs.
    Path,
}

#[derive(Args, Debug)]
pub struct LogsReport {
    #[command(flatten)]
    filter: LogsFilter,
}

fn print_entries(entries: Vec<logs::LogEntry>, json: bool, empty: &str) -> Result<(), CliError> {
    if json {
        return print_json(&entries);
    }
    if entries.is_empty() {
        println!("{empty}");
    }
    for e in entries {
        println!("{}", e.line());
    }
    Ok(())
}

fn run_logs(a: LogsArgs, ctx: &Context) -> Result<(), CliError> {
    let command = a.command.unwrap_or(LogsCommand::List(a.list));
    let store = logs::LogStore::default_store();
    match command {
        LogsCommand::List(l) => {
            let entries = store.entries(&l.filter.filter(ctx)?);
            print_entries(entries, l.json, "Nenhuma entrada no período.")?;
        }
        LogsCommand::Report(r) => {
            let header = format!(
                "Relatório de diagnóstico do VibeDeck {}",
                env!("CARGO_PKG_VERSION")
            );
            print!("{}", store.report(&r.filter.filter(ctx)?, Some(&header)));
        }
        LogsCommand::Crashes { since, json } => {
            let filter = logs::LogFilter {
                since: Some(logs::LogFilter::parse_since(
                    &since,
                    vibedeck_core::time::now(),
                )?),
                min_level: logs::LogLevel::Crash,
                ..logs::LogFilter::default()
            };
            print_entries(
                store.entries(&filter),
                json,
                "Nenhum crash registrado no período.",
            )?;
        }
        LogsCommand::Path => println!("{}", store.dir.display()),
    }
    Ok(())
}
