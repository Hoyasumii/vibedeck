//! Stack e padrões do projeto: tecnologias de destaque (ícones do Skill Icons), badge no README.md,
//! catálogo embutido de padrões e os tópicos de regras que os impõem.
//!
//! Porte de `Stack.swift` e `Patterns.swift`. Tudo é síncrono; a rede (Skill Icons) fica atrás do trait
//! [`SkillIconsApi`], para os testes trocarem o cliente HTTP por um servidor local.

use std::collections::BTreeMap;

use crate::error::Error;
use crate::model::Project;
use crate::store::Store;

pub mod catalog;
pub mod icons;
pub mod patterns;
pub mod readme;
pub mod service;

pub use catalog::{PatternCatalog, PatternCategory, PatternRuleTemplate, PatternTemplate};
pub use icons::{
    SkillBadge, SkillBadgeUnknown, SkillIcon, SkillIconTheme, SkillIcons, SkillIconsApi,
};
pub use readme::ReadmeStack;
pub use service::{Change, StackService};

pub type Result<T, E = StackError> = std::result::Result<T, E>;

/// Erros da área; as mensagens em PT espelham `VibeDeckError` do Swift.
#[derive(Debug, thiserror::Error)]
pub enum StackError {
    #[error("Skill Icons indisponível: {0}")]
    SkillIconsUnavailable(String),
    #[error("Ícone(s) desconhecido(s) no Skill Icons; nada foi alterado:\n{}", unknown_list(.0))]
    UnknownStackIcons(BTreeMap<String, Vec<String>>),
    #[error("Tecnologia não encontrada na stack: {0}")]
    StackItemNotFound(String),
    #[error(
        "Padrão(ões) desconhecido(s) no catálogo; nada foi alterado:\n{}\nVeja `pattern_catalog` / `vibedeck patterns catalog`, ou crie um padrão personalizado.",
        unknown_list(.0)
    )]
    UnknownPatterns(BTreeMap<String, Vec<String>>),
    #[error("Padrão não encontrado no projeto: {0}")]
    PatternNotFound(String),
    #[error(transparent)]
    Core(#[from] Error),
}

fn unknown_list(unknown: &BTreeMap<String, Vec<String>>) -> String {
    unknown
        .iter()
        .map(|(name, suggestions)| {
            if suggestions.is_empty() {
                format!("- {name}")
            } else {
                format!("- {name} (sugestões: {})", suggestions.join(", "))
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// `updateProject`: carrega `vibedeck.json`, aplica a mudança e grava (a falha da mudança não grava nada).
pub(crate) fn update_project(
    store: &Store,
    change: impl FnOnce(&mut Project) -> Result<()>,
) -> Result<Project> {
    let mut project = store.project()?;
    change(&mut project)?;
    store.save_project(&project)?;
    Ok(project)
}

/// `trimmingCharacters(in: .whitespaces)`: espaços e tabs, sem quebras de linha.
pub(crate) fn trim_ws(s: &str) -> &str {
    s.trim_matches(|c: char| {
        c.is_whitespace()
            && !matches!(
                c,
                '\n' | '\r' | '\u{b}' | '\u{c}' | '\u{85}' | '\u{2028}' | '\u{2029}'
            )
    })
}

/// `trimmed.nonEmpty` (`.whitespacesAndNewlines`).
pub(crate) fn trim_non_empty(s: &str) -> Option<String> {
    let t = s.trim();
    (!t.is_empty()).then(|| t.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mensagens_de_erro() {
        let mut m = BTreeMap::new();
        m.insert("zzz".to_string(), vec![]);
        m.insert(
            "post".to_string(),
            vec!["postgresql".into(), "postman".into()],
        );
        assert_eq!(
            StackError::UnknownStackIcons(m.clone()).to_string(),
            "Ícone(s) desconhecido(s) no Skill Icons; nada foi alterado:\n- post (sugestões: postgresql, postman)\n- zzz"
        );
        assert!(StackError::UnknownPatterns(m).to_string().ends_with(
            "\nVeja `pattern_catalog` / `vibedeck patterns catalog`, ou crie um padrão personalizado."
        ));
        assert_eq!(
            StackError::StackItemNotFound("x".into()).to_string(),
            "Tecnologia não encontrada na stack: x"
        );
        assert_eq!(
            StackError::PatternNotFound("x".into()).to_string(),
            "Padrão não encontrado no projeto: x"
        );
    }

    #[test]
    fn trim_so_de_espacos() {
        assert_eq!(trim_ws("  a\t"), "a");
        assert_eq!(trim_ws("\na "), "\na");
    }
}
