//! Saída JSON dos comandos.

use serde::Serialize;

/// Imprime `value` como JSON em stdout, com `\n` final.
///
/// INTEGRAÇÃO: trocar por `vibedeck_core::json` (emissor VDJSON: chaves ordenadas, `" : "`, sem
/// escapar `/`, `[\n\n]` para vazio) quando existir. Até lá: pretty do serde_json.
pub fn print_json<T: Serialize>(value: &T) -> Result<(), super::CliError> {
    let text =
        serde_json::to_string_pretty(value).map_err(|e| super::CliError::new(e.to_string()))?;
    println!("{text}");
    Ok(())
}
