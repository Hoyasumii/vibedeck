//! Comportamento de `Rule`/`RuleTopic` (hash de conteúdo, estado do teste, casamento de arquivos).

use sha2::{Digest, Sha256};

use crate::model::{Rule, RuleTestMode, RuleTopic};

use super::glob;

/// `trimmed.nonEmpty`: corta espaços e quebras nas pontas; vazio vira `None`.
pub fn trimmed_non_empty(s: &str) -> Option<String> {
    let t = s.trim();
    (!t.is_empty()).then(|| t.to_string())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleTestState {
    None,
    Script,
    Manual,
    Stale,
}

impl RuleTestState {
    pub fn label(self) -> &'static str {
        match self {
            RuleTestState::None => "Sem teste",
            RuleTestState::Script => "Script",
            RuleTestState::Manual => "Manual",
            RuleTestState::Stale => "Desatualizado",
        }
    }

    /// `true` quando o agente precisa responder a regra num check.
    pub fn needs_agent(self) -> bool {
        self != RuleTestState::Script
    }
}

pub trait RuleExt {
    /// `hex(SHA-256(text + "\n" + (details ?? "")))[0..16]`.
    fn content_hash(&self) -> String;
    fn test_state(&self) -> RuleTestState;
    /// Comando a rodar quando a regra é decidida por script (`None` se manual, sem teste ou desatualizada).
    fn script_command(&self) -> Option<String>;
}

impl RuleExt for Rule {
    fn content_hash(&self) -> String {
        let mut hasher = Sha256::new();
        hasher.update(self.text.as_bytes());
        hasher.update(b"\n");
        hasher.update(self.details.as_deref().unwrap_or("").as_bytes());
        let digest = hasher.finalize();
        digest.iter().take(8).map(|b| format!("{b:02x}")).collect()
    }

    fn test_state(&self) -> RuleTestState {
        let Some(test) = &self.test else {
            return RuleTestState::None;
        };
        if test.rule_hash != self.content_hash() {
            return RuleTestState::Stale;
        }
        let has_command = test
            .command
            .as_deref()
            .and_then(trimmed_non_empty)
            .is_some();
        if test.mode == RuleTestMode::Script && has_command {
            RuleTestState::Script
        } else {
            RuleTestState::Manual
        }
    }

    fn script_command(&self) -> Option<String> {
        if self.test_state() == RuleTestState::Script {
            self.test
                .as_ref()
                .and_then(|t| t.command.as_deref())
                .and_then(trimmed_non_empty)
        } else {
            None
        }
    }
}

pub trait TopicExt {
    fn matches_file(&self, file: &str) -> bool;
}

impl TopicExt for RuleTopic {
    fn matches_file(&self, file: &str) -> bool {
        self.paths.iter().any(|p| glob::matches(p, file))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{RuleTest, Timestamp};

    fn with_test(rule: &mut Rule, mode: RuleTestMode, command: Option<&str>, hash: String) {
        rule.test = Some(RuleTest {
            mode,
            command: command.map(String::from),
            reason: None,
            rule_hash: hash,
            generated_at: Timestamp::now(),
        });
    }

    #[test]
    fn hash_and_state() {
        let mut rule = Rule::new("texto");
        assert_eq!(rule.test_state(), RuleTestState::None);
        // sha256("texto\n")[0..8]
        assert_eq!(rule.content_hash().len(), 16);
        let h = rule.content_hash();
        with_test(&mut rule, RuleTestMode::Script, Some("ok.sh"), h.clone());
        assert_eq!(rule.test_state(), RuleTestState::Script);
        assert_eq!(rule.script_command().as_deref(), Some("ok.sh"));
        with_test(&mut rule, RuleTestMode::Script, Some("  "), h.clone());
        assert_eq!(rule.test_state(), RuleTestState::Manual);
        with_test(&mut rule, RuleTestMode::Manual, None, h);
        assert_eq!(rule.test_state(), RuleTestState::Manual);
        assert!(rule.script_command().is_none());
        rule.details = Some("novo".into());
        assert_eq!(rule.test_state(), RuleTestState::Stale);
        assert!(RuleTestState::Stale.needs_agent());
        assert!(!RuleTestState::Script.needs_agent());
    }

    #[test]
    fn hash_matches_known_value() {
        // sha256("a\n") = 87428fc522803d31065e7bce3cf03fe475096631e5e07bbd7a0fde60c4cf25c7
        let rule = Rule::new("a");
        assert_eq!(rule.content_hash(), "87428fc522803d31");
        let mut with_details = Rule::new("a");
        with_details.details = Some(String::new());
        assert_eq!(with_details.content_hash(), "87428fc522803d31");
    }
}
