//! Binário `vibedeck`: adaptadores finos (CLI clap + servidor MCP stdio) sobre `vibedeck-core`.

mod cli;
mod mcp;

fn main() {
    std::process::exit(cli::run(std::env::args_os()));
}
