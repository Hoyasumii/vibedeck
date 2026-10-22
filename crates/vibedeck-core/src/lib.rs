//! VibeDeck Core: domain, persistence of `.vibedeck/` and use cases shared by the CLI, MCP and app.

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

pub mod ai;
pub mod app;
pub mod docs;
pub mod error;
pub mod ideas;
pub mod json;
pub mod model;
pub mod onboarding;
pub mod paths;
pub mod project;
pub mod resources;
pub mod reviews;
pub mod rules;
pub mod slug;
pub mod stack;
pub mod store;
pub mod time;
pub mod workflows;

pub use error::{Error, Result};
pub use store::{Record, Store};
