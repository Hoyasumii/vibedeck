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

use std::path::PathBuf;

/// Inicia o servidor em stdin/stdout. Retorna o exit code (0 no EOF).
pub fn serve(root: PathBuf) -> i32 {
    let server = Server::new(
        root.clone(),
        tools::all(),
        Box::new(resources::ProjectResources::new(root)),
        env!("CARGO_PKG_VERSION").to_string(),
    );
    let stdin = std::io::stdin().lock();
    let stdout = std::io::stdout().lock();
    match transport::run(&server, stdin, stdout) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("vibedeck mcp: {e}");
            1
        }
    }
}
