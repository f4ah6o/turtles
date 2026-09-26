use std::env;
use std::ffi::OsStr;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, PartialEq, Eq)]
struct Mutation {
    path: PathBuf,
    start: usize,
    end: usize,
    line: usize,
    column: usize,
    original: &'static str,
    replacement: &'static str,
}

#[derive(Debug, Clone)]
struct Config {
    dir: PathBuf,
    timeout: Duration,
    list: bool,
    file_filter: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OperatorGroup {
    Comparison,
    Boolean,
    Arithmetic,
    Literal,
}

impl OperatorGroup {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "comparison" | "comparisons" => Ok(Self::Comparison),
            "boolean" | "boolean-logic" => Ok(Self::Boolean),
            "arithmetic" => Ok(Self::Arithmetic),
            "literal" | "boolean-literal" | "boolean-literals" => Ok(Self::Literal),
            other => Err(format!(
                "unknown operator group {other:?}; expected comparison, boolean, arithmetic, or literal"
            )),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
struct ProjectConfig {
    include: Vec<String>,
    exclude: Vec<String>,
    operators: Option<Vec<OperatorGroup>>,
}

impl ProjectConfig {
    fn path_enabled(&self, path: &Path) -> bool {
        let path = path.to_string_lossy().replace('\\', "/");
        let included = self.include.is_empty()
            || self
                .include
                .iter()
                .any(|pattern| path.contains(pattern.as_str()));
        included
            && !self
                .exclude
                .iter()
                .any(|pattern| path.contains(pattern.as_str()))
    }

    fn operator_enabled(&self, group: OperatorGroup) -> bool {
        self.operators
            .as_ref()
            .is_none_or(|operators| operators.contains(&group))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Outcome {
    Killed,
    Survived,
    Timeout,
    Unviable,
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => code,
        Err(message) => {
            eprintln!("turtles: {message}");
            ExitCode::from(2)
        }
    }
}

fn run() -> Result<ExitCode, String> {
    let config = parse_args(env::args().skip(1))?;
    let root = fs::canonicalize(&config.dir)
        .map_err(|e| format!("cannot open {}: {e}", config.dir.display()))?;

    if !root.join("moon.mod").is_file() && !root.join("moon.mod.json").is_file() {
        return Err(format!(
            "{} is not a MoonBit module (moon.mod not found)",
            root.display()
        ));
    }

    let project_config = load_project_config(&root)?;
    let mutations = discover_mutations(&root, config.file_filter.as_deref(), &project_config)
        .map_err(|e| format!("failed to scan MoonBit sources: {e}"))?;

    if mutations.is_empty() {
        println!("No mutations found.");
        return Ok(ExitCode::SUCCESS);
    }

    println!("Found {} mutation(s).", mutations.len());
    if config.list {
        for mutation in &mutations {
            println!("{}", describe_mutation(mutation));
        }
        return Ok(ExitCode::SUCCESS);
    }

    print!("Baseline: moon test ... ");
    let baseline = run_command(&root, "moon", &["test"], config.timeout)
        .map_err(|e| format!("failed to run baseline: {e}"))?;
    match baseline {
        CommandResult::Success => println!("ok"),
        CommandResult::Failure => {
            println!("FAILED");
            return Err("baseline test suite failed; refusing to classify mutants".into());
        }
        CommandResult::Timeout => {
            println!("TIMEOUT");
            return Err("baseline test suite timed out".into());
        }
    }

    let workspace = TempWorkspace::copy_from(&root)
        .map_err(|e| format!("failed to create temporary workspace: {e}"))?;
    let mut results = Vec::with_capacity(mutations.len());

    for (index, mutation) in mutations.iter().enumerate() {
        let target = workspace.path().join(&mutation.path);
        let original_source = fs::read_to_string(&target)
            .map_err(|e| format!("failed to read {}: {e}", target.display()))?;
        let mutated = apply_mutation(&original_source, mutation)
            .map_err(|e| format!("failed to apply {}: {e}", describe_mutation(mutation)))?;

        fs::write(&target, mutated)
            .map_err(|e| format!("failed to write {}: {e}", target.display()))?;

        let outcome = classify_mutant(workspace.path(), config.timeout)
            .map_err(|e| format!("failed while testing mutant: {e}"))?;

        fs::write(&target, original_source)
            .map_err(|e| format!("failed to restore {}: {e}", target.display()))?;

        println!(
            "[{}/{}] {:9} {}",
            index + 1,
            mutations.len(),
            outcome_name(outcome),
            describe_mutation(mutation)
        );
        results.push(outcome);
    }

    let killed = results.iter().filter(|&&x| x == Outcome::Killed).count();
    let survived = results.iter().filter(|&&x| x == Outcome::Survived).count();
    let timeout = results.iter().filter(|&&x| x == Outcome::Timeout).count();
    let unviable = results.iter().filter(|&&x| x == Outcome::Unviable).count();
    let viable = killed + survived + timeout;
    let score = if viable == 0 {
        100.0
    } else {
        killed as f64 * 100.0 / viable as f64
    };

    println!();
    println!("Mutation testing complete:");
    println!("  killed:    {killed}");
    println!("  survived:  {survived}");
    println!("  timeout:   {timeout}");
    println!("  unviable:  {unviable}");
    println!("  score:     {score:.1}%");

    if survived > 0 || timeout > 0 {
        Ok(ExitCode::from(1))
    } else {
        Ok(ExitCode::SUCCESS)
    }
}

fn parse_args(args: impl Iterator<Item = String>) -> Result<Config, String> {
    let mut dir = PathBuf::from(".");
    let mut timeout = Duration::from_secs(60);
    let mut list = false;
    let mut file_filter = None;
    let mut args = args.peekable();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                println!(
                    "turtles - mutation testing for MoonBit\n\n\
Usage: turtles [OPTIONS]\n\n\
Options:\n\
  -d, --dir <PATH>       MoonBit module directory (default: .)\n\
      --timeout <SECS>   Per-command timeout (default: 60)\n\
      --file <TEXT>      Only mutate source paths containing TEXT\n\
      --list             List mutations without running tests\n\
  -h, --help             Print help\n"
                );
                std::process::exit(0);
            }
            "-d" | "--dir" => {
                let value = args.next().ok_or("--dir requires a path")?;
                dir = PathBuf::from(value);
            }
            "--timeout" => {
                let value = args.next().ok_or("--timeout requires seconds")?;
                let seconds: u64 = value
                    .parse()
                    .map_err(|_| format!("invalid timeout: {value}"))?;
                if seconds == 0 {
                    return Err("--timeout must be greater than zero".into());
                }
                timeout = Duration::from_secs(seconds);
            }
            "--file" => {
                file_filter = Some(args.next().ok_or("--file requires text")?);
            }
            "--list" => list = true,
            other => return Err(format!("unknown argument: {other} (try --help)")),
        }
    }

    Ok(Config {
        dir,
        timeout,
        list,
        file_filter,
    })
}

fn load_project_config(root: &Path) -> Result<ProjectConfig, String> {
    let path = root.join("turtles.toml");
    if !path.is_file() {
        return Ok(ProjectConfig::default());
    }

    let source =
        fs::read_to_string(&path).map_err(|e| format!("failed to read {}: {e}", path.display()))?;
    parse_project_config(&source).map_err(|e| format!("invalid {}: {e}", path.display()))
}

fn parse_project_config(source: &str) -> Result<ProjectConfig, String> {
    ConfigParser::new(source).parse()
}

struct ConfigParser<'a> {
    source: &'a str,
    bytes: &'a [u8],
    position: usize,
}

impl<'a> ConfigParser<'a> {
    fn new(source: &'a str) -> Self {
        Self {
            source,
            bytes: source.as_bytes(),
            position: 0,
        }
    }

    fn parse(mut self) -> Result<ProjectConfig, String> {
        let mut config = ProjectConfig::default();
        let mut seen_include = false;
        let mut seen_exclude = false;
        let mut seen_operators = false;

        loop {
            self.skip_space_and_comments();
            if self.position >= self.bytes.len() {
                break;
            }

            let key = self.parse_key()?;
            self.skip_space_and_comments();
            self.expect_byte(b'=')?;
            self.skip_space_and_comments();
            let values = self.parse_string_array()?;

            match key.as_str() {
                "include" => {
                    if seen_include {
                        return Err(self.error("duplicate include key"));
                    }
                    seen_include = true;
                    config.include = values;
                }
                "exclude" => {
                    if seen_exclude {
                        return Err(self.error("duplicate exclude key"));
                    }
                    seen_exclude = true;
                    config.exclude = values;
                }
                "operators" => {
                    if seen_operators {
                        return Err(self.error("duplicate operators key"));
                    }
                    seen_operators = true;
                    config.operators = Some(
                        values
                            .iter()
                            .map(|value| OperatorGroup::parse(value))
                            .collect::<Result<Vec<_>, _>>()?,
                    );
                }
                other => {
                    return Err(self.error(&format!(
                        "unknown key {other:?}; expected include, exclude, or operators"
                    )));
                }
            }
        }

        Ok(config)
    }

    fn skip_space_and_comments(&mut self) {
        loop {
            while self
                .bytes
                .get(self.position)
                .is_some_and(|byte| byte.is_ascii_whitespace())
            {
                self.position += 1;
            }
            if self.bytes.get(self.position) != Some(&b'#') {
                break;
            }
            while self.position < self.bytes.len() && self.bytes[self.position] != b'\n' {
                self.position += 1;
            }
        }
    }

    fn parse_key(&mut self) -> Result<String, String> {
        let start = self.position;
        while self
            .bytes
            .get(self.position)
            .is_some_and(|byte| byte.is_ascii_alphanumeric() || *byte == b'_' || *byte == b'-')
        {
            self.position += 1;
        }
        if start == self.position {
            return Err(self.error("expected a configuration key"));
        }
        Ok(self.source[start..self.position].to_owned())
    }

    fn parse_string_array(&mut self) -> Result<Vec<String>, String> {
        self.expect_byte(b'[')?;
        let mut values = Vec::new();

        loop {
            self.skip_space_and_comments();
            if self.consume_byte(b']') {
                return Ok(values);
            }

            values.push(self.parse_string()?);
            self.skip_space_and_comments();

            if self.consume_byte(b',') {
                continue;
            }
            if self.consume_byte(b']') {
                return Ok(values);
            }
            return Err(self.error("expected ',' or ']' after array item"));
        }
    }

    fn parse_string(&mut self) -> Result<String, String> {
        self.expect_byte(b'"')?;
        let mut output = String::new();

        while self.position < self.bytes.len() {
            let byte = self.bytes[self.position];
            self.position += 1;
            match byte {
                b'"' => return Ok(output),
                b'\\' => {
                    let escaped = *self
                        .bytes
                        .get(self.position)
                        .ok_or_else(|| self.error("unterminated string escape"))?;
                    self.position += 1;
                    match escaped {
                        b'"' => output.push('"'),
                        b'\\' => output.push('\\'),
                        b'n' => output.push('\n'),
                        b'r' => output.push('\r'),
                        b't' => output.push('\t'),
                        _ => {
                            return Err(self.error(
                                "unsupported string escape; use \", \\\\, \\n, \\r, or \\t",
                            ));
                        }
                    }
                }
                b'\n' | b'\r' => return Err(self.error("newline in quoted string")),
                _ if byte.is_ascii() => output.push(byte as char),
                _ => {
                    let start = self.position - 1;
                    let ch = self.source[start..]
                        .chars()
                        .next()
                        .ok_or_else(|| self.error("invalid UTF-8 in string"))?;
                    output.push(ch);
                    self.position = start + ch.len_utf8();
                }
            }
        }

        Err(self.error("unterminated quoted string"))
    }

    fn expect_byte(&mut self, expected: u8) -> Result<(), String> {
        if self.consume_byte(expected) {
            Ok(())
        } else {
            Err(self.error(&format!("expected {:?}", expected as char)))
        }
    }

    fn consume_byte(&mut self, expected: u8) -> bool {
        if self.bytes.get(self.position) == Some(&expected) {
            self.position += 1;
            true
        } else {
            false
        }
    }

    fn error(&self, message: &str) -> String {
        let prefix = &self.source[..self.position.min(self.source.len())];
        let line = prefix.bytes().filter(|&byte| byte == b'\n').count() + 1;
        let column = prefix
            .rsplit_once('\n')
            .map_or(prefix.len() + 1, |(_, tail)| tail.len() + 1);
        format!("{message} at {line}:{column}")
    }
}

fn discover_mutations(
    root: &Path,
    file_filter: Option<&str>,
    project_config: &ProjectConfig,
) -> io::Result<Vec<Mutation>> {
    let mut files = Vec::new();
    collect_moonbit_files(root, root, file_filter, project_config, &mut files)?;
    files.sort();

    let mut mutations = Vec::new();
    for relative in files {
        let source = fs::read_to_string(root.join(&relative))?;
        mutations.extend(scan_source(&relative, &source, project_config));
    }
    Ok(mutations)
}

fn collect_moonbit_files(
    root: &Path,
    dir: &Path,
    file_filter: Option<&str>,
    project_config: &ProjectConfig,
    out: &mut Vec<PathBuf>,
) -> io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let name = entry.file_name();

        if path.is_dir() {
            if should_skip_dir(&name) {
                continue;
            }
            collect_moonbit_files(root, &path, file_filter, project_config, out)?;
            continue;
        }

        if path.extension() != Some(OsStr::new("mbt")) {
            continue;
        }

        let file_name = path.file_name().and_then(OsStr::to_str).unwrap_or_default();
        if file_name.ends_with("_test.mbt") || file_name.ends_with("_wbtest.mbt") {
            continue;
        }

        let relative = path.strip_prefix(root).unwrap_or(&path).to_path_buf();
        if !project_config.path_enabled(&relative) {
            continue;
        }
        if let Some(filter) = file_filter
            && !relative.to_string_lossy().contains(filter)
        {
            continue;
        }
        out.push(relative);
    }
    Ok(())
}

fn should_skip_dir(name: &OsStr) -> bool {
    matches!(
        name.to_str(),
        Some(".git") | Some("target") | Some(".mooncakes") | Some(".moon") | Some("node_modules")
    )
}

fn scan_source(path: &Path, source: &str, project_config: &ProjectConfig) -> Vec<Mutation> {
    const OPS: &[(OperatorGroup, &str, &str)] = &[
        (OperatorGroup::Comparison, "==", "!="),
        (OperatorGroup::Comparison, "!=", "=="),
        (OperatorGroup::Comparison, ">=", "<"),
        (OperatorGroup::Comparison, "<=", ">"),
        (OperatorGroup::Boolean, "&&", "||"),
        (OperatorGroup::Boolean, "||", "&&"),
        (OperatorGroup::Literal, "true", "false"),
        (OperatorGroup::Literal, "false", "true"),
        (OperatorGroup::Arithmetic, "+", "-"),
        (OperatorGroup::Arithmetic, "-", "+"),
        (OperatorGroup::Arithmetic, "*", "/"),
        (OperatorGroup::Arithmetic, "/", "*"),
        (OperatorGroup::Comparison, ">", "<"),
        (OperatorGroup::Comparison, "<", ">"),
    ];

    let bytes = source.as_bytes();
    let mut i = 0;
    let mut line = 1;
    let mut column = 1;
    let mut mutations = Vec::new();

    while i < bytes.len() {
        if starts(bytes, i, b"//") {
            advance_until_newline(bytes, &mut i, &mut line, &mut column);
            continue;
        }
        if starts(bytes, i, b"/*") {
            advance_block_comment(bytes, &mut i, &mut line, &mut column);
            continue;
        }
        if bytes[i] == b'"' {
            advance_quoted(bytes, &mut i, &mut line, &mut column, b'"');
            continue;
        }
        if bytes[i] == b'\'' {
            advance_quoted(bytes, &mut i, &mut line, &mut column, b'\'');
            continue;
        }

        let mut matched = false;
        for &(group, original, replacement) in OPS {
            if !project_config.operator_enabled(group) {
                continue;
            }
            let op = original.as_bytes();
            if !starts(bytes, i, op) {
                continue;
            }
            if (original == "true" || original == "false")
                && (!word_start_boundary(bytes, i) || !word_end_boundary(bytes, i + op.len()))
            {
                continue;
            }
            if is_syntax_punctuation(bytes, i, original) {
                continue;
            }

            mutations.push(Mutation {
                path: path.to_path_buf(),
                start: i,
                end: i + op.len(),
                line,
                column,
                original,
                replacement,
            });
            advance_plain(bytes, &mut i, &mut line, &mut column, op.len());
            matched = true;
            break;
        }

        if !matched {
            let width = source[i..].chars().next().map(char::len_utf8).unwrap_or(1);
            advance_plain(bytes, &mut i, &mut line, &mut column, width);
        }
    }

    mutations
}

fn is_syntax_punctuation(bytes: &[u8], i: usize, token: &str) -> bool {
    match token {
        "-" => i + 1 < bytes.len() && bytes[i + 1] == b'>',
        ">" => i > 0 && bytes[i - 1] == b'-',
        "/" => i + 1 < bytes.len() && (bytes[i + 1] == b'/' || bytes[i + 1] == b'*'),
        "*" => i > 0 && bytes[i - 1] == b'/',
        _ => false,
    }
}

fn word_start_boundary(bytes: &[u8], index: usize) -> bool {
    index == 0 || !is_ident_byte(bytes[index - 1])
}

fn word_end_boundary(bytes: &[u8], index: usize) -> bool {
    index >= bytes.len() || !is_ident_byte(bytes[index])
}

fn is_ident_byte(byte: u8) -> bool {
    byte == b'_' || byte.is_ascii_alphanumeric()
}

fn starts(bytes: &[u8], index: usize, needle: &[u8]) -> bool {
    bytes.get(index..index + needle.len()) == Some(needle)
}

fn advance_until_newline(bytes: &[u8], i: &mut usize, line: &mut usize, column: &mut usize) {
    while *i < bytes.len() {
        let byte = bytes[*i];
        advance_plain(bytes, i, line, column, 1);
        if byte == b'\n' {
            break;
        }
    }
}

fn advance_block_comment(bytes: &[u8], i: &mut usize, line: &mut usize, column: &mut usize) {
    advance_plain(bytes, i, line, column, 2);
    let mut depth = 1usize;
    while *i < bytes.len() && depth > 0 {
        if starts(bytes, *i, b"/*") {
            depth += 1;
            advance_plain(bytes, i, line, column, 2);
        } else if starts(bytes, *i, b"*/") {
            depth -= 1;
            advance_plain(bytes, i, line, column, 2);
        } else {
            advance_plain(bytes, i, line, column, 1);
        }
    }
}

fn advance_quoted(bytes: &[u8], i: &mut usize, line: &mut usize, column: &mut usize, quote: u8) {
    advance_plain(bytes, i, line, column, 1);
    while *i < bytes.len() {
        if bytes[*i] == b'\\' {
            let width = if *i + 1 < bytes.len() { 2 } else { 1 };
            advance_plain(bytes, i, line, column, width);
            continue;
        }
        let current = bytes[*i];
        advance_plain(bytes, i, line, column, 1);
        if current == quote {
            break;
        }
    }
}

fn advance_plain(bytes: &[u8], i: &mut usize, line: &mut usize, column: &mut usize, width: usize) {
    for _ in 0..width {
        if *i >= bytes.len() {
            return;
        }
        if bytes[*i] == b'\n' {
            *line += 1;
            *column = 1;
        } else {
            *column += 1;
        }
        *i += 1;
    }
}

fn apply_mutation(source: &str, mutation: &Mutation) -> Result<String, String> {
    if source.get(mutation.start..mutation.end) != Some(mutation.original) {
        return Err("source changed after mutation discovery".into());
    }
    let mut output = String::with_capacity(source.len() + mutation.replacement.len());
    output.push_str(&source[..mutation.start]);
    output.push_str(mutation.replacement);
    output.push_str(&source[mutation.end..]);
    Ok(output)
}

fn classify_mutant(root: &Path, timeout: Duration) -> io::Result<Outcome> {
    match run_command(root, "moon", &["check"], timeout)? {
        CommandResult::Failure => return Ok(Outcome::Unviable),
        CommandResult::Timeout => return Ok(Outcome::Timeout),
        CommandResult::Success => {}
    }

    Ok(match run_command(root, "moon", &["test"], timeout)? {
        CommandResult::Success => Outcome::Survived,
        CommandResult::Failure => Outcome::Killed,
        CommandResult::Timeout => Outcome::Timeout,
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CommandResult {
    Success,
    Failure,
    Timeout,
}

fn run_command(
    root: &Path,
    program: &str,
    args: &[&str],
    timeout: Duration,
) -> io::Result<CommandResult> {
    let mut child = Command::new(program)
        .args(args)
        .current_dir(root)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;

    let started = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            return Ok(if status.success() {
                CommandResult::Success
            } else {
                CommandResult::Failure
            });
        }
        if started.elapsed() >= timeout {
            let _ = child.kill();
            let _ = child.wait();
            return Ok(CommandResult::Timeout);
        }
        thread::sleep(Duration::from_millis(25));
    }
}

fn describe_mutation(mutation: &Mutation) -> String {
    format!(
        "{}:{}:{}: {} -> {}",
        mutation.path.display(),
        mutation.line,
        mutation.column,
        mutation.original,
        mutation.replacement
    )
}

fn outcome_name(outcome: Outcome) -> &'static str {
    match outcome {
        Outcome::Killed => "KILLED",
        Outcome::Survived => "SURVIVED",
        Outcome::Timeout => "TIMEOUT",
        Outcome::Unviable => "UNVIABLE",
    }
}

struct TempWorkspace {
    path: PathBuf,
}

impl TempWorkspace {
    fn copy_from(source: &Path) -> io::Result<Self> {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let path = env::temp_dir().join(format!("turtles-{}-{stamp}", std::process::id()));
        fs::create_dir_all(&path)?;
        if let Err(error) = copy_tree(source, source, &path) {
            let _ = fs::remove_dir_all(&path);
            return Err(error);
        }
        Ok(Self { path })
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempWorkspace {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

fn copy_tree(root: &Path, current: &Path, destination: &Path) -> io::Result<()> {
    for entry in fs::read_dir(current)? {
        let entry = entry?;
        let source = entry.path();
        let name = entry.file_name();
        if source.is_dir() && should_skip_dir(&name) {
            continue;
        }

        let relative = source.strip_prefix(root).unwrap_or(&source);
        let target = destination.join(relative);
        if source.is_dir() {
            fs::create_dir_all(&target)?;
            copy_tree(root, &source, destination)?;
        } else if source.is_file() {
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(&source, &target)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_mutations_but_skips_comments_and_strings() {
        let source = r#"
fn f(a : Int, b : Int) -> Bool {
  // a + b > 0
  let text = "true && false"
  a + b >= 1 && true
}
"#;
        let mutations = scan_source(Path::new("sample.mbt"), source, &ProjectConfig::default());
        let pairs: Vec<_> = mutations
            .iter()
            .map(|m| (m.original, m.replacement))
            .collect();
        assert_eq!(
            pairs,
            vec![("+", "-"), (">=", "<"), ("&&", "||"), ("true", "false")]
        );
    }

    #[test]
    fn does_not_mutate_function_arrow() {
        let source = "fn f(x : Int) -> Int { x - 1 }";
        let mutations = scan_source(Path::new("sample.mbt"), source, &ProjectConfig::default());
        assert_eq!(mutations.len(), 1);
        assert_eq!(mutations[0].original, "-");
        assert_eq!(mutations[0].column, 26);
    }

    #[test]
    fn parses_project_config_with_multiline_arrays_and_comments() {
        let config = parse_project_config(
            r#"
# Paths are substring matches against normalized relative paths.
include = [
  "src/",
  "lib/",
]
exclude = ["generated/", "vendor/"]
operators = ["comparison", "literal"]
"#,
        )
        .unwrap();

        assert_eq!(config.include, vec!["src/", "lib/"]);
        assert_eq!(config.exclude, vec!["generated/", "vendor/"]);
        assert_eq!(
            config.operators,
            Some(vec![OperatorGroup::Comparison, OperatorGroup::Literal])
        );
        assert!(config.path_enabled(Path::new("src/math.mbt")));
        assert!(!config.path_enabled(Path::new("src/generated/math.mbt")));
        assert!(config.operator_enabled(OperatorGroup::Comparison));
        assert!(!config.operator_enabled(OperatorGroup::Arithmetic));
    }

    #[test]
    fn project_config_rejects_unknown_operator_group() {
        let error = parse_project_config(r#"operators = ["mystery"]"#).unwrap_err();
        assert!(error.contains("unknown operator group"));
    }

    #[test]
    fn applies_exact_mutation() {
        let source = "pub fn enabled() -> Bool { true }";
        let mutation = scan_source(Path::new("sample.mbt"), source, &ProjectConfig::default())
            .into_iter()
            .next()
            .unwrap();
        let output = apply_mutation(source, &mutation).unwrap();
        assert_eq!(output, "pub fn enabled() -> Bool { false }");
    }

    #[test]
    fn nested_block_comments_are_skipped() {
        let source = "/* true /* + */ && */ false";
        let mutations = scan_source(Path::new("sample.mbt"), source, &ProjectConfig::default());
        assert_eq!(mutations.len(), 1);
        assert_eq!(mutations[0].original, "false");
    }
}
