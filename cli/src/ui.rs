//! The terminal view.
//!
//! The site's design language, in a terminal: hot magenta, electric cyan and the amber
//! the pages use, the wordmark up top the way the Makefile wears it, and a rice drawn
//! when there is one to draw.
//!
//! Colour is for a person. Anything that is not a terminal — a pipe, a redirect, a
//! `NO_COLOR` prompt — gets the same view in plain text, so `ricespace page pull -` can be
//! piped somewhere without escape codes landing in the file. Every failure writes to
//! stderr so it never contaminates that pipe.

use crate::space::{Failure, Page, Rating, Showcase};

/// The wordmark, as the Makefile draws it. Kept in the binary because the CLI is what
/// somebody runs on a machine that has none of this checked out.
const WORDMARK: [&str; 5] = [
    r" ___ _        ___                   ",
    r"| _ (_)__ ___/ __|_ __  __ _ __ ___ ",
    r"|   / / _/ -_)__ \ '_ \/ _` / _/ -_)",
    r"|_|_\_\__\___|___/ .__/\__,_\__\___|",
    r"                 |_|                ",
];

/// A rice, for when the page has one — or when it needs one.
const RICE: [&str; 4] = [
    r" ___ ___ ___ ___ ",
    r"| _ \_ _/ __| __|",
    r"|   /| | (__| _| ",
    r"|_|_\___\___|___|",
];

// The site's palette, as the Makefile has it.
const MAGENTA: &str = "\x1b[95m";
const CYAN: &str = "\x1b[96m";
const AMBER: &str = "\x1b[38;2;255;194;75m";
const GREEN: &str = "\x1b[92m";
const YELLOW: &str = "\x1b[93m";
const BOLD: &str = "\x1b[1m";
const DIM: &str = "\x1b[2m";
const RESET: &str = "\x1b[0m";

/// Whether the output is a terminal, so a pipe gets plain text and a person gets the
/// colour. Read once; `NO_COLOR` wins over everything, as it should.
fn styled() -> bool {
    std::env::var("NO_COLOR").is_err() && std::io::IsTerminal::is_terminal(&std::io::stdout())
}

fn paint(value: &str, colour: &str) -> String {
    if styled() {
        format!("{colour}{value}{RESET}")
    } else {
        value.to_string()
    }
}

fn dim(value: &str) -> String {
    paint(value, DIM)
}

fn bright(value: &str) -> String {
    paint(value, BOLD)
}

fn accent(value: &str) -> String {
    paint(value, AMBER)
}

fn cyan(value: &str) -> String {
    paint(value, CYAN)
}

fn magenta(value: &str) -> String {
    paint(value, MAGENTA)
}

fn green(value: &str) -> String {
    paint(value, GREEN)
}

/// The wordmark and the version line, worn the way the Makefile wears it.
pub fn wordmark() {
    println!();
    for line in WORDMARK {
        println!("{}", magenta(line));
    }
    println!(
        "  {} {} {}",
        dim(&format!("v{}", env!("CARGO_PKG_VERSION"))),
        accent("pages you build"),
        dim("· the space in your terminal")
    );
    println!();
}

/// A section heading: the name in cyan, so the eye finds it while scrolling.
pub fn section(title: &str) {
    println!("{}", cyan(&title.to_uppercase()));
}

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

/// A label over a value, the unit the whole view is built from. The label is quiet, the
/// value is what you read.
pub fn key_value(label: &str, value: &str) {
    println!("  {}  {}", dim(&format!("{:<14}", label.to_uppercase())), value);
}

/// A line of information, not an error: stdout, so a pipe keeps it in order.
pub fn notice(message: &str) {
    println!("{} {}", cyan("=>"), accent(message));
}

/// A page's rating. The score is the number a visitor sees; the counts underneath are
/// what it is made of, which the site itself does not show — this is the owner's own
/// terminal, and an owner is allowed to see their own working.
pub fn rating(rating: &Rating) {
    section("rating");
    key_value("page", &format!("@{}", rating.username));
    key_value("score", &rating.score.to_string());
    key_value("likes", &rating.likes.to_string());
    key_value("dislikes", &rating.dislikes.to_string());
    key_value("raters", &rating.raters.to_string());

    if rating.score == 0 {
        println!("  {}", dim("nobody has rated this page yet"));
    }
}

/// The answer to rating somebody: what it is now, and what you said.
pub fn rated(username: &str, opinion: &str, rating: &Rating) {
    let now = rating.score;

    match (opinion, rating.changed) {
        ("none", Some(false)) => ok(&format!("you had no rating on @{username} — nothing to take back")),
        ("none", _) => ok(&format!("took your rating off @{username} — it is on {now}")),
        (_, Some(false)) => ok(&format!("already your rating on @{username} — it is on {now}")),
        ("dislike", _) => ok(&format!("disliked @{username} — it is on {now}")),
        _ => ok(&format!("liked @{username} — it is on {now}")),
    }
}

/// Yes/no as a person reads it, in the colour the answer deserves.
pub fn ok(message: &str) {
    println!("{} {}", green("ok"), message);
}

/// A failure: stderr, so it never contaminates a pipe, and with the server's own words
/// rather than a code.
pub fn failure(failure: &Failure) {
    let mark = paint("fail", "\x1b[91m");
    match failure {
        Failure::Usage(message) => eprintln!("{mark} ricespace: {message}"),
        Failure::Transport(message) => eprintln!("{mark} ricespace: {message}"),
        Failure::Refused { status, code, message, details } => {
            eprintln!("{mark} ricespace: {message} {}({status} {code}){}", dim(""), RESET);
            for detail in details {
                eprintln!("  {} {detail}", dim("·"));
            }
        }
    }
}

/// The raw response, for `--json`. Pretty, because a person reads it, and untouched by
/// colour because a machine reads it too.
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
            section(kind);
            println!("  {}", dim("(none)"));
            println!();
            return;
        }
    };

    section(kind);

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
                    Some(name) => println!("  {}  {}", accent(name), dim(&rest.join("  "))),
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

    section("the page");
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
    println!();
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
    let empty = headed.is_empty() && showcase.filled.is_empty() && showcase.shots.is_empty();

    section("the rice");

    if empty {
        // An empty rice is the main event missing, so the art is the whole point here.
        for line in RICE {
            println!("  {}", magenta(line));
        }
        println!();
        println!("  {}", paint("empty — this is the main event on your page", YELLOW));
        println!("  {}", dim("`ricespace page rice --title …` to start it"));
        println!();
        return;
    }

    for line in RICE {
        println!("  {}", magenta(line));
    }
    println!();

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
