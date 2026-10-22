//! Transporte stdio: JSON-RPC delimitado por newline. stdout é exclusivo do protocolo.

use super::server::{PARSE_ERROR, Server, error_response};
use serde_json::Value;
use std::io::{self, BufRead, Write};

/// Lê linhas até EOF; cada resposta sai inteira numa linha, com flush. EOF = `Ok(())`.
pub fn run<R: BufRead, W: Write>(server: &Server, mut input: R, mut output: W) -> io::Result<()> {
    let mut buf = Vec::new();
    loop {
        buf.clear();
        if input.read_until(b'\n', &mut buf)? == 0 {
            return Ok(());
        }
        let line = String::from_utf8_lossy(&buf);
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let reply = match serde_json::from_str::<Value>(line) {
            Err(_) => Some(error_response(Value::Null, PARSE_ERROR, "Parse error")),
            Ok(Value::Array(batch)) => {
                let replies: Vec<Value> = batch.iter().filter_map(|m| server.handle(m)).collect();
                (!replies.is_empty()).then_some(Value::Array(replies))
            }
            Ok(message) => server.handle(&message),
        };
        if let Some(reply) = reply {
            // `to_string` nunca emite newline cru: o JSON compacto cabe em uma linha.
            let mut text = reply.to_string();
            text.push('\n');
            output.write_all(text.as_bytes())?;
            output.flush()?;
        }
    }
}
