///|
fn print_help() -> Unit {
  println(
    (
      #|turtles - mutation testing for MoonBit
      #|
      #|Usage: turtles [OPTIONS]
      #|
      #|Options:
      #|  -d, --dir <PATH>       MoonBit module directory (default: .)
      #|      --timeout <SECS>   Per-command timeout (default: 60)
      #|      --file <TEXT>      Only mutate source paths containing TEXT
      #|      --json <PATH>      Write a JSON report to PATH
      #|      --list             List mutations without running tests
      #|  -h, --help             Print help
    ),
  )
}

///|
fn parse_args() -> Config raise {
  let args = @env.args()
  let mut dir = "."
  let mut timeout_ms = 60000
  let mut list = false
  let mut file_filter : String? = None
  let mut json_report : String? = None
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    match arg {
      "-h" | "--help" => {
        print_help()
        @sys.exit(0)
      }
      "-d" | "--dir" => {
        guard i + 1 < args.length() else { fail("--dir requires a path") }
        i = i + 1
        dir = args[i]
      }
      "--timeout" => {
        guard i + 1 < args.length() else { fail("--timeout requires seconds") }
        i = i + 1
        let seconds = @string.parse_int(args[i]) catch {
          _ => fail("invalid timeout: \{args[i]}")
        }
        guard seconds > 0 else { fail("--timeout must be greater than zero") }
        timeout_ms = seconds * 1000
      }
      "--file" => {
        guard i + 1 < args.length() else { fail("--file requires text") }
        i = i + 1
        file_filter = Some(args[i])
      }
      "--json" => {
        guard i + 1 < args.length() else { fail("--json requires a path") }
        i = i + 1
        json_report = Some(args[i])
      }
      "--list" => list = true
      other => fail("unknown argument: \{other} (try --help)")
    }
    i = i + 1
  }
  { dir, timeout_ms, list, file_filter, json_report, }
}

///|
fn config_is_space(byte : Byte) -> Bool {
  byte == b' ' || byte == b'\t' || byte == b'\n' || byte == b'\r'
}

///|
fn config_skip_space_and_comments(bytes : Bytes, position : Ref[Int]) -> Unit {
  while true {
    while position.val < bytes.length() && config_is_space(bytes[position.val]) {
      position.val = position.val + 1
    }
    if position.val >= bytes.length() || bytes[position.val] != b'#' {
      break
    }
    while position.val < bytes.length() && bytes[position.val] != b'\n' {
      position.val = position.val + 1
    }
  }
}

///|
fn config_error(bytes : Bytes, position : Int, message : String) -> String {
  let mut line = 1
  let mut column = 1
  let mut i = 0
  while i < position && i < bytes.length() {
    if bytes[i] == b'\n' {
      line = line + 1
      column = 1
    } else {
      column = column + 1
    }
    i = i + 1
  }
  "\{message} at \{line}:\{column}"
}

///|
fn config_consume(bytes : Bytes, position : Ref[Int], expected : Byte) -> Bool {
  if position.val < bytes.length() && bytes[position.val] == expected {
    position.val = position.val + 1
    true
  } else {
    false
  }
}

///|
fn config_expect(
  bytes : Bytes,
  position : Ref[Int],
  expected : Byte,
) -> Unit raise {
  guard config_consume(bytes, position, expected) else {
    fail(
      config_error(bytes, position.val, "expected configuration punctuation"),
    )
  }
}

///|
fn config_parse_key(bytes : Bytes, position : Ref[Int]) -> String raise {
  let start = position.val
  while position.val < bytes.length() {
    let byte = bytes[position.val]
    let valid = (byte >= b'a' && byte <= b'z') ||
      (byte >= b'A' && byte <= b'Z') ||
      (byte >= b'0' && byte <= b'9') ||
      byte == b'_' ||
      byte == b'-'
    if !valid {
      break
    }
    position.val = position.val + 1
  }
  guard start != position.val else {
    fail(config_error(bytes, position.val, "expected a configuration key"))
  }
  @utf8.decode(bytes[start:position.val])
}

///|
fn config_parse_string(bytes : Bytes, position : Ref[Int]) -> String raise {
  config_expect(bytes, position, b'"')
  let output = @buffer.Buffer()
  while position.val < bytes.length() {
    let byte = bytes[position.val]
    position.val = position.val + 1
    match byte {
      b'"' => return @utf8.decode(output.to_bytes())
      b'\\' => {
        guard position.val < bytes.length() else {
          fail(config_error(bytes, position.val, "unterminated string escape"))
        }
        let escaped = bytes[position.val]
        position.val = position.val + 1
        match escaped {
          b'"' => output.write_byte(b'"')
          b'\\' => output.write_byte(b'\\')
          b'n' => output.write_byte(b'\n')
          b'r' => output.write_byte(b'\r')
          b't' => output.write_byte(b'\t')
          _ =>
            fail(
              config_error(
                bytes,
                position.val,
                "unsupported string escape; use \", \\\\, \\n, \\r, or \\t",
              ),
            )
        }
      }
      b'\n' | b'\r' =>
        fail(config_error(bytes, position.val, "newline in quoted string"))
      _ => output.write_byte(byte)
    }
  }
  fail(config_error(bytes, position.val, "unterminated quoted string"))
}

///|
fn config_parse_string_array(
  bytes : Bytes,
  position : Ref[Int],
) -> Array[String] raise {
  config_expect(bytes, position, b'[')
  let values : Array[String] = []
  while true {
    config_skip_space_and_comments(bytes, position)
    if config_consume(bytes, position, b']') {
      return values
    }
    values.push(config_parse_string(bytes, position))
    config_skip_space_and_comments(bytes, position)
    if config_consume(bytes, position, b',') {
      continue
    }
    if config_consume(bytes, position, b']') {
      return values
    }
    fail(
      config_error(bytes, position.val, "expected ',' or ']' after array item"),
    )
  }
}

///|
fn parse_project_config(source : String) -> ProjectConfig raise {
  let bytes = @utf8.encode(source)
  let position = Ref(0)
  let include_patterns : Array[String] = []
  let exclude_patterns : Array[String] = []
  let operators : Array[OperatorGroup] = []
  let mut operators_set = false
  let mut include_set = false
  let mut exclude_set = false
  while true {
    config_skip_space_and_comments(bytes, position)
    if position.val >= bytes.length() {
      break
    }
    let key = config_parse_key(bytes, position)
    config_skip_space_and_comments(bytes, position)
    config_expect(bytes, position, b'=')
    config_skip_space_and_comments(bytes, position)
    let values = config_parse_string_array(bytes, position)
    match key {
      "include" => {
        guard !include_set else {
          fail(config_error(bytes, position.val, "duplicate include key"))
        }
        include_set = true
        for value in values {
          include_patterns.push(value)
        }
      }
      "exclude" => {
        guard !exclude_set else {
          fail(config_error(bytes, position.val, "duplicate exclude key"))
        }
        exclude_set = true
        for value in values {
          exclude_patterns.push(value)
        }
      }
      "operators" => {
        guard !operators_set else {
          fail(config_error(bytes, position.val, "duplicate operators key"))
        }
        operators_set = true
        for value in values {
          operators.push(operator_group_from_string(value))
        }
      }
      other =>
        fail(
          config_error(
            bytes,
            position.val,
            "unknown key \{other}; expected include, exclude, or operators",
          ),
        )
    }
  }
  {
    include_patterns,
    exclude_patterns,
    operators: if operators_set {
      Some(operators)
    } else {
      None
    },
  }
}

///|
async fn load_project_config(root : String) -> ProjectConfig {
  let path = @path.Path(root).join(Path("turtles.toml")).to_string()
  if !@fs.exists(path) {
    return default_project_config()
  }
  let source = @fs.read_file(path).text()
  parse_project_config(source) catch {
    error => fail("invalid \{path}: \{error}")
  }
}
