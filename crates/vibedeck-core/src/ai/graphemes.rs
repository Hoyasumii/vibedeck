//! Segmentação aproximada em clusters de grafemas estendidos (o `Character` do Swift).
//!
//! Sem dependência de `unicode-segmentation`: cobre CRLF, marcas combinantes, ZWJ (emoji compostos),
//! seletores de variação, modificadores de tom de pele, tags e pares de indicadores regionais (bandeiras).

use unicode_normalization::char::is_combining_mark;

fn is_extend(c: char) -> bool {
    let u = c as u32;
    is_combining_mark(c)
        || (0xFE00..=0xFE0F).contains(&u)
        || (0xE0100..=0xE01EF).contains(&u)
        || (0x1F3FB..=0x1F3FF).contains(&u)
        || (0xE0020..=0xE007F).contains(&u)
        || u == 0x200C
}

fn is_regional(c: char) -> bool {
    (0x1F1E6..=0x1F1FF).contains(&(c as u32))
}

/// Pedaços (`&str`) de cada cluster, em ordem.
pub fn clusters(text: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut iter = text.char_indices().peekable();
    while let Some((start, c)) = iter.next() {
        let mut end = start + c.len_utf8();
        if c == '\r' {
            if let Some(&(i, '\n')) = iter.peek() {
                iter.next();
                end = i + 1;
            }
            out.push(&text[start..end]);
            continue;
        }
        if c == '\n' || (c as u32) < 0x20 {
            out.push(&text[start..end]);
            continue;
        }
        let mut regional = is_regional(c);
        while let Some(&(i, n)) = iter.peek() {
            if is_extend(n) {
                iter.next();
                end = i + n.len_utf8();
            } else if n == '\u{200D}' {
                iter.next();
                end = i + n.len_utf8();
                // ZWJ une o próximo caractere ao cluster
                if let Some(&(j, m)) = iter.peek() {
                    iter.next();
                    end = j + m.len_utf8();
                }
            } else if regional && is_regional(n) {
                regional = false;
                iter.next();
                end = i + n.len_utf8();
            } else {
                break;
            }
        }
        out.push(&text[start..end]);
    }
    out
}

pub fn count(text: &str) -> usize {
    clusters(text).len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clusters_de_emoji_e_combinantes() {
        assert_eq!(count("a"), 1);
        assert_eq!(count("👩🏽‍💻"), 1);
        assert_eq!(count("e\u{301}x"), 2);
        assert_eq!(count("🇧🇷🇺🇸"), 2);
        assert_eq!(count("a\r\nb"), 3);
        assert_eq!(count(""), 0);
    }
}
