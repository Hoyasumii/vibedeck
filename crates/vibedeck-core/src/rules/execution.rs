//! Execução de scripts de regras: resultado, runner injetável, escalonador paralelo com trava por
//! ferramenta (dados.md §5) e utilidades da verificação feita pelo app (`RuleExecution.swift`).

use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::model::{Id, Rule, RuleResult, RuleVerdict};
use crate::time::{self, DateTimeUtc};

use super::error::{Result, RuleError};
use super::rule::RuleExt;
use super::runner::{BuildToolLock, Cancellation, ShellOptions, run_shell};

pub const NOT_APPLICABLE_EXIT: i32 = 77;

/// O que o script de uma regra disse: 0 = cumpre, 77 = não se aplica, outro = viola.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuleTestOutcome {
    pub verdict: RuleVerdict,
    pub exit_code: i32,
    pub output: String,
}

impl RuleTestOutcome {
    pub fn from_exit(exit_code: i32, output: impl Into<String>) -> Self {
        let verdict = match exit_code {
            0 => RuleVerdict::Pass,
            NOT_APPLICABLE_EXIT => RuleVerdict::Na,
            _ => RuleVerdict::Fail,
        };
        RuleTestOutcome {
            verdict,
            exit_code,
            output: output.into(),
        }
    }
}

/// Uma execução de script, como `run_rule_tests` reporta.
#[derive(Debug, Clone)]
pub struct RuleTestRun {
    pub topic: String,
    pub rule: Rule,
    pub command: String,
    pub outcome: RuleTestOutcome,
}

/// Contexto entregue ao runner.
#[derive(Clone)]
pub struct RunContext {
    pub root: PathBuf,
    pub files: Vec<String>,
    pub rule_id: Id,
    /// Disparado no cancelamento: o script em andamento tem de parar e retornar.
    pub cancellation: Option<Cancellation>,
}

type RunFn = dyn Fn(&str, &RunContext) -> RuleTestOutcome + Send + Sync;

/// Roda o script de uma regra. Injetável: testes não precisam lançar processos.
#[derive(Clone)]
pub struct RuleTestRunner(Arc<RunFn>);

impl RuleTestRunner {
    pub fn new(f: impl Fn(&str, &RunContext) -> RuleTestOutcome + Send + Sync + 'static) -> Self {
        RuleTestRunner(Arc::new(f))
    }

    /// Runner real: `$SHELL -lc`, timeout de 120 s, saída de até 4000 caracteres.
    pub fn live() -> Self {
        Self::live_with(Duration::from_secs(120), 4000)
    }

    /// Como `live`, com timeout e limite de saída configuráveis (testes).
    pub fn live_with(timeout: Duration, output_limit: usize) -> Self {
        RuleTestRunner::new(move |command, ctx| {
            let opts = ShellOptions {
                env: vec![
                    ("VIBEDECK_ROOT".into(), ctx.root.display().to_string()),
                    ("VIBEDECK_FILES".into(), ctx.files.join("\n")),
                    ("VIBEDECK_RULE_ID".into(), ctx.rule_id.to_string()),
                ],
                timeout,
                output_limit,
                cancellation: ctx.cancellation.clone(),
            };
            let result = run_shell(command, &ctx.root, &opts);
            RuleTestOutcome::from_exit(result.status, result.output)
        })
    }

    pub fn run(&self, command: &str, ctx: &RunContext) -> RuleTestOutcome {
        (self.0)(command, ctx)
    }
}

#[derive(Debug, Clone)]
pub enum RuleScriptEvent {
    Started {
        topic: String,
        rule: Rule,
        at: DateTimeUtc,
    },
    Finished {
        run: RuleTestRun,
        at: DateTimeUtc,
    },
}

#[derive(Clone, Default)]
pub struct RunOptions {
    /// Limite pedido de scripts simultâneos (`None` = núcleos ativos).
    pub concurrency: Option<usize>,
    pub cancellation: Option<Cancellation>,
    /// Depois de um `must` reprovado nenhum script novo começa (só o app usa).
    pub stop_on_must_failure: bool,
}

/// Núcleos ativos.
pub fn default_script_concurrency() -> usize {
    std::thread::available_parallelism().map_or(1, |n| n.get())
}

/// O limite pedido preso a `1..=núcleos`; `None` = padrão.
pub fn script_concurrency(requested: Option<usize>) -> usize {
    let cores = default_script_concurrency();
    requested.unwrap_or(cores).clamp(1, cores)
}

struct Job {
    topic: String,
    rule: Rule,
    command: String,
    locks: HashSet<&'static str>,
}

struct State {
    pending: Vec<usize>,
    running: usize,
    busy: HashSet<&'static str>,
    stopped: bool,
    results: Vec<Option<RuleTestRun>>,
}

struct Shared {
    state: Mutex<State>,
    cv: Condvar,
}

fn lock(shared: &Shared) -> MutexGuard<'_, State> {
    shared.state.lock().unwrap_or_else(|e| e.into_inner())
}

/// Roda os scripts em paralelo (até `concurrency`). Scripts com a mesma ferramenta de build nunca se
/// sobrepõem (esperar a trava não ocupa vaga). Resultados na ordem de declaração; eventos serializados,
/// `Started` antes de `Finished` por regra. Só regras no estado `script` viram trabalho.
pub fn run_scripts(
    root: &Path,
    rules: &[(String, Rule)],
    files: &[String],
    runner: &RuleTestRunner,
    opts: &RunOptions,
    on_event: &(dyn Fn(RuleScriptEvent) + Sync),
) -> Vec<RuleTestRun> {
    let jobs: Vec<Job> = rules
        .iter()
        .filter_map(|(slug, rule)| {
            rule.script_command().map(|command| Job {
                topic: slug.clone(),
                rule: rule.clone(),
                locks: BuildToolLock::keys_for_command(&command, root)
                    .into_iter()
                    .collect(),
                command,
            })
        })
        .collect();
    if jobs.is_empty() {
        return Vec::new();
    }
    let limit = script_concurrency(opts.concurrency);
    let shared = Arc::new(Shared {
        state: Mutex::new(State {
            pending: (0..jobs.len()).collect(),
            running: 0,
            busy: HashSet::new(),
            stopped: false,
            results: vec![None; jobs.len()],
        }),
        cv: Condvar::new(),
    });
    let wake = opts.cancellation.as_ref().map(|c| {
        let shared = Arc::clone(&shared);
        c.on_cancel(move || {
            let _g = lock(&shared);
            shared.cv.notify_all();
        })
    });
    let cancelled = || {
        opts.cancellation
            .as_ref()
            .is_some_and(Cancellation::is_cancelled)
    };

    std::thread::scope(|scope| {
        let mut guard = lock(&shared);
        while !guard.pending.is_empty() && !guard.stopped && !cancelled() {
            let next = if guard.running < limit {
                guard
                    .pending
                    .iter()
                    .position(|&i| jobs[i].locks.is_disjoint(&guard.busy))
            } else {
                None
            };
            let Some(position) = next else {
                guard = shared.cv.wait(guard).unwrap_or_else(|e| e.into_inner());
                continue;
            };
            let index = guard.pending.remove(position);
            let job = &jobs[index];
            guard.running += 1;
            guard.busy.extend(job.locks.iter().copied());
            on_event(RuleScriptEvent::Started {
                topic: job.topic.clone(),
                rule: job.rule.clone(),
                at: time::now(),
            });
            let shared = Arc::clone(&shared);
            let cancellation = opts.cancellation.clone();
            let stop_on_must = opts.stop_on_must_failure;
            scope.spawn(move || {
                let ctx = RunContext {
                    root: root.to_path_buf(),
                    files: files.to_vec(),
                    rule_id: job.rule.id,
                    cancellation,
                };
                let outcome = runner.run(&job.command, &ctx);
                let run = RuleTestRun {
                    topic: job.topic.clone(),
                    rule: job.rule.clone(),
                    command: job.command.clone(),
                    outcome,
                };
                let mut g = lock(&shared);
                // A vaga e a trava são liberadas seja qual for o fim do script.
                g.running -= 1;
                for k in &job.locks {
                    g.busy.remove(k);
                }
                if stop_on_must
                    && job.rule.severity == crate::model::RuleSeverity::Must
                    && run.outcome.verdict == RuleVerdict::Fail
                {
                    g.stopped = true;
                }
                g.results[index] = Some(run.clone());
                on_event(RuleScriptEvent::Finished {
                    run,
                    at: time::now(),
                });
                shared.cv.notify_all();
            });
        }
        drop(guard);
    });
    if let (Some(c), Some(t)) = (&opts.cancellation, wake) {
        c.remove(t);
    }
    let mut g = lock(&shared);
    std::mem::take(&mut g.results)
        .into_iter()
        .flatten()
        .collect()
}

// ---- verificação estruturada da IA (RuleExecution.swift) -----------------------------------------

/// Respostas estruturadas estritas: omissões, duplicatas e regras inesperadas são erro, nunca passes.
pub struct RuleVerificationAnswer;

#[derive(Deserialize)]
struct AnswerEntry {
    #[serde(rename = "ruleId")]
    rule_id: Id,
    verdict: RuleVerdict,
    note: String,
}

#[derive(Deserialize)]
struct Answer {
    results: Vec<AnswerEntry>,
}

impl RuleVerificationAnswer {
    pub const SCHEMA: &'static str = r#"{"type":"object","additionalProperties":false,"properties":{"results":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"ruleId":{"type":"string"},"verdict":{"type":"string","enum":["pass","fail","na"]},"note":{"type":"string"}},"required":["ruleId","verdict","note"]}}},"required":["results"]}"#;

    pub fn parse(data: &[u8], rules: &[Rule], topic: &str) -> Result<Vec<RuleResult>> {
        let answer: Answer = serde_json::from_slice(data).map_err(|_| RuleError::InvalidAnswer)?;
        let given: HashSet<Id> = answer.results.iter().map(|e| e.rule_id).collect();
        let expected: HashSet<Id> = rules.iter().map(|r| r.id).collect();
        if answer.results.len() != rules.len()
            || given != expected
            || answer.results.iter().any(|e| e.note.trim().is_empty())
        {
            return Err(RuleError::InvalidAnswer);
        }
        Ok(answer
            .results
            .into_iter()
            .map(|e| RuleResult {
                topic: topic.to_string(),
                rule_id: e.rule_id,
                verdict: e.verdict,
                note: Some(e.note),
                source: crate::model::RuleResultSource::Agent,
                exit_code: None,
            })
            .collect())
    }
}

/// Histórico limitado de tempos; quem chama persiste fora do repositório.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RuleExecutionTimings {
    pub samples: BTreeMap<String, Vec<f64>>,
}

impl RuleExecutionTimings {
    pub fn record(&mut self, duration: f64, key: &str) {
        if !duration.is_finite() || duration < 0.0 {
            return;
        }
        let entry = self.samples.entry(key.to_string()).or_default();
        entry.push(duration);
        if entry.len() > 10 {
            let drop = entry.len() - 10;
            entry.drain(..drop);
        }
    }

    /// Mediana das amostras da chave; sem elas, das chaves da categoria (`"<categoria>:..."`).
    pub fn estimate(&self, key: &str, category: &str) -> Option<f64> {
        let exact = self.samples.get(key).cloned().unwrap_or_default();
        let mut values: Vec<f64> = if exact.is_empty() {
            let prefix = format!("{category}:");
            self.samples
                .iter()
                .filter(|(k, _)| k.starts_with(&prefix))
                .flat_map(|(_, v)| v.iter().copied())
                .collect()
        } else {
            exact
        };
        if values.is_empty() {
            return None;
        }
        values.sort_by(f64::total_cmp);
        let middle = values.len() / 2;
        Some(if values.len() % 2 == 0 {
            (values[middle - 1] + values[middle]) / 2.0
        } else {
            values[middle]
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{RuleSeverity, RuleTest, RuleTestMode, Timestamp};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Instant;

    fn script_rule(text: &str, command: &str) -> Rule {
        let mut rule = Rule::new(text);
        rule.test = Some(RuleTest {
            mode: RuleTestMode::Script,
            command: Some(command.to_string()),
            reason: None,
            rule_hash: rule.content_hash(),
            generated_at: Timestamp::now(),
        });
        rule
    }

    fn noop(_: RuleScriptEvent) {}

    #[test]
    fn outcome_from_exit_code() {
        assert_eq!(RuleTestOutcome::from_exit(0, "").verdict, RuleVerdict::Pass);
        assert_eq!(RuleTestOutcome::from_exit(77, "").verdict, RuleVerdict::Na);
        for code in [1, 2, 124, 127, 130, 255] {
            assert_eq!(
                RuleTestOutcome::from_exit(code, "").verdict,
                RuleVerdict::Fail
            );
        }
    }

    #[test]
    fn concurrency_is_clamped() {
        let cores = default_script_concurrency();
        assert_eq!(script_concurrency(None), cores);
        assert_eq!(script_concurrency(Some(0)), 1);
        assert_eq!(script_concurrency(Some(10_000)), cores);
    }

    #[test]
    fn results_come_back_in_declaration_order_with_event_pairs() {
        let rules: Vec<(String, Rule)> = (0..6)
            .map(|i| {
                (
                    "t".to_string(),
                    script_rule(&format!("r{i}"), &format!("job{i}")),
                )
            })
            .collect();
        let events = Mutex::new(Vec::new());
        let runner = RuleTestRunner::new(|cmd, _| {
            // os primeiros demoram mais: a ordem de término difere da de declaração
            let n: u64 = cmd.trim_start_matches("job").parse().unwrap();
            std::thread::sleep(Duration::from_millis(60 - n * 10));
            RuleTestOutcome::from_exit(0, cmd)
        });
        let runs = run_scripts(
            Path::new("/tmp"),
            &rules,
            &[],
            &runner,
            &RunOptions {
                concurrency: Some(4),
                ..RunOptions::default()
            },
            &|e| {
                let (kind, id) = match &e {
                    RuleScriptEvent::Started { rule, .. } => ("s", rule.id),
                    RuleScriptEvent::Finished { run, .. } => ("f", run.rule.id),
                };
                events.lock().unwrap().push((kind, id));
            },
        );
        let commands: Vec<_> = runs.iter().map(|r| r.command.as_str()).collect();
        assert_eq!(commands, ["job0", "job1", "job2", "job3", "job4", "job5"]);
        let events = events.into_inner().unwrap();
        assert_eq!(events.len(), 12);
        for (_, rule) in &rules {
            let s = events.iter().position(|e| *e == ("s", rule.id)).unwrap();
            let f = events.iter().position(|e| *e == ("f", rule.id)).unwrap();
            assert!(s < f);
        }
    }

    #[test]
    fn runs_in_parallel_up_to_the_limit() {
        if default_script_concurrency() < 2 {
            return;
        }
        let rules: Vec<(String, Rule)> = (0..4)
            .map(|i| {
                (
                    "t".to_string(),
                    script_rule(&format!("r{i}"), &format!("p{i}")),
                )
            })
            .collect();
        let current = Arc::new(AtomicUsize::new(0));
        let peak = Arc::new(AtomicUsize::new(0));
        let (c, p) = (Arc::clone(&current), Arc::clone(&peak));
        let runner = RuleTestRunner::new(move |_, _| {
            let now = c.fetch_add(1, Ordering::SeqCst) + 1;
            p.fetch_max(now, Ordering::SeqCst);
            std::thread::sleep(Duration::from_millis(150));
            c.fetch_sub(1, Ordering::SeqCst);
            RuleTestOutcome::from_exit(0, "")
        });
        let runs = run_scripts(
            Path::new("/tmp"),
            &rules,
            &[],
            &runner,
            &RunOptions {
                concurrency: Some(2),
                ..RunOptions::default()
            },
            &noop,
        );
        assert_eq!(runs.len(), 4);
        let observed = peak.load(Ordering::SeqCst);
        assert!((2..=2).contains(&observed), "pico {observed}");
    }

    #[test]
    fn same_build_tool_never_overlaps() {
        if default_script_concurrency() < 2 {
            return;
        }
        let rules: Vec<(String, Rule)> = vec![
            ("t".into(), script_rule("a", "cargo build a")),
            ("t".into(), script_rule("b", "cargo test b")),
            ("t".into(), script_rule("c", "npm test c")),
        ];
        let current = Arc::new(Mutex::new(HashSet::<String>::new()));
        let overlap = Arc::new(AtomicUsize::new(0));
        let (cur, ov) = (Arc::clone(&current), Arc::clone(&overlap));
        let runner = RuleTestRunner::new(move |cmd, _| {
            let tool = cmd.split(' ').next().unwrap().to_string();
            if !cur.lock().unwrap().insert(tool.clone()) {
                ov.fetch_add(1, Ordering::SeqCst);
            }
            std::thread::sleep(Duration::from_millis(120));
            cur.lock().unwrap().remove(&tool);
            RuleTestOutcome::from_exit(0, "")
        });
        let started = Instant::now();
        let runs = run_scripts(
            Path::new("/tmp"),
            &rules,
            &[],
            &runner,
            &RunOptions::default(),
            &noop,
        );
        assert_eq!(runs.len(), 3);
        assert_eq!(overlap.load(Ordering::SeqCst), 0);
        assert!(started.elapsed() >= Duration::from_millis(240));
    }

    #[test]
    fn cancellation_stops_the_queue_and_running_scripts() {
        let rules: Vec<(String, Rule)> = (0..4)
            .map(|i| {
                (
                    "t".to_string(),
                    script_rule(&format!("r{i}"), &format!("c{i}")),
                )
            })
            .collect();
        let cancellation = Cancellation::new();
        let started = Arc::new(AtomicUsize::new(0));
        let st = Arc::clone(&started);
        let runner = RuleTestRunner::new(move |_, ctx| {
            st.fetch_add(1, Ordering::SeqCst);
            let c = ctx.cancellation.clone().unwrap();
            let deadline = Instant::now() + Duration::from_secs(10);
            while !c.is_cancelled() && Instant::now() < deadline {
                std::thread::sleep(Duration::from_millis(5));
            }
            RuleTestOutcome::from_exit(130, "Cancelado.")
        });
        let c2 = cancellation.clone();
        let canceller = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(200));
            c2.cancel();
        });
        let runs = run_scripts(
            Path::new("/tmp"),
            &rules,
            &[],
            &runner,
            &RunOptions {
                concurrency: Some(1),
                cancellation: Some(cancellation),
                ..RunOptions::default()
            },
            &noop,
        );
        canceller.join().unwrap();
        assert_eq!(started.load(Ordering::SeqCst), 1);
        assert_eq!(runs.len(), 1);
        assert_eq!(runs[0].outcome.exit_code, 130);
    }

    #[test]
    fn must_failure_stops_the_queue_only_when_asked() {
        let mut should = script_rule("s", "boom2");
        should.severity = RuleSeverity::Should;
        let rules: Vec<(String, Rule)> = vec![
            ("t".into(), script_rule("m", "boom1")),
            ("t".into(), should),
            ("t".into(), script_rule("x", "ok")),
        ];
        let runner = RuleTestRunner::new(|cmd, _| {
            RuleTestOutcome::from_exit(if cmd.starts_with("boom") { 1 } else { 0 }, "")
        });
        let all = run_scripts(
            Path::new("/tmp"),
            &rules,
            &[],
            &runner,
            &RunOptions {
                concurrency: Some(1),
                ..RunOptions::default()
            },
            &noop,
        );
        assert_eq!(all.len(), 3);
        let stopped = run_scripts(
            Path::new("/tmp"),
            &rules,
            &[],
            &runner,
            &RunOptions {
                concurrency: Some(1),
                stop_on_must_failure: true,
                ..RunOptions::default()
            },
            &noop,
        );
        assert_eq!(stopped.len(), 1);
    }

    #[test]
    fn stale_and_manual_rules_do_not_run() {
        let mut stale = script_rule("antes", "x");
        stale.text = "depois".into();
        let rules = vec![
            ("t".to_string(), stale),
            ("t".to_string(), Rule::new("sem teste")),
        ];
        let runner = RuleTestRunner::new(|_, _| panic!("não deve rodar"));
        assert!(
            run_scripts(
                Path::new("/tmp"),
                &rules,
                &[],
                &runner,
                &RunOptions::default(),
                &noop
            )
            .is_empty()
        );
    }

    #[test]
    fn validates_ai_answers() {
        let a = Rule::new("a");
        let b = Rule::new("b");
        let ok = format!(
            r#"{{"results":[{{"ruleId":"{}","verdict":"pass","note":"ok"}},{{"ruleId":"{}","verdict":"fail","note":"x"}}]}}"#,
            a.id, b.id
        );
        let parsed =
            RuleVerificationAnswer::parse(ok.as_bytes(), &[a.clone(), b.clone()], "t").unwrap();
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[1].verdict, RuleVerdict::Fail);
        for bad in [
            format!(
                r#"{{"results":[{{"ruleId":"{}","verdict":"pass","note":"ok"}}]}}"#,
                a.id
            ),
            format!(
                r#"{{"results":[{{"ruleId":"{0}","verdict":"pass","note":"ok"}},{{"ruleId":"{0}","verdict":"pass","note":"ok"}}]}}"#,
                a.id
            ),
            format!(
                r#"{{"results":[{{"ruleId":"{}","verdict":"pass","note":" "}},{{"ruleId":"{}","verdict":"pass","note":"ok"}}]}}"#,
                a.id, b.id
            ),
            "não é json".to_string(),
        ] {
            assert!(matches!(
                RuleVerificationAnswer::parse(bad.as_bytes(), &[a.clone(), b.clone()], "t"),
                Err(RuleError::InvalidAnswer)
            ));
        }
    }

    #[test]
    fn bounded_timing_history_and_category_fallback() {
        let mut t = RuleExecutionTimings::default();
        for i in 0..15 {
            t.record(f64::from(i), "script:a");
        }
        t.record(-1.0, "script:a");
        t.record(f64::NAN, "script:a");
        assert_eq!(t.samples["script:a"].len(), 10);
        assert_eq!(t.estimate("script:a", "script"), Some(9.5));
        t.record(100.0, "script:b");
        assert_eq!(t.estimate("script:zzz", "script"), Some(10.0));
        assert_eq!(t.estimate("x", "nada"), None);
    }
}
