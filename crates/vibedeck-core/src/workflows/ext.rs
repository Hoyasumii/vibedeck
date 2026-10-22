//! Métodos de domínio dos modelos de workflow e de execução.

use std::collections::HashSet;

use crate::model::*;
use crate::slug;

pub fn kind_str(kind: NextStepKind) -> &'static str {
    match kind {
        NextStepKind::Agent => "agent",
        NextStepKind::Command => "command",
        NextStepKind::Skill => "skill",
    }
}

pub fn provider_str(provider: AiProvider) -> &'static str {
    match provider {
        AiProvider::Claude => "claude",
        AiProvider::Codex => "codex",
    }
}

pub fn status_str(status: WorkflowRunStatus) -> &'static str {
    match status {
        WorkflowRunStatus::Running => "running",
        WorkflowRunStatus::Waiting => "waiting",
        WorkflowRunStatus::Done => "done",
        WorkflowRunStatus::Stopped => "stopped",
    }
}

impl WorkflowTransition {
    pub fn new(verdict: Option<String>, when: Option<String>, to: impl Into<String>) -> Self {
        WorkflowTransition {
            verdict,
            when,
            to: to.into(),
        }
    }

    /// Sem veredito e sem condição: o "senão" da etapa.
    pub fn is_fallback(&self) -> bool {
        self.verdict.is_none() && self.when.is_none()
    }

    /// `= APROVADO`, `se <condição>` ou `senão`.
    pub fn label(&self) -> String {
        if let Some(v) = &self.verdict {
            return format!("= {v}");
        }
        if let Some(w) = &self.when {
            return format!("se {w}");
        }
        "senão".to_string()
    }

    /// Se `other` (a última linha do resultado de uma etapa) casa com o veredito desta transição.
    pub fn matches(&self, other: &str) -> bool {
        match &self.verdict {
            Some(v) => Self::normalize(v) == Self::normalize(other),
            None => false,
        }
    }

    /// Aparo + remoção de `` ` * _ . `` nas pontas + dobra de caixa e diacríticos.
    pub fn normalize(verdict: &str) -> String {
        let trimmed = verdict.trim().trim_matches(['`', '*', '_', '.']);
        slug::fold(trimmed)
    }
}

impl WorkflowStep {
    pub fn new(id: impl Into<String>, kind: NextStepKind, reference: impl Into<String>) -> Self {
        WorkflowStep {
            id: id.into(),
            kind,
            r#ref: reference.into(),
            note: None,
            max_visits: None,
            transitions: vec![],
        }
    }
}

impl Workflow {
    /// Índice de uma etapa por id, por `Slug.make(ref)` ou por posição (1-based).
    pub fn step_index(&self, reference: &str) -> Option<usize> {
        let r = reference.trim();
        if let Some(i) = self.steps.iter().position(|s| s.id == r) {
            return Some(i);
        }
        let made = slug::make(r);
        if let Some(i) = self.steps.iter().position(|s| s.id == made) {
            return Some(i);
        }
        if let Ok(n) = r.parse::<i64>()
            && n >= 1
            && (n as usize) <= self.steps.len()
        {
            return Some(n as usize - 1);
        }
        None
    }

    /// Id de etapa ainda não usado, derivado de `base` (`revisor`, `revisor-2`, ...).
    pub fn new_step_id(&self, base: &str) -> String {
        let base = slug::make(base);
        let taken: HashSet<&str> = self.steps.iter().map(|s| s.id.as_str()).collect();
        let mut id = base.clone();
        let mut n = 2;
        while taken.contains(id.as_str()) {
            id = format!("{base}-{n}");
            n += 1;
        }
        id
    }

    /// Remove uma etapa e toda transição que aponta para ela.
    pub fn remove_step(&mut self, index: usize) {
        let id = self.steps.remove(index).id;
        for s in &mut self.steps {
            s.transitions.retain(|t| t.to != id);
        }
    }

    /// Acrescenta uma transição mantendo a incondicional ("senão") por último.
    pub fn add_transition(&mut self, transition: WorkflowTransition, index: usize) {
        let list = &mut self.steps[index].transitions;
        if list.contains(&transition) {
            return;
        }
        if !transition.is_fallback()
            && let Some(otherwise) = list.iter().position(|t| t.is_fallback())
        {
            list.insert(otherwise, transition);
        } else {
            list.push(transition);
        }
    }
}

impl WorkflowRun {
    pub fn new(
        workflow: impl Into<String>,
        input: Option<String>,
        start: Option<String>,
        provider: AiProvider,
    ) -> Self {
        let now = Timestamp::now();
        WorkflowRun {
            schema: Some(crate::model::schema_url("workflow-run")),
            id: Id::new(),
            workflow: workflow.into(),
            provider,
            input,
            status: if start.is_none() {
                WorkflowRunStatus::Done
            } else {
                WorkflowRunStatus::Running
            },
            reason: start
                .is_none()
                .then(|| "o workflow não tem etapas".to_string()),
            current: start,
            cycle: 1,
            checkpoint: None,
            history: vec![],
            questions: vec![],
            created_at: now,
            updated_at: now,
        }
    }

    pub fn open_questions(&self) -> Vec<&WorkflowQuestion> {
        self.questions.iter().filter(|q| q.is_open()).collect()
    }

    /// Entradas do ciclo atual (o que `maxSteps` e `maxVisits` contam).
    pub fn current_cycle(&self) -> Vec<&WorkflowRunEntry> {
        self.history
            .iter()
            .filter(|e| e.cycle == self.cycle)
            .collect()
    }

    pub fn is_finished(&self) -> bool {
        matches!(
            self.status,
            WorkflowRunStatus::Done | WorkflowRunStatus::Stopped
        )
    }

    /// Respostas já dadas a uma etapa (ela as lê antes de começar, em vez de perguntar de novo).
    pub fn answers_for(&self, step: &str) -> Vec<&WorkflowQuestion> {
        self.questions
            .iter()
            .filter(|q| q.step == step && !q.is_open())
            .collect()
    }
}
