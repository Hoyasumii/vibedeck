//! Modelos serde de `vibedeck.json` e `.vibedeck/**` (um arquivo por schema v1).

pub mod common;
pub mod idea;
pub mod persona;
pub mod project;
pub mod review_group;
pub mod rule_check;
pub mod rule_topic;
pub mod workflow;
pub mod workflow_run;

pub use common::{Author, Id, Timestamp, TimestampMs};
pub use idea::{Idea, IdeaReadiness, IdeaStatus};
pub use persona::{
    Agent, Command, NextStep, NextStepKind, ProviderSettings, ProviderSettingsMap, Skill,
};
pub use project::{
    ClaudeItem, ClaudeItemKind, Link, Project, ProjectPattern, ReviewKind, StackItem, schema_url,
};
pub use review_group::{ReviewGroup, ReviewItem, ReviewPriority, ReviewStatus, ReviewTarget};
pub use rule_check::{RuleCheck, RuleResult, RuleResultSource, RuleVerdict};
pub use rule_topic::{Rule, RuleSeverity, RuleTest, RuleTestMode, RuleTopic};
pub use workflow::{DEFAULT_MAX_STEPS, Workflow, WorkflowStep, WorkflowTransition};
pub use workflow_run::{
    AiProvider, WorkflowQuestion, WorkflowQuestionOption, WorkflowRun, WorkflowRunEntry,
    WorkflowRunStatus, WorkflowStepCheckpoint,
};
