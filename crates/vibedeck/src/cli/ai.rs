//! Comandos CLI — IA: guia embutido, catálogo, contexto, uso, reorganize e (para o `McpCommand`) o registro
//! do servidor MCP nos agentes.
//!
//! A área declara seus comandos de primeiro nível em `Command` e os executa em `run`.

use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command as Process, Stdio};

use clap::{Args, Subcommand, ValueEnum};
use serde_json::json;
use vibedeck_core::ai::codex::{self, RateLimit};
use vibedeck_core::ai::context::ContextStore;
use vibedeck_core::ai::mcp_install::{self, Scope};
use vibedeck_core::ai::usage::{self, UsageStore};
use vibedeck_core::ai::{Provider, catalog, guide, item, reorganize};
use vibedeck_core::model::ProviderSettings;

use super::output::print_json;
use super::{CliError, Context};

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Documentação, contexto e consumo local de IA.
    #[command(subcommand_required = true, arg_required_else_help = true)]
    Ai {
        #[command(subcommand)]
        command: AiCommand,
    },
    /// Limites de uso do Claude Code (sessão de 5h e semana), lidos da statusline dele.
    Usage(UsageArgs),
    /// Propõe organização com IA; só aplica ações com aceite explícito.
    #[command(subcommand_required = true, arg_required_else_help = true)]
    Reorganize {
        #[command(subcommand)]
        command: ReorganizeCommand,
    },
}

#[derive(Subcommand, Debug)]
pub enum AiCommand {
    /// Índice do guia; leia uma seção por vez.
    Guide {
        /// Número da seção no índice.
        #[arg(long, allow_hyphen_values = true)]
        section: Option<i64>,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Lê uma página de contexto local, sem perder o restante.
    Context {
        /// Identificador da referência.
        id: String,
        /// Saída JSON com próxima posição.
        #[arg(long)]
        json: bool,
        #[arg(long, default_value_t = 0, allow_hyphen_values = true)]
        offset: i64,
        #[arg(long, default_value_t = 4000, allow_hyphen_values = true)]
        limit: i64,
    },
    /// Lista registros sem carregar prompts; JSON paginado.
    Catalog {
        /// agents, commands, skills, workflows ou rules.
        kind: String,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
        #[arg(long, default_value_t = 0, allow_hyphen_values = true)]
        offset: i64,
        #[arg(long, default_value_t = 20, allow_hyphen_values = true)]
        limit: i64,
    },
    /// Consumo local por tarefa; dados ausentes são não informados.
    Usage {
        /// Saída JSON.
        #[arg(long)]
        json: bool,
        /// Apaga somente as métricas locais deste projeto.
        #[arg(long)]
        clear: bool,
    },
    /// Prompt e schema para criar/editar agente, comando, skill ou workflow com IA (não grava).
    #[command(name = "item-prompt")]
    ItemPrompt {
        /// agent, command, skill ou workflow.
        kind: String,
        /// O que a IA deve criar ou mudar.
        #[arg(long)]
        request: String,
        /// Item existente a editar (omita para criar).
        #[arg(long)]
        item: Option<String>,
    },
    /// Valida o JSON da IA e cria (author=ai) ou substitui o item; erro em pt-BR sem gravar.
    #[command(name = "item-apply")]
    ItemApply {
        /// agent, command, skill ou workflow.
        kind: String,
        /// Arquivo com o JSON da proposta (ou - para a entrada padrão).
        #[arg(long)]
        file: String,
        /// Item existente a substituir (omita para criar).
        #[arg(long)]
        item: Option<String>,
    },
}

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct UsageArgs {
    /// Sem subcomando equivale a `show`.
    #[command(subcommand)]
    pub command: Option<UsageCommand>,
    #[command(flatten)]
    pub show: ShowArgs,
}

#[derive(Args, Debug, Default)]
pub struct ShowArgs {
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
    #[arg(long, value_enum, default_value = "claude")]
    pub provider: ProviderArg,
}

#[derive(Debug, Clone, Copy, ValueEnum, Default, PartialEq, Eq)]
#[value(rename_all = "lower")]
pub enum ProviderArg {
    #[default]
    Claude,
    Codex,
}

impl From<ProviderArg> for Provider {
    fn from(p: ProviderArg) -> Self {
        match p {
            ProviderArg::Claude => Provider::Claude,
            ProviderArg::Codex => Provider::Codex,
        }
    }
}

#[derive(Subcommand, Debug)]
pub enum UsageCommand {
    /// Mostra o último uso informado pelo Claude Code.
    Show(ShowArgs),
    /// Comando da statusline: lê o JSON do Claude Code no stdin, grava o uso e imprime a linha.
    Record {
        /// Statusline anterior: recebe o mesmo JSON e a saída dela é a que aparece.
        #[arg(long)]
        then: Option<String>,
    },
    /// Liga a statusline do Claude Code (~/.claude/settings.json) ao VibeDeck, mantendo a atual encadeada.
    Install,
    /// Desliga a statusline do VibeDeck, devolvendo a anterior.
    Uninstall,
}

#[derive(Subcommand, Debug)]
pub enum ReorganizeCommand {
    /// Exporta prompt, schema e fingerprint sem gravar.
    Prompt,
    /// Analisa com provedor somente leitura; saída é uma proposta JSON.
    Analyze {
        /// claude ou codex; escolha explícita.
        #[arg(long)]
        provider: String,
        /// Modelo do provedor.
        #[arg(long)]
        model: Option<String>,
        /// Esforço do modelo.
        #[arg(long)]
        effort: Option<String>,
    },
    /// Converte resposta JSON em proposta validada, sem gravar.
    Validate {
        /// JSON da resposta da IA; - lê stdin.
        #[arg(long)]
        file: String,
        /// Fingerprint fornecido por prompt.
        #[arg(long)]
        fingerprint: String,
    },
    /// Aplica somente IDs aceitos; conflitos precisam de escolha explícita.
    Apply {
        /// Arquivo JSON da proposta validada.
        #[arg(long)]
        file: String,
        /// JSON de aceite: selected (IDs) e conflicts (ID da ação -> chave do item mantido).
        #[arg(long)]
        acceptance: String,
    },
}

fn fail(e: impl std::fmt::Display) -> CliError {
    CliError::new(e.to_string())
}

fn read_input(file: &str) -> Result<Vec<u8>, CliError> {
    if file == "-" {
        let mut buf = Vec::new();
        std::io::stdin().read_to_end(&mut buf).map_err(fail)?;
        return Ok(buf);
    }
    std::fs::read(file).map_err(|e| CliError::new(format!("{file}: {e}")))
}

pub fn run(command: Command, ctx: &Context) -> Result<i32, CliError> {
    match command {
        Command::Ai { command } => run_ai(command, ctx),
        Command::Usage(args) => run_usage(args, ctx),
        Command::Reorganize { command } => run_reorganize(command, ctx),
    }
}

fn run_ai(command: AiCommand, ctx: &Context) -> Result<i32, CliError> {
    match command {
        AiCommand::Guide { section, json } => {
            let text = match section {
                None => guide::index(),
                Some(n) => guide::section(n).ok_or_else(|| CliError::new("Seção inexistente."))?,
            };
            if json {
                print_json(&text)?;
            } else {
                println!("{text}");
            }
        }
        AiCommand::Context {
            id,
            json,
            offset,
            limit,
        } => {
            let root = ctx.store()?.root().to_path_buf();
            let page = ContextStore::for_root(&root)
                .page(&id, offset, limit)
                .map_err(fail)?;
            if json {
                print_json(&page)?;
            } else {
                println!("{}", page.text);
                if let Some(next) = page.next_offset {
                    println!(
                        "\nContinuação: --offset {next} (total: {} caracteres)",
                        page.total_characters
                    );
                }
            }
        }
        AiCommand::Catalog {
            kind,
            json,
            offset,
            limit,
        } => {
            let page = catalog::catalog(&ctx.store()?, &kind, offset, limit).map_err(fail)?;
            if json {
                print_json(&page)?;
            } else {
                for item in &page.items {
                    println!(
                        "{}: {}{}",
                        item.reference,
                        item.title,
                        item.summary
                            .as_ref()
                            .map(|s| format!(" — {s}"))
                            .unwrap_or_default()
                    );
                }
                if let Some(next) = page.next_offset {
                    println!("Continuação: --offset {next}");
                }
            }
        }
        AiCommand::Usage { json, clear } => {
            let store = UsageStore::for_root(ctx.store()?.root());
            if clear {
                store.clear().map_err(fail)?;
                return Ok(0);
            }
            let records = store.list().map_err(fail)?;
            if json {
                print_json(&records)?;
            } else {
                for r in &records {
                    println!("{}", usage::usage_line(r));
                }
            }
        }
        AiCommand::ItemPrompt {
            kind,
            request,
            item: target,
        } => {
            let kind = item::Kind::parse(&kind).ok_or_else(|| CliError::new(item::INVALID_KIND))?;
            let (prompt, schema) =
                item::item_ai_prompt(&ctx.store()?, kind, &request, target.as_deref())
                    .map_err(fail)?;
            print_json(&json!({"prompt": prompt, "schema": schema}))?;
        }
        AiCommand::ItemApply {
            kind,
            file,
            item: target,
        } => {
            let kind = item::Kind::parse(&kind).ok_or_else(|| CliError::new(item::INVALID_KIND))?;
            let data = read_input(&file)?;
            let slug =
                item::item_ai_apply(&ctx.store()?, kind, &data, target.as_deref()).map_err(fail)?;
            println!("{slug}");
        }
    }
    Ok(0)
}

// ---- usage -----------------------------------------------------------------------------------------

fn run_usage(args: UsageArgs, ctx: &Context) -> Result<i32, CliError> {
    match args.command.unwrap_or(UsageCommand::Show(args.show)) {
        UsageCommand::Show(a) => show_usage(ctx, &a),
        UsageCommand::Record { then } => {
            let mut input = Vec::new();
            let _ = std::io::stdin().read_to_end(&mut input);
            let recorded =
                usage::record_usage(&input, &usage::usage_path(), chrono::Utc::now()).ok();
            if let Some(command) = then {
                let mut child = Process::new("/bin/sh")
                    .arg("-c")
                    .arg(&command)
                    .stdin(Stdio::piped())
                    .spawn()
                    .map_err(fail)?;
                if let Some(mut stdin) = child.stdin.take() {
                    let _ = stdin.write_all(&input);
                }
                let _ = child.wait();
            } else if let Some(usage) = recorded {
                println!("{}", usage.summary(chrono::Utc::now()));
            }
            Ok(0)
        }
        UsageCommand::Install => {
            let settings = usage::settings_path();
            usage::install_status_line(&usage::vibedeck_executable_path(), &settings)
                .map_err(fail)?;
            println!(
                "Statusline ligada em {}. O uso aparece depois da próxima resposta do Claude Code.",
                settings.display()
            );
            Ok(0)
        }
        UsageCommand::Uninstall => {
            let settings = usage::settings_path();
            usage::uninstall_status_line(&settings).map_err(fail)?;
            println!("Statusline do VibeDeck removida de {}.", settings.display());
            Ok(0)
        }
    }
}

fn show_usage(_ctx: &Context, args: &ShowArgs) -> Result<i32, CliError> {
    if Provider::from(args.provider) == Provider::Codex {
        let cwd = std::env::current_dir().map_err(fail)?;
        let result = codex::limits(&cwd).map_err(fail)?;
        if args.json {
            print_json(&result)?;
        } else {
            for limit in RateLimit::list(&result) {
                println!("{}", limit.line());
            }
        }
        return Ok(0);
    }
    let Some(found) = usage::load_usage(&usage::usage_path()) else {
        return Err(CliError::new(
            "Nenhum uso registrado ainda. Rode `vibedeck usage install` e use o Claude Code.",
        ));
    };
    if args.json {
        print_json(&found)?;
    } else {
        println!("{}", found.summary(chrono::Utc::now()));
        println!(
            "Atualizado em {}",
            usage::local_date_time(found.updated_at.0)
        );
    }
    Ok(0)
}

// ---- reorganize ------------------------------------------------------------------------------------

/// `reorganize` localiza o projeto sem atualizar o guia (como o Swift).
fn locate_store(ctx: &Context) -> Result<vibedeck_core::Store, CliError> {
    let root = ctx.root()?;
    vibedeck_core::Store::open(&root).map_err(fail)
}

fn run_reorganize(command: ReorganizeCommand, ctx: &Context) -> Result<i32, CliError> {
    match command {
        ReorganizeCommand::Prompt => {
            let store = locate_store(ctx)?;
            print_json(&json!({
                "prompt": reorganize::prompt(&store).map_err(fail)?,
                "schema": reorganize::SCHEMA,
                "fingerprint": reorganize::fingerprint(&store).map_err(fail)?,
            }))?;
        }
        ReorganizeCommand::Analyze {
            provider,
            model,
            effort,
        } => {
            let provider =
                Provider::parse(&provider).ok_or_else(|| CliError::new("Use claude ou codex."))?;
            let store = locate_store(ctx)?;
            let proposal =
                reorganize::analyze(&store, provider, &ProviderSettings { model, effort })
                    .map_err(fail)?;
            print_json(&proposal)?;
        }
        ReorganizeCommand::Validate { file, fingerprint } => {
            let data = read_input(&file)?;
            let store = locate_store(ctx)?;
            print_json(&reorganize::parse(&data, &store, &fingerprint).map_err(fail)?)?;
        }
        ReorganizeCommand::Apply { file, acceptance } => {
            let proposal = reorganize::decode_proposal(&read_input(&file)?).map_err(fail)?;
            let accepted =
                reorganize::decode_acceptance(&read_input(&acceptance)?).map_err(fail)?;
            let store = locate_store(ctx)?;
            print_json(&reorganize::apply(&store, &proposal, &accepted).map_err(fail)?)?;
        }
    }
    Ok(0)
}

// ---- mcp install/uninstall (ligados ao `McpCommand` pelo integrador) ---------------------------------

#[derive(Debug, Clone, Copy, ValueEnum, PartialEq, Eq)]
#[value(rename_all = "lower")]
pub enum ScopeArg {
    Local,
    Project,
    User,
}

impl From<ScopeArg> for Scope {
    fn from(s: ScopeArg) -> Self {
        match s {
            ScopeArg::Local => Scope::Local,
            ScopeArg::Project => Scope::Project,
            ScopeArg::User => Scope::User,
        }
    }
}

/// `vibedeck mcp install`.
#[derive(Args, Debug)]
pub struct McpInstallArgs {
    /// Escopo: local, project ou user.
    #[arg(short = 's', long, value_enum)]
    pub scope: Option<ScopeArg>,
    /// Provedor: claude ou codex.
    #[arg(long, value_enum, default_value = "claude")]
    pub provider: ProviderArg,
    /// Nome do servidor.
    #[arg(long, default_value = "vibedeck")]
    pub name: String,
    /// Substitui um registro existente com o mesmo nome.
    #[arg(long)]
    pub force: bool,
}

/// `vibedeck mcp uninstall`.
#[derive(Args, Debug)]
pub struct McpUninstallArgs {
    /// Escopo: local, project ou user.
    #[arg(short = 's', long, value_enum)]
    pub scope: Option<ScopeArg>,
    /// Provedor: claude ou codex.
    #[arg(long, value_enum, default_value = "claude")]
    pub provider: ProviderArg,
    /// Nome do servidor.
    #[arg(long, default_value = "vibedeck")]
    pub name: String,
}

fn emit(outcome: mcp_install::Outcome) -> i32 {
    print!("{}", outcome.stdout);
    eprint!("{}", outcome.stderr);
    outcome.code
}

pub fn mcp_install(args: &McpInstallArgs, ctx: &Context) -> Result<i32, CliError> {
    let root: PathBuf = ctx.store()?.root().to_path_buf();
    let outcome = mcp_install::install(
        &root,
        args.provider.into(),
        args.scope.map(Scope::from),
        &args.name,
        args.force,
        &usage::vibedeck_executable_path(),
    )
    .map_err(fail)?;
    Ok(emit(outcome))
}

pub fn mcp_uninstall(args: &McpUninstallArgs, ctx: &Context) -> Result<i32, CliError> {
    let root: PathBuf = ctx.store()?.root().to_path_buf();
    let outcome = mcp_install::uninstall(
        &root,
        args.provider.into(),
        args.scope.map(Scope::from),
        &args.name,
    )
    .map_err(fail)?;
    Ok(emit(outcome))
}

/// Reescreve `AGENTS.md`/`guide.md` se diferirem do guia embutido (erros ignorados, como no Swift).
pub fn refresh_guide(store: &vibedeck_core::Store) {
    let _ = guide::refresh_agents_guide(store);
}
