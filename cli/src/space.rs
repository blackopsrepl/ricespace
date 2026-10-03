//! The client: everything this program knows about the API.
//!
//! It is deliberately thin. The server owns the rules — what a page may contain, what a
//! refused request means — and this side's job is to send the right thing, keep a write
//! safe with the revision it was built on, and turn a failure into one sentence a person
//! can act on.
//!
//! It is also the only part that touches a credential, and it never prints one.

use serde::Deserialize;
use serde_json::Value;

/// A failure the user has to hear about, in the words they need.
#[derive(Debug)]
pub enum Failure {
    /// The command itself was wrong — a missing flag, an unreadable file.
    Usage(String),
    /// The request never reached the space, or it did not answer.
    Transport(String),
    /// The space answered and said no. The message is the server's own.
    Refused { status: u16, code: String, message: String, details: Vec<String> },
}

pub struct Space {
    base: String,
    token: String,
}

/// The account a token speaks for.
#[derive(Debug, Deserialize)]
pub struct Who {
    pub username: String,
}

/// The page, as the API presents it.
#[derive(Debug, Deserialize)]
pub struct Page {
    pub username: String,
    pub url: String,
    pub document: String,
    pub html: String,
    pub css: String,
    pub version: i64,
    pub updated_at: String,
    pub limits: Limits,
    /// The server's own response, kept so `--json` prints exactly what was sent.
    #[serde(skip)]
    pub raw: Value,
}

#[derive(Debug, Deserialize)]
pub struct Limits {
    pub document_bytes: usize,
    pub html_bytes: usize,
    pub css_bytes: usize,
}

/// The rice, as the API presents it.
#[derive(Debug, Deserialize)]
pub struct Showcase {
    pub url: String,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub details: String,
    #[serde(default)]
    pub filled: Vec<Fact>,
    pub shots: Vec<Shot>,
    #[serde(skip)]
    pub raw: Value,
}

#[derive(Debug, Deserialize)]
pub struct Fact {
    pub label: String,
    pub value: String,
}

/// Everything on a page that is not its markup. Kept as the raw value: these lists are
/// pass-through, and re-modelling them in Rust would mean a change on the server needs a
/// change here for no gain.
#[derive(Debug)]
pub struct Lists {
    pub raw: Value,
}

#[derive(Debug, Deserialize)]
pub struct Shot {
    #[serde(default)]
    pub caption: Option<String>,
    #[serde(default)]
    pub bytes: Option<u64>,
}

impl Space {
    pub fn new(base: &str, token: &str) -> Self {
        Self {
            base: base.trim().trim_end_matches('/').to_string(),
            token: token.trim().to_string(),
        }
    }

    /// The account this token belongs to. This is also how a token is checked, because it
    /// is the smallest request that needs one.
    pub fn whoami(&self) -> Result<Who, Failure> {
        let raw = self.send("GET", "/api/v1/profile", None)?;
        // The profile payload nests the account; both shapes are accepted so this keeps
        // working if a future response is flattened.
        let username = raw
            .get("profile")
            .and_then(|profile| profile.get("username"))
            .or_else(|| raw.get("username"))
            .and_then(Value::as_str)
            .ok_or_else(|| Failure::Transport("the space answered without a username".into()))?;

        Ok(Who { username: username.to_string() })
    }

    pub fn page(&self) -> Result<Page, Failure> {
        let raw = self.send("GET", "/api/v1/profile", None)?;
        let mut page: Page = serde_json::from_value(
            raw.get("profile").cloned().unwrap_or_else(|| raw.clone()),
        )
        .map_err(|error| Failure::Transport(format!("could not read the page: {error}")))?;

        page.raw = raw;
        Ok(page)
    }

    pub fn rice(&self) -> Result<Showcase, Failure> {
        let raw = self.send("GET", "/api/v1/showcase", None)?;
        let mut showcase: Showcase = serde_json::from_value(
            raw.get("showcase").cloned().unwrap_or_else(|| raw.clone()),
        )
        .map_err(|error| Failure::Transport(format!("could not read the rice: {error}")))?;

        showcase.raw = raw;
        Ok(showcase)
    }

    /// Write the whole document, on top of the revision it was built from. The server
    /// refuses a stale write, which is why the version travels with it.
    pub fn push(&self, document: &str, version: i64) -> Result<Page, Failure> {
        let body = serde_json::json!({ "profile": { "document": document, "version": version } });
        let raw = self.send("PATCH", "/api/v1/profile", Some(body))?;

        let mut page: Page = serde_json::from_value(
            raw.get("profile").cloned().unwrap_or_else(|| raw.clone()),
        )
        .map_err(|error| Failure::Transport(format!("could not read the saved page: {error}")))?;

        page.raw = raw;
        Ok(page)
    }

    /// Set the named rice facts, leaving every other one alone.
    pub fn set_rice(&self, changes: &serde_json::Map<String, Value>) -> Result<Showcase, Failure> {
        let body = serde_json::json!({ "showcase": Value::Object(changes.clone()) });
        let raw = self.send("PATCH", "/api/v1/showcase", Some(body))?;

        let mut showcase: Showcase = serde_json::from_value(
            raw.get("showcase").cloned().unwrap_or_else(|| raw.clone()),
        )
        .map_err(|error| Failure::Transport(format!("could not read the saved rice: {error}")))?;

        showcase.raw = raw;
        Ok(showcase)
    }

    /// Everything on the page that is not its markup.
    pub fn lists(&self) -> Result<Lists, Failure> {
        let raw = self.send("GET", "/api/v1/page", None)?;

        Ok(Lists { raw })
    }

    /// Replace the named lists, leaving the rest of the page alone.
    pub fn set_lists(&self, changes: &serde_json::Map<String, Value>) -> Result<Lists, Failure> {
        let body = serde_json::json!({ "page": Value::Object(changes.clone()) });
        let raw = self.send("PUT", "/api/v1/page", Some(body))?;

        Ok(Lists { raw })
    }

    /// The agent contract, as the server serves it to agents.
    pub fn contract(&self) -> Result<String, Failure> {
        self.send_text("GET", "/agents.md")
    }

    fn send(&self, method: &str, path: &str, body: Option<Value>) -> Result<Value, Failure> {
        let text = self.send_text_with(method, path, body)?;

        serde_json::from_str(&text)
            .map_err(|error| Failure::Transport(format!("the space answered with something unreadable: {error}")))
    }

    fn send_text(&self, method: &str, path: &str) -> Result<String, Failure> {
        self.send_text_with(method, path, None)
    }

    fn send_text_with(&self, method: &str, path: &str, body: Option<Value>) -> Result<String, Failure> {
        if self.base.is_empty() {
            return Err(Failure::Usage(
                "no space configured — run `ricespace login`, or pass --url".into(),
            ));
        }

        if self.token.is_empty() {
            return Err(Failure::Usage(
                "no token configured — run `ricespace login`, or pass --token".into(),
            ));
        }

        let url = format!("{}{}", self.base, path);
        // The status is data here, not an exception: a refusal carries a message written
        // for a person, and it is the message the CLI has to show.
        let agent = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .build()
            .new_agent();

        let authorize = |_url: &str| format!("Bearer {}", self.token);

        // A GET and a PATCH are different request types, so they cannot share one binding:
        // each carries the same header, and the handling below is shared.
        let response = match (method, body) {
            ("GET", _) => agent.get(&url).header("Authorization", &authorize(&url)).call(),
            ("PATCH", payload) => agent
                .patch(&url)
                .header("Authorization", &authorize(&url))
                .send_json(payload.unwrap_or(Value::Null)),
            ("PUT", payload) => agent
                .put(&url)
                .header("Authorization", &authorize(&url))
                .send_json(payload.unwrap_or(Value::Null)),
            ("POST", payload) => agent
                .post(&url)
                .header("Authorization", &authorize(&url))
                .send_json(payload.unwrap_or(Value::Null)),
            (other, _) => return Err(Failure::Usage(format!("unsupported method {other}"))),
        };

        match response {
            Ok(response) => {
                let status = response.status().as_u16();
                let text = response.into_body().read_to_string().map_err(|error| {
                    Failure::Transport(format!("could not read the answer: {error}"))
                })?;

                if status >= 400 {
                    return Err(self.refusal(status, &text));
                }

                Ok(text)
            }

            Err(error) => Err(Failure::Transport(format!("could not reach {}: {error}", self.base))),
        }
    }

    /// A refusal is turned into a sentence. The server's own error body is authoritative
    /// when it sent one — it knows why it said no, and it writes for a person — and the
    /// status is only a fallback for a response that came from somewhere else.
    fn refusal(&self, status: u16, body: &str) -> Failure {
        let parsed = serde_json::from_str::<Value>(body).ok();
        let error = parsed.as_ref().and_then(|value| value.get("error"));

        let code = error
            .and_then(|value| value.get("code"))
            .and_then(Value::as_str)
            .unwrap_or("error")
            .to_string();

        let fallback = match status {
            401 => "the token was refused — is it still issued?",
            404 => "the space does not have that endpoint",
            409 => "the page moved since you read it; re-read it and reapply your edit",
            _ => "the space refused the request",
        };

        let message = error
            .and_then(|value| value.get("message"))
            .and_then(Value::as_str)
            .unwrap_or(fallback)
            .to_string();

        let details = error
            .and_then(|value| value.get("details"))
            .and_then(Value::as_array)
            .map(|items| items.iter().filter_map(Value::as_str).map(str::to_string).collect())
            .unwrap_or_default();

        Failure::Refused { status, code, message, details }
    }
}