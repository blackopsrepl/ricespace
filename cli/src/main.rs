//! The RiceSpace command line, run from the terminal you already live in.
//!
//! Three levels, and the split is the design:
//!
//! - `main.rs` is the clap surface — the commands, their flags, and the words a person
//!   types. It decides nothing.
//! - `space.rs` is the client: it knows the API, the error shape the server returns, and
//!   how a write is protected by a revision.
//! - `ui.rs` is the output: the same label-over-value vocabulary the site uses, in a
//!   terminal.
//!
//! The API is the one a coding agent already uses, so nothing here is a second way into
//! the data — it is the same way, typed by hand.

mod config;
mod space;
mod ui;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "ricespace",
    version,
    about = "Manage your RiceSpace page from your own terminal",
    long_about = "ricespace talks to your space over the same HTTP API an agent uses, with \
                  the same token. Everything it can do, you can do from the studio in a \
                  browser — this is for the terminal you already live in."
)]
struct Cli {
    /// Where the space is. Overrides the config file.
    #[arg(long, short = 'H', global = true, env = "RICESPACE_URL")]
    url: Option<String>,

    /// Your agent token. Overrides the config file. Prefer `ricespace login`.
    #[arg(long, short = 't', global = true, env = "RICESPACE_TOKEN", hide_env_values = true)]
    token: Option<String>,

    /// Print raw API responses instead of the rendered view.
    #[arg(long, global = true)]
    json: bool,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Save the space's address and your token for next time.
    Login {
        /// The space's address, e.g. https://rice.example.com.
        #[arg(long, short = 'H')]
        url: Option<String>,

        /// Your agent token (rs_…). Issue one in the studio under "Write it with an agent".
        #[arg(long, short = 't')]
        token: Option<String>,
    },

    /// Show the address and token this machine will use.
    Whoami,

    /// Check that the space is reachable and your token is accepted.
    Ping,

    /// What the API can do to your page, as it is served to agents.
    Contract,

    /// Shell completions for this command.
    Completions {
        /// bash, zsh or fish.
        shell: clap_complete::Shell,
    },

    /// Your page and your rice.
    #[command(subcommand)]
    Page(PageCommand),
}

#[derive(Subcommand)]
enum PageCommand {
    /// Show your page: the rice, the markup, the facts.
    Show,

    /// Read your markup into a file.
    Pull {
        /// Where to write it. `-` writes to standard output.
        #[arg(default_value = "-")]
        file: String,
    },

    /// Write a file in as your markup.
    Push {
        /// The file to send. `-` reads standard input.
        file: String,

        /// Send even if the page moved since you read it.
        #[arg(long)]
        force: bool,
    },

    /// Show the rice, or set its facts.
    Rice {
        #[arg(long)]
        title: Option<String>,
        #[arg(long)]
        summary: Option<String>,
        #[arg(long)]
        hardware: Option<String>,
        #[arg(long = "wm")]
        window_manager: Option<String>,
        #[arg(long)]
        bar: Option<String>,
        #[arg(long)]
        terminal: Option<String>,
        #[arg(long)]
        font: Option<String>,
        #[arg(long)]
        theme: Option<String>,
    },

    /// The videos and streams on your page.
    Links(ListArgs),

    /// The demoscene demos on your page.
    Demos(ListArgs),

    /// The hardware on your page.
    Hardware(ListArgs),

    /// The blurbs — titled blocks of text — on your page.
    Blurbs(ListArgs),

    /// Your friends list.
    Friends {
        /// Usernames to set the list to. None means show it instead.
        usernames: Vec<String>,

        /// Empty the list.
        #[arg(long, conflicts_with = "usernames")]
        clear: bool,
    },
}

/// One of the page's lists: show it, set it from a file, or empty it.
#[derive(clap::Args)]
struct ListArgs {
    /// A JSON file holding the list to set. `-` reads standard input.
    ///
    /// Either a bare array, or an object with the list under its own name — whatever
    /// `ricespace page <list> --json` printed will round-trip.
    #[arg(long)]
    set: Option<String>,

    /// Empty the list.
    #[arg(long, conflicts_with = "set")]
    clear: bool,
}

fn main() {
    let cli = Cli::parse();

    // Configuration, in the order it should be read: a flag beats the environment, which
    // beats the file. A one-off run against another space does not have to rewrite what is
    // saved here.
    let saved = config::Config::load().unwrap_or_default();
    let base = cli.url.clone().or(saved.url).unwrap_or_default();
    let token = cli.token.clone().or(saved.token).unwrap_or_default();

    let code = match run(&cli, &base, &token) {
        Ok(()) => 0,
        Err(failure) => {
            ui::failure(&failure);
            1
        }
    };

    std::process::exit(code);
}

fn run(cli: &Cli, base: &str, token: &str) -> Result<(), space::Failure> {
    match &cli.command {
        Command::Login { url, token: new_token } => {
            let url = url.clone().or_else(|| cli.url.clone()).unwrap_or_default();
            let token = new_token
                .clone()
                .or_else(|| cli.token.clone())
                .unwrap_or_default();

            if url.trim().is_empty() || token.trim().is_empty() {
                return Err(space::Failure::Usage(
                    "login needs both a space and a token:
`ricespace login --url https://rice.example.com --token rs_…`"
                        .into(),
                ));
            }

            // Checked before it is saved: a stored token that does not work is worse than
            // none, because the next command fails somewhere less obvious.
            let who = space::Space::new(&url, &token).whoami()?;

            config::Config { url: Some(url.clone()), token: Some(token) }.save()?;
            ui::notice(&format!("Saved. This machine now speaks for @{}.", who.username));
            ui::key_value("space", &url);
            ui::key_value("config", &config::Config::path().to_string_lossy());
            Ok(())
        }

        Command::Whoami => {
            if base.trim().is_empty() {
                ui::key_value("space", "(not set)");
                ui::key_value("token", if token.trim().is_empty() { "(not set)" } else { "set" });
                ui::notice("Nothing to call yet — run `ricespace login`.");
                return Ok(());
            }

            let who = space::Space::new(base, token).whoami()?;

            ui::key_value("space", base);
            ui::key_value("username", &format!("@{}", who.username));
            ui::key_value("token", &mask(token));
            ui::key_value("config", &config::Config::path().to_string_lossy());
            Ok(())
        }

        Command::Ping => {
            let who = space::Space::new(base, token).whoami()?;

            ui::notice(&format!("{base} is reachable and the token works."));
            ui::key_value("speaking for", &format!("@{}", who.username));
            Ok(())
        }

        Command::Contract => {
            print!("{}", space::Space::new(base, token).contract()?);
            Ok(())
        }

        Command::Completions { shell } => {
            use clap::CommandFactory;

            clap_complete::generate(*shell, &mut Cli::command(), "ricespace", &mut std::io::stdout());
            Ok(())
        }

        Command::Page(PageCommand::Show) => {
            let client = space::Space::new(base, token);
            let page = client.page()?;
            let rice = client.rice().ok();

            if cli.json {
                return ui::raw(&page.raw);
            }

            ui::page(&page, rice.as_ref());
            Ok(())
        }

        Command::Page(PageCommand::Pull { file }) => {
            let page = space::Space::new(base, token).page()?;

            if file == "-" {
                print!("{}", page.document);
                return Ok(());
            }

            std::fs::write(file, &page.document)
                .map_err(|error| space::Failure::Usage(format!("could not write {file}: {error}")))?;

            // The revision is written beside the file, because it is what makes the next
            // push safe, and there is nowhere else to keep it.
            let sidecar = format!("{file}.ricespace");
            let _ = std::fs::write(
                &sidecar,
                serde_json::json!({ "version": page.version, "username": page.username }).to_string(),
            );

            ui::notice(&format!("Read revision {} into {}.", page.version, file));
            ui::key_value("beside it", &sidecar);
            Ok(())
        }

        Command::Page(PageCommand::Push { file, force }) => {
            let document = read_document(file)?;
            let client = space::Space::new(base, token);

            // The revision this edit is built on, from the sidecar `pull` left behind.
            let known = std::fs::read_to_string(format!("{file}.ricespace"))
                .ok()
                .and_then(|raw| serde_json::from_str::<serde_json::Value>(&raw).ok())
                .and_then(|value| value.get("version").and_then(serde_json::Value::as_i64));

            // `--force` means "send it anyway", so it reads the revision that is current
            // now — the sidecar is a stale opinion by definition on that path. Without it,
            // the sidecar is what makes the write safe, and its absence is refused rather
            // than guessed at.
            let version = match resolve_version(*force, known).map_err(space::Failure::Usage)? {
                VersionPlan::Beside(version) => version,
                VersionPlan::Current => client.page()?.version,
            };

            let page = client.push(&document, version)?;

            if cli.json {
                return ui::raw(&page.raw);
            }

            ui::notice(&format!("Saved. The page is now revision {}.", page.version));
            ui::key_value("url", &page.url);
            Ok(())
        }

        Command::Page(PageCommand::Rice { .. }) => rice(cli, base, token),

        Command::Page(PageCommand::Links(args)) => list(cli, base, token, "links", args),
        Command::Page(PageCommand::Demos(args)) => list(cli, base, token, "demos", args),
        Command::Page(PageCommand::Hardware(args)) => list(cli, base, token, "builds", args),
        Command::Page(PageCommand::Blurbs(args)) => list(cli, base, token, "blurbs", args),

        Command::Page(PageCommand::Friends { usernames, clear }) => {
            friends(cli, base, token, usernames, *clear)
        }
    }
}

/// One of the page's lists. `kind` is the name the API uses for it, which is not always
/// the word a person types — the command is `hardware`, the field is `builds`.
fn list(cli: &Cli, base: &str, token: &str, kind: &str, args: &ListArgs) -> Result<(), space::Failure> {
    let client = space::Space::new(base, token);
    // The lists live under `page` in the response, so the pointer is what reads them.
    let pointer = format!("/page/{kind}");

    // Nothing to change: show the list.
    if args.set.is_none() && !args.clear {
        let lists = client.lists()?;
        let value = lists.raw.pointer(&pointer).cloned().unwrap_or(serde_json::Value::Null);

        if cli.json {
            return ui::raw(&value);
        }

        ui::list(kind, &value);
        return Ok(());
    }

    let value = if args.clear {
        serde_json::Value::Array(Vec::new())
    } else {
        let path = args.set.as_deref().unwrap_or("-");
        let body = read_document(path)?;
        let parsed: serde_json::Value = serde_json::from_str(&body).map_err(|error| {
            space::Failure::Usage(format!("{path} is not JSON: {error}"))
        })?;

        // A file may hold the bare array or the object `--json` printed; both are accepted,
        // so `ricespace page links --json > links.json` round-trips.
        parsed
            .get("page")
            .and_then(|page| page.get(kind))
            .or_else(|| parsed.get(kind))
            .cloned()
            .unwrap_or(parsed)
    };

    if !value.is_array() {
        return Err(space::Failure::Usage(format!(
            "{kind} must be a JSON array, got {}",
            match &value {
                serde_json::Value::Object(_) => "an object",
                serde_json::Value::String(_) => "a string",
                serde_json::Value::Number(_) => "a number",
                _ => "something else",
            }
        )));
    }

    let mut changes = serde_json::Map::new();
    changes.insert(kind.to_string(), value);
    let lists = client.set_lists(&changes)?;
    let value = lists.raw.pointer(&pointer).cloned().unwrap_or(serde_json::Value::Null);

    if cli.json {
        return ui::raw(&value);
    }

    ui::notice("Saved.");
    ui::list(kind, &value);
    Ok(())
}

/// The friends list, which is the one list whose entries are a name rather than a record —
/// so it takes them as arguments instead of a JSON file.
fn friends(
    cli: &Cli,
    base: &str,
    token: &str,
    usernames: &[String],
    clear: bool,
) -> Result<(), space::Failure> {
    let client = space::Space::new(base, token);

    if usernames.is_empty() && !clear {
        let lists = client.lists()?;
        let value = lists.raw.pointer("/page/friends").cloned().unwrap_or(serde_json::Value::Null);

        if cli.json {
            return ui::raw(&value);
        }

        ui::list("friends", &value);
        return Ok(());
    }

    let entries: Vec<serde_json::Value> = if clear {
        Vec::new()
    } else {
        usernames
            .iter()
            .map(|name| serde_json::json!({ "username": name }))
            .collect()
    };

    let mut changes = serde_json::Map::new();
    changes.insert("friends".to_string(), serde_json::Value::Array(entries));
    let lists = client.set_lists(&changes)?;
    let value = lists.raw.pointer("/page/friends").cloned().unwrap_or(serde_json::Value::Null);

    if cli.json {
        return ui::raw(&value);
    }

    ui::notice("Saved.");
    ui::list("friends", &value);
    Ok(())
}

fn rice(cli: &Cli, base: &str, token: &str) -> Result<(), space::Failure> {
    let Command::Page(PageCommand::Rice {
        title,
        summary,
        hardware,
        window_manager,
        bar,
        terminal,
        font,
        theme,
    }) = &cli.command
    else {
        unreachable!("rice() is only reached for the rice command");
    };

    let client = space::Space::new(base, token);

    // Only what was named. A flag that was not passed must leave the value alone, which is
    // why this is a map of set fields rather than a struct of Options.
    let mut changes = serde_json::Map::new();
    for (key, value) in [
        ("title", title),
        ("summary", summary),
        ("hardware", hardware),
        ("window_manager", window_manager),
        ("bar", bar),
        ("terminal", terminal),
        ("font", font),
        ("theme", theme),
    ] {
        if let Some(value) = value {
            changes.insert(key.to_string(), serde_json::Value::String(value.clone()));
        }
    }

    // No flags: show the rice rather than quietly doing nothing.
    if changes.is_empty() {
        let showcase = client.rice()?;

        if cli.json {
            return ui::raw(&showcase.raw);
        }

        let page = client.page()?;
        ui::rice(&page, &showcase);
        return Ok(());
    }

    let showcase = client.set_rice(&changes)?;

    if cli.json {
        return ui::raw(&showcase.raw);
    }

    ui::notice("Rice saved.");
    let page = client.page()?;
    ui::rice(&page, &showcase);
    Ok(())
}

fn read_document(file: &str) -> Result<String, space::Failure> {
    if file == "-" {
        let mut buffer = String::new();
        std::io::Read::read_to_string(&mut std::io::stdin(), &mut buffer)
            .map_err(|error| space::Failure::Usage(format!("could not read standard input: {error}")))?;
        return Ok(buffer);
    }

    std::fs::read_to_string(file)
        .map_err(|error| space::Failure::Usage(format!("could not read {file}: {error}")))
}

/// Which revision a push should be built on.
#[derive(Debug, PartialEq)]
enum VersionPlan {
    /// The sidecar `pull` left beside the file.
    Beside(i64),
    /// Whatever the space says right now — the reader is called for it.
    Current,
}

/// Decide what a push is built on, before anything is sent.
///
/// This is the one decision the CLI owns rather than the server, and it is the one that
/// loses data when it is wrong: a write sent on the wrong revision either overwrites
/// somebody else's edit or is refused for no reason. Hence a name and a test.
fn resolve_version(force: bool, beside: Option<i64>) -> Result<VersionPlan, String> {
    match (force, beside) {
        // --force means "send it anyway", so the current revision is the one to build on.
        // The sidecar is by definition a stale opinion on this path.
        (true, _) => Ok(VersionPlan::Current),
        (false, Some(version)) => Ok(VersionPlan::Beside(version)),
        (false, None) => Err(
            "no revision beside the file — pull it first, or pass --force to send it anyway".into(),
        ),
    }
}

/// A token is a credential, so what gets printed is its shape, never its value. This is
/// also the only place one could be printed, and it deliberately cannot be.
fn mask(token: &str) -> String {
    let trimmed = token.trim();

    if trimmed.is_empty() {
        return "(not set)".into();
    }

    if trimmed.chars().count() <= 12 {
        return "rs_…".into();
    }

    let head: String = trimmed.chars().take(7).collect();
    let tail: String = trimmed.chars().skip(trimmed.chars().count() - 4).collect();
    format!("{head}…{tail}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_push_without_force_uses_the_revision_beside_the_file() {
        assert_eq!(resolve_version(false, Some(8)), Ok(VersionPlan::Beside(8)));
    }

    #[test]
    fn force_ignores_a_stale_sidecar_rather_than_being_refused_by_it() {
        // The bug this test exists for: force matched the sidecar first, sent its stale
        // revision, and the server refused — so --force forced nothing.
        assert_eq!(resolve_version(true, Some(3)), Ok(VersionPlan::Current));
        assert_eq!(resolve_version(true, None), Ok(VersionPlan::Current));
    }

    #[test]
    fn a_push_with_no_revision_and_no_force_is_refused_before_it_is_sent() {
        assert!(resolve_version(false, None).is_err());
    }

    #[test]
    fn a_token_is_shown_as_its_shape_and_never_its_value() {
        let token = "rs_0123456789abcdef0123456789abcdef0123456789abcdef";

        let shown = mask(token);

        assert_ne!(shown, token);
        assert!(!shown.contains("0123456789abcdef"));
        assert!(shown.starts_with("rs_0123"));
        assert!(shown.ends_with("cdef"));

        assert_eq!(mask(""), "(not set)");
        assert_eq!(mask("short"), "rs_…");
    }
}
