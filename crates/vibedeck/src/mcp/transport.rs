//! Transporte stdio: JSON-RPC delimitado por newline. stdout é exclusivo do protocolo.

use super::server::{PARSE_ERROR, Server, error_response};
use serde_json::Value;
use std::io::{self, BufRead, Write};
use std::sync::{Arc, Mutex, mpsc};

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

/// Saída compartilhada entre a thread principal, o observador de arquivos e o progresso das tools: cada
/// mensagem sai inteira, numa linha, sob o mesmo lock.
pub type SharedOutput = Arc<Mutex<Box<dyn Write + Send>>>;

pub fn shared_output(writer: impl Write + Send + 'static) -> SharedOutput {
    Arc::new(Mutex::new(Box::new(writer)))
}

/// Escreve `message` como uma linha, com flush, sob o lock da saída.
pub fn write_message(output: &SharedOutput, message: &Value) -> io::Result<()> {
    let mut text = message.to_string();
    text.push('\n');
    let mut out = output.lock().unwrap_or_else(|e| e.into_inner());
    out.write_all(text.as_bytes())?;
    out.flush()
}

enum Incoming {
    Message(Value),
    ParseError,
}

/// Transporte do modo `--app`: uma thread lê o stdin e entrega as mensagens em ordem à thread principal, que
/// as executa uma a uma. `notifications/cancelled` é tratada na própria thread de leitura, para valer
/// enquanto uma tool longa (scripts de regras) ainda roda. EOF = `Ok(())` depois de atender o que já chegou.
pub fn run_app<R: BufRead + Send + 'static>(
    server: &Server,
    mut input: R,
    output: &SharedOutput,
) -> io::Result<()> {
    let calls = server.app().map(|a| Arc::clone(&a.calls));
    let (tx, rx) = mpsc::channel::<Incoming>();
    let reader = std::thread::spawn(move || -> io::Result<()> {
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
            let incoming = match serde_json::from_str::<Value>(line) {
                Err(_) => Incoming::ParseError,
                Ok(message) => {
                    if let (Some(calls), Some(id)) = (&calls, cancelled_request(&message)) {
                        calls.cancel(&id);
                        continue;
                    }
                    Incoming::Message(message)
                }
            };
            if tx.send(incoming).is_err() {
                return Ok(());
            }
        }
    });
    for incoming in rx {
        let reply = match incoming {
            Incoming::ParseError => Some(error_response(Value::Null, PARSE_ERROR, "Parse error")),
            Incoming::Message(Value::Array(batch)) => {
                let replies: Vec<Value> = batch.iter().filter_map(|m| server.handle(m)).collect();
                (!replies.is_empty()).then_some(Value::Array(replies))
            }
            Incoming::Message(message) => server.handle(&message),
        };
        if let Some(reply) = reply {
            write_message(output, &reply)?;
        }
    }
    reader
        .join()
        .unwrap_or_else(|_| Err(io::Error::other("thread de leitura falhou")))
}

/// `requestId` de uma `notifications/cancelled`, na forma usada para identificar a chamada.
fn cancelled_request(message: &Value) -> Option<String> {
    if message.get("method").and_then(Value::as_str)? != "notifications/cancelled" {
        return None;
    }
    message
        .pointer("/params/requestId")
        .filter(|v| v.is_string() || v.is_number())
        .map(Value::to_string)
}
