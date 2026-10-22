//! Piloto F03: scripts reais deste repositório rodando pelo runner de produção (`$SHELL -lc`).

use std::path::PathBuf;
use vibedeck_core::Store;
use vibedeck_core::model::RuleVerdict;
use vibedeck_core::rules::{self, RuleTestRunner, RunContext};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// (id completo do UUID, esperado com FILES vazio, esperado com README.md)
const PILOT: &[(&str, RuleVerdict, RuleVerdict)] = &[
    ("9F92A765", RuleVerdict::Pass, RuleVerdict::Na),
    ("0A89A5BC", RuleVerdict::Pass, RuleVerdict::Na),
    ("57ADA275", RuleVerdict::Pass, RuleVerdict::Na),
    ("DFE3361B", RuleVerdict::Pass, RuleVerdict::Pass),
];

#[test]
fn real_rule_scripts_decide_as_expected() {
    let root = repo_root();
    if !root.join(".vibedeck/tests/geral/9f92a765.sh").exists() {
        eprintln!("scripts do piloto ausentes; teste ignorado");
        return;
    }
    let store = Store::open(&root).unwrap();
    let runner = RuleTestRunner::live();
    for (prefix, empty, readme) in PILOT {
        let (_, topic, index) = rules::find_rule(&store, prefix).unwrap();
        let rule = &topic.rules[index];
        let command = rules::RuleExt::script_command(rule).expect("regra com script atual");
        for (files, expected) in [(vec![], *empty), (vec!["README.md".to_string()], *readme)] {
            let ctx = RunContext {
                root: store.root().to_path_buf(),
                files: files.clone(),
                rule_id: rule.id,
                cancellation: None,
            };
            let outcome = runner.run(&command, &ctx);
            assert_eq!(
                outcome.verdict, expected,
                "{prefix} com {files:?}: exit {} {}",
                outcome.exit_code, outcome.output
            );
        }
    }
}
