//! Runner de scripts de regras (dados.md §5) pela API pública: timeout, saídas, truncamento,
//! cancelamento e concorrência.

use std::path::Path;
use std::time::{Duration, Instant};
use vibedeck_core::Store;
use vibedeck_core::model::{Rule, RuleTestMode, RuleVerdict};
use vibedeck_core::rules::{self, Cancellation, RuleTestRunner, RunContext, RunOptions, TaskSpec};

fn ctx(root: &Path) -> RunContext {
    RunContext {
        root: root.to_path_buf(),
        files: vec!["a.rs".into(), "b.rs".into()],
        rule_id: Default::default(),
        cancellation: None,
    }
}

#[test]
fn timeout_is_configurable_and_exits_124() {
    let dir = tempfile::tempdir().unwrap();
    let runner = RuleTestRunner::live_with(Duration::from_millis(400), 4000);
    let started = Instant::now();
    let out = runner.run("echo antes; sleep 30", &ctx(dir.path()));
    assert!(started.elapsed() < Duration::from_secs(10));
    assert_eq!(out.exit_code, 124);
    assert_eq!(out.verdict, RuleVerdict::Fail);
    assert!(out.output.starts_with("antes\n"));
}

#[test]
fn exit_codes_map_to_verdicts() {
    let dir = tempfile::tempdir().unwrap();
    let runner = RuleTestRunner::live();
    let c = ctx(dir.path());
    assert_eq!(runner.run("exit 0", &c).verdict, RuleVerdict::Pass);
    assert_eq!(runner.run("exit 77", &c).verdict, RuleVerdict::Na);
    let two = runner.run("echo motivo; exit 2", &c);
    assert_eq!((two.verdict, two.exit_code), (RuleVerdict::Fail, 2));
    assert_eq!(two.output, "motivo");
    let missing = runner.run("comando-que-nao-existe-xyz", &c);
    assert_eq!(
        (missing.verdict, missing.exit_code),
        (RuleVerdict::Fail, 127)
    );
}

#[test]
fn environment_cwd_and_stdin() {
    let dir = tempfile::tempdir().unwrap();
    let c = ctx(dir.path());
    let out = RuleTestRunner::live().run(
        "pwd; echo \"$VIBEDECK_ROOT\"; echo \"$VIBEDECK_FILES\"; echo \"$VIBEDECK_RULE_ID\"; cat",
        &c,
    );
    assert_eq!(out.exit_code, 0);
    let lines: Vec<&str> = out.output.lines().collect();
    assert_eq!(
        std::fs::canonicalize(lines[0]).unwrap(),
        std::fs::canonicalize(dir.path()).unwrap()
    );
    assert_eq!(lines[1], dir.path().display().to_string());
    assert_eq!(&lines[2..4], ["a.rs", "b.rs"]);
    assert_eq!(lines[4], c.rule_id.to_string());
}

#[test]
fn output_is_truncated_to_the_limit() {
    let dir = tempfile::tempdir().unwrap();
    let out = RuleTestRunner::live_with(Duration::from_secs(20), 100).run(
        "i=0; while [ $i -lt 500 ]; do printf x; i=$((i+1)); done; printf FIM",
        &ctx(dir.path()),
    );
    assert!(out.output.ends_with("xxFIM"));
    assert!(out.output.chars().count() < 150);
}

#[test]
fn cancellation_stops_the_script() {
    let dir = tempfile::tempdir().unwrap();
    let cancel = Cancellation::new();
    let mut c = ctx(dir.path());
    c.cancellation = Some(cancel.clone());
    let handle =
        std::thread::spawn(move || RuleTestRunner::live().run("echo rodando; sleep 30", &c));
    std::thread::sleep(Duration::from_millis(400));
    let started = Instant::now();
    cancel.cancel();
    let out = handle.join().unwrap();
    assert!(started.elapsed() < Duration::from_secs(10));
    assert_eq!(out.exit_code, 130);
}

fn project_with_scripts(n: usize, body: &str) -> (tempfile::TempDir, Store) {
    let tmp = tempfile::tempdir().unwrap();
    let store = Store::init(tmp.path(), "demo", None).unwrap();
    for i in 0..n {
        let (_, rule) = rules::add_rule(&store, Rule::new(format!("regra {i}")), "Geral").unwrap();
        rules::set_rule_test(
            &store,
            &rule.id.to_string(),
            RuleTestMode::Script,
            Some(&body.replace("{i}", &i.to_string())),
            None,
        )
        .unwrap();
    }
    (tmp, store)
}

#[test]
fn results_keep_declaration_order_under_concurrency() {
    // Os primeiros scripts dormem mais: a ordem do resultado não pode seguir a do término.
    let (_tmp, store) = project_with_scripts(6, "sleep 0.$((6 - {i})); echo r{i}; exit 0");
    let runs = rules::run_rule_tests(&store, &TaskSpec::default(), false, &RuleTestRunner::live())
        .unwrap();
    let texts: Vec<_> = runs.iter().map(|r| r.rule.text.clone()).collect();
    assert_eq!(
        texts,
        (0..6).map(|i| format!("regra {i}")).collect::<Vec<_>>()
    );
    assert!(runs.iter().all(|r| r.outcome.verdict == RuleVerdict::Pass));
}

#[test]
fn concurrency_limit_is_respected() {
    // Cada script marca presença; com limite 1 nunca há dois ao mesmo tempo.
    let body = "d=\"$VIBEDECK_ROOT/.run\"; mkdir -p $d; touch $d/{i}; n=$(ls $d | wc -l); \
                if [ $n -gt 1 ]; then echo sobreposto; rm $d/{i}; exit 1; fi; sleep 0.2; rm $d/{i}";
    let (_tmp, store) = project_with_scripts(4, body);
    let runs = rules::run_rule_tests_with(
        &store,
        &TaskSpec::default(),
        false,
        &RuleTestRunner::live(),
        &RunOptions {
            concurrency: Some(1),
            ..RunOptions::default()
        },
        &|_| {},
    )
    .unwrap();
    assert_eq!(runs.len(), 4);
    assert!(
        runs.iter().all(|r| r.outcome.verdict == RuleVerdict::Pass),
        "{:?}",
        runs.iter().map(|r| &r.outcome.output).collect::<Vec<_>>()
    );
}
