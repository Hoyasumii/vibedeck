//! Comandos CLI — Regras (`rules`) e gate do hook Stop (`hook`).
//!
//! Porta `Rules` e `Hook` de `CLI.swift`. A lógica mora em `vibedeck_core::rules`; aqui só argumentos e saída.

use super::output::print_json;
use super::{CliError, Context, EXIT_USAGE};
use clap::{Args, Subcommand, ValueEnum};
use serde::Serialize;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use vibedeck_core::Store;
use vibedeck_core::model::{
    Author, Rule, RuleCheck, RuleResultSource, RuleSeverity, RuleTestMode, RuleTopic, RuleVerdict,
};
use vibedeck_core::rules::{
    self, HookAgent, HookScope, RuleAnswer, RuleError, RuleExt, RuleTestRunRow, RuleTestRunner,
    RuleTestState, SubmitParams, TaskSpec, TopicChecklist,
};
use vibedeck_core::store::Record;

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Tópicos de regras que toda tarefa precisa cumprir antes de ser concluída.
    Rules(RulesArgs),
    /// Hook Stop do Claude Code ou do Codex: o agente não conclui a resposta com alterações sem check de
    /// regras aprovado.
    Hook(HookArgs),
}

pub fn run(command: Command, ctx: &Context) -> Result<i32, CliError> {
    match command {
        Command::Rules(args) => run_rules(args, ctx),
        Command::Hook(args) => run_hook(args, ctx),
    }
}

impl From<RuleError> for CliError {
    fn from(e: RuleError) -> Self {
        CliError::new(e.to_string())
    }
}

fn id8(id: &impl ToString) -> String {
    id.to_string().chars().take(8).collect()
}

fn hashtags(tags: &[String]) -> String {
    if tags.is_empty() {
        String::new()
    } else {
        format!("  #{}", tags.join(" #"))
    }
}

fn scope_text(topic: &RuleTopic) -> String {
    if topic.is_global() {
        "global".to_string()
    } else {
        topic.paths.join(", ")
    }
}

fn print_rules(rules: &[Rule]) {
    for r in rules {
        let mark = if r.severity == RuleSeverity::Must {
            "●"
        } else {
            "○"
        };
        let test = match r.test_state() {
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
        let ai = if r.author == Author::Ai { "  ✨" } else { "" };
        println!("  {}  {mark} {}{ai}{test}", id8(&r.id), r.text);
    }
}

// ---- rules ------------------------------------------------------------------------------------------

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct RulesArgs {
    #[command(subcommand)]
    pub command: Option<RulesCommand>,
    /// Saída JSON (sem subcomando, equivale a `list`).
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand, Debug)]
pub enum RulesCommand {
    /// Lista os tópicos de regras.
    List {
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Mostra um tópico e suas regras.
    Show {
        /// Tópico (slug, id ou título).
        topic: String,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Cria um tópico. Sem --path, vale para toda tarefa.
    New {
        title: String,
        #[arg(long)]
        description: Option<String>,
        /// Glob de escopo (repetível), ex.: 'Sources/App/**'.
        #[arg(long = "path")]
        paths: Vec<String>,
        #[arg(long, num_args = 1..)]
        tags: Vec<String>,
    },
    /// Adiciona uma regra a um tópico (cria o tópico se não existir).
    Add {
        topic: String,
        text: String,
        #[arg(long)]
        details: Option<String>,
        /// Regra recomendada (não bloqueia).
        #[arg(long)]
        should: bool,
        /// Marca a regra como criada por IA.
        #[arg(long)]
        ai: bool,
    },
    /// Remove uma regra.
    Remove {
        /// Id ou prefixo da regra.
        id: String,
    },
    /// Regras aplicáveis a um conjunto de arquivos.
    For {
        /// Arquivos alterados.
        files: Vec<String>,
        /// Tópicos extras.
        #[arg(long, num_args = 1..)]
        topics: Vec<String>,
        /// Id do item de revisão relacionado.
        #[arg(long)]
        item: Option<String>,
        /// Lista também as regras manuais (por padrão só as de script, as outras viram contagem).
        #[arg(long)]
        manual: bool,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Roda os scripts das regras aplicáveis (não grava check).
    ///
    /// Exit do script: 0 = cumpre, 77 = não se aplica, outro = viola. Sem arquivos nem tópicos, roda todos
    /// os tópicos.
    Test {
        /// Arquivos alterados.
        files: Vec<String>,
        /// Tópicos (só eles, quando não há arquivos).
        #[arg(long, num_args = 1..)]
        topics: Vec<String>,
        /// Id do item de revisão relacionado.
        #[arg(long)]
        item: Option<String>,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Define como uma regra é verificada: por script (--command) ou manual (--manual).
    #[command(name = "set-test")]
    SetTest {
        /// Id ou prefixo da regra.
        id: String,
        /// Comando do script, rodado na raiz do projeto (ex.: .vibedeck/tests/geral/ab12cd34.sh).
        #[arg(long)]
        command: Option<String>,
        /// A regra não é testável por script: continua com o agente.
        #[arg(long)]
        manual: bool,
        /// O que o script verifica ou por que a regra é manual.
        #[arg(long)]
        reason: Option<String>,
        /// Remove o teste da regra (e o script em .vibedeck/tests).
        #[arg(long)]
        clear: bool,
    },
    /// Registra a verificação das regras aplicáveis.
    ///
    /// Por padrão só roda os scripts das regras; as manuais ficam pendentes. Com --manual, lê de stdin (ou
    /// --results) um JSON e exige a resposta de todas as manuais:
    /// [{"ruleId": "ab12", "verdict": "pass|fail|na", "note": "..."}]
    Check {
        /// Resumo do que foi feito.
        #[arg(long)]
        task: String,
        /// Arquivo alterado (repetível).
        #[arg(long = "file")]
        files: Vec<String>,
        /// Tópicos extras.
        #[arg(long, num_args = 1..)]
        topics: Vec<String>,
        /// Id do item de revisão relacionado.
        #[arg(long)]
        item: Option<String>,
        /// JSON dos resultados (padrão: stdin).
        #[arg(long)]
        results: Option<String>,
        /// Marca o check como feito por IA.
        #[arg(long)]
        ai: bool,
        /// Exige a resposta de todas as regras manuais (a parte feita pela IA).
        #[arg(long)]
        manual: bool,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Histórico de verificações.
    Checks {
        /// Filtra por tópico.
        #[arg(long)]
        topic: Option<String>,
        #[arg(long, default_value_t = 20)]
        limit: i64,
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
}

fn run_rules(args: RulesArgs, ctx: &Context) -> Result<i32, CliError> {
    let command = args
        .command
        .unwrap_or(RulesCommand::List { json: args.json });
    match command {
        RulesCommand::List { json } => rules_list(ctx, json),
        RulesCommand::Show { topic, json } => rules_show(ctx, &topic, json),
        RulesCommand::New {
            title,
            description,
            paths,
            tags,
        } => {
            let store = ctx.store()?;
            let created = rules::create_topic(&store, &title, description, tags, paths, vec![])?;
            println!("{}", created.slug);
            Ok(0)
        }
        RulesCommand::Add {
            topic,
            text,
            details,
            should,
            ai,
        } => {
            let store = ctx.store()?;
            let mut rule = Rule::new(text);
            rule.details = details;
            rule.severity = if should {
                RuleSeverity::Should
            } else {
                RuleSeverity::Must
            };
            rule.author = if ai { Author::Ai } else { Author::Human };
            let id = rule.id;
            let (slug, _) = rules::add_rule(&store, rule, &topic)?;
            println!("{id}\t{slug}");
            Ok(0)
        }
        RulesCommand::Remove { id } => {
            rules::delete_rule(&ctx.store()?, &id)?;
            Ok(0)
        }
        RulesCommand::For {
            files,
            topics,
            item,
            manual,
            json,
        } => rules_for(ctx, files, topics, item, manual, json),
        RulesCommand::Test {
            files,
            topics,
            item,
            json,
        } => rules_test(ctx, files, topics, item, json),
        RulesCommand::SetTest {
            id,
            command,
            manual,
            reason,
            clear,
        } => rules_set_test(ctx, &id, command, manual, reason, clear),
        RulesCommand::Check {
            task,
            files,
            topics,
            item,
            results,
            ai,
            manual,
            json,
        } => rules_check(ctx, task, files, topics, item, results, ai, manual, json),
        RulesCommand::Checks { topic, limit, json } => rules_checks(ctx, topic, limit, json),
    }
}

fn rules_list(ctx: &Context, json: bool) -> Result<i32, CliError> {
    let topics = rules::list_topics(&ctx.store()?)?;
    if json {
        let rows: Vec<TopicChecklist> = topics
            .iter()
            .map(|t| TopicChecklist::new(&t.slug, &t.value, true))
            .collect();
        print_json(&rows)?;
        return Ok(0);
    }
    for Record { slug, value: t } in &topics {
        println!(
            "{slug}\t{}\t{} regra(s)\t[{}]{}",
            t.title,
            t.rules.len(),
            scope_text(t),
            hashtags(&t.tags)
        );
    }
    Ok(0)
}

fn rules_show(ctx: &Context, topic: &str, json: bool) -> Result<i32, CliError> {
    let store = ctx.store()?;
    let slug = rules::resolve_topic_slug(&store, topic)?;
    let t = rules::load_topic(&store, &slug)?;
    if json {
        print_json(&TopicChecklist::new(&slug, &t, true))?;
        return Ok(0);
    }
    println!("{} [{slug}] — {}", t.title, scope_text(&t));
    if let Some(d) = &t.description {
        println!("{d}");
    }
    print_rules(&t.rules);
    Ok(0)
}

fn rules_for(
    ctx: &Context,
    mut files: Vec<String>,
    mut topics: Vec<String>,
    item: Option<String>,
    manual: bool,
    json: bool,
) -> Result<i32, CliError> {
    let store = ctx.store()?;
    if let Some(reference) = item {
        let item = rules::find_review_item(&store, &reference)?;
        topics.extend(item.rules.iter().cloned());
        if let Some(file) = item.target.as_ref().and_then(|t| t.file.clone()) {
            files.push(file);
        }
    }
    let applicable = rules::applicable_topics(&store, &files, &topics)?;
    if json {
        let rows: Vec<TopicChecklist> = applicable
            .iter()
            .map(|t| TopicChecklist::new(&t.slug, &t.value, manual))
            .collect();
        print_json(&rows)?;
        return Ok(0);
    }
    if applicable.is_empty() {
        println!("Nenhuma regra aplicável.");
        return Ok(0);
    }
    for Record { slug, value: t } in &applicable {
        println!("## {} [{slug}]", t.title);
        print_rules(&t.rules);
    }
    Ok(0)
}

fn rules_test(
    ctx: &Context,
    files: Vec<String>,
    topics: Vec<String>,
    item: Option<String>,
    json: bool,
) -> Result<i32, CliError> {
    let store = ctx.store()?;
    let all = files.is_empty() && topics.is_empty() && item.is_none();
    let only_topics = files.is_empty() && item.is_none();
    let topics = if all {
        rules::list_topics(&store)?
            .into_iter()
            .map(|t| t.slug)
            .collect()
    } else {
        topics
    };
    let spec = TaskSpec {
        files,
        topics,
        review_item: item,
    };
    let runs = rules::run_rule_tests(&store, &spec, only_topics, &RuleTestRunner::live())?;
    if json {
        let rows: Vec<RuleTestRunRow> = runs.iter().map(RuleTestRunRow::from).collect();
        print_json(&rows)?;
        return Ok(0);
    }
    if runs.is_empty() {
        println!("Nenhuma regra aplicável tem script. Gere com o botão \"Gerar testes\" no app.");
        return Ok(0);
    }
    for r in &runs {
        let icon = match r.outcome.verdict {
            RuleVerdict::Pass => "✅",
            RuleVerdict::Fail => "❌",
            RuleVerdict::Na => "–",
        };
        println!(
            "{icon} [{}] {} {}  (exit {})",
            r.topic,
            id8(&r.rule.id),
            r.rule.text,
            r.outcome.exit_code
        );
        if r.outcome.verdict == RuleVerdict::Fail {
            let indented: Vec<String> = r
                .outcome
                .output
                .split('\n')
                .map(|l| format!("    {l}"))
                .collect();
            println!("{}", indented.join("\n"));
        }
    }
    let must_failed = runs
        .iter()
        .any(|r| r.outcome.verdict == RuleVerdict::Fail && r.rule.severity == RuleSeverity::Must);
    Ok(i32::from(must_failed))
}

fn rules_set_test(
    ctx: &Context,
    id: &str,
    command: Option<String>,
    manual: bool,
    reason: Option<String>,
    clear: bool,
) -> Result<i32, CliError> {
    let modes = [command.is_some(), manual, clear]
        .iter()
        .filter(|m| **m)
        .count();
    if modes != 1 {
        return Err(CliError {
            message: "Use exatamente um de --command, --manual ou --clear.".to_string(),
            code: EXIT_USAGE,
        });
    }
    let store = ctx.store()?;
    let rule = if clear {
        rules::clear_rule_test(&store, id)?
    } else {
        let mode = if manual {
            RuleTestMode::Manual
        } else {
            RuleTestMode::Script
        };
        rules::set_rule_test(&store, id, mode, command.as_deref(), reason.as_deref())?
    };
    println!("{}\t{}", id8(&rule.id), rule.test_state().label());
    Ok(0)
}

#[allow(clippy::too_many_arguments)]
fn rules_check(
    ctx: &Context,
    task: String,
    files: Vec<String>,
    topics: Vec<String>,
    item: Option<String>,
    results: Option<String>,
    ai: bool,
    manual: bool,
    json: bool,
) -> Result<i32, CliError> {
    let raw = match results {
        Some(r) => r.into_bytes(),
        None if manual => {
            let mut buf = Vec::new();
            let _ = std::io::stdin().read_to_end(&mut buf);
            buf
        }
        None => Vec::new(),
    };
    let raw = if raw.is_empty() { b"[]".to_vec() } else { raw };
    let answers: Vec<RuleAnswer> =
        serde_json::from_slice(&raw).map_err(|e| CliError::new(e.to_string()))?;
    let store = ctx.store()?;
    let check = rules::submit_check(
        &store,
        &SubmitParams {
            task,
            spec: TaskSpec {
                files,
                topics,
                review_item: item,
            },
            answers,
            verify_manual: manual,
            author: if ai { Author::Ai } else { Author::Human },
        },
        &RuleTestRunner::live(),
    )?;
    if json {
        print_json(&check)?;
        return Ok(0);
    }
    let scripted = check
        .results
        .iter()
        .filter(|r| r.source == RuleResultSource::Script)
        .count();
    if check.passed {
        println!(
            "✅ Aprovado ({} regra(s), {scripted} por script)",
            check.results.len()
        );
    } else {
        println!("❌ Reprovado");
    }
    for f in &check.failures {
        println!("  ✗ {f}");
    }
    for w in &check.warnings {
        println!("  ⚠ {w}");
    }
    if !check.pending.is_empty() {
        println!(
            "  ⏭ {} regra(s) manual(is) não verificada(s) (use --manual)",
            check.pending.len()
        );
    }
    Ok(i32::from(!check.passed))
}

fn rules_checks(
    ctx: &Context,
    topic: Option<String>,
    limit: i64,
    json: bool,
) -> Result<i32, CliError> {
    let store = ctx.store()?;
    let slug = topic
        .map(|t| rules::resolve_topic_slug(&store, &t))
        .transpose()?;
    let checks: Vec<RuleCheck> = rules::list_checks(&store)?
        .into_iter()
        .filter(|c| slug.as_ref().is_none_or(|s| c.topics.contains(s)))
        .take(limit.max(0) as usize)
        .collect();
    if json {
        print_json(&checks)?;
        return Ok(0);
    }
    for c in &checks {
        let item = c
            .review_item
            .map(|i| format!("  item {}", id8(&i)))
            .unwrap_or_default();
        let when = c
            .created_at
            .0
            .with_timezone(&chrono::Local)
            .format("%-m/%-d/%Y, %-I:%M %p");
        println!(
            "{when}  {}  {}{item}",
            if c.passed { "✅" } else { "❌" },
            c.task
        );
    }
    Ok(0)
}

// ---- hook -------------------------------------------------------------------------------------------

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct HookArgs {
    #[command(subcommand)]
    pub command: Option<HookCommand>,
    /// Saída JSON (sem subcomando, equivale a `status`).
    #[arg(long)]
    pub json: bool,
}

#[derive(Clone, Copy, Debug, ValueEnum)]
#[value(rename_all = "lowercase")]
pub enum AgentArg {
    Claude,
    Codex,
}

impl From<AgentArg> for HookAgent {
    fn from(a: AgentArg) -> Self {
        match a {
            AgentArg::Claude => HookAgent::Claude,
            AgentArg::Codex => HookAgent::Codex,
        }
    }
}

#[derive(Clone, Copy, Debug, ValueEnum)]
#[value(rename_all = "lowercase")]
pub enum ScopeArg {
    Local,
    Project,
}

impl From<ScopeArg> for HookScope {
    fn from(s: ScopeArg) -> Self {
        match s {
            ScopeArg::Local => HookScope::Local,
            ScopeArg::Project => HookScope::Project,
        }
    }
}

#[derive(Subcommand, Debug)]
pub enum HookCommand {
    /// Mostra onde o hook está ligado e quais alterações ele bloquearia agora.
    Status {
        /// Saída JSON.
        #[arg(long)]
        json: bool,
    },
    /// Comando do hook Stop: lê o JSON do agente no stdin e bloqueia o fim da resposta se faltar check.
    Stop {
        /// Bloqueios seguidos na sessão antes de liberar com aviso ao usuário (evita laço infinito).
        #[arg(long, default_value_t = 3)]
        max_blocks: i64,
    },
    /// Comando do hook SessionStart: marca o início da sessão.
    Start,
    /// Liga o hook neste projeto, no Claude Code ou no Codex.
    Install {
        /// Agente: claude ou codex.
        #[arg(short, long, value_enum, default_value_t = AgentArg::Claude)]
        agent: AgentArg,
        /// Escopo: local (só você) ou project (versionado). Padrão: local no Claude Code, project no Codex.
        #[arg(short, long, value_enum)]
        scope: Option<ScopeArg>,
    },
    /// Desliga o hook do VibeDeck neste projeto.
    Uninstall {
        /// Agente: claude ou codex.
        #[arg(short, long, value_enum, default_value_t = AgentArg::Claude)]
        agent: AgentArg,
        /// Escopo: local ou project. Padrão: local no Claude Code, project no Codex.
        #[arg(short, long, value_enum)]
        scope: Option<ScopeArg>,
    },
}

fn run_hook(args: HookArgs, ctx: &Context) -> Result<i32, CliError> {
    match args
        .command
        .unwrap_or(HookCommand::Status { json: args.json })
    {
        HookCommand::Status { json } => hook_status(ctx, json),
        HookCommand::Stop { max_blocks } => hook_stop(ctx, max_blocks),
        HookCommand::Start => hook_start(),
        HookCommand::Install { agent, scope } => hook_install(ctx, agent.into(), scope),
        HookCommand::Uninstall { agent, scope } => hook_uninstall(ctx, agent.into(), scope),
    }
}

#[derive(Serialize)]
struct Installed {
    agent: &'static str,
    scope: &'static str,
    file: String,
    on: bool,
}

#[derive(Serialize)]
struct Summary {
    hooks: Vec<Installed>,
    unverified: Vec<rules::UnverifiedChange>,
}

fn hook_status(ctx: &Context, json: bool) -> Result<i32, CliError> {
    let store = ctx.store()?;
    let mut hooks = Vec::new();
    for agent in HookAgent::ALL {
        for scope in HookScope::ALL {
            let Some(file) = rules::hook_file(agent, scope, store.root()) else {
                continue;
            };
            hooks.push(Installed {
                agent: agent.as_str(),
                scope: scope.as_str(),
                on: rules::has_stop_hook(&file)?,
                file: file.display().to_string(),
            });
        }
    }
    let changes = rules::working_tree_changes(store.root(), None);
    let unverified = rules::unverified_changes(&store, &changes)?;
    if json {
        print_json(&Summary { hooks, unverified })?;
        return Ok(0);
    }
    for h in &hooks {
        println!(
            "{} {}: {} ({})",
            h.agent,
            h.scope,
            if h.on { "ligado" } else { "desligado" },
            h.file
        );
    }
    if unverified.is_empty() {
        println!("Nenhuma alteração pendente de check.");
    } else {
        println!("{}", rules::stop_gate_reason(&unverified));
    }
    Ok(0)
}

/// Entrada comum dos hooks do Claude Code e do Codex (o Codex pode mandar `transcript_path: null`).
#[derive(Default)]
struct HookInput {
    session_id: Option<String>,
    transcript_path: Option<String>,
    cwd: Option<String>,
}

impl HookInput {
    fn read() -> Option<HookInput> {
        let mut buf = Vec::new();
        std::io::stdin().read_to_end(&mut buf).ok()?;
        let v: serde_json::Value = serde_json::from_slice(&buf).ok()?;
        let get = |k: &str| v.get(k).and_then(|x| x.as_str()).map(str::to_string);
        v.is_object().then(|| HookInput {
            session_id: get("session_id"),
            transcript_path: get("transcript_path"),
            cwd: get("cwd"),
        })
    }

    /// Arquivo temporário da sessão (`start` marca o início; `count`, os bloqueios seguidos).
    fn state_path(&self, kind: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "vibedeck-{kind}-{}",
            self.session_id.as_deref().unwrap_or("sem-sessao")
        ))
    }
}

fn created_at(path: &Path) -> Option<SystemTime> {
    let meta = std::fs::metadata(path).ok()?;
    meta.created().or_else(|_| meta.modified()).ok()
}

fn print_hook_output(entries: &[(&str, String)]) {
    let map: serde_json::Map<String, serde_json::Value> = entries
        .iter()
        .map(|(k, v)| ((*k).to_string(), serde_json::Value::String(v.clone())))
        .collect();
    println!("{}", serde_json::Value::Object(map));
}

fn hook_stop(ctx: &Context, max_blocks: i64) -> Result<i32, CliError> {
    let input = HookInput::read();
    let start = match (&ctx.root_arg, input.as_ref().and_then(|i| i.cwd.as_ref())) {
        (None, Some(cwd)) => Some(PathBuf::from(cwd)),
        (root, _) => root.clone(),
    };
    // Fora de um projeto VibeDeck o hook não tem o que verificar.
    let Ok(root) = super::locate_root(start.as_deref()) else {
        return Ok(0);
    };
    let Ok(store) = Store::open(&root) else {
        return Ok(0);
    };
    // A sessão começa quando o transcript nasce (Claude Code) ou quando `hook start` rodou (Codex).
    let since = input
        .as_ref()
        .and_then(|i| i.transcript_path.as_deref())
        .and_then(|p| created_at(Path::new(p)))
        .or_else(|| {
            input
                .as_ref()
                .and_then(|i| created_at(&i.state_path("start")))
        });
    let changes = rules::working_tree_changes(store.root(), since);
    let unverified = rules::unverified_changes(&store, &changes)?;

    let counter = input
        .as_ref()
        .unwrap_or(&HookInput::default())
        .state_path("count");
    if unverified.is_empty() {
        let _ = std::fs::remove_file(&counter);
        return Ok(0);
    }
    let blocks: i64 = std::fs::read_to_string(&counter)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);
    if blocks >= max_blocks {
        let _ = std::fs::remove_file(&counter);
        let files: Vec<&str> = unverified.iter().map(|u| u.file.as_str()).collect();
        print_hook_output(&[(
            "systemMessage",
            format!(
                "⚠️ VibeDeck: o agente parou sem check de regras aprovado para: {}",
                files.join(", ")
            ),
        )]);
        return Ok(0);
    }
    let _ = std::fs::write(&counter, (blocks + 1).to_string());
    print_hook_output(&[
        ("decision", "block".to_string()),
        ("reason", rules::stop_gate_reason(&unverified)),
    ]);
    Ok(0)
}

fn hook_start() -> Result<i32, CliError> {
    let Some(input) = HookInput::read() else {
        return Ok(0);
    };
    if input.session_id.is_none() {
        return Ok(0);
    }
    let marker = input.state_path("start");
    // Retomar ou compactar a sessão não muda o início: só a primeira chamada cria a marca.
    if !marker.exists() {
        let _ = std::fs::write(&marker, b"");
    }
    Ok(0)
}

fn default_scope(agent: HookAgent, scope: Option<ScopeArg>) -> HookScope {
    scope
        .map(Into::into)
        .unwrap_or(if agent == HookAgent::Codex {
            HookScope::Project
        } else {
            HookScope::Local
        })
}

/// Caminho do executável `vibedeck` a registrar: o encontrado no PATH ou, na falta dele, o binário atual.
fn executable_path() -> String {
    let arg0 = std::env::args().next().unwrap_or_default();
    if arg0.contains('/') {
        return std::fs::canonicalize(&arg0)
            .map(|p| p.display().to_string())
            .unwrap_or(arg0);
    }
    if let Some(path) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&path) {
            let candidate = dir.join(&arg0);
            if candidate.is_file() {
                return candidate.display().to_string();
            }
        }
    }
    std::env::current_exe()
        .map(|p| p.display().to_string())
        .unwrap_or(arg0)
}

fn hook_install(ctx: &Context, agent: HookAgent, scope: Option<ScopeArg>) -> Result<i32, CliError> {
    let scope = default_scope(agent, scope);
    let root = ctx.root()?;
    let Some(file) = rules::hook_file(agent, scope, &root) else {
        return Err(CliError::new(
            "O Codex não tem um arquivo de hooks só seu por projeto. Use --scope project (.codex/hooks.json).",
        ));
    };
    // Arquivos versionados usam o comando do PATH em vez de um caminho absoluto desta máquina.
    let executable = if scope == HookScope::Project {
        "vibedeck".to_string()
    } else {
        executable_path()
    };
    rules::install_stop_hook(&executable, &file, agent.needs_session_start())?;
    println!("Hook ligado em {}.", file.display());
    if agent == HookAgent::Codex {
        println!(
            "No Codex, aprove o hook com /hooks antes da próxima resposta (hooks novos só rodam depois de aprovados)."
        );
    }
    Ok(0)
}

fn hook_uninstall(
    ctx: &Context,
    agent: HookAgent,
    scope: Option<ScopeArg>,
) -> Result<i32, CliError> {
    let scope = default_scope(agent, scope);
    let root = ctx.root()?;
    let Some(file) = rules::hook_file(agent, scope, &root) else {
        return Err(CliError::new(
            "O Codex só tem o escopo project (.codex/hooks.json).",
        ));
    };
    rules::uninstall_stop_hook(&file)?;
    println!("Hook do VibeDeck removido de {}.", file.display());
    Ok(0)
}
