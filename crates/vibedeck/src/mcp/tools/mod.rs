//! Registro das tools expostas: cada área tem seu arquivo com `pub fn tools() -> Vec<Tool>`.
//! Nenhuma tool de teste é registrada aqui; testes montam seu próprio `Vec<Tool>`.

use super::tool::Tool;

mod ai;
mod docs;
mod ideas;
mod onboarding;
mod project;
mod resources;
mod reviews;
mod rules;
mod stack;
mod workflows;

pub fn all() -> Vec<Tool> {
    let mut tools = Vec::new();
    tools.extend(project::tools());
    tools.extend(docs::tools());
    tools.extend(reviews::tools());
    tools.extend(rules::tools());
    tools.extend(ideas::tools());
    tools.extend(stack::tools());
    tools.extend(resources::tools());
    tools.extend(workflows::tools());
    tools.extend(ai::tools());
    tools.extend(onboarding::tools());
    tools
}
