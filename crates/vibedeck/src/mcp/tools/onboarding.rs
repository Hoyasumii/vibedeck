//! Tools MCP — Início guiado (MUD-001): detecção e cadastro de recursos existentes.
//!
//! Tools novas, aditivas ao contrato. `onboarding_apply` só cadastra o que a lista `items` nomear.

use vibedeck_core::model::Author;
use vibedeck_core::onboarding::{self, ItemRef};

use crate::mcp::schema::{prop, schema};
use crate::mcp::tool::{Tool, ToolError, json_text};

fn err(e: onboarding::OnboardingError) -> ToolError {
    ToolError::new(e.to_string())
}

pub fn tools() -> Vec<Tool> {
    vec![
        Tool::new(
            "onboarding_status",
            "Início guiado: estado, etapa sugerida, stack, padrões e recursos detectados (.claude, .codex).",
            schema(&[], &[], &[], &[]),
            |ctx, _| json_text(&onboarding::status_at(&ctx.root)),
        )
        .read_only(),
        Tool::new(
            "onboarding_apply",
            "skip adia, complete conclui, import cadastra só os items escolhidos.",
            schema(
                &[
                    prop("action", "string", ""),
                    prop(
                        "items",
                        "array",
                        "Só para import: <tipo>:<nome> (agent|command|skill). Já cadastrados são mantidos.",
                    ),
                ],
                &["action"],
                &[("action", &["skip", "complete", "import"])],
                &[],
            ),
            |ctx, args| {
                let store = ctx.store()?;
                match args.req("action")? {
                    "skip" => json_text(&onboarding::skip(&store).map_err(err)?),
                    "complete" => json_text(&onboarding::complete(&store).map_err(err)?),
                    "import" => {
                        let items = args.list("items").unwrap_or_default();
                        if items.is_empty() {
                            return Err(ToolError::invalid_params("Parâmetro obrigatório: items"));
                        }
                        let refs = items
                            .iter()
                            .map(|i| ItemRef::parse(i))
                            .collect::<Result<Vec<_>, _>>()
                            .map_err(err)?;
                        let out = onboarding::import_selected(&store, &refs, Author::Ai)
                            .map_err(err)?;
                        json_text(&out)
                    }
                    other => Err(ToolError::invalid_params(format!(
                        "action inválida: {other}. Use skip, complete ou import."
                    ))),
                }
            },
        ),
    ]
}
