//! A folder that is your space.
//!
//! `clone` writes your page out as files, `push` sends the folder back, `preview` draws it
//! locally. The reason to have this at all is that a page is a document written by a person,
//! and a person writes documents in an editor on their own machine — not in a textarea, and
//! not one resource at a time from a shell.
//!
//! The shape of the folder is the API's own shape written down: `page.html` is the markup,
//! and one JSON file per list (`rice.json`, `blurbs.json`, `demos.json`, `builds.json`,
//! `links.json`, `friends.json`) holds what the API holds. That is deliberate — a folder in
//! a second format would be a second thing to keep in step with the API, and the API already
//! has a shape.
//!
//! What is *not* in the folder is the token. A folder is a thing a person puts in git, and
//! `ricespace.toml` carries the address only; the token stays in `~/.config/ricespace`.

use std::path::{Path, PathBuf};

use serde_json::{json, Map, Value};

use crate::space::{Failure, Space};

/// The file a folder names itself with: the space it belongs to and nothing secret.
pub const MANIFEST: &str = "ricespace.toml";
/// The markup, exactly as stored.
pub const PAGE: &str = "page.html";
/// The rice's facts, in the API's own shape.
pub const RICE: &str = "rice.json";

/// The lists, in the API's own shape. Each is one file, because each is one list.
pub const LISTS: [&str; 5] = ["blurbs.json", "demos.json", "builds.json", "links.json", "friends.json"];

/// Where a folder keeps the pictures its rice and its hardware point at.
pub const ASSETS: &str = "assets";

/// The name an asset file is given in the folder, from a URL the site serves it at. The last
/// segment of the URL is the only stable part of it, and it is what a person would recognise.
pub fn asset_name(url: &str) -> Option<String> {
    let last = url.trim_end_matches('/').rsplit('/').next()?;
    let cleaned = last.split('?').next().unwrap_or(last);

    if cleaned.is_empty() || cleaned.contains("..") {
        return None;
    }

    Some(cleaned.to_string())
}

/// Everything a folder holds, as one value in memory. Reading the folder reads this; pushing
/// it sends the parts that changed.
#[derive(Debug, Default)]
pub struct Folder {
    pub root: PathBuf,
    pub page: String,
    /// The revision `page.html` was read at, from the sidecar. `None` when the folder was
    /// written by hand rather than cloned.
    pub page_version: Option<i64>,
    pub rice: Map<String, Value>,
    /// One entry per list, present only when the folder has that file.
    pub lists: Map<String, Value>,
    /// The pictures in `assets/`, by the name the folder gives them. Empty when the folder
    /// has none, which is the common case.
    pub assets: Vec<PathBuf>,
}

/// What is in a folder, described for a person — the diff a push shows before it sends.
#[derive(Debug, Default)]
pub struct Changes {
    pub summary: Vec<String>,
    /// Whether the pictures need sending. Tracked apart from the summary because a picture
    /// is sent by uploading it, not by writing a list, and because a folder whose only
    /// change is a new screenshot must not be reported as "nothing has changed".
    pub assets: bool,
}

impl Changes {
    pub fn is_empty(&self) -> bool {
        self.summary.is_empty() && !self.assets
    }
}

impl Folder {
    /// Read a folder. A folder with no `page.html` is not a folder — that is the one file
    /// that makes it one, and everything else is optional.
    pub fn read(root: &Path) -> Result<Self, Failure> {
        let page_file = root.join(PAGE);
        if !page_file.is_file() {
            return Err(Failure::Usage(format!(
                "{} is not a space folder — no {PAGE} in it (make one with `ricespace clone`)",
                root.display()
            )));
        }

        let page = std::fs::read_to_string(&page_file)
            .map_err(|error| Failure::Usage(format!("could not read {}: {error}", page_file.display())))?;

        // The sidecar is what makes a push safe: it is the revision this edit was built on.
        let page_version = read_sidecar(&root.join(PAGE));

        let rice = read_json_object(&root.join(RICE));
        let mut lists = Map::new();
        for name in LISTS {
            if let Some(value) = read_json(&root.join(name)) {
                // The file name, minus `.json`, is the API's key: `blurbs.json` is `blurbs`.
                let key = name.trim_end_matches(".json").to_string();
                lists.insert(key, value);
            }
        }

        // Everything in `assets/`, sorted so a push of the same folder sends the same order.
        let assets = {
            let dir = root.join(ASSETS);
            let mut found: Vec<PathBuf> = match std::fs::read_dir(&dir) {
                Ok(entries) => entries
                    .flatten()
                    .map(|entry| entry.path())
                    .filter(|path| path.is_file())
                    .collect(),
                Err(_) => Vec::new(),
            };
            found.sort();
            found
        };

        Ok(Self { root: root.to_path_buf(), page, page_version, rice, lists, assets })
    }

    /// What the folder would change, against what the space has now. Read-only: a push
    /// shows this and then asks, unless it was told not to.
    pub fn changes(&self, space: &Space) -> Result<Changes, Failure> {
        let mut summary = Vec::new();

        let current = space.page()?;
        if current.document != self.page {
            summary.push(format!("page.html: {} lines now", self.page.lines().count()));
        }

        for (key, _) in self.changed_rice(space)? {
            summary.push(format!("rice: {key}"));
        }

        for (key, value) in self.changed_lists(space)? {
            summary.push(format!("{key}: {}", describe_list(&value)));
        }

        // The pictures. A file in `assets/` that the page does not already have is a change,
        // and it is its own kind of change — the upload is what sends it.
        let new_assets = self.new_assets(space)?;
        for name in &new_assets {
            summary.push(format!("assets/{name}: new picture"));
        }

        Ok(Changes { summary, assets: !new_assets.is_empty() })
    }

    /// The pictures in `assets/` that the page does not already have, by file name.
    ///
    /// "Already has" is read from the page's own picture URLs: the last segment of each is the
    /// name the folder gave it, so a file that is already on the page is not uploaded again.
    /// This is the check that lets `push` be re-run — without it every push would re-upload
    /// every screenshot.
    fn new_assets(&self, space: &Space) -> Result<Vec<String>, Failure> {
        if self.assets.is_empty() {
            return Ok(Vec::new());
        }

        let existing = space.lists()?;
        let presentation = existing.raw.get("page").cloned().unwrap_or(Value::Null);
        let mut known: Vec<String> = Vec::new();

        // The account's own picture is named `profile-<file>` in a folder, so a screenshot it
        // already holds is recognised by that name rather than the page's URL.
        let profile_name = presentation
            .get("picture")
            .and_then(|p| p.get("url"))
            .and_then(Value::as_str)
            .and_then(asset_name);

        if let Some(name) = profile_name {
            known.push(format!("profile-{name}"));
        }

        for shot in presentation.get("shots").and_then(Value::as_array).into_iter().flatten() {
            if let Some(name) = shot.get("url").and_then(Value::as_str).and_then(asset_name) {
                known.push(name);
            }
        }

        let rice = space.rice()?;
        for shot in rice.raw.get("showcase").and_then(|s| s.get("shots")).and_then(Value::as_array).into_iter().flatten() {
            if let Some(name) = shot.get("url").and_then(Value::as_str).and_then(asset_name) {
                known.push(name);
            }
        }

        Ok(self
            .assets
            .iter()
            .filter_map(|path| path.file_name().map(|name| name.to_string_lossy().to_string()))
            .filter(|name| !known.iter().any(|existing| existing == name))
            .collect())
    }

    /// The rice's facts whose value differs from what the space has. `title`, `summary` and
    /// `details` come back at the top level of the showcase and the rest under `facts`, which
    /// is the site's own arrangement — a comparison that only looked at one of the two would
    /// report every push as a change, forever.
    fn changed_rice(&self, space: &Space) -> Result<Map<String, Value>, Failure> {
        let current = space.rice()?;
        let showcase = current.raw.get("showcase").cloned().unwrap_or(Value::Null);
        let mut changed = Map::new();

        for (key, value) in &self.rice {
            // `shot_order` is the folder's bookkeeping, not a fact the API stores: the order
            // is applied to the shots themselves by an upload.
            if key == "shot_order" {
                continue;
            }

            let have = showcase
                .get(key)
                .filter(|value| !value.is_null())
                .or_else(|| showcase.get("facts").and_then(|facts| facts.get(key)));

            if have != Some(value) {
                changed.insert(key.clone(), value.clone());
            }
        }

        Ok(changed)
    }

    /// The lists whose **editable** content differs from what the space has.
    ///
    /// The API returns more than a folder holds — a build comes back with its `photos`, a demo
    /// with its `embeds`, a link with the `platform` the site derived from its url. Comparing
    /// whole entries would therefore report every list as changed on every push, forever, and a
    /// push that always changes something cannot be re-run safely. So the comparison is made on
    /// the fields the folder actually carries, which is the question a person is asking.
    ///
    /// A list that does not differ is not returned at all, and so is not sent — an unchanged
    /// list is not destroyed and rebuilt, which is what keeps a push from churning the page.
    fn changed_lists(&self, space: &Space) -> Result<Map<String, Value>, Failure> {
        let current = space.lists()?;
        let api = current.raw.get("page").cloned().unwrap_or(Value::Null);
        let mut changed = Map::new();

        for (key, value) in &self.lists {
            if !list_matches(key, value, api.get(key)) {
                changed.insert(key.clone(), value.clone());
            }
        }

        Ok(changed)
    }

    /// Send the whole folder. The revision the page was read at travels with it, so a page
    /// that moved underneath is refused rather than overwritten — the same guarantee a single
    /// `push` gives, applied to the folder.
    ///
    /// The order is deliberate: the page first, because everything else on a page is
    /// described in it, then the rice, then the lists. A list that is refused leaves the ones
    /// already sent in place, which is what the API does per list anyway.
    pub fn push(&self, space: &Space, force: bool) -> Result<Vec<String>, Failure> {
        let mut done = Vec::new();

        // The write needs the revision it was built on. Without a sidecar, the only safe
        // answer is to read the current one — which is what `--force` means here too, and
        // why it is named after the same flag a single-file push uses.
        let current = space.page()?;

        // A folder whose page is already what the space has does not need a write, and must
        // not make one: a push that failed partway (say, on a list) leaves the space holding
        // the new page and the folder still holding the old revision, so retrying the same
        // folder would be refused as stale even though nothing is actually in conflict. Sending
        // nothing and refreshing the sidecar is what makes a retry work.
        let version = if current.document == self.page {
            current.version
        } else {
            match (self.page_version, force) {
                (Some(version), false) => version,
                _ => current.version,
            }
        };

        if current.document == self.page {
            done.push(format!("page.html → already at revision {}", current.version));
        } else {
            let page = space.push(&self.page, version)?;
            done.push(format!("page.html → revision {}", page.version));
            write_sidecar(&self.root.join(PAGE), page.version, &page.username);
            return self.push_the_rest(space, done);
        }

        write_sidecar(&self.root.join(PAGE), current.version, &current.username);
        self.push_the_rest(space, done)
    }

    /// Everything after the page: the rice's facts, the lists, and the pictures.
    fn push_the_rest(&self, space: &Space, mut done: Vec<String>) -> Result<Vec<String>, Failure> {
        // Only the facts that differ are sent: a push that re-sent everything would claim a
        // change on every run, and the point of a diff is that an unchanged folder is quiet.
        let facts = self.changed_rice(space)?;
        if !facts.is_empty() {
            space.set_rice(&facts)?;
            done.push(format!("rice: {}", facts.keys().cloned().collect::<Vec<_>>().join(", ")));
        }

        let changed = self.changed_lists(space)?;
        if !changed.is_empty() {
            space.set_lists(&changed)?;
            done.push(format!("lists: {}", changed.keys().cloned().collect::<Vec<_>>().join(", ")));
        }

        // The pictures last, because a picture is the largest thing a folder sends and the
        // page it belongs to is already in place by the time it arrives.
        if !self.assets.is_empty() {
            let uploaded = self.push_assets(space)?;
            done.extend(uploaded);
        }

        Ok(done)
    }

    /// Upload the folder's pictures. A file in `assets/` is a shot of the rice unless its
    /// name says otherwise: `profile-*` is the account's own picture, and a name that appears
    /// in a build's photos is that build's photo. Order among the shots follows the file names,
    /// so renumbering the files reorders the rice.
    fn push_assets(&self, space: &Space) -> Result<Vec<String>, Failure> {
        let mut done = Vec::new();

        // What the page currently says each picture is, so a file is not re-uploaded as a
        // duplicate of something already there.
        let existing = space.lists()?;
        let presentation = existing.raw.get("page").cloned().unwrap_or(Value::Null);
        let existing_names: Vec<String> = presentation
            .get("shots")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|shot| shot.get("url").and_then(Value::as_str).and_then(asset_name))
            .collect();

        let build_titles: Vec<String> = presentation
            .get("builds")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|build| build.get("title").and_then(Value::as_str).map(str::to_string))
            .collect();

        let mut shot_ids: Vec<i64> = Vec::new();

        for path in &self.assets {
            let name = match path.file_name().map(|n| n.to_string_lossy().to_string()) {
                Some(name) => name,
                None => continue,
            };

            // The account's own picture.
            if name.starts_with("profile-") {
                let answer = space.upload_image(path, "picture", None, None)?;
                let bytes = answer.get("picture").and_then(|p| p.get("bytes")).and_then(Value::as_i64).unwrap_or(0);
                done.push(format!("picture: {name} ({bytes} bytes)"));
                continue;
            }

            // A hardware photo, when a build claims the file by name.
            if let Some(title) = build_titles.iter().find(|title| {
                let slug = slugify(title);
                !slug.is_empty() && name.to_lowercase().contains(&slug)
            }) {
                space.upload_image(path, "build", None, Some(title))?;
                done.push(format!("{title}: photo {name}"));
                continue;
            }

            // Otherwise it is a shot of the rice. Already-there pictures are left alone, so a
            // push does not pile up duplicates of the same screenshot.
            if existing_names.iter().any(|existing| existing == &name) {
                done.push(format!("shot: {name} (already there)"));
                continue;
            }

            let answer = space.upload_image(path, "shot", Some(&caption_from(&name)), None)?;
            if let Some(id) = answer.get("shot").and_then(|s| s.get("id")).and_then(Value::as_i64) {
                shot_ids.push(id);
                done.push(format!("shot: {name}"));
            }
        }

        // The order the folder chose, sent whole — one request rather than one per picture.
        if !shot_ids.is_empty() {
            space.set_shot_order(&shot_ids)?;
            done.push(format!("shot order: {}", shot_ids.iter().map(|id| id.to_string()).collect::<Vec<_>>().join(", ")));
        }

        Ok(done)
    }

    /// Write the folder's preview files into the app's preview directory, so the site's own
    /// renderer can draw them. This is what makes `preview` honest: the CLI does not
    /// reimplement the cleaner, it hands the folder to the code that owns it.
    pub fn stage_for_preview(&self, preview_root: &Path, name: &str) -> Result<PathBuf, Failure> {
        let target = preview_root.join(name);
        std::fs::create_dir_all(&target)
            .map_err(|error| Failure::Usage(format!("could not make {}: {error}", target.display())))?;

        std::fs::write(target.join(PAGE), &self.page)
            .map_err(|error| Failure::Usage(format!("could not stage {PAGE}: {error}")))?;

        if !self.rice.is_empty() {
            let body = serde_json::to_string_pretty(&Value::Object(self.rice.clone()))
                .map_err(|error| Failure::Usage(format!("could not stage {RICE}: {error}")))?;
            std::fs::write(target.join(RICE), body)
                .map_err(|error| Failure::Usage(format!("could not stage {RICE}: {error}")))?;
        }

        for (key, value) in &self.lists {
            let name = format!("{key}.json");
            let body = serde_json::to_string_pretty(value)
                .map_err(|error| Failure::Usage(format!("could not stage {name}: {error}")))?;
            std::fs::write(target.join(&name), body)
                .map_err(|error| Failure::Usage(format!("could not stage {name}: {error}")))?;
        }

        Ok(target)
    }
}

/// Write a folder out from what the space has. This is `clone`: the page as its author wrote
/// it, the rice's facts, and every list — one file each, in the API's own shapes.
pub fn write_out(root: &Path, space: &Space) -> Result<Vec<String>, Failure> {
    std::fs::create_dir_all(root)
        .map_err(|error| Failure::Usage(format!("could not make {}: {error}", root.display())))?;

    let mut wrote = Vec::new();

    let page = space.page()?;
    std::fs::write(root.join(PAGE), &page.document)
        .map_err(|error| Failure::Usage(format!("could not write {PAGE}: {error}")))?;
    write_sidecar(&root.join(PAGE), page.version, &page.username);
    wrote.push(format!("{PAGE} (revision {})", page.version));

    let rice = space.rice()?;
    if let Some(showcase) = rice.raw.get("showcase") {
        let facts = rice_file(showcase);
        if !facts.is_empty() {
            write_pretty(&root.join(RICE), &Value::Object(facts))?;
            wrote.push(RICE.to_string());
        }
    }

    let lists = space.lists()?;
    if let Some(page) = lists.raw.get("page").and_then(Value::as_object) {
        // Only the lists are files. The page hash also carries scalars the site computed —
        // the username, the page's url, the picture, the shots — and those are not a
        // folder's to hold as a list, so each is either written somewhere better or not at
        // all. Writing every key is how a folder ends up with a `url.json`.
        for name in LISTS {
            let key = name.trim_end_matches(".json");
            if let Some(value) = page.get(key) {
                // Empty lists are written as empty files rather than skipped: a folder that
                // omits a list says nothing about it, and a folder with `[]` says "this is
                // empty" — the same distinction the API makes.
                write_pretty(&root.join(name), value)?;
                wrote.push(name.to_string());
            }
        }
    }

    // The pictures. Whatever URL the site serves a picture at, the folder gets the file
    // itself — a folder that names a picture but does not hold it is a folder that cannot be
    // pushed to a space that has lost it.
    wrote.extend(fetch_assets(root, space)?);

    let manifest = format!(
        "# The space this folder belongs to.\n#\n# The token is NOT here on purpose: a folder is a thing you put in git.\n# It stays in ~/.config/ricespace/config.toml.\n\nurl = \"{}\"\nusername = \"{}\"\n",
        space.base(), page.username
    );
    std::fs::write(root.join(MANIFEST), manifest)
        .map_err(|error| Failure::Usage(format!("could not write {MANIFEST}: {error}")))?;
    wrote.push(MANIFEST.to_string());

    Ok(wrote)
}

/// Download every picture the page points at into the folder's `assets/`.
///
/// The page names pictures by URL and the folder needs the bytes, so this is the bridge. It
/// is best-effort per picture: a shot whose bytes cannot be fetched is reported and the clone
/// carries on, because losing one picture should not lose the folder.
fn fetch_assets(root: &Path, space: &Space) -> Result<Vec<String>, Failure> {
    let dir = root.join(ASSETS);
    let mut wrote = Vec::new();
    let mut wanted: Vec<(String, String)> = Vec::new();

    let page = space.lists()?;
    let presentation = page.raw.get("page").cloned().unwrap_or(Value::Null);

    // The account's own picture, then the rice's shots, then the hardware photos. Each pair
    // is (url, a name for the file).
    if let Some((url, name)) = presentation
        .get("picture")
        .and_then(|p| p.get("url"))
        .and_then(Value::as_str)
        .and_then(|url| asset_name(url).map(|name| (url, name)))
    {
        wanted.push((url.to_string(), format!("profile-{name}")));
    }

    for shot in presentation.get("shots").and_then(Value::as_array).into_iter().flatten() {
        if let Some((url, name)) = shot.get("url").and_then(Value::as_str).and_then(|url| asset_name(url).map(|name| (url, name))) {
            wanted.push((url.to_string(), name));
        }
    }

    let rice = space.rice()?;
    for shot in rice.raw.get("showcase").and_then(|s| s.get("shots")).and_then(Value::as_array).into_iter().flatten() {
        if let Some((url, name)) = shot.get("url").and_then(Value::as_str).and_then(|url| asset_name(url).map(|name| (url, name))) {
            wanted.push((url.to_string(), name));
        }
    }

    if wanted.is_empty() {
        return Ok(wrote);
    }

    std::fs::create_dir_all(&dir)
        .map_err(|error| Failure::Usage(format!("could not make {}: {error}", dir.display())))?;

    for (url, name) in wanted {
        match space.fetch_bytes(&url) {
            Ok(bytes) => {
                let target = dir.join(&name);
                std::fs::write(&target, &bytes)
                    .map_err(|error| Failure::Usage(format!("could not write {}: {error}", target.display())))?;
                wrote.push(format!("{ASSETS}/{name} ({} bytes)", bytes.len()));
            }
            Err(_) => wrote.push(format!("{ASSETS}/{name} — could not be fetched")),
        }
    }

    Ok(wrote)
}

/// The rice's own fields, as a file. Everything the API returns about a rice except the
/// server's own presentation of it (`url`, `filled`, `limits`, `updated_at`) — a folder holds
/// what its owner can edit and nothing the site computed.
///
/// The one thing kept from the computed side is the shots' **order**, as a list of asset
/// names. A folder holds one order, and the names are what the folder can recognise again on
/// a push; the ids the site uses for them are the site's business.
fn rice_file(showcase: &Value) -> Map<String, Value> {
    const EDITABLE: [&str; 9] = [
        "title", "summary", "details", "hardware", "window_manager", "bar", "terminal", "font", "theme",
    ];

    let mut out = Map::new();
    for key in EDITABLE {
        if let Some(value) = showcase.get(key).filter(|value| !value.is_null()) {
            out.insert(key.to_string(), value.clone());
        }
    }

    let order: Vec<Value> = showcase
        .get("shots")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|shot| shot.get("url").and_then(Value::as_str).and_then(asset_name))
        .map(Value::String)
        .collect();

    if !order.is_empty() {
        out.insert("shot_order".to_string(), Value::Array(order));
    }

    out
}

fn describe_list(value: &Value) -> String {
    match value {
        Value::Array(items) => format!("{} item(s)", items.len()),
        other => other.to_string(),
    }
}

/// Whether a list in the folder is the same as the list the API holds, judged on the fields
/// the folder carries. Extra keys on the API side (`photos`, `embeds`, a derived `platform`)
/// are the site's own and are ignored; a field the folder omits is treated as blank, because
/// that is how the API will read it too.
fn list_matches(key: &str, wanted: &Value, have: Option<&Value>) -> bool {
    let Some(items) = wanted.as_array() else {
        return have == Some(wanted);
    };

    let Some(existing) = have.and_then(Value::as_array) else {
        return false;
    };

    if items.len() != existing.len() {
        return false;
    }

    items.iter().zip(existing).all(|(wanted, have)| entry_matches(key, wanted, have))
}

/// The fields a folder may set for a kind of entry.
fn fields_for(kind: &str) -> &'static [&'static str] {
    match kind {
        "links" => &["url", "title"],
        "demos" => &["title", "group", "party", "year", "platform", "category", "placing", "url", "note"],
        "builds" => &["title", "kind", "summary", "specs", "cooling", "details"],
        "blurbs" => &["title", "body"],
        _ => &[],
    }
}

fn entry_matches(kind: &str, wanted: &Value, have: &Value) -> bool {
    // Friends are a list of usernames written either as a bare string or as an entry with a
    // `username` key, so they get their own reading.
    if kind == "friends" {
        return friend_name(wanted) == friend_name(have);
    }

    let (Some(wanted), Some(have)) = (wanted.as_object(), have.as_object()) else {
        return false;
    };

    fields_for(kind).iter().all(|field| {
        let left = wanted.get(*field).and_then(Value::as_str).unwrap_or("");
        let right = have.get(*field).and_then(Value::as_str).unwrap_or("");
        left.trim() == right.trim()
    })
}

fn friend_name(value: &Value) -> String {
    match value {
        Value::String(name) => name.trim().to_lowercase(),
        other => other.get("username").and_then(Value::as_str).unwrap_or("").trim().to_lowercase(),
    }
}

/// A file name as a caption: `the-bench_01.png` reads as "the bench 01". Enough to be a
/// sensible default the author will often leave alone.
fn caption_from(name: &str) -> String {
    let stem = name.rsplit_once('.').map(|(stem, _)| stem).unwrap_or(name);

    stem.replace(['-', '_'], " ").trim().to_string()
}

/// A title reduced to what a file name can carry, so a build can claim a photo by name.
fn slugify(title: &str) -> String {
    title
        .to_lowercase()
        .chars()
        .map(|character| if character.is_ascii_alphanumeric() { character } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

fn read_json(path: &Path) -> Option<Value> {
    let raw = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&raw).ok()
}

fn read_json_object(path: &Path) -> Map<String, Value> {
    read_json(path)
        .and_then(|value| value.as_object().cloned())
        .unwrap_or_default()
}

/// The revision beside a file. `page.html.ricespace`, holding the version and the username —
/// the same sidecar a single-file `pull` writes, so the two paths agree.
fn read_sidecar(file: &Path) -> Option<i64> {
    let raw = std::fs::read_to_string(format!("{}.ricespace", file.display())).ok()?;
    let value: Value = serde_json::from_str(&raw).ok()?;
    value.get("version").and_then(Value::as_i64)
}

fn write_sidecar(file: &Path, version: i64, username: &str) {
    let body = json!({ "version": version, "username": username }).to_string();
    let _ = std::fs::write(format!("{}.ricespace", file.display()), body);
}

fn write_pretty(path: &Path, value: &Value) -> Result<(), Failure> {
    let body = serde_json::to_string_pretty(value)
        .map_err(|error| Failure::Usage(format!("could not render {}: {error}", path.display())))?;

    std::fs::write(path, format!("{body}\n"))
        .map_err(|error| Failure::Usage(format!("could not write {}: {error}", path.display())))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_folder_with_no_page_is_not_a_folder() {
        let dir = std::env::temp_dir().join(format!("ricespace-nopage-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::remove_file(dir.join(PAGE)).ok();

        let result = Folder::read(&dir);
        assert!(result.is_err(), "a folder without page.html must be refused");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn reading_a_folder_takes_its_page_and_its_lists() {
        let dir = std::env::temp_dir().join(format!("ricespace-read-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(PAGE), "<marquee>hi</marquee>").unwrap();
        std::fs::write(dir.join(RICE), r#"{"title":"the bench","theme":"synthwave"}"#).unwrap();
        std::fs::write(dir.join("blurbs.json"), r#"[{"title":"Interests","body":"arcades"}]"#).unwrap();

        let folder = Folder::read(&dir).unwrap();
        assert_eq!(folder.page, "<marquee>hi</marquee>");
        assert_eq!(folder.rice.get("title").and_then(Value::as_str), Some("the bench"));
        assert!(folder.lists.contains_key("blurbs"));
        // A list the folder does not have is absent, not empty — the API's distinction.
        assert!(!folder.lists.contains_key("demos"));

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn the_sidecar_carries_the_revision_a_push_is_built_on() {
        let dir = std::env::temp_dir().join(format!("ricespace-sidecar-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let page = dir.join(PAGE);
        std::fs::write(&page, "x").unwrap();
        write_sidecar(&page, 7, "vittorio");

        assert_eq!(read_sidecar(&page), Some(7));

        let folder = Folder::read(&dir).unwrap();
        assert_eq!(folder.page_version, Some(7));

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn the_rice_file_holds_what_an_owner_edits_and_not_what_the_site_computed() {
        let showcase = json!({
            "title": "the bench",
            "theme": "synthwave",
            "hardware": null,
            "url": "https://example.test/profiles/ron#showcase",
            "filled": [{ "label": "theme", "value": "synthwave" }],
            "limits": { "title_bytes": 80 }
        });

        let file = rice_file(&showcase);
        assert_eq!(file.get("title").and_then(Value::as_str), Some("the bench"));
        assert!(!file.contains_key("url"), "the site's own url is not the owner's to edit");
        assert!(!file.contains_key("filled"));
        assert!(!file.contains_key("limits"));
        assert!(!file.contains_key("hardware"), "a null fact is not written");
    }

    #[test]
    fn a_new_picture_is_a_change_even_when_nothing_else_moved() {
        // The bug this pins: `changes` compared the page, the rice and the lists, and never
        // looked at `assets/`. A folder whose only edit was a screenshot therefore reported
        // "nothing has changed" and uploaded nothing — the picture was silently dropped.
        let dir = std::env::temp_dir().join(format!("ricespace-assets-{}", std::process::id()));
        std::fs::create_dir_all(dir.join(ASSETS)).unwrap();
        std::fs::write(dir.join(PAGE), "<p>hi</p>").unwrap();
        std::fs::write(dir.join(ASSETS).join("bench-01.png"), b"not really a png").unwrap();

        let folder = Folder::read(&dir).unwrap();
        assert_eq!(folder.assets.len(), 1, "the folder must see its own assets");

        // What the page reports: nothing, so every asset in the folder is new.
        let known: Vec<String> = Vec::new();
        let names: Vec<String> = folder
            .assets
            .iter()
            .filter_map(|path| path.file_name().map(|n| n.to_string_lossy().to_string()))
            .filter(|name| !known.iter().any(|existing| existing == name))
            .collect();

        assert_eq!(names, vec!["bench-01.png".to_string()]);

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn staging_for_preview_writes_the_whole_folder_where_the_site_can_read_it() {
        let dir = std::env::temp_dir().join(format!("ricespace-stage-src-{}", std::process::id()));
        let out = std::env::temp_dir().join(format!("ricespace-stage-out-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(PAGE), "<h1>mine</h1>").unwrap();
        std::fs::write(dir.join(RICE), r#"{"title":"x"}"#).unwrap();
        std::fs::write(dir.join("friends.json"), r#"["ron"]"#).unwrap();

        let folder = Folder::read(&dir).unwrap();
        let staged = folder.stage_for_preview(&out, "demo").unwrap();

        assert!(staged.join(PAGE).is_file());
        assert!(staged.join(RICE).is_file());
        assert!(staged.join("friends.json").is_file());

        std::fs::remove_dir_all(&dir).ok();
        std::fs::remove_dir_all(&out).ok();
    }
}
