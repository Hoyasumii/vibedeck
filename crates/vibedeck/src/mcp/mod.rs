//! Servidor MCP (JSON-RPC 2.0 sobre stdio, uma mensagem por linha).
//!
//! Pontos de integração:
//! - tools: adicione em `tools::all()` (um `Tool` por ferramenta, handler chama o core);
//! - resources: implemente `ResourceProvider` e passe a `Server::new`.

// API de registro ainda sem consumidores no binário (tools entram nas próximas fatias).

pub mod args;
pub mod instructions;
pub mod resources;
pub mod schema;
pub mod server;
pub mod tool;
pub mod tools;
pub mod transport;

pub use server::Server;

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::json;
use tool::Notifier;

/// Inicia o servidor em stdin/stdout. Retorna o exit code (0 no EOF). Com `app`, registra as tools extras do
/// aplicativo e avisa o cliente das mudanças em `.vibedeck/` e `vibedeck.json`.
pub fn serve(root: PathBuf, app: bool) -> i32 {
    let version = env!("CARGO_PKG_VERSION").to_string();
    let provider = Box::new(resources::ProjectResources::new(root.clone()));
    let result = if app {
        serve_app(root, provider, version)
    } else {
        let server = Server::new(root, tools::all(), provider, version);
        let stdin = std::io::stdin().lock();
        let stdout = std::io::stdout().lock();
        transport::run(&server, stdin, stdout)
    };
    match result {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("vibedeck mcp: {e}");
            1
        }
    }
}

/// Intervalo do observador de mudanças (só mtimes e tamanhos, sem ler arquivos).
const WATCH_INTERVAL: Duration = Duration::from_secs(1);

fn serve_app(
    root: PathBuf,
    provider: Box<dyn server::ResourceProvider>,
    version: String,
) -> std::io::Result<()> {
    let output = transport::shared_output(std::io::stdout());
    let notifier = Notifier::new({
        let output = Arc::clone(&output);
        move |message| {
            let _ = transport::write_message(&output, &message);
        }
    });
    let runtime = server::AppRuntime::new(notifier.clone());
    let subscriptions = Arc::clone(&runtime.subscriptions);
    let server = Server::new(root.clone(), tools::all_app(), provider, version).with_app(runtime);
    // A revisão inicial é lida antes de atender qualquer mensagem: mudanças depois dela são notificadas.
    let initial = vibedeck_core::app::revision(&root);
    std::thread::spawn(move || watch(&root, initial, &notifier, &subscriptions));
    transport::run_app(&server, std::io::BufReader::new(std::io::stdin()), &output)
}

/// Compara a revisão a cada `WATCH_INTERVAL` e emite `list_changed` (e `updated` das URIs assinadas).
fn watch(
    root: &std::path::Path,
    mut last: String,
    notifier: &Notifier,
    subscriptions: &Mutex<HashSet<String>>,
) {
    loop {
        std::thread::sleep(WATCH_INTERVAL);
        let now = vibedeck_core::app::revision(root);
        if now == last {
            continue;
        }
        last = now;
        notifier.send(json!({"jsonrpc": "2.0", "method": "notifications/resources/list_changed"}));
        let uris: Vec<String> = subscriptions
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .cloned()
            .collect();
        for uri in uris {
            notifier.send(json!({
                "jsonrpc": "2.0",
                "method": "notifications/resources/updated",
                "params": {"uri": uri},
            }));
        }
    }
}
