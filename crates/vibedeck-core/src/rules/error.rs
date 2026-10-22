//! Erros da área de regras (mensagens iguais às de `VibeDeckError` do Swift).

use crate::error::Error;

pub type Result<T, E = RuleError> = std::result::Result<T, E>;

fn bullets(items: &[String]) -> String {
    items
        .iter()
        .map(|i| format!("- {i}"))
        .collect::<Vec<_>>()
        .join("\n")
}

#[derive(Debug, thiserror::Error)]
pub enum RuleError {
    #[error(transparent)]
    Core(#[from] Error),
    /// Falha de outra área chamada por uma operação de regras (ex.: soltar ideias órfãs).
    #[error("{0}")]
    Other(String),
    #[error("Regra não encontrada entre as aplicáveis: {0}")]
    RuleNotFound(String),
    #[error("Prefixo de id de regra ambíguo: {0}")]
    AmbiguousRule(String),
    #[error(
        "Check incompleto: responda todas as regras aplicáveis que não são decididas por script (pass, fail ou na). Faltando:\n{}",
        bullets(.0)
    )]
    IncompleteCheck(Vec<String>),
    #[error("Teste de regra inválido: {0}")]
    InvalidRuleTest(String),
    #[error(
        "O item não pode ser concluído sem passar pelas regras:\n{}\nUse rules_for / submit_rule_check (ou `vibedeck rules check`) com o id do item.",
        bullets(.0)
    )]
    RulesNotVerified(Vec<String>),
    #[error("{0} não é um objeto JSON válido; corrija antes de ligar a statusline.")]
    InvalidClaudeSettings(String),
    #[error("As regras mudaram durante a execução. Execute novamente para salvar a verificação.")]
    ExecutionChanged,
    #[error("A verificação está incompleta e não foi salva.")]
    ExecutionIncomplete,
    #[error("Execução cancelada.")]
    Cancelled,
    #[error("A IA não retornou um resultado válido para cada regra.")]
    InvalidAnswer,
}
