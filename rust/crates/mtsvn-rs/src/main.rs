use std::error::Error;
use std::path::PathBuf;

use status_engine::StatusEngine;
use svn_backend::{CommandLineSvnBackend, StatusDepth, StatusOptions, SvnStatusEntry};

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_else(|| "help".to_string());

    match command.as_str() {
        "status" | "refresh" => {
            let root = args
                .next()
                .map(PathBuf::from)
                .unwrap_or(std::env::current_dir()?);

            let backend = CommandLineSvnBackend::system();
            let mut engine = StatusEngine::new(backend);
            engine.schedule_full_refresh(&root);
            let snapshot = engine.refresh_root(&root)?;

            println!("root: {}", snapshot.root.display());
            println!("dirty_entries: {}", snapshot.entries.len());
            for (path, entry) in snapshot.entries {
                println!(
                    "{} {} props_modified={}",
                    path.display(),
                    entry.status.as_bridge_value(),
                    entry.props_modified
                );
            }
            Ok(())
        }
        "bridge-status" => {
            let request = StatusRequest::parse(args.collect())?;
            let backend = CommandLineSvnBackend::system();
            let entries =
                svn_backend::StatusProvider::status(&backend, &request.root, &request.options)?;

            println!("{}", serialize_status_response(&request.root, &entries));
            Ok(())
        }
        "bridge-snapshot" => {
            let request = StatusRequest::parse(args.collect())?;
            let backend = CommandLineSvnBackend::system();
            let mut engine = StatusEngine::new(backend);
            engine.schedule_full_refresh(&request.root);
            let snapshot = engine.refresh_root_with_options(&request.root, &request.options)?;

            println!("{}", serialize_snapshot_response(&snapshot));
            Ok(())
        }
        "bridge-add" => {
            let request = PathsRequest::parse(args.collect(), false)?;
            let backend = CommandLineSvnBackend::system();
            backend.add(&request.paths, request.depth, request.force)?;

            println!("{}", serialize_add_response(&request.paths));
            Ok(())
        }
        "bridge-commit" => {
            let request = CommitRequest::parse(args.collect())?;
            let backend = CommandLineSvnBackend::system();
            let revision = backend.commit(&request.paths, &request.message)?;

            println!("{}", serialize_commit_response(revision));
            Ok(())
        }
        _ => {
            eprintln!("Usage:");
            eprintln!("  mtsvn-rs status <working-copy-root>");
            eprintln!("  mtsvn-rs refresh <working-copy-root>");
            eprintln!("  mtsvn-rs bridge-status <working-copy-root> [--include-ignored] [--exclude-unversioned] [--depth VALUE]");
            eprintln!("  mtsvn-rs bridge-snapshot <working-copy-root> [--include-ignored] [--exclude-unversioned] [--depth VALUE]");
            eprintln!("  mtsvn-rs bridge-add --path <path> [--path <path> ...] [--depth VALUE] [--force]");
            eprintln!("  mtsvn-rs bridge-commit --path <path> [--path <path> ...] --message <message>");
            Ok(())
        }
    }
}

struct StatusRequest {
    root: PathBuf,
    options: StatusOptions,
}

impl StatusRequest {
    fn parse(arguments: Vec<String>) -> Result<Self, Box<dyn Error>> {
        let mut root: Option<PathBuf> = None;
        let mut options = StatusOptions::default();
        let mut iter = arguments.into_iter();

        while let Some(argument) = iter.next() {
            match argument.as_str() {
                "--include-ignored" => {
                    options.include_ignored = true;
                }
                "--exclude-ignored" => {
                    options.include_ignored = false;
                }
                "--include-unversioned" => {
                    options.include_unversioned = true;
                }
                "--exclude-unversioned" => {
                    options.include_unversioned = false;
                }
                "--depth" => {
                    let value = iter.next().ok_or("missing value after --depth")?;
                    options.depth = StatusDepth::from_cli_arg(&value)
                        .ok_or("invalid depth, expected empty|files|immediates|infinity")?;
                }
                value if value.starts_with("--") => {
                    return Err(format!("unknown flag: {value}").into());
                }
                value => {
                    if root.is_some() {
                        return Err("multiple working copy roots supplied".into());
                    }
                    root = Some(PathBuf::from(value));
                }
            }
        }

        Ok(Self {
            root: root.unwrap_or(std::env::current_dir()?),
            options,
        })
    }
}

struct PathsRequest {
    paths: Vec<PathBuf>,
    depth: StatusDepth,
    force: bool,
}

impl PathsRequest {
    fn parse(arguments: Vec<String>, message_required: bool) -> Result<Self, Box<dyn Error>> {
        let mut paths: Vec<PathBuf> = Vec::new();
        let mut depth = StatusDepth::Infinity;
        let mut force = false;
        let mut iter = arguments.into_iter();

        while let Some(argument) = iter.next() {
            match argument.as_str() {
                "--path" => {
                    let value = iter.next().ok_or("missing value after --path")?;
                    paths.push(PathBuf::from(value));
                }
                "--depth" => {
                    let value = iter.next().ok_or("missing value after --depth")?;
                    depth = StatusDepth::from_cli_arg(&value)
                        .ok_or("invalid depth, expected empty|files|immediates|infinity")?;
                }
                "--force" => {
                    force = true;
                }
                "--message" if !message_required => {
                    return Err("unexpected --message flag for this command".into());
                }
                value if value.starts_with("--") => {
                    return Err(format!("unknown flag: {value}").into());
                }
                value => {
                    paths.push(PathBuf::from(value));
                }
            }
        }

        if paths.is_empty() {
            return Err("at least one --path is required".into());
        }

        Ok(Self { paths, depth, force })
    }
}

struct CommitRequest {
    paths: Vec<PathBuf>,
    message: String,
}

impl CommitRequest {
    fn parse(arguments: Vec<String>) -> Result<Self, Box<dyn Error>> {
        let mut paths: Vec<PathBuf> = Vec::new();
        let mut message: Option<String> = None;
        let mut iter = arguments.into_iter();

        while let Some(argument) = iter.next() {
            match argument.as_str() {
                "--path" => {
                    let value = iter.next().ok_or("missing value after --path")?;
                    paths.push(PathBuf::from(value));
                }
                "--message" => {
                    message = Some(iter.next().ok_or("missing value after --message")?);
                }
                value if value.starts_with("--") => {
                    return Err(format!("unknown flag: {value}").into());
                }
                value => {
                    paths.push(PathBuf::from(value));
                }
            }
        }

        if paths.is_empty() {
            return Err("at least one --path is required".into());
        }

        Ok(Self {
            paths,
            message: message.ok_or("commit requires --message")?,
        })
    }
}

fn serialize_status_response(root: &PathBuf, entries: &[SvnStatusEntry]) -> String {
    let body = entries
        .iter()
        .map(|entry| {
            format!(
                "{{\"path\":\"{}\",\"status\":\"{}\",\"props_modified\":{},\"is_directory\":{}}}",
                escape_json(&entry.path.display().to_string()),
                entry.status.as_bridge_value(),
                entry.props_modified,
                entry.path.is_dir()
            )
        })
        .collect::<Vec<_>>()
        .join(",");

    format!(
        "{{\"kind\":\"status\",\"root\":\"{}\",\"entries\":[{}]}}",
        escape_json(&root.display().to_string()),
        body
    )
}

fn serialize_snapshot_response(snapshot: &status_engine::BadgeSnapshot) -> String {
    let body = snapshot
        .entries
        .iter()
        .map(|(path, entry)| {
            format!(
                "{{\"path\":\"{}\",\"status\":\"{}\",\"props_modified\":{},\"is_directory\":{}}}",
                escape_json(&path.display().to_string()),
                entry.status.as_bridge_value(),
                entry.props_modified,
                path.is_dir()
            )
        })
        .collect::<Vec<_>>()
        .join(",");

    format!(
        "{{\"kind\":\"snapshot\",\"root\":\"{}\",\"entries\":[{}]}}",
        escape_json(&snapshot.root.display().to_string()),
        body
    )
}

fn serialize_add_response(paths: &[PathBuf]) -> String {
    format!(
        "{{\"kind\":\"add\",\"path_count\":{}}}",
        paths.len()
    )
}

fn serialize_commit_response(revision: Option<i64>) -> String {
    let revision_text = revision
        .map(|value| value.to_string())
        .unwrap_or_else(|| "null".to_string());
    format!(
        "{{\"kind\":\"commit\",\"revision\":{}}}",
        revision_text
    )
}

fn escape_json(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}
