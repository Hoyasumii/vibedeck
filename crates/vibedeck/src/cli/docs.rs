//! Comandos CLI — Docs (`docs`), grupos de itens (`groups`), anexos e Docs vinculados por symlink (MUD-002).
//!
//! `docs` tem `list` como subcomando padrão; `groups` tem os 8 subcomandos de `ItemGroups`. Além do Swift,
//! `docs unlink <slug>` remove só o vínculo (D4) de um doc vinculado, inclusive quebrado.

use std::io::Read;

use super::output::print_json;
use super::{CliError, Context};
use clap::{Args, Subcommand};
use serde_json::Value;
use vibedeck_core::docs::error::DocError;
use vibedeck_core::docs::groups::{self as grp, ItemConcept};
use vibedeck_core::docs::{self, DocInfo};
use vibedeck_core::model::Author;
use vibedeck_core::project::links::hashtags;

impl From<DocError> for CliError {
    fn from(e: DocError) -> Self {
        CliError::new(e.to_string())
    }
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Documentos markdown.
    Docs(DocsArgs),
    /// Diretórios de ideias, revisões, docs e skills; regras dentro de tópicos.
    Groups(GroupsArgs),
}

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct DocsArgs {
    #[command(subcommand)]
    pub command: Option<DocsCommand>,
    /// Saída JSON com o grupo.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum DocsCommand {
    /// Lista os docs (padrão).
    List {
        /// Saída JSON com o grupo.
        #[arg(long)]
        json: bool,
    },
    /// Imprime o conteúdo de um doc.
    Cat { slug: String },
    /// Cria um doc novo e imprime o slug.
    New {
        title: String,
        #[arg(long, default_value = "")]
        body: String,
        /// Caminho completo grupo/slug.
        #[arg(long)]
        reference: Option<String>,
        #[arg(long)]
        ai: bool,
    },
    /// Sobrescreve um doc com o conteúdo de --text ou stdin.
    Write {
        slug: String,
        #[arg(long)]
        text: Option<String>,
    },
    /// Remove só o vínculo de um doc vinculado a um .md da raiz (a origem nunca é tocada).
    Unlink { slug: String },
}

fn concept_parser() -> clap::builder::PossibleValuesParser {
    clap::builder::PossibleValuesParser::new(ItemConcept::NAMES)
}

fn concept(name: &str) -> ItemConcept {
    name.parse().expect("validado pelo clap")
}

#[derive(Args, Debug)]
pub struct GroupsArgs {
    #[command(subcommand)]
    pub command: GroupsCommand,
}

#[derive(Subcommand, Debug)]
pub enum GroupsCommand {
    List {
        #[arg(value_parser = concept_parser())]
        concept: String,
        #[arg(long)]
        json: bool,
    },
    Create {
        #[arg(value_parser = concept_parser())]
        concept: String,
        path: String,
    },
    Move {
        #[arg(value_parser = concept_parser())]
        concept: String,
        from: String,
        to: String,
    },
    Rename {
        #[arg(value_parser = concept_parser())]
        concept: String,
        path: String,
        name: String,
    },
    Remove {
        #[arg(value_parser = concept_parser())]
        concept: String,
        path: String,
        /// Confirma apagar todos os itens do grupo, inclusive de autoria humana.
        #[arg(long)]
        confirmed: bool,
    },
    MoveItem {
        #[arg(value_parser = concept_parser())]
        concept: String,
        reference: String,
        /// Grupo de destino; string vazia para a raiz.
        group: String,
    },
    MoveRule {
        rule: String,
        group: String,
    },
    RenameRules {
        topic: String,
        from: String,
        to: String,
    },
}

fn list(ctx: &Context, json: bool) -> Result<i32, CliError> {
    let store = ctx.store()?;
    let listing = docs::list_docs_detailed(&store)?;
    for w in &listing.warnings {
        eprintln!("{w}");
    }
    if json {
        let rows: Vec<Value> = listing.docs.iter().map(DocInfo::to_grouped_json).collect();
        print_json(&rows)?;
    } else {
        for d in &listing.docs {
            let link = match &d.link {
                None => String::new(),
                Some(l) if l.broken => format!(" → {} (vínculo quebrado)", l.target),
                Some(l) => format!(" → {}", l.target),
            };
            println!("{}\t{}{}{}", d.slug, d.title, hashtags(&d.tags), link);
        }
    }
    Ok(0)
}

pub fn run(command: Command, ctx: &Context) -> Result<i32, CliError> {
    match command {
        Command::Docs(args) => match args.command {
            None => list(ctx, args.json),
            Some(DocsCommand::List { json }) => list(ctx, json),
            Some(DocsCommand::Cat { slug }) => {
                print!("{}", docs::read_doc(&ctx.store()?, &slug)?);
                Ok(0)
            }
            Some(DocsCommand::New {
                title,
                body,
                reference,
                ai,
            }) => {
                let store = ctx.store()?;
                let author = if ai { Author::Ai } else { Author::Human };
                let slug = docs::create_doc(&store, &title, &body, author, reference.as_deref())?;
                println!("{slug}");
                Ok(0)
            }
            Some(DocsCommand::Write { slug, text }) => {
                let content = match text {
                    Some(t) => t,
                    None => {
                        let mut buf = Vec::new();
                        std::io::stdin()
                            .read_to_end(&mut buf)
                            .map_err(|e| CliError::new(e.to_string()))?;
                        String::from_utf8_lossy(&buf).into_owned()
                    }
                };
                docs::write_doc(&ctx.store()?, &slug, &content)?;
                Ok(0)
            }
            Some(DocsCommand::Unlink { slug }) => {
                let removed = docs::unlink_doc(&ctx.store()?, &slug)?;
                println!("Vínculo removido: {removed}");
                Ok(0)
            }
        },
        Command::Groups(args) => groups(args.command, ctx),
    }
}

fn groups(command: GroupsCommand, ctx: &Context) -> Result<i32, CliError> {
    let store = ctx.store()?;
    match command {
        GroupsCommand::List { concept: c, json } => {
            let dirs = grp::list_item_directories(&store, concept(&c))?;
            if json {
                print_json(&dirs)?;
            } else {
                for d in dirs {
                    println!("{}", d.path);
                }
            }
        }
        GroupsCommand::Create { concept: c, path } => {
            println!(
                "{}",
                grp::create_item_directory(&store, concept(&c), &path)?
            );
        }
        GroupsCommand::Move {
            concept: c,
            from,
            to,
        } => {
            grp::move_item_directory(&store, concept(&c), &from, &to)?;
            println!("Grupo movido.");
        }
        GroupsCommand::Rename {
            concept: c,
            path,
            name,
        } => {
            if name.contains('/') {
                return Err(DocError::invalid_path(&name).into());
            }
            let parent = grp::group_path_of(&path);
            let to = if parent.is_empty() {
                name
            } else {
                format!("{parent}/{name}")
            };
            grp::move_item_directory(&store, concept(&c), &path, &to)?;
            println!("Grupo renomeado.");
        }
        GroupsCommand::Remove {
            concept: c,
            path,
            confirmed,
        } => {
            grp::delete_item_directory(&store, concept(&c), &path, confirmed)?;
            println!("Grupo apagado.");
        }
        GroupsCommand::MoveItem {
            concept: c,
            reference,
            group,
        } => {
            println!(
                "{}",
                grp::move_grouped_item(&store, concept(&c), &reference, &group)?
            );
        }
        GroupsCommand::MoveRule { rule, group } => {
            grp::move_rule_to_group(&store, &rule, &group)?;
            println!("Regra movida.");
        }
        GroupsCommand::RenameRules { topic, from, to } => {
            grp::rename_rule_group(&store, &topic, &from, &to)?;
            println!("Grupo de regras movido.");
        }
    }
    Ok(0)
}
