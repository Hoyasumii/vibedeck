//! Tipos e ajudas comuns aos modelos: `Id`, datas, `Author` e helpers de (de)serialização tolerante.

use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use uuid::Uuid;

use crate::time::{self, DateTimeUtc};

/// UUID que serializa em MAIÚSCULAS (`UUID.uuidString`) e aceita maiúsculas/minúsculas ao ler.
/// `Default` gera um UUID novo (como o default do decoder Swift).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Id(pub Uuid);

impl Id {
    pub fn new() -> Self {
        Id(Uuid::new_v4())
    }
}

impl Default for Id {
    fn default() -> Self {
        Id::new()
    }
}

impl fmt::Display for Id {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}",
            self.0
                .as_hyphenated()
                .encode_upper(&mut Uuid::encode_buffer())
        )
    }
}

impl FromStr for Id {
    type Err = uuid::Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        // `UUID(uuidString:)` só aceita a forma hifenizada de 36 caracteres.
        if s.len() != 36 {
            return Uuid::parse_str("x").map(Id);
        }
        Uuid::parse_str(s).map(Id)
    }
}

impl Serialize for Id {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

impl<'de> Deserialize<'de> for Id {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        s.parse().map_err(serde::de::Error::custom)
    }
}

/// Data gravada em ISO-8601 UTC **sem fração** (a fração é truncada ao gravar). `Default` = agora.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Timestamp(pub DateTimeUtc);

impl Timestamp {
    pub fn now() -> Self {
        Timestamp(time::now())
    }
}

impl Default for Timestamp {
    fn default() -> Self {
        Timestamp::now()
    }
}

impl From<DateTimeUtc> for Timestamp {
    fn from(d: DateTimeUtc) -> Self {
        Timestamp(d)
    }
}

impl Serialize for Timestamp {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&time::format_iso(self.0))
    }
}

impl<'de> Deserialize<'de> for Timestamp {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        time::parse_iso(&s)
            .map(Timestamp)
            .ok_or_else(|| serde::de::Error::custom(format!("data ISO 8601 inválida: {s}")))
    }
}

/// Data gravada com **milissegundos** (`RuleCheck.createdAt`). `Default` = agora.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TimestampMs(pub DateTimeUtc);

impl TimestampMs {
    pub fn now() -> Self {
        TimestampMs(time::now())
    }
}

impl Default for TimestampMs {
    fn default() -> Self {
        TimestampMs::now()
    }
}

impl Serialize for TimestampMs {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&time::format_iso_millis(self.0))
    }
}

impl<'de> Deserialize<'de> for TimestampMs {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        time::parse_iso(&s)
            .map(TimestampMs)
            .ok_or_else(|| serde::de::Error::custom(format!("data ISO 8601 inválida: {s}")))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Author {
    #[default]
    Human,
    Ai,
}

/// `decodeIfPresent(...) ?? default`: `null` conta como ausente.
pub(crate) fn nd<'de, D, T>(d: D) -> Result<T, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de> + Default,
{
    Ok(Option::<T>::deserialize(d)?.unwrap_or_default())
}

pub(crate) fn vec_empty<T>(v: &[T]) -> bool {
    v.is_empty()
}

/// Opcional omitido quando `None` **ou** vazio (`if let x, !x.isEmpty`).
pub(crate) fn opt_str_empty(v: &Option<String>) -> bool {
    v.as_deref().is_none_or(str::is_empty)
}

/// `trimmed.nonEmpty` (trim de espaços e quebras nas pontas; vazio vira `None`).
pub(crate) fn trim_non_empty(s: Option<String>) -> Option<String> {
    s.map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
}

pub(crate) fn de_trim_non_empty<'de, D: Deserializer<'de>>(
    d: D,
) -> Result<Option<String>, D::Error> {
    Ok(trim_non_empty(Option::<String>::deserialize(d)?))
}
