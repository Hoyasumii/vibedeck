//! Comandos CLI — Ideias: CRUD, dependências, readiness, regras rascunho, promoção.
//!
//! A área declara seus comandos de primeiro nível em `Command` e os executa em `run`.

use std::collections::HashSet;

use clap::{Args, Subcommand, ValueEnum};
use vibedeck_core::ideas::{
    GroupedIdea, IdeaStatusExt, RuleTestState, group_path, rule_test_state,
};
use vibedeck_core::model::{Author, Idea, IdeaStatus, Rule, RuleSeverity};

use super::output::print_json;
use super::{CliError, Context};

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Ideias futuras do projeto (brainstorm), com regras rascunho.
    Ideas(IdeasArgs),
}

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct IdeasArgs {
    /// Sem subcomando equivale a `list`.
    #[command(subcommand)]
    pub command: Option<IdeasCommand>,
    #[command(flatten)]
    pub list: ListArgs,
}

#[derive(Args, Debug, Default)]
pub struct ListArgs {
    /// Filtra por status.
    #[arg(long, value_enum)]
    pub status: Option<StatusArg>,
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
#[value(rename_all = "lower")]
pub enum StatusArg {
    New,
    Exploring,
    Approved,
    Discarded,
    Done,
}

impl From<StatusArg> for IdeaStatus {
    fn from(s: StatusArg) -> Self {
        match s {
            StatusArg::New => IdeaStatus::New,
            StatusArg::Exploring => IdeaStatus::Exploring,
            StatusArg::Approved => IdeaStatus::Approved,
            StatusArg::Discarded => IdeaStatus::Discarded,
            StatusArg::Done => IdeaStatus::Done,
        }
    }
}

#[derive(Subcommand, Debug)]
pub enum IdeasCommand {
    /// Lista as ideias.
    List(ListArgs),
    /// Mostra uma ideia.
    Show {
        idea: String,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Cria uma ideia e imprime o slug.
    New {
        title: String,
        /// Caminho completo grupo/slug.
        #[arg(long)]
        reference: Option<String>,
        #[arg(long)]
        body: Option<String>,
        #[arg(long, num_args = 1..)]
        tags: Vec<String>,
        /// Marca a ideia como criada por IA.
        #[arg(long)]
        ai: bool,
    },
    /// Altera status, título ou corpo da ideia.
    Set {
        idea: String,
        #[arg(long, value_enum)]
        status: Option<StatusArg>,
        #[arg(long)]
        title: Option<String>,
        #[arg(long)]
        body: Option<String>,
    },
    /// Adiciona uma regra rascunho à ideia.
    #[command(name = "add-rule")]
    AddRule {
        idea: String,
        text: String,
        /// Regra recomendada (não bloqueia).
        #[arg(long)]
        should: bool,
        /// Marca a regra como criada por IA.
        #[arg(long)]
        ai: bool,
    },
    /// Adiciona dependências: ideias que precisam estar implementadas (done) antes desta.
    Depend {
        idea: String,
        /// Ideias (slug, UUID, prefixo ou título).
        #[arg(required = true, num_args = 1..)]
        dependencies: Vec<String>,
    },
    /// Remove dependências da ideia.
    Undepend {
        idea: String,
        /// Ideias (slug, UUID, prefixo ou título).
        #[arg(required = true, num_args = 1..)]
        dependencies: Vec<String>,
    },
    /// Transforma as regras da ideia em um tópico de regras ativo.
    Promote { idea: String },
    /// Desfaz a promoção: apaga o tópico de regras da ideia e remove o vínculo.
    Unpromote { idea: String },
}

pub fn run(command: Command, ctx: &Context) -> Result<i32, CliError> {
    let Command::Ideas(args) = command;
    let cmd = args.command.unwrap_or(IdeasCommand::List(args.list));
    match cmd {
        IdeasCommand::List(a) => list(ctx, a),
        IdeasCommand::Show { idea, json } => show(ctx, &idea, json),
        IdeasCommand::New {
            title,
            reference,
            body,
            tags,
            ai,
        } => {
            let store = ctx.store()?;
            let author = if ai { Author::Ai } else { Author::Human };
            let rec =
                store.create_idea(&title, body.as_deref(), &tags, author, reference.as_deref())?;
            println!("{}", rec.slug);
            Ok(0)
        }
        IdeasCommand::Set {
            idea,
            status,
            title,
            body,
        } => {
            let store = ctx.store()?;
            let rec = store
                .update_idea(&idea, |i| {
                    if let Some(s) = status {
                        i.status = s.into();
                    }
                    if let Some(t) = title {
                        i.title = t;
                    }
                    if let Some(b) = body {
                        i.body = Some(b);
                    }
                    Ok(())
                })
                .map_err(msg)?;
            println!(
                "{}\t[{}] {}",
                rec.slug,
                rec.value.status.raw(),
                rec.value.title
            );
            Ok(0)
        }
        IdeasCommand::AddRule {
            idea,
            text,
            should,
            ai,
        } => {
            let store = ctx.store()?;
            let mut rule = Rule::new(text);
            rule.severity = if should {
                RuleSeverity::Should
            } else {
                RuleSeverity::Must
            };
            rule.author = if ai { Author::Ai } else { Author::Human };
            let (_, saved) = store.add_idea_rule(&idea, rule).map_err(msg)?;
            println!("{}", saved.id);
            Ok(0)
        }
        IdeasCommand::Depend { idea, dependencies } => {
            let store = ctx.store()?;
            let rec = store
                .add_idea_dependencies(&idea, &dependencies)
                .map_err(msg)?;
            println!(
                "{}\t{} dependência(s)",
                rec.slug,
                rec.value.dependencies.len()
            );
            Ok(0)
        }
        IdeasCommand::Undepend { idea, dependencies } => {
            let store = ctx.store()?;
            let rec = store
                .remove_idea_dependencies(&idea, &dependencies)
                .map_err(msg)?;
            println!(
                "{}\t{} dependência(s)",
                rec.slug,
                rec.value.dependencies.len()
            );
            Ok(0)
        }
        IdeasCommand::Promote { idea } => {
            let store = ctx.store()?;
            let stale = store.unmatched_idea_paths(&idea)?;
            let topic = store.promote_idea(&idea, &HashSet::new()).map_err(msg)?;
            println!("{topic}");
            if !stale.is_empty() {
                eprintln!(
                    "Aviso: globs da ideia que não casam nenhum arquivo foram copiados: {}",
                    stale.join(", ")
                );
            }
            Ok(0)
        }
        IdeasCommand::Unpromote { idea } => {
            let store = ctx.store()?;
            let slug = store.resolve::<Idea>(&idea)?;
            if store.load::<Idea>(&slug)?.promoted_topic.is_none() {
                println!("A ideia não estava promovida.");
                return Ok(0);
            }
            match store.unpromote_idea(&slug).map_err(msg)? {
                Some(t) => println!("Tópico removido: {t}"),
                None => println!("Vínculo removido (o tópico já não existia)."),
            }
            Ok(0)
        }
    }
}

fn msg(e: vibedeck_core::ideas::IdeaError) -> CliError {
    CliError::new(e.to_string())
}

fn hashtags(tags: &[String]) -> String {
    if tags.is_empty() {
        String::new()
    } else {
        format!("  #{}", tags.join(" #"))
    }
}

fn list(ctx: &Context, args: ListArgs) -> Result<i32, CliError> {
    let store = ctx.store()?;
    let wanted: Option<IdeaStatus> = args.status.map(Into::into);
    let ideas: Vec<_> = store
        .ideas()?
        .into_iter()
        .filter(|r| wanted.is_none_or(|s| r.value.status == s))
        .collect();
    if args.json {
        let rows: Vec<GroupedIdea> = ideas
            .iter()
            .map(|r| GroupedIdea {
                idea: &r.value,
                slug: &r.slug,
                group: group_path(&r.slug),
            })
            .collect();
        print_json(&rows)?;
        return Ok(0);
    }
    for r in &ideas {
        println!(
            "{}\t[{}] {}  ({} regra(s)){}",
            r.slug,
            r.value.status.raw(),
            r.value.title,
            r.value.rules.len(),
            hashtags(&r.value.tags)
        );
    }
    Ok(0)
}

fn print_rules(rules: &[Rule], indent: &str) {
    for r in rules {
        let mark = if r.severity == RuleSeverity::Must {
            "●"
        } else {
            "○"
        };
        let test = match rule_test_state(r) {
            RuleTestState::None => String::new(),
            RuleTestState::Script => format!(
                "  ⚙ {}",
                r.test
                    .as_ref()
                    .and_then(|t| t.command.as_deref())
                    .unwrap_or("")
            ),
            RuleTestState::Manual => "  ✋ manual".to_string(),
            RuleTestState::Stale => "  ⚠ teste desatualizado".to_string(),
        };
        let id = r.id.to_string();
        let ai = if r.author == Author::Ai { "  ✨" } else { "" };
        println!("{indent}{}  {mark} {}{ai}{test}", &id[..8], r.text);
    }
}

fn show(ctx: &Context, reference: &str, json: bool) -> Result<i32, CliError> {
    let store = ctx.store()?;
    let detail = store.idea_detail(reference)?;
    if json {
        print_json(&detail)?;
        return Ok(0);
    }
    let idea = &detail.idea;
    println!("{} — {}", idea.title, idea.status.label());
    if let Some(body) = idea.body.as_deref().filter(|b| !b.is_empty()) {
        println!("\n{body}\n");
    }
    if !idea.rules.is_empty() {
        println!("Regras rascunho:");
        print_rules(&idea.rules, "  ");
    }
    if let Some(t) = &idea.promoted_topic {
        println!("Promovida para o tópico: {t}");
    }
    if !idea.dependencies.is_empty() {
        let ids: Vec<String> = idea.dependencies.iter().map(|d| d.to_string()).collect();
        println!("Dependências: {}", ids.join(", "));
    }
    for b in &detail.dependency_blockers {
        println!("Impedimento: {}", b.message);
    }
    if !detail.dependents.is_empty() {
        let d: Vec<String> = detail
            .dependents
            .iter()
            .map(|l| format!("{} [{}]", l.slug, l.status.raw()))
            .collect();
        println!("Dependentes: {}", d.join(", "));
    }
    Ok(0)
}
