//! Where this machine remembers the space it speaks for.
//!
//! A config file, not a keychain: this is a token for one page on a self-hosted space, it
//! is meant to be revocable in one click, and a CLI a person runs in a terminal should not
//! need a session keyring to answer `ricespace ping`. It is written 0600 on Unix, which is
//! the same protection the shell history it would otherwise live in does not have.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::space::Failure;

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Config {
    pub url: Option<String>,
    pub token: Option<String>,
}

impl Config {
    /// `$XDG_CONFIG_HOME/ricespace/config.toml`, or `~/.config/ricespace/config.toml`.
    pub fn path() -> PathBuf {
        let dir = std::env::var("XDG_CONFIG_HOME")
            .ok()
            .filter(|value| !value.trim().is_empty())
            .map(PathBuf::from)
            .or_else(|| std::env::var("HOME").ok().map(|home| PathBuf::from(home).join(".config")))
            .unwrap_or_else(|| PathBuf::from("."));

        dir.join("ricespace").join("config.toml")
    }

    /// The saved configuration, or the default when there is none. A config that cannot be
    /// read is not an error: the next command may be the one that writes it.
    pub fn load() -> Result<Self, Failure> {
        let path = Self::path();

        let Ok(raw) = std::fs::read_to_string(&path) else {
            return Ok(Self::default());
        };

        toml::from_str(&raw).map_err(|error| {
            Failure::Usage(format!("{} is not readable as config: {error}", path.display()))
        })
    }

    pub fn save(&self) -> Result<(), Failure> {
        let path = Self::path();

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|error| {
                Failure::Usage(format!("could not create {}: {error}", parent.display()))
            })?;
        }

        let body = toml::to_string(self).map_err(|error| {
            Failure::Usage(format!("could not render the config: {error}"))
        })?;

        std::fs::write(&path, body).map_err(|error| {
            Failure::Usage(format!("could not write {}: {error}", path.display()))
        })?;

        // The file holds a credential, so it is not left group- or world-readable.
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600));
        }

        Ok(())
    }
}
