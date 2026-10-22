//! Gate de conclusão de itens de revisão (dados.md §5.5).
//!
//! Item com regras (explícitas, as de tópicos globais ou as de tópicos cujos `paths` casam
//! `target.file`) só vai a `done` se o último check do item passou e respondeu todas as regras do escopo;
//! regras manuais `must` sem resposta seguram o item. A lógica vive em `rules` (`verification_problems`);
//! aqui só a tradução para `ReviewError`.

use super::{ReviewError, ReviewResult, find_item};
use crate::rules::{self, RuleError};
use crate::store::Store;

/// `RulesNotVerified` a menos que o item possa ser marcado `done`.
pub fn ensure_verified(store: &Store, item_ref: &str) -> ReviewResult<()> {
    let (_, group, index) = find_item(store, item_ref)?;
    let problems =
        rules::verification_problems(store, &group.items[index]).map_err(|e| match e {
            RuleError::Core(e) => ReviewError::Core(e),
            other => ReviewError::RulesNotVerified(vec![other.to_string()]),
        })?;
    if problems.is_empty() {
        Ok(())
    } else {
        Err(ReviewError::RulesNotVerified(problems))
    }
}
