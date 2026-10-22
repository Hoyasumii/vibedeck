//! Datas: ISO-8601 UTC sem fração (padrão) e com milissegundos (só `RuleCheck.createdAt`).

use chrono::{DateTime, SecondsFormat, TimeZone, Utc};

pub type DateTimeUtc = DateTime<Utc>;

pub fn now() -> DateTimeUtc {
    Utc::now()
}

/// `yyyy-MM-ddTHH:mm:ssZ`; a fração é truncada (não arredondada).
pub fn format_iso(dt: DateTimeUtc) -> String {
    let secs = dt.timestamp();
    Utc.timestamp_opt(secs, 0)
        .single()
        .unwrap_or(dt)
        .to_rfc3339_opts(SecondsFormat::Secs, true)
}

/// `yyyy-MM-ddTHH:mm:ss.SSSZ` (3 dígitos, truncados).
pub fn format_iso_millis(dt: DateTimeUtc) -> String {
    let millis = dt.timestamp_millis();
    Utc.timestamp_millis_opt(millis)
        .single()
        .unwrap_or(dt)
        .to_rfc3339_opts(SecondsFormat::Millis, true)
}

/// Aceita RFC 3339 com ou sem fração e com `Z` ou deslocamento; normaliza para UTC.
pub fn parse_iso(s: &str) -> Option<DateTimeUtc> {
    DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|d| d.with_timezone(&Utc))
}

/// Parte de data do nome de um check: `yyyyMMdd-HHmmss` em GMT.
pub fn check_stamp(dt: DateTimeUtc) -> String {
    dt.format("%Y%m%d-%H%M%S").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truncates_fraction() {
        let d = parse_iso("2026-10-09T03:17:31.999Z").unwrap();
        assert_eq!(format_iso(d), "2026-10-09T03:17:31Z");
        assert_eq!(format_iso_millis(d), "2026-10-09T03:17:31.999Z");
        let d = parse_iso("2026-10-09T03:17:31Z").unwrap();
        assert_eq!(format_iso_millis(d), "2026-10-09T03:17:31.000Z");
    }

    #[test]
    fn offsets_become_utc() {
        let d = parse_iso("2026-10-09T00:17:31-03:00").unwrap();
        assert_eq!(format_iso(d), "2026-10-09T03:17:31Z");
        assert!(parse_iso("ontem").is_none());
    }

    #[test]
    fn stamp() {
        let d = parse_iso("2026-10-09T03:17:31.836Z").unwrap();
        assert_eq!(check_stamp(d), "20261009-031731");
    }
}
