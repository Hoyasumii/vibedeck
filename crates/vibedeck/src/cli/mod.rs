//! CLI clap. Cada área nova adiciona um módulo com seu `Subcommand` e uma variante em `Command`.
//!
//! Padrões previstos (cli.md):
//! - grupos com subcomando padrão: `#[command(args_conflicts_with_subcommands = true)]` +
//!   `Option<Sub>` e, quando `None`, rodar o `list` com as opções do nível do grupo;
//! - `--json` por comando folha e saída via `output::print_json`;
//! - erros: `CliError` (exit 1, `Error: <msg>` em stderr); erros de parse de argumentos saem com 64.

// Helpers ainda sem consumidores (comandos entram nas próximas fatias).
#[allow(dead_code)]
pub mod output;

pub mod ai;
pub mod docs;
pub mod ideas;
pub mod onboarding;
pub mod project;
pub mod resources;
pub mod reviews;
pub mod rules;
pub mod stack;
pub mod workflows;

use clap::{Args, Parser, Subcommand};
use std::ffi::OsString;
use std::fmt;
use std::path::{Path, PathBuf};

pub const EXIT_FAILURE: i32 = 1;
/// EX_USAGE: erro de parse/validação de argumentos (como o swift-argument-parser).
pub const EXIT_USAGE: i32 = 64;

#[derive(Parser, Debug)]
#[command(
    name = "vibedeck",
    version,
    about = "VibeDeck: projeto, regras e revisões para agentes de IA"
)]
pub struct Cli {
    /// Diretório de partida (padrão: diretório atual); o projeto é achado subindo até vibedeck.json.
    #[arg(short = 'C', long = "root", global = true, value_name = "dir")]
    pub root: Option<PathBuf>,

    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Servidor MCP por stdio (ou instalação nos agentes).
    Mcp(McpArgs),
    #[command(flatten)]
    Project(project::Command),
    #[command(flatten)]
    Docs(docs::Command),
    #[command(flatten)]
    Reviews(reviews::Command),
    #[command(flatten)]
    Rules(rules::Command),
    #[command(flatten)]
    Ideas(ideas::Command),
    #[command(flatten)]
    Stack(stack::Command),
    #[command(flatten)]
    Resources(resources::Command),
    #[command(flatten)]
    Workflows(workflows::Command),
    #[command(flatten)]
    Ai(ai::Command),
    #[command(flatten)]
    Onboarding(onboarding::Command),
}

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct McpArgs {
    /// Sem subcomando equivale a `serve` (defaultSubcommand).
    #[command(subcommand)]
    pub command: Option<McpCommand>,

    /// Modo do aplicativo: tools extras e avisos de mudança em `.vibedeck/`.
    #[arg(long)]
    pub app: bool,
}

#[derive(Subcommand, Debug)]
pub enum McpCommand {
    /// Inicia o servidor MCP em stdin/stdout.
    Serve {
        /// Modo do aplicativo: tools extras e avisos de mudança em `.vibedeck/`.
        #[arg(long)]
        app: bool,
    },
    /// Registra o servidor no Claude Code ou no Codex.
    Install(ai::McpInstallArgs),
    /// Remove o registro do servidor.
    Uninstall(ai::McpUninstallArgs),
}

/// Erro de comando: mensagem em stderr e exit code.
#[derive(Debug)]
pub struct CliError {
    pub message: String,
    pub code: i32,
}

impl CliError {
    pub fn new(message: impl Into<String>) -> Self {
        CliError {
            message: message.into(),
            code: EXIT_FAILURE,
        }
    }
}

impl fmt::Display for CliError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for CliError {}

/// Ponto de entrada: devolve o exit code.
pub fn run<I, T>(args: I) -> i32
where
    I: IntoIterator<Item = T>,
    T: Into<OsString> + Clone,
{
    let cli = match Cli::try_parse_from(args) {
        Ok(cli) => cli,
        Err(e) => {
            let _ = e.print();
            // --help/--version saem 0; qualquer erro de uso sai 64.
            return if e.use_stderr() { EXIT_USAGE } else { 0 };
        }
    };
    match execute(cli) {
        Ok(code) => code,
        Err(e) => {
            if !e.message.is_empty() {
                eprintln!("Error: {}", e.message);
            }
            e.code
        }
    }
}

/// Contexto dos comandos: diretório de partida (`-C`) e acesso ao projeto.
#[allow(dead_code)]
pub struct Context {
    pub root_arg: Option<PathBuf>,
}

#[allow(dead_code)]
impl Context {
    /// Raiz do projeto (sobe até `vibedeck.json`).
    pub fn root(&self) -> Result<PathBuf, CliError> {
        locate_root(self.root_arg.as_deref())
    }

    /// Store do projeto.
    pub fn store(&self) -> Result<vibedeck_core::Store, CliError> {
        let root = self.root()?;
        let store = vibedeck_core::Store::open(&root).map_err(|e| CliError::new(e.to_string()))?;
        // Como o Swift: o guia gerado em .vibedeck/ acompanha a versão do binário.
        ai::refresh_guide(&store);
        Ok(store)
    }

    /// Diretório de partida sem exigir projeto (para `init`).
    pub fn start_dir(&self) -> Result<PathBuf, CliError> {
        start_dir(self.root_arg.as_deref())
    }
}

impl From<vibedeck_core::Error> for CliError {
    fn from(e: vibedeck_core::Error) -> Self {
        CliError::new(e.to_string())
    }
}

fn execute(cli: Cli) -> Result<i32, CliError> {
    let ctx = Context {
        root_arg: cli.root.clone(),
    };
    match cli.command {
        Command::Project(c) => project::run(c, &ctx),
        Command::Docs(c) => docs::run(c, &ctx),
        Command::Reviews(c) => reviews::run(c, &ctx),
        Command::Rules(c) => rules::run(c, &ctx),
        Command::Ideas(c) => ideas::run(c, &ctx),
        Command::Stack(c) => stack::run(c, &ctx),
        Command::Resources(c) => resources::run(c, &ctx),
        Command::Workflows(c) => workflows::run(c, &ctx),
        Command::Ai(c) => ai::run(c, &ctx),
        Command::Onboarding(c) => onboarding::run(c, &ctx),

        Command::Mcp(mcp) => match mcp.command.unwrap_or(McpCommand::Serve { app: mcp.app }) {
            McpCommand::Serve { app } => {
                let root = locate_root(cli.root.as_deref())?;
                if let Ok(store) = vibedeck_core::Store::open(&root) {
                    ai::refresh_guide(&store);
                }
                Ok(crate::mcp::serve(root, app))
            }
            McpCommand::Install(args) => ai::mcp_install(&args, &ctx),
            McpCommand::Uninstall(args) => ai::mcp_uninstall(&args, &ctx),
        },
    }
}

/// `~` expandido; `None` = cwd.
fn start_dir(root: Option<&Path>) -> Result<PathBuf, CliError> {
    let raw = match root {
        Some(p) => p.to_path_buf(),
        None => std::env::current_dir().map_err(|e| CliError::new(e.to_string()))?,
    };
    let s = raw.to_string_lossy();
    if let Some(rest) = s
        .strip_prefix("~/")
        .or(if s == "~" { Some("") } else { None })
        && let Some(home) = std::env::var_os("HOME")
    {
        return Ok(PathBuf::from(home).join(rest));
    }
    Ok(raw)
}

/// Sobe diretórios até achar `vibedeck.json`.
/// INTEGRAÇÃO: trocar por `ProjectStore::locate` do vibedeck-core quando existir.
pub fn locate_root(root: Option<&Path>) -> Result<PathBuf, CliError> {
    let start = start_dir(root)?;
    let start = std::fs::canonicalize(&start).unwrap_or(start);
    for dir in start.ancestors() {
        if dir.join("vibedeck.json").is_file() {
            return Ok(dir.to_path_buf());
        }
    }
    Err(CliError::new(format!(
        "Nenhum vibedeck.json encontrado em {} ou diretórios acima. Rode `vibedeck init`.",
        start.display()
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn estrutura_clap_valida() {
        use clap::CommandFactory;
        Cli::command().debug_assert();
    }

    #[test]
    fn mcp_padrao_e_serve() {
        let a = Cli::try_parse_from(["vibedeck", "-C", "/x", "mcp"]).unwrap();
        assert!(matches!(
            a.command,
            Command::Mcp(McpArgs {
                command: None,
                app: false
            })
        ));
        let b = Cli::try_parse_from(["vibedeck", "mcp", "serve", "-C", "/y"]).unwrap();
        assert_eq!(b.root.as_deref(), Some(Path::new("/y")));
    }

    #[test]
    fn uso_invalido_sai_64() {
        assert_eq!(run(["vibedeck", "nope"]), EXIT_USAGE);
    }
}
