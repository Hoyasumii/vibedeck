//! Comandos CLI — Revisões: grupos e itens de revisão.
//!
//! A área declara seus comandos de primeiro nível em `Command` e os executa em `run`.

use super::{CliError, Context};
use clap::Subcommand;

#[derive(Subcommand, Debug)]
pub enum Command {}

pub fn run(command: Command, _ctx: &Context) -> Result<i32, CliError> {
    match command {}
}
