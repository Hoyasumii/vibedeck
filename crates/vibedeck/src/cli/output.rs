//! Saída JSON dos comandos.

use serde::Serialize;

/// Imprime `value` em stdout no formato VDJSON (o mesmo dos arquivos do projeto), com `\n` final.
pub fn print_json<T: Serialize>(value: &T) -> Result<(), super::CliError> {
    let bytes =
        vibedeck_core::json::encode(value).map_err(|e| super::CliError::new(e.to_string()))?;
    print!("{}", String::from_utf8_lossy(&bytes));
    Ok(())
}
