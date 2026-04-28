use std::env;
use std::error::Error;
use std::fmt;
use std::path::{Path, PathBuf};
use std::process::Command;

const SVN_BINARY_NAME: &str = "svn";

#[derive(Debug)]
pub enum SvnError {
    Io(std::io::Error),
    Parse(ParseError),
    InvalidUtf8Path(PathBuf),
    CommandFailed {
        program: PathBuf,
        args: Vec<String>,
        status_code: Option<i32>,
        stderr: String,
    },
}

impl fmt::Display for SvnError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(error) => write!(f, "I/O error: {error}"),
            Self::Parse(error) => write!(f, "parse error: {error}"),
            Self::InvalidUtf8Path(path) => {
                write!(f, "path contains non-UTF-8 bytes: {}", path.display())
            }
            Self::CommandFailed {
                program,
                args,
                status_code,
                stderr,
            } => write!(
                f,
                "command failed: {} {} (status: {:?}){}",
                program.display(),
                args.join(" "),
                status_code,
                if stderr.is_empty() {
                    String::new()
                } else {
                    format!(", stderr: {stderr}")
                }
            ),
        }
    }
}

impl Error for SvnError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            Self::Parse(error) => Some(error),
            Self::InvalidUtf8Path(_) | Self::CommandFailed { .. } => None,
        }
    }
}

impl From<std::io::Error> for SvnError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

impl From<ParseError> for SvnError {
    fn from(value: ParseError) -> Self {
        Self::Parse(value)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError {
    message: String,
}

impl ParseError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl Error for ParseError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandOutput {
    pub status_code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
}

pub trait CommandRunner {
    fn run(
        &self,
        program: &Path,
        args: &[String],
        cwd: Option<&Path>,
    ) -> Result<CommandOutput, SvnError>;
}

#[derive(Debug, Default, Clone, Copy)]
pub struct SystemCommandRunner;

impl CommandRunner for SystemCommandRunner {
    fn run(
        &self,
        program: &Path,
        args: &[String],
        cwd: Option<&Path>,
    ) -> Result<CommandOutput, SvnError> {
        let mut command = Command::new(program);
        command.args(args);

        if let Some(working_directory) = cwd {
            command.current_dir(working_directory);
        }

        let output = command.output()?;
        Ok(CommandOutput {
            status_code: output.status.code(),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatusDepth {
    Empty,
    Files,
    Immediates,
    Infinity,
}

impl StatusDepth {
    pub fn as_cli_arg(self) -> &'static str {
        match self {
            Self::Empty => "empty",
            Self::Files => "files",
            Self::Immediates => "immediates",
            Self::Infinity => "infinity",
        }
    }

    pub fn from_cli_arg(value: &str) -> Option<Self> {
        match value {
            "empty" => Some(Self::Empty),
            "files" => Some(Self::Files),
            "immediates" => Some(Self::Immediates),
            "infinity" => Some(Self::Infinity),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StatusOptions {
    pub include_ignored: bool,
    pub include_unversioned: bool,
    pub depth: StatusDepth,
}

impl Default for StatusOptions {
    fn default() -> Self {
        Self {
            include_ignored: false,
            include_unversioned: true,
            depth: StatusDepth::Infinity,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum SvnStatusKind {
    None,
    Normal,
    Modified,
    Added,
    Deleted,
    Conflicted,
    Missing,
    Unversioned,
    Ignored,
    External,
    Replaced,
    Incomplete,
    Obstructed,
    Unknown(String),
}

impl SvnStatusKind {
    pub fn from_wc_item(value: &str) -> Self {
        match value {
            "none" => Self::None,
            "normal" => Self::Normal,
            "modified" => Self::Modified,
            "added" => Self::Added,
            "deleted" => Self::Deleted,
            "conflicted" => Self::Conflicted,
            "missing" => Self::Missing,
            "unversioned" => Self::Unversioned,
            "ignored" => Self::Ignored,
            "external" => Self::External,
            "replaced" => Self::Replaced,
            "incomplete" => Self::Incomplete,
            "obstructed" => Self::Obstructed,
            other => Self::Unknown(other.to_string()),
        }
    }

    pub fn is_dirty(&self) -> bool {
        matches!(
            self,
            Self::Modified
                | Self::Added
                | Self::Deleted
                | Self::Conflicted
                | Self::Missing
                | Self::Unversioned
                | Self::Replaced
                | Self::Incomplete
                | Self::Obstructed
                | Self::Unknown(_)
        )
    }

    pub fn as_bridge_value(&self) -> &str {
        match self {
            Self::None => "none",
            Self::Normal => "normal",
            Self::Modified => "modified",
            Self::Added => "added",
            Self::Deleted => "deleted",
            Self::Conflicted => "conflicted",
            Self::Missing => "missing",
            Self::Unversioned => "unversioned",
            Self::Ignored => "ignored",
            Self::External => "external",
            Self::Replaced => "replaced",
            Self::Incomplete => "incomplete",
            Self::Obstructed => "obstructed",
            Self::Unknown(value) => value.as_str(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SvnStatusEntry {
    pub path: PathBuf,
    pub status: SvnStatusKind,
    pub props_modified: bool,
}

pub trait StatusProvider {
    fn status(&self, root: &Path, options: &StatusOptions)
        -> Result<Vec<SvnStatusEntry>, SvnError>;
}

#[derive(Debug)]
pub struct CommandLineSvnBackend<R = SystemCommandRunner> {
    binary: PathBuf,
    runner: R,
}

impl CommandLineSvnBackend<SystemCommandRunner> {
    pub fn system() -> Self {
        Self::new(discover_system_svn_binary(), SystemCommandRunner)
    }
}

impl<R> CommandLineSvnBackend<R> {
    pub fn new(binary: PathBuf, runner: R) -> Self {
        Self { binary, runner }
    }
}

impl<R: CommandRunner> CommandLineSvnBackend<R> {
    pub fn add(&self, paths: &[PathBuf], depth: StatusDepth, force: bool) -> Result<(), SvnError> {
        let mut args = vec![
            "add".to_string(),
            "--depth".to_string(),
            depth.as_cli_arg().to_string(),
        ];
        if force {
            args.push("--force".to_string());
        }
        args.extend(
            paths
                .iter()
                .map(|path| path_to_string(path.as_path()))
                .collect::<Result<Vec<_>, _>>()?,
        );

        self.run_checked(&args, None)?;
        Ok(())
    }

    pub fn commit(&self, paths: &[PathBuf], message: &str) -> Result<Option<i64>, SvnError> {
        let mut args = vec!["commit".to_string(), "-m".to_string(), message.to_string()];
        args.extend(
            paths
                .iter()
                .map(|path| path_to_string(path.as_path()))
                .collect::<Result<Vec<_>, _>>()?,
        );

        let output = self.run_checked(&args, None)?;
        Ok(parse_committed_revision(&output.stdout))
    }

    fn run_checked(&self, args: &[String], cwd: Option<&Path>) -> Result<CommandOutput, SvnError> {
        let output = self.runner.run(&self.binary, args, cwd)?;
        if output.status_code == Some(0) {
            Ok(output)
        } else {
            Err(SvnError::CommandFailed {
                program: self.binary.clone(),
                args: args.to_vec(),
                status_code: output.status_code,
                stderr: output.stderr,
            })
        }
    }
}

impl<R: CommandRunner> StatusProvider for CommandLineSvnBackend<R> {
    fn status(
        &self,
        root: &Path,
        options: &StatusOptions,
    ) -> Result<Vec<SvnStatusEntry>, SvnError> {
        let mut args = vec!["status".to_string(), "--xml".to_string()];
        if options.include_ignored {
            args.push("--no-ignore".to_string());
        }
        if options.depth != StatusDepth::Infinity {
            args.push("--depth".to_string());
            args.push(options.depth.as_cli_arg().to_string());
        }
        args.push(path_to_string(root)?);

        let output = self.run_checked(&args, Some(root))?;
        parse_status_xml(root, &output.stdout, options)
    }
}

pub fn parse_status_xml(
    root: &Path,
    xml: &str,
    options: &StatusOptions,
) -> Result<Vec<SvnStatusEntry>, SvnError> {
    let mut entries = Vec::new();
    let mut cursor = 0usize;

    while let Some(entry_start) = find_from(xml, "<entry", cursor) {
        let opening_end = find_from(xml, ">", entry_start)
            .ok_or_else(|| ParseError::new("unterminated <entry> tag"))?;
        let closing_start = find_from(xml, "</entry>", opening_end)
            .ok_or_else(|| ParseError::new("missing </entry> tag"))?;

        let opening_tag = &xml[entry_start..=opening_end];
        let body = &xml[opening_end + 1..closing_start];
        let raw_path = extract_attribute(opening_tag, "path")
            .ok_or_else(|| ParseError::new("entry is missing path attribute"))?;
        let decoded_path = decode_xml_entities(&raw_path);
        let wc_status_start = body
            .find("<wc-status")
            .ok_or_else(|| ParseError::new("entry is missing <wc-status>"))?;
        let wc_tag_absolute = opening_end + 1 + wc_status_start;
        let wc_opening_end = find_from(xml, ">", wc_tag_absolute)
            .ok_or_else(|| ParseError::new("unterminated <wc-status> tag"))?;
        let wc_opening_tag = &xml[wc_tag_absolute..=wc_opening_end];

        let item = extract_attribute(wc_opening_tag, "item")
            .ok_or_else(|| ParseError::new("wc-status is missing item attribute"))?;
        let props =
            extract_attribute(wc_opening_tag, "props").unwrap_or_else(|| "none".to_string());

        let status = SvnStatusKind::from_wc_item(&item);
        let should_keep = match status {
            SvnStatusKind::Ignored => options.include_ignored,
            SvnStatusKind::Unversioned => options.include_unversioned,
            _ => true,
        };

        if should_keep {
            entries.push(SvnStatusEntry {
                path: normalize_entry_path(root, &decoded_path),
                status,
                props_modified: props != "none" && props != "normal",
            });
        }

        cursor = closing_start + "</entry>".len();
    }

    Ok(entries)
}

fn normalize_entry_path(root: &Path, raw: &str) -> PathBuf {
    let candidate = PathBuf::from(raw);
    if candidate.is_absolute() {
        candidate
    } else {
        root.join(candidate)
    }
}

fn parse_committed_revision(stdout: &str) -> Option<i64> {
    let words = stdout.split_whitespace().collect::<Vec<_>>();
    for window in words.windows(3) {
        if window[0] == "Committed" && window[1] == "revision" {
            let digits = window[2].trim_end_matches('.');
            if let Ok(revision) = digits.parse::<i64>() {
                return Some(revision);
            }
        }
    }
    None
}

fn path_to_string(path: &Path) -> Result<String, SvnError> {
    path.to_str()
        .map(str::to_owned)
        .ok_or_else(|| SvnError::InvalidUtf8Path(path.to_path_buf()))
}

fn find_from(haystack: &str, needle: &str, start: usize) -> Option<usize> {
    haystack[start..].find(needle).map(|index| index + start)
}

fn extract_attribute(tag: &str, attribute: &str) -> Option<String> {
    let search = format!("{attribute}=\"");
    let start = tag.find(&search)? + search.len();
    let end = tag[start..].find('"')? + start;
    Some(tag[start..end].to_string())
}

fn decode_xml_entities(value: &str) -> String {
    value
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
}

fn discover_system_svn_binary() -> PathBuf {
    discover_svn_binary_from_candidates(
        env::var_os("MACSVN_SVN_BINARY").map(PathBuf::from),
        env_path_svn_candidates(),
        common_svn_binary_candidates(),
    )
    .unwrap_or_else(|| PathBuf::from(SVN_BINARY_NAME))
}

fn discover_svn_binary_from_candidates(
    override_candidate: Option<PathBuf>,
    path_candidates: Vec<PathBuf>,
    common_candidates: Vec<PathBuf>,
) -> Option<PathBuf> {
    override_candidate
        .into_iter()
        .chain(path_candidates)
        .chain(common_candidates)
        .find(|candidate| is_usable_binary(candidate))
}

fn env_path_svn_candidates() -> Vec<PathBuf> {
    env::var_os("PATH")
        .map(|path_var| {
            env::split_paths(&path_var)
                .map(|directory| directory.join(SVN_BINARY_NAME))
                .collect()
        })
        .unwrap_or_default()
}

fn common_svn_binary_candidates() -> Vec<PathBuf> {
    let mut candidates: Vec<PathBuf> = Vec::new();

    if let Some(developer_dir) = env::var_os("DEVELOPER_DIR") {
        candidates.push(PathBuf::from(developer_dir).join("usr/bin").join(SVN_BINARY_NAME));
    }

    candidates.extend([
        PathBuf::from("/opt/homebrew/bin/svn"),
        PathBuf::from("/usr/local/bin/svn"),
        PathBuf::from("/Applications/Xcode.app/Contents/Developer/usr/bin/svn"),
        PathBuf::from("/usr/bin/svn"),
    ]);

    deduplicate_paths(candidates)
}

fn deduplicate_paths(paths: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut deduplicated: Vec<PathBuf> = Vec::new();
    for path in paths {
        if !deduplicated.iter().any(|existing| existing == &path) {
            deduplicated.push(path);
        }
    }
    deduplicated
}

fn is_usable_binary(path: &Path) -> bool {
    path.is_file()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::env;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    const SAMPLE_STATUS_XML: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<status>
  <target path="/tmp/repo">
    <entry path="src/main.rs">
      <wc-status props="none" item="modified" revision="12"></wc-status>
    </entry>
    <entry path="README.md">
      <wc-status props="modified" item="normal" revision="12"></wc-status>
    </entry>
    <entry path="scratch.txt">
      <wc-status props="none" item="unversioned"></wc-status>
    </entry>
    <entry path="ignored.log">
      <wc-status props="none" item="ignored"></wc-status>
    </entry>
  </target>
</status>"#;

    const MULTILINE_STATUS_XML: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<status>
<target
   path="/tmp/repo">
<entry
   path="/tmp/repo/README.md">
<wc-status
   item="modified"
   revision="12"
   props="none">
</wc-status>
</entry>
<entry
   path="/tmp/repo/new.txt">
<wc-status
   item="unversioned"
   props="none">
</wc-status>
</entry>
</target>
</status>"#;

    #[test]
    fn parses_status_xml_and_filters_optional_items() {
        let root = Path::new("/tmp/repo");
        let options = StatusOptions::default();
        let entries = parse_status_xml(root, SAMPLE_STATUS_XML, &options).unwrap();

        assert_eq!(entries.len(), 3);
        assert_eq!(entries[0].path, PathBuf::from("/tmp/repo/src/main.rs"));
        assert_eq!(entries[0].status, SvnStatusKind::Modified);
        assert_eq!(entries[1].status, SvnStatusKind::Normal);
        assert!(entries[1].props_modified);
        assert_eq!(entries[2].status, SvnStatusKind::Unversioned);
    }

    #[test]
    fn keeps_ignored_items_when_requested() {
        let root = Path::new("/tmp/repo");
        let options = StatusOptions {
            include_ignored: true,
            include_unversioned: true,
            depth: StatusDepth::Infinity,
        };
        let entries = parse_status_xml(root, SAMPLE_STATUS_XML, &options).unwrap();

        assert!(entries
            .iter()
            .any(|entry| entry.status == SvnStatusKind::Ignored));
    }

    #[test]
    fn parses_multiline_opening_tags_from_real_svn_output() {
        let root = Path::new("/tmp/repo");
        let options = StatusOptions::default();
        let entries = parse_status_xml(root, MULTILINE_STATUS_XML, &options).unwrap();

        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].path, PathBuf::from("/tmp/repo/README.md"));
        assert_eq!(entries[0].status, SvnStatusKind::Modified);
        assert_eq!(entries[1].path, PathBuf::from("/tmp/repo/new.txt"));
        assert_eq!(entries[1].status, SvnStatusKind::Unversioned);
    }

    #[test]
    fn parses_committed_revision_from_stdout() {
        assert_eq!(
            parse_committed_revision("Sending foo\nCommitted revision 194.\n"),
            Some(194)
        );
        assert_eq!(parse_committed_revision("Nothing committed"), None);
    }

    #[derive(Debug)]
    struct RecordingRunner {
        stdout: String,
        captured_args: RefCell<Vec<String>>,
    }

    impl CommandRunner for RecordingRunner {
        fn run(
            &self,
            _program: &Path,
            args: &[String],
            _cwd: Option<&Path>,
        ) -> Result<CommandOutput, SvnError> {
            self.captured_args.replace(args.to_vec());
            Ok(CommandOutput {
                status_code: Some(0),
                stdout: self.stdout.clone(),
                stderr: String::new(),
            })
        }
    }

    #[test]
    fn backend_builds_status_command_with_expected_flags() {
        let runner = RecordingRunner {
            stdout: SAMPLE_STATUS_XML.to_string(),
            captured_args: RefCell::new(Vec::new()),
        };
        let backend = CommandLineSvnBackend::new(PathBuf::from("svn"), runner);
        let options = StatusOptions {
            include_ignored: true,
            include_unversioned: false,
            depth: StatusDepth::Files,
        };

        let entries = backend.status(Path::new("/tmp/repo"), &options).unwrap();

        assert_eq!(entries.len(), 3);
        let args = backend.runner.captured_args.borrow().clone();
        assert_eq!(args[0], "status");
        assert!(args.contains(&"--xml".to_string()));
        assert!(args.contains(&"--no-ignore".to_string()));
        assert!(args.contains(&"--depth".to_string()));
        assert!(args.contains(&"files".to_string()));
    }

    #[test]
    fn prefers_override_binary_when_present() {
        let temp_dir = make_temp_dir("override");
        let override_binary = temp_dir.join("custom-svn");
        let path_binary = temp_dir.join("svn");
        fs::write(&override_binary, "override").unwrap();
        fs::write(&path_binary, "path").unwrap();

        let discovered = discover_svn_binary_from_candidates(
            Some(override_binary.clone()),
            vec![path_binary],
            vec![PathBuf::from("/usr/bin/svn")],
        );

        assert_eq!(discovered, Some(override_binary));
        fs::remove_dir_all(temp_dir).unwrap();
    }

    #[test]
    fn prefers_path_candidate_before_common_locations() {
        let temp_dir = make_temp_dir("path");
        let path_binary = temp_dir.join("svn");
        let common_binary = temp_dir.join("common-svn");
        fs::write(&path_binary, "path").unwrap();
        fs::write(&common_binary, "common").unwrap();

        let discovered = discover_svn_binary_from_candidates(
            None,
            vec![path_binary.clone()],
            vec![common_binary],
        );

        assert_eq!(discovered, Some(path_binary));
        fs::remove_dir_all(temp_dir).unwrap();
    }

    fn make_temp_dir(label: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = env::temp_dir().join(format!("mtsvn-svn-backend-{label}-{unique}"));
        fs::create_dir_all(&directory).unwrap();
        directory
    }
}
