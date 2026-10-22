//! Registro das tools expostas. Vazio no esqueleto F02-B.
//!
//! Integração (F02-C em diante): `tools.push(Tool::new("get_project", ...))`.
//! Nenhuma tool de teste deve ser registrada aqui; testes montam seu próprio `Vec<Tool>`.

use super::tool::Tool;

pub fn all() -> Vec<Tool> {
    Vec::new()
}
