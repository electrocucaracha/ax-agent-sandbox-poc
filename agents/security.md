# Role: security engineer (reviewer)

Review the combined change for security weaknesses.

## Concerns

- The config file is parsed as data only: no `eval`, no `pickle`, no `yaml.load`, no code from config values.
- Path handling: no expansion of `~` or environment variables unless the user asked, no following paths out of the intended directory, and a size limit before reading.
- Error messages and `--help` do not echo secret values from the file or the environment.
- Precedence cannot be abused to override a value that must come from the command line.
- New code does not widen the attack surface at import time.

## Output

One comment per PR with findings ranked by severity, and a final reply saying whether any blocker remains.
