//! Comandos CLI — Início guiado (MUD-001): detecção e cadastro de recursos existentes.
//!
//! `onboarding [status]` é o padrão; só `import` grava registros, e apenas os itens pedidos.

use clap::{Args, Subcommand};
use vibedeck_core::model::Author;
use vibedeck_core::onboarding::{self, ItemRef, OnboardingError, Report, Status, Step};

use super::output::print_json;
use super::{CliError, Context};

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Início guiado: stack, padrões e recursos (.claude, .codex) já existentes no projeto.
    ///
    /// Sem subcomando mostra o estado. Nada é cadastrado sem `onboarding import`.
    Onboarding(OnboardingArgs),
}

impl From<OnboardingError> for CliError {
    fn from(e: OnboardingError) -> Self {
        CliError::new(e.to_string())
    }
}

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct OnboardingArgs {
    #[command(subcommand)]
    pub command: Option<OnboardingCommand>,
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum OnboardingCommand {
    /// Mostra o estado, a etapa sugerida e os recursos detectados.
    Status {
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Pula por agora (retomável com `onboarding`); não cria registros.
    Skip {
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Marca o início guiado como concluído.
    Complete {
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Cadastra os recursos escolhidos (<tipo>:<nome>, tipo agent|command|skill).
    ///
    /// Já cadastrados são ignorados, nunca sobrescritos.
    Import {
        /// Itens, ex.: agent:reviewer skill:deploy command:ship.
        #[arg(required = true, num_args = 1..)]
        items: Vec<String>,
        /// Marca os registros como criados por IA.
        #[arg(long)]
        ai: bool,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
}

pub fn run(command: Command, ctx: &Context) -> Result<i32, CliError> {
    let Command::Onboarding(args) = command;
    match args
        .command
        .unwrap_or(OnboardingCommand::Status { json: args.json })
    {
        OnboardingCommand::Status { json } => {
            // Funciona também em pasta sem vibedeck.json (só leitura).
            let report = match ctx.store() {
                Ok(store) => onboarding::status(&store),
                Err(_) => onboarding::status_at(&ctx.start_dir()?),
            };
            if json {
                print_json(&report)?;
            } else {
                print_report(&report);
            }
        }
        OnboardingCommand::Skip { json } => {
            let store = ctx.store()?;
            let state = onboarding::skip(&store)?;
            if json {
                print_json(&state)?;
            } else {
                println!("Início guiado adiado. Retome com `vibedeck onboarding`.");
            }
        }
        OnboardingCommand::Complete { json } => {
            let store = ctx.store()?;
            let state = onboarding::complete(&store)?;
            if json {
                print_json(&state)?;
            } else {
                println!("Início guiado concluído.");
            }
        }
        OnboardingCommand::Import { items, ai, json } => {
            let store = ctx.store()?;
            let refs = parse(&items)?;
            let author = if ai { Author::Ai } else { Author::Human };
            let outcome = onboarding::import_selected(&store, &refs, author)?;
            if json {
                print_json(&outcome)?;
            } else {
                print_outcome(&outcome);
            }
        }
    }
    Ok(0)
}

fn parse(items: &[String]) -> Result<Vec<ItemRef>, CliError> {
    items.iter().map(|i| Ok(ItemRef::parse(i)?)).collect()
}

fn print_outcome(o: &onboarding::Outcome) {
    for i in &o.imported {
        println!("cadastrado: {i}");
    }
    for i in &o.already_registered {
        println!("já cadastrado (mantido): {i}");
    }
    for w in &o.warnings {
        eprintln!("aviso: {w}");
    }
    if o.imported.is_empty() && o.already_registered.is_empty() {
        println!("Nada a cadastrar.");
    }
}

fn print_report(r: &Report) {
    let status = match r.status {
        Status::Pending => "pendente",
        Status::Skipped => "adiado",
        Status::Done => "concluído",
    };
    println!("Início guiado: {status}");
    if !r.has_project {
        println!("Pasta sem vibedeck.json. Rode `vibedeck init` para começar.");
    }
    let step = match r.step {
        Step::Stack => "informar a stack (`vibedeck stack add <tecnologias…>`)",
        Step::Patterns => "escolher padrões (`vibedeck patterns add <padrões…>`)",
        Step::Resources => {
            "revisar os recursos detectados (`vibedeck onboarding import <tipo:nome>…`)"
        }
        Step::Done => "nada pendente",
    };
    println!("Próxima etapa: {step}");
    if r.stack_empty {
        println!("Stack: vazia");
    } else {
        println!("Stack: {}", r.stack.join(", "));
    }
    if r.patterns.is_empty() {
        println!("Padrões: nenhum");
    } else {
        let names: Vec<&str> = r.patterns.iter().map(|p| p.name.as_str()).collect();
        println!("Padrões: {}", names.join(", "));
    }
    if r.resources.is_empty() {
        println!("Recursos detectados: nenhum");
    } else {
        println!("Recursos detectados:");
        for x in &r.resources {
            let mark = if x.registered {
                "[ ] já cadastrado"
            } else {
                "[x] novo"
            };
            println!(
                "  {mark}  {}:{} ({}, {})",
                x.kind, x.slug, x.provider, x.origin
            );
        }
    }
}
