//! Regras: tópicos e regras, testes por script (runner), checks, gate do hook Stop e instalação do hook.
//!
//! Porta `Rules.swift`, `RuleTests.swift`, `RuleExecution.swift`, `RuleAgentOutput.swift`, `StopGate.swift`
//! e os trechos de `ProjectStore.swift` sobre regras. As funções recebem o `&Store` (funções livres, sem
//! `impl Store`, para não colidir com as demais áreas).

mod checklist;
mod error;
mod execution;
mod glob;
mod hook;
mod prompt;
mod rule;
mod runner;
mod stopgate;
mod tasks;
mod topics;

pub use checklist::{RuleRow, TopicChecklist, agent_summary};
pub use error::{Result, RuleError};
pub use execution::{
    RuleExecutionTimings, RuleScriptEvent, RuleTestOutcome, RuleTestRun, RuleTestRunner,
    RuleVerificationAnswer, RunContext, RunOptions, script_concurrency,
};
pub use glob::{matches as glob_matches, project_files};
pub use hook::{
    HookAgent, HookScope, has_stop_hook, hook_file, install_stop_hook, uninstall_stop_hook,
};
pub use prompt::{PromptSelection, generate_prompt, rules_for_selection, script_path};
pub use rule::{RuleExt, RuleTestState, TopicExt, trimmed_non_empty};
pub use runner::{
    BuildToolLock, CANCELLED_STATUS, Cancellation, ShellOptions, ShellResult, TIMED_OUT_STATUS,
    run_shell,
};
pub use stopgate::{UnverifiedChange, stop_gate_reason, unverified_changes, working_tree_changes};
pub use tasks::{
    RuleAnswer, RuleTestRunRow, SubmitParams, TaskScope, TaskSpec, complete_rule_execution,
    ensure_verified, list_checks, required_topics, run_rule_scripts, run_rule_tests,
    run_rule_tests_with, submit_check, task_scope, verification_problems,
};
pub use topics::{
    add_rule, applicable_topics, clear_rule_test, create_topic, delete_rule, delete_topic,
    find_review_item, find_rule, list_topics, load_topic, relative_path, relative_to_root,
    resolve_topic_slug, save_topic, set_rule_test, update_rule, update_topic,
};
