//! The terminal view.
//!
//! The site's design language, in a terminal: a label is small and quiet, the value under
//! it is what you read, and nothing is decorated that is not information. No colour unless
//! the output is a terminal that wants it, and no boxes.
//!
//! Everything here writes to stdout; a failure writes to stderr, so `ricespace page pull -`
//! can be piped somewhere without a stray notice landing in the file.

use crate::space::{Failure, Page, Showcase};

/// Bytes as a person reads them.
fn human_bytes(bytes: u64) -> String {
    const MB: u64 = 1024 * 1024;

    if bytes >= MB {
        format!("{:.1} MB", bytes as f64 / MB as f64)
    } else if bytes >= 1024 {
        format!("{} KB", bytes / 1024)
    } else {
        format!("{bytes} B")
    }
}

/// Whether the output is a terminal, so a pipe gets plain text and a person gets the
/// emphasis. Read once; `NO_COLOR` wins over everything, as it should.
fn styled() -> bool {
    std::env::var("NO_COLOR").is_err() && std::io::IsTerminal::is_terminal(&std::io::stdout())
}

fn dim(value: &str) -> String {
    if styled() {
        format!("\x1b[2m{value}\x1b[0m")
    } else {
        value.to_string()
    }
}

fn bright(value: &str) -> String {
    if styled() {
        format!("\x1b[1m{value}\x1b[0m")
    } else {
        value.to_string()
    }
}

fn accent(value: &str) -> String {
    if styled() {
        format!("\x1b[33m{value}\x1b[0m")
    } else {
        value.to_string()
    }
}

/// A label over a value, the unit the whole view is built from.
pub fn key_value(label: &str, value: &str) {
    println!("{}  {}", dim(&format!("{:<14}", label.to_uppercase())), value);
}

/// A line of information, not an error: stdout, so a pipe keeps it in order.
pub fn notice(message: &str) {
    println!("{}", accent(message));
}

/// A failure: stderr, so it never contaminates a pipe, and with the server's own words
/// rather than a code.
pub fn failure(failure: &Failure) {
    match failure {
        Failure::Usage(message) => eprintln!("ricespace: {message}"),
        Failure::Transport(message) => eprintln!("ricespace: {message}"),
        Failure::Refused { status, code, message, details } => {
            eprintln!("ricespace: {message} ({status} {code})");
            for detail in details {
                eprintln!("  · {detail}");
            }
        }
    }
}

/// The raw response, for `--json`. Pretty, because a person reads it.
pub fn raw(value: &serde_json::Value) -> Result<(), Failure> {
    println!(
        "{}",
        serde_json::to_string_pretty(value)
            .map_err(|error| Failure::Transport(format!("could not render the answer: {error}")))?
    );
    Ok(())
}

/// A list of entries, as a terminal reads it: one line each, with the entry's most
/// identifying field first. Kept deliberately generic — these are pass-through lists, and
/// each kind names its own fields.
pub fn list(kind: &str, value: &serde_json::Value) {
    let items = match value.as_array() {
        Some(items) if !items.is_empty() => items,
        _ => {
            println!("{}", dim(&kind.to_uppercase()));
            println!("  (none)");
            println!();
            return;
        }
    };

    println!("{}", dim(&kind.to_uppercase()));

    for item in items {
        match item {
            serde_json::Value::String(name) => println!("  {name}"),
            serde_json::Value::Object(fields) => {
                // The first field that is a name is the one a person scans for; the rest
                // follow as key: value, so a line still carries everything.
                let named: Option<&str> = [ "title", "username", "name" ]
                    .iter()
                    .find(|key| fields.contains_key(**key))
                    .copied();

                let rest: Vec<String> = fields
                    .iter()
                    .filter(|(key, _)| Some(key.as_str()) != named)
                    .filter(|(key, value)| !matches!(value, serde_json::Value::Null) && !key.is_empty())
                    .map(|(key, value)| format!("{key}: {}", flatten(value)))
                    .collect();

                match named.and_then(|key| fields.get(key)).and_then(serde_json::Value::as_str) {
                    Some(name) => println!("  {}  {}", bright(name), dim(&rest.join("  "))),
                    None => println!("  {}", dim(&rest.join("  "))),
                }
            }
            other => println!("  {}", flatten(other)),
        }
    }

    println!();
}

fn flatten(value: &serde_json::Value) -> String {
    match value {
        serde_json::Value::String(text) => {
            if text.is_empty() { "-".into() } else { text.clone() }
        }
        serde_json::Value::Bool(flag) => if *flag { "yes".into() } else { "no".into() },
        serde_json::Value::Null => "-".into(),
        serde_json::Value::Array(items) => format!("{} item(s)", items.len()),
        other => other.to_string(),
    }
}

/// The page: the rice first, because it is the main event there as much as here, then the
/// facts of the markup.
pub fn page(page: &Page, rice: Option<&Showcase>) {
    println!("{}", bright(&format!("@{}", page.username)));
    println!("{}", dim(&page.url));
    println!();

    if let Some(rice) = rice {
        rice_facts(rice);
    }

    println!("{}", dim("THE PAGE"));
    key_value("revision", &page.version.to_string());
    key_value("changed", &page.updated_at);
    key_value("markup", &format!("{} bytes", page.document.len()));
    key_value("renders to", &format!("{} markup · {} stylesheet", page.html.len(), page.css.len()));
    key_value(
        "limits",
        &format!(
            "{} / {} / {} bytes",
            page.limits.document_bytes, page.limits.html_bytes, page.limits.css_bytes
        ),
    );
}

/// The rice, if there is one. Says so plainly when there is not, because an empty rice is
/// the thing most worth fixing on a page.
pub fn rice(page: &Page, showcase: &Showcase) {
    println!("{}", bright(&format!("@{}", page.username)));
    println!("{}", dim(&page.url));
    println!();
    rice_facts(showcase);
}

fn rice_facts(showcase: &Showcase) {
    let headed = showcase.title.as_deref().unwrap_or("");

    if headed.is_empty() && showcase.filled.is_empty() && showcase.shots.is_empty() {
        println!("{}", dim("THE RICE"));
        println!("{}", accent("  empty — this is the main event on your page"));
        println!("  `ricespace page rice --title …` to start it");
        println!();
        return;
    }

    println!("{}", dim("THE RICE"));
    if !showcase.url.is_empty() {
        key_value("on the page", &showcase.url);
    }
    if !headed.is_empty() {
        key_value("title", headed);
    }
    if let Some(summary) = showcase.summary.as_deref().filter(|value| !value.is_empty()) {
        key_value("summary", summary);
    }

    for fact in &showcase.filled {
        key_value(&fact.label, &fact.value);
    }

    if !showcase.shots.is_empty() {
        let lead = &showcase.shots[0];
        let bytes: u64 = showcase.shots.iter().filter_map(|shot| shot.bytes).sum();
        key_value(
            "shots",
            &format!(
                "{} ({}, first: {})",
                showcase.shots.len(),
                human_bytes(bytes),
                lead.caption.as_deref().unwrap_or("no caption")
            ),
        );
    }

    if !showcase.details.is_empty() {
        key_value("details", &format!("{} bytes", showcase.details.len()));
    }

    println!();
}
