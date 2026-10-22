//! Comandos CLI — Revisões: `review groups|list|add|set|remove` (cli.md §2.13).

use super::output::print_json;
use super::{CliError, Context};
use clap::{Args, Subcommand};
use vibedeck_core::model::{Author, ReviewPriority, ReviewTarget};
use vibedeck_core::reviews::{self, ItemUpdate, NewItem, ReviewError};

const STATUSES: [&str; 4] = ["open", "in_progress", "done", "wontfix"];
const PRIORITIES: [&str; 3] = ["low", "normal", "high"];

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Itens de revisão agrupados por tema.
    Review(Box<ReviewArgs>),
}

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct ReviewArgs {
    #[command(subcommand)]
    pub command: Option<ReviewCommand>,
    #[command(flatten)]
    pub list: ListArgs,
}

#[derive(Args, Debug, Default)]
pub struct ListArgs {
    /// Filtra por grupo (slug, id ou título).
    #[arg(long, value_name = "group")]
    pub group: Option<String>,
    /// Filtra por status.
    #[arg(long, value_name = "status", value_parser = STATUSES)]
    pub status: Option<String>,
    /// Filtra por kind.
    #[arg(long, value_name = "kind")]
    pub kind: Option<String>,
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum ReviewCommand {
    /// Lista os grupos de revisão.
    Groups {
        /// Saída JSON com o grupo de diretório.
        #[arg(long)]
        json: bool,
    },
    /// Lista itens (comando padrão).
    List(ListArgs),
    /// Adiciona um item (cria o grupo se não existir).
    Add(AddArgs),
    /// Atualiza um item (id completo ou prefixo).
    Set(SetArgs),
    /// Remove um item.
    Remove {
        /// Id completo ou prefixo.
        id: String,
    },
}

#[derive(Args, Debug)]
pub struct AddArgs {
    /// Grupo/tema (slug, id ou título).
    pub group: String,
    /// Título do item.
    pub title: String,
    /// Kind (ex.: disable, hide, fix, change, remove, note).
    #[arg(long, default_value = "note")]
    pub kind: String,
    #[arg(long)]
    pub details: Option<String>,
    #[arg(long, default_value = "normal", value_parser = PRIORITIES)]
    pub priority: String,
    #[arg(long)]
    pub file: Option<String>,
    #[arg(long)]
    pub route: Option<String>,
    #[arg(long)]
    pub component: Option<String>,
    #[arg(long)]
    pub selector: Option<String>,
    /// Tópicos de regras que o item precisa cumprir.
    #[arg(long, num_args = 1..)]
    pub rules: Vec<String>,
    /// Marca o item como criado por IA.
    #[arg(long)]
    pub ai: bool,
}

#[derive(Args, Debug)]
pub struct SetArgs {
    pub id: String,
    #[arg(long, value_parser = STATUSES)]
    pub status: Option<String>,
    #[arg(long, value_parser = PRIORITIES)]
    pub priority: Option<String>,
    #[arg(long)]
    pub kind: Option<String>,
    #[arg(long)]
    pub title: Option<String>,
    #[arg(long)]
    pub details: Option<String>,
    /// Substitui os tópicos de regras do item.
    #[arg(long, num_args = 1..)]
    pub rules: Vec<String>,
    /// Conclui sem check de regras aprovado (só humanos).
    #[arg(long)]
    pub force: bool,
}

fn fail(e: ReviewError) -> CliError {
    CliError::new(e.to_string())
}

fn id8(id: &vibedeck_core::model::Id) -> String {
    id.to_string().chars().take(8).collect()
}

fn hashtags(tags: &[String]) -> String {
    if tags.is_empty() {
        String::new()
    } else {
        format!("  #{}", tags.join(" #"))
    }
}

pub fn run(command: Command, ctx: &Context) -> Result<i32, CliError> {
    let Command::Review(args) = command;
    match args.command.unwrap_or(ReviewCommand::List(args.list)) {
        ReviewCommand::Groups { json } => groups(ctx, json),
        ReviewCommand::List(a) => list(ctx, a),
        ReviewCommand::Add(a) => add(ctx, a),
        ReviewCommand::Set(a) => set(ctx, a),
        ReviewCommand::Remove { id } => {
            reviews::delete_item(&ctx.store()?, &id)?;
            Ok(0)
        }
    }
}

fn groups(ctx: &Context, json: bool) -> Result<i32, CliError> {
    let records = reviews::list_groups(&ctx.store()?)?;
    if json {
        let rows = records
            .iter()
            .map(reviews::grouped_json)
            .collect::<Result<Vec<_>, _>>()?;
        print_json(&rows)?;
        return Ok(0);
    }
    for r in &records {
        println!(
            "{}\t{}\t{}/{}{}",
            r.slug,
            r.value.title,
            reviews::open_count(&r.value),
            r.value.items.len(),
            hashtags(&r.value.tags)
        );
    }
    Ok(0)
}

fn list(ctx: &Context, a: ListArgs) -> Result<i32, CliError> {
    let store = ctx.store()?;
    let status = a.status.as_deref().and_then(reviews::parse_status);
    let rows = reviews::list_items(&store, a.group.as_deref(), status, a.kind.as_deref())?;
    if a.json {
        print_json(&rows)?;
        return Ok(0);
    }
    let mut current = "";
    for row in &rows {
        if row.group != current {
            current = &row.group;
            println!("\n## {current}");
        }
        let i = &row.item;
        let place = i
            .target
            .as_ref()
            .map(|t| {
                [&t.file, &t.route, &t.component, &t.selector]
                    .into_iter()
                    .flatten()
                    .cloned()
                    .collect::<Vec<_>>()
                    .join(" ")
            })
            .unwrap_or_default();
        println!(
            "{}  [{}] ({}) {}{}",
            id8(&i.id),
            reviews::status_name(i.status),
            i.kind,
            i.title,
            if place.is_empty() {
                String::new()
            } else {
                format!("  → {place}")
            }
        );
    }
    Ok(0)
}

fn add(ctx: &Context, a: AddArgs) -> Result<i32, CliError> {
    let store = ctx.store()?;
    let new = NewItem {
        kind: a.kind,
        title: a.title,
        details: a.details,
        priority: reviews::parse_priority(&a.priority).unwrap_or(ReviewPriority::Normal),
        target: ReviewTarget {
            file: a.file,
            route: a.route,
            component: a.component,
            selector: a.selector,
        },
        rules: a.rules,
        author: if a.ai { Author::Ai } else { Author::Human },
    };
    let (slug, item) = reviews::add_item(&store, new, &a.group).map_err(fail)?;
    println!("{}\t{slug}", item.id);
    Ok(0)
}

fn set(ctx: &Context, a: SetArgs) -> Result<i32, CliError> {
    let store = ctx.store()?;
    let change = ItemUpdate {
        rules: (!a.rules.is_empty()).then_some(a.rules),
        status: a.status,
        priority: a.priority.as_deref().and_then(reviews::parse_priority),
        kind: a.kind,
        title: a.title,
        details: a.details,
        force: a.force,
    };
    let item = reviews::apply_update(&store, &a.id, change).map_err(fail)?;
    println!(
        "{}  [{}] {}",
        id8(&item.id),
        reviews::status_name(item.status),
        item.title
    );
    Ok(0)
}
