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
use std::path::Path;

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

impl Space {
    /// The address this client speaks to. Public because a folder records it.
    pub fn base(&self) -> &str {
        &self.base
    }
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

    /// Upload one picture. A rice shot, a hardware photo, or the account's own picture.
    ///
    /// Multipart, because that is what an upload is; the body is built here rather than by a
    /// client library so the dependency list stays what it is (ureq, serde, toml, clap).
    /// The account's quota and the file's own ceiling are the server's to enforce — this
    /// side sends the bytes and reports what the server said.
    pub fn upload_image(
        &self,
        path: &Path,
        kind: &str,
        caption: Option<&str>,
        record: Option<&str>,
    ) -> Result<Value, Failure> {
        let bytes = std::fs::read(path)
            .map_err(|error| Failure::Usage(format!("could not read {}: {error}", path.display())))?;

        let filename = path
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .unwrap_or_else(|| "upload".to_string());

        let content_type = match path.extension().and_then(|e| e.to_str()).map(str::to_lowercase).as_deref() {
            Some("png") => "image/png",
            Some("jpg") | Some("jpeg") => "image/jpeg",
            Some("gif") => "image/gif",
            Some("webp") => "image/webp",
            Some("avif") => "image/avif",
            _ => "application/octet-stream",
        };

        let boundary = format!("ricespace-{}", std::process::id());
        let mut body: Vec<u8> = Vec::with_capacity(bytes.len() + 512);

        let mut field = |name: &str, value: &str| {
            body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
            body.extend_from_slice(
                format!("Content-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n").as_bytes(),
            );
        };

        field("kind", kind);
        if let Some(caption) = caption {
            field("caption", caption);
        }
        if let Some(record) = record {
            field("record", record);
        }

        // The file itself is the last part, and carries its own filename and type.
        body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
        body.extend_from_slice(
            format!(
                "Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\nContent-Type: {content_type}\r\n\r\n"
            )
            .as_bytes(),
        );
        body.extend_from_slice(&bytes);
        body.extend_from_slice(b"\r\n");
        body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());

        let text = self.send_bytes(
            "POST",
            "/api/v1/images",
            body,
            &format!("multipart/form-data; boundary={boundary}"),
        )?;

        serde_json::from_str(&text)
            .map_err(|error| Failure::Transport(format!("the space answered with something unreadable: {error}")))
    }

    /// Reorder the rice's shots, whole. One request rather than one per picture, because a
    /// folder holds one order.
    pub fn set_shot_order(&self, ids: &[i64]) -> Result<Value, Failure> {
        let body = serde_json::json!({ "kind": "shot", "ids": ids });
        let text = self.send_bytes(
            "PATCH",
            "/api/v1/images/order",
            body.to_string().into_bytes(),
            "application/json",
        )?;

        serde_json::from_str(&text)
            .map_err(|error| Failure::Transport(format!("the space answered with something unreadable: {error}")))
    }

    /// A picture's bytes, from a URL the space served. Used by `clone` to bring the pictures
    /// down into the folder, so the folder holds the page rather than a list of links to it.
    pub fn fetch_bytes(&self, url: &str) -> Result<Vec<u8>, Failure> {
        let agent = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .build()
            .new_agent();

        let response = agent.get(url).call().map_err(|error| Failure::Transport(format!("could not fetch {url}: {error}")))?;

        let status = response.status().as_u16();
        if status >= 400 {
            return Err(Failure::Transport(format!("{url} answered {status}")));
        }

        let mut bytes = Vec::new();
        std::io::Read::read_to_end(&mut response.into_body().into_reader(), &mut bytes)
            .map_err(|error| Failure::Transport(format!("could not read {url}: {error}")))?;

        Ok(bytes)
    }

    fn send(&self, method: &str, path: &str, body: Option<Value>) -> Result<Value, Failure> {
        let text = self.send_text_with(method, path, body)?;

        serde_json::from_str(&text)
            .map_err(|error| Failure::Transport(format!("the space answered with something unreadable: {error}")))
    }

    /// A request whose body is bytes rather than JSON — an upload, or a JSON body built by
    /// hand for the multipart path. Kept separate from `send_text_with` because a multipart
    /// body must not be re-encoded: the boundary and the file's own bytes have to arrive
    /// exactly as written.
    fn send_bytes(
        &self,
        method: &str,
        path: &str,
        body: Vec<u8>,
        content_type: &str,
    ) -> Result<String, Failure> {
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
        let agent = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .build()
            .new_agent();

        let authorization = format!("Bearer {}", self.token);
        let response = match method {
            "POST" => agent
                .post(&url)
                .header("Authorization", &authorization)
                .header("Content-Type", content_type)
                .send(body),
            "PATCH" => agent
                .patch(&url)
                .header("Authorization", &authorization)
                .header("Content-Type", content_type)
                .send(body),
            "DELETE" => agent.delete(&url).header("Authorization", &authorization).call(),
            other => return Err(Failure::Usage(format!("unsupported method {other}"))),
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