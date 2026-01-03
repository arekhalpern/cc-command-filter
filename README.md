# cc-command-filter

A Claude Code hook that automatically intercepts verbose terminal commands, saves full output to a log file, and returns concise summaries to the AI - **saving 95%+ tokens** on build commands, package installs, and test runs.

## The Problem

AI coding agents like Claude Code consume tokens for every character of terminal output. Verbose commands waste thousands of tokens:

| Command | Typical Output | Tokens Wasted |
|---------|---------------|---------------|
| `npm install` | 50+ lines of package trees | 2-5k |
| `docker compose build` | Hundreds of lines of layer downloads | 5-15k |
| `cargo build` | Compilation progress for every crate | 3-10k |
| `pytest` | Test results for every test | 2-10k |

**Real example**: `docker compose build --no-cache` produced ~7,000 tokens of output. The useful information was just "build succeeded."

## The Solution

This hook:
1. Intercepts verbose commands before they run
2. Executes them and saves full output to `~/.command-filter/latest.log`
3. Returns a concise summary to Claude (e.g., "npm install succeeded. added 47 packages. 0 vulnerabilities.")
4. You can view the full output anytime with `cat ~/.command-filter/latest.log`

## Installation

### 1. Clone or download the hook

```bash
# Clone this repo
git clone https://github.com/arekhalpern/cc-command-filter.git ~/.cc-command-filter

# Or just download the hook script
mkdir -p ~/.cc-command-filter/hooks
curl -o ~/.cc-command-filter/hooks/smart-bash-hook.sh \
  https://raw.githubusercontent.com/arekhalpern/cc-command-filter/main/hooks/smart-bash-hook.sh
chmod +x ~/.cc-command-filter/hooks/smart-bash-hook.sh
```

### 2. Configure Claude Code

Add the hook to your Claude Code settings. Edit `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.cc-command-filter/hooks/smart-bash-hook.sh",
            "timeout": 300
          }
        ]
      }
    ]
  }
}
```

### 3. (Optional) Auto-allow verbose commands

To skip permission prompts for common verbose commands, add these to your settings:

```json
{
  "permissions": {
    "allow": [
      "Bash(npm install:*)",
      "Bash(npm ci:*)",
      "Bash(yarn install:*)",
      "Bash(pnpm install:*)",
      "Bash(docker compose:*)",
      "Bash(docker build:*)",
      "Bash(cargo build:*)",
      "Bash(cargo test:*)",
      "Bash(pip install:*)",
      "Bash(pytest:*)",
      "Bash(make:*)",
      "Bash(go build:*)",
      "Bash(go test:*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.cc-command-filter/hooks/smart-bash-hook.sh",
            "timeout": 300
          }
        ]
      }
    ]
  }
}
```

### 4. Restart Claude Code

Settings take effect after restart.

## Usage

Just use Claude Code normally. When Claude runs a verbose command:

**Before (without cc-command-filter):**
```
> npm install

added 847 packages, and audited 848 packages in 12s

134 packages are looking for funding
  run `npm fund` for details

12 vulnerabilities (1 low, 7 moderate, 4 high)

To address issues that do not require attention, run:
  npm audit fix

To address all issues (including breaking changes), run:
  npm audit fix --force

Run `npm audit` for details.
```
*(~500 tokens)*

**After (with cc-command-filter):**
```
> npm install

npm install succeeded. added 847 packages. 12 vulnerabilities. in 12s (View full: cat ~/.command-filter/latest.log)
```
*(~30 tokens)*

## Supported Commands

The hook intercepts these verbose command patterns:

| Category | Commands |
|----------|----------|
| **Node.js** | `npm install`, `npm ci`, `yarn install`, `pnpm install`, `npm run build` |
| **Docker** | `docker compose build`, `docker compose up`, `docker build` |
| **Rust** | `cargo build`, `cargo test`, `cargo run`, `cargo clippy` |
| **Python** | `pip install`, `poetry install`, `pipenv install`, `pytest` |
| **Go** | `go build`, `go test`, `go mod` |
| **Build tools** | `make`, `cmake`, `ninja`, `gradle`, `mvn` |
| **Testing** | `jest`, `vitest`, `mocha`, `ava` |
| **Other** | `kubectl logs`, `terraform plan`, `git clone`, `bundle install` |

## Viewing Full Output

Full command output is always saved:

```bash
# View the most recent command output
cat ~/.command-filter/latest.log

# List all saved logs
ls ~/.command-filter/output_*.log

# View a specific log
cat ~/.command-filter/output_20240115_143022.log
```

## How It Works

1. **PreToolUse Hook**: Claude Code calls the hook before running any Bash command
2. **Pattern Matching**: Hook checks if the command matches verbose patterns
3. **Execute & Capture**: Hook runs the command and saves output to log file
4. **Smart Extraction**: Hook extracts key information (success/failure, package counts, errors)
5. **Return Summary**: Hook outputs JSON that replaces the command with an `echo` of the summary

The hook uses Claude Code's `updatedInput` feature to modify the Bash command before execution.

## Customization

### Adding New Command Patterns

Edit the hook script and add patterns to the verbose detection section:

```bash
elif [[ "$command" =~ ^your-command-pattern ]]; then
  is_verbose=true
  command_type="your_type"
```

Then add a case in the summary extraction:

```bash
your_type)
  if [ $exit_code -eq 0 ]; then
    summary="Your command succeeded."
  else
    summary="Your command failed (exit $exit_code)."
  fi
  ;;
```

### Changing Log Location

Edit the `LOGS_DIR` variable at the top of the hook:

```bash
LOGS_DIR="$HOME/.command-filter"  # Change this
```

## Compatibility

- **Claude Code**: Tested with v2.0.x+
- **Other MCP Clients**: Should work with any client that supports PreToolUse hooks
- **Operating Systems**: macOS, Linux (Windows untested)
- **Shell**: Bash required

## Troubleshooting

### Hook not intercepting commands

1. Check settings are valid JSON: `cat ~/.claude/settings.json | jq .`
2. Verify hook path is correct and executable: `ls -la ~/.cc-command-filter/hooks/`
3. Restart Claude Code after settings changes

### Commands failing

1. Check log for errors: `cat ~/.command-filter/latest.log`
2. Verify hook has execute permission: `chmod +x ~/.cc-command-filter/hooks/smart-bash-hook.sh`

### Compound commands not intercepted

Commands like `cd /path && npm install` are not intercepted because they start with `cd`, not `npm`. This is intentional - the hook uses prefix matching for simplicity.

## License

MIT

## Credits

Built with Claude Code. Inspired by the need to stop burning tokens on `npm install` output.
