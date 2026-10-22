//! Servidor MCP (JSON-RPC 2.0 sobre stdio, uma mensagem por linha).
//!
//! Pontos de integração:
//! - tools: adicione em `tools::all()` (um `Tool` por ferramenta, handler chama o core);
//! - resources: implemente `ResourceProvider` e passe a `Server::new`.

pub mod args;
pub mod instructions;
pub mod schema;
pub mod server;
pub mod tool;
pub mod tools;
pub mod transport;

pub use server::{NoResources, ResourceProvider, Server};
pub use tool::{Tool, ToolCtx, ToolError};

use std::path::PathBuf;

/// Inicia o servidor em stdin/stdout. Retorna o exit code (0 no EOF).
pub fn serve(root: PathBuf) -> i32 {
    let server = Server::new(
        root,
        tools::all(),
        Box::new(NoResources),
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
