//! Comandos CLI — `stack` (tecnologias do Skill Icons, badge no README) e `patterns` (catálogo de padrões).
//!
//! Cada grupo tem subcomando padrão `list`; as opções do nível do grupo (`--json`) valem para ele.

use clap::{Args, Subcommand};
use vibedeck_core::Store;
use vibedeck_core::model::{Author, ProjectPattern, StackItem};
use vibedeck_core::stack::{
    Change, PatternCatalog, PatternCategory, SkillIconTheme, SkillIcons, SkillIconsApi, StackError,
    StackService,
};

use super::output::print_json;
use super::{CliError, Context};

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Stack do projeto: as tecnologias de destaque (ícones do Skill Icons).
    ///
    /// Ao adicionar ou retirar, o badge da stack no README.md é atualizado.
    Stack(StackArgs),
    /// Padrões de projeto que o código deve seguir (TDD, hexagonal, DDD, CQRS…).
    ///
    /// Cada padrão cria um tópico de regras em .vibedeck/rules/, cobrado pelo `rules for` / `rules check`.
    Patterns(PatternsArgs),
}

impl From<StackError> for CliError {
    fn from(e: StackError) -> Self {
        CliError::new(e.to_string())
    }
}

pub fn run(command: Command, ctx: &Context) -> Result<i32, CliError> {
    match command {
        Command::Stack(args) => run_stack(args, ctx),
        Command::Patterns(args) => run_patterns(args, ctx),
    }
}

// ---- stack -----------------------------------------------------------------------------------

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct StackArgs {
    #[command(subcommand)]
    pub command: Option<StackCommand>,
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum StackCommand {
    /// Lista a stack do projeto.
    List {
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Adiciona tecnologias pelo Skill Icons.
    Add {
        /// Ids, nomes ou aliases do Skill Icons (ex.: swift k8s "Next.js").
        #[arg(required = true, num_args = 1..)]
        icons: Vec<String>,
        /// Nota de uso para essas tecnologias.
        #[arg(long)]
        note: Option<String>,
        /// Marca as tecnologias como adicionadas por IA.
        #[arg(long)]
        ai: bool,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Retira tecnologias da stack.
    Remove {
        /// Id, nome ou prefixo do id.
        #[arg(required = true, num_args = 1..)]
        icons: Vec<String>,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Define a nota de uso de uma tecnologia (vazia apaga).
    Note {
        /// Id, nome ou prefixo do id.
        icon: String,
        /// Nota.
        #[arg(default_value = "")]
        note: String,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Move uma tecnologia para outra posição (a partir de 0).
    Move {
        /// Id, nome ou prefixo do id.
        icon: String,
        /// Nova posição.
        #[arg(allow_negative_numbers = true)]
        position: i64,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Procura tecnologias no catálogo do Skill Icons.
    Search {
        /// Texto a procurar (vazio = tudo).
        query: Option<String>,
        /// Categoria: language, frontend, backend, database, cloud, devops, tooling, testing, observability,
        /// auth, ide, ai, design, game, payments, os, social, productivity.
        #[arg(long)]
        category: Option<String>,
        /// Máximo de resultados.
        #[arg(long, default_value_t = 50, allow_negative_numbers = true)]
        limit: i64,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Mostra o badge da stack (Markdown) e, com --sync, regrava o bloco no README.md.
    Badge {
        /// Tema: dark ou light.
        #[arg(long)]
        theme: Option<String>,
        /// Regrava o bloco da stack no README.md.
        #[arg(long)]
        sync: bool,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
}

pub fn stack_line(item: &StackItem) -> String {
    let mut line = format!("{}  {}", item.icon, item.name);
    if let Some(c) = &item.category {
        line.push_str(&format!("  [{c}]"));
    }
    if let Some(n) = &item.note {
        line.push_str(&format!("  — {n}"));
    }
    line
}

fn report_stack(change: &Change, json: bool) -> Result<i32, CliError> {
    if json {
        print_json(change)?;
        return Ok(0);
    }
    for item in &change.items {
        println!("{}", stack_line(item));
    }
    if let Some(w) = &change.readme_warning {
        eprintln!("{w}");
    }
    Ok(0)
}

fn run_stack(args: StackArgs, ctx: &Context) -> Result<i32, CliError> {
    let api = SkillIcons::default();
    match args
        .command
        .unwrap_or(StackCommand::List { json: args.json })
    {
        StackCommand::List { json } => {
            let stack = ctx.store()?.project().map_err(CliError::from)?.stack;
            if json {
                print_json(&stack)?;
                return Ok(0);
            }
            if stack.is_empty() {
                println!("Stack vazia. Adicione com `vibedeck stack add <tecnologias…>`.");
            }
            for item in &stack {
                println!("{}", stack_line(item));
            }
            Ok(0)
        }
        StackCommand::Add {
            icons,
            note,
            ai,
            json,
        } => {
            let store = ctx.store()?;
            let author = if ai { Author::Ai } else { Author::Human };
            let change = StackService::new(&store, &api).add(&icons, note.as_deref(), author)?;
            report_stack(&change, json)
        }
        StackCommand::Remove { icons, json } => {
            let store = ctx.store()?;
            let change = StackService::new(&store, &api).remove(&icons)?;
            report_stack(&change, json)
        }
        StackCommand::Note { icon, note, json } => {
            let store = ctx.store()?;
            let change = StackService::new(&store, &api).set_note(&icon, Some(&note))?;
            report_stack(&change, json)
        }
        StackCommand::Move {
            icon,
            position,
            json,
        } => {
            let store = ctx.store()?;
            let change = StackService::new(&store, &api).move_to(&icon, position)?;
            report_stack(&change, json)
        }
        StackCommand::Search {
            query,
            category,
            limit,
            json,
        } => {
            let icons = api.search(query.as_deref(), category.as_deref(), Some(limit))?;
            if json {
                print_json(&icons)?;
                return Ok(0);
            }
            let current: Vec<String> = ctx
                .store()
                .ok()
                .and_then(|s| s.project().ok())
                .map(|p| p.stack.into_iter().map(|i| i.icon).collect())
                .unwrap_or_default();
            for icon in &icons {
                let mark = if current.contains(&icon.id) {
                    "✓ "
                } else {
                    "  "
                };
                let category = icon
                    .category
                    .as_ref()
                    .map(|c| format!("  [{c}]"))
                    .unwrap_or_default();
                println!("{mark}{}  {}{category}", icon.id, icon.name);
            }
            Ok(0)
        }
        StackCommand::Badge { theme, sync, json } => {
            let store = ctx.store()?;
            let service = StackService::new(&store, &api);
            if sync && let Some(warning) = service.sync_readme() {
                return Err(CliError::new(warning));
            }
            let theme = theme.as_deref().and_then(SkillIconTheme::parse);
            match service.badge(theme)? {
                None => {
                    if json {
                        println!("null");
                    } else {
                        println!("Stack vazia.");
                    }
                }
                Some(badge) => {
                    if json {
                        print_json(&badge)?;
                    } else {
                        println!("{}", badge.markdown);
                    }
                }
            }
            Ok(0)
        }
    }
}

// ---- patterns --------------------------------------------------------------------------------

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct PatternsArgs {
    #[command(subcommand)]
    pub command: Option<PatternsCommand>,
    /// Saída JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum PatternsCommand {
    /// Lista os padrões do projeto.
    List {
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Lista o catálogo embutido de padrões.
    Catalog {
        /// Texto a procurar (vazio = tudo).
        query: Option<String>,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Adiciona padrões do catálogo, ou um personalizado com --custom.
    ///
    /// Ex.: vibedeck patterns add tdd hexagonal --path 'Sources/Core/**'
    ///      vibedeck patterns add --custom "Feature folders" --rule "Uma pasta por feature"
    Add {
        /// Ids, nomes ou aliases do catálogo.
        patterns: Vec<String>,
        /// Nome de um padrão personalizado.
        #[arg(long)]
        custom: Option<String>,
        /// Resumo do padrão personalizado.
        #[arg(long)]
        summary: Option<String>,
        /// Regra obrigatória do padrão personalizado (repita).
        #[arg(long = "rule")]
        rule: Vec<String>,
        /// Como o projeto aplica o padrão.
        #[arg(long)]
        note: Option<String>,
        /// Glob de escopo (repita; sem = projeto inteiro).
        #[arg(long = "path")]
        path: Vec<String>,
        /// Marca como adicionado por IA.
        #[arg(long)]
        ai: bool,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Retira padrões e apaga o tópico de regras deles.
    Remove {
        /// Id, nome ou prefixo do id.
        #[arg(required = true, num_args = 1..)]
        patterns: Vec<String>,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Define como o projeto aplica um padrão (vazia apaga).
    Note {
        /// Id, nome ou prefixo do id.
        pattern: String,
        /// Nota.
        #[arg(default_value = "")]
        note: String,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Define os globs de escopo de um padrão (sem globs = projeto inteiro).
    Paths {
        /// Id, nome ou prefixo do id.
        pattern: String,
        /// Globs (ex.: 'Sources/Core/**').
        globs: Vec<String>,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Move um padrão para outra posição (a partir de 0).
    Move {
        /// Id, nome ou prefixo do id.
        pattern: String,
        /// Nova posição.
        #[arg(allow_negative_numbers = true)]
        position: i64,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
}

pub fn pattern_line(pattern: &ProjectPattern, store: &Store) -> String {
    let topic = store.pattern_topic(pattern);
    let scope = match &topic {
        Some(rec) if rec.value.paths.is_empty() => "projeto inteiro".to_string(),
        Some(rec) => rec.value.paths.join(", "),
        None => "sem tópico".to_string(),
    };
    let rules = topic
        .as_ref()
        .map(|rec| format!("{} regra(s) em {}", rec.value.rules.len(), rec.slug))
        .unwrap_or_default();
    let mut line = format!(
        "{}  {}  [{}]  ({scope}; {rules})",
        pattern.id,
        pattern.name,
        PatternCategory::label(pattern.category.as_deref())
    );
    if let Some(note) = &pattern.note {
        line.push_str(&format!("\n    — {note}"));
    }
    line
}

fn report_patterns(store: &Store, json: bool) -> Result<i32, CliError> {
    let patterns = store.project().map_err(CliError::from)?.patterns;
    if json {
        print_json(&patterns)?;
        return Ok(0);
    }
    if patterns.is_empty() {
        println!(
            "Nenhum padrão. Veja `vibedeck patterns catalog` e adicione com `vibedeck patterns add <ids…>`."
        );
    }
    for pattern in &patterns {
        println!("{}", pattern_line(pattern, store));
    }
    Ok(0)
}

fn run_patterns(args: PatternsArgs, ctx: &Context) -> Result<i32, CliError> {
    match args
        .command
        .unwrap_or(PatternsCommand::List { json: args.json })
    {
        PatternsCommand::List { json } => report_patterns(&ctx.store()?, json),
        PatternsCommand::Catalog { query, json } => {
            let templates = PatternCatalog::search(query.as_deref());
            if json {
                print_json(&templates)?;
                return Ok(0);
            }
            let current: Vec<String> = ctx
                .store()
                .ok()
                .and_then(|s| s.project().ok())
                .map(|p| p.patterns.into_iter().map(|p| p.id).collect())
                .unwrap_or_default();
            for t in templates {
                let mark = if current.contains(&t.id) {
                    "✓ "
                } else {
                    "  "
                };
                println!(
                    "{mark}{}  {}  [{}]  — {}",
                    t.id,
                    t.name,
                    PatternCategory::label(Some(&t.category)),
                    t.summary
                );
            }
            Ok(0)
        }
        PatternsCommand::Add {
            patterns,
            custom,
            summary,
            rule,
            note,
            path,
            ai,
            json,
        } => {
            let store = ctx.store()?;
            let author = if ai { Author::Ai } else { Author::Human };
            let paths = (!path.is_empty()).then_some(path);
            if let Some(name) = custom {
                if rule.is_empty() {
                    return Err(CliError::new(
                        "Padrão personalizado precisa de ao menos uma --rule.",
                    ));
                }
                store.add_custom_pattern(
                    &name,
                    summary.as_deref(),
                    &rule,
                    note.as_deref(),
                    paths.as_deref(),
                    author,
                )?;
            } else {
                if patterns.is_empty() {
                    return Err(CliError::new("Informe ids do catálogo ou --custom <nome>."));
                }
                store.add_patterns(&patterns, note.as_deref(), paths.as_deref(), author)?;
            }
            report_patterns(&store, json)
        }
        PatternsCommand::Remove { patterns, json } => {
            let store = ctx.store()?;
            store.remove_patterns(&patterns)?;
            report_patterns(&store, json)
        }
        PatternsCommand::Note {
            pattern,
            note,
            json,
        } => {
            let store = ctx.store()?;
            store.set_pattern_note(&pattern, Some(&note))?;
            report_patterns(&store, json)
        }
        PatternsCommand::Paths {
            pattern,
            globs,
            json,
        } => {
            let store = ctx.store()?;
            store.set_pattern_paths(&pattern, &globs)?;
            report_patterns(&store, json)
        }
        PatternsCommand::Move {
            pattern,
            position,
            json,
        } => {
            let store = ctx.store()?;
            store.move_pattern(&pattern, position)?;
            report_patterns(&store, json)
        }
    }
}
