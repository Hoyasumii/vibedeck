//! VibeDeck Core: domain, persistence of `.vibedeck/` and use cases shared by the CLI, MCP and app.

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

pub mod error;
pub mod json;
pub mod model;
pub mod paths;
pub mod slug;
pub mod store;
pub mod time;

pub use error::{Error, Result};
pub use store::{Record, Store};
