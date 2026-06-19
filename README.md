# franka - Franka Desk API CLI

Unix Bash CLI for operating and maintaining Franka FR3 systems through the Desk
API using `curl` underneath. It is designed for NUC-side operations and
maintenance scripts where a small, inspectable shell tool is easier to deploy
than a language-specific client or robot-control stack.

The tool wraps common Desk API actions as operator-friendly subcommands, keeps
robot connection settings and SPoC token state in per-user config, and provides
a `raw` command for any endpoint that needs an exact request body.

Named commands print operator-friendly output by default. Use `--json` for raw
JSON from named read commands, and use `raw` when you need exact low-level
request/response behavior.

## Requirements

- `bash`
- `curl`
- standard Unix tools: `sed`, `tr`, `grep`, `paste`, `mktemp`

No Python, Node, package install, or virtual environment is required.

## Install

Install the CLI and Bash completion for the current user:

```sh
./install.sh --user
```

Install systemwide for all users:

```sh
./install.sh --system --copy
```

Open a new shell after installing completion. Systemwide install requires
`sudo` and makes the CLI available to all users. Connection settings are
per-user; each account should run `franka setup`.

Manual user install is also possible:

```sh
mkdir -p ~/.local/bin ~/.local/share/bash-completion/completions
ln -sfn "$PWD/franka" ~/.local/bin/franka
./franka completion bash > ~/.local/share/bash-completion/completions/franka
```

You can also run the CLI directly from this checkout without installing it:

```sh
./franka --help
./franka setup
```

## Setup

After installing, configure the robot connection once for the current user:

```sh
franka setup
```

Or provide the settings non-interactively:

```sh
franka setup --host <robot-ip> --username <desk-user> --password '<password>' --insecure
```

Show the effective setup without printing the password:

```sh
franka setup --show
```

`franka setup` writes:

```text
~/.config/franka-deskapi/config
```

with `0600` permissions. The SPoC control token is stored separately at
`~/.config/franka-deskapi/control-token` by default.

The precedence for connection settings is:

```text
command-line flags > environment variables > setup config > built-in defaults
```

So this uses the setup config:

```sh
franka system state
```

and this overrides them for one command:

```sh
franka --host <robot-ip> --username <desk-user> --password '<password>' system state
```

Environment variables also override the setup config:

```sh
export FRANKA_DESKAPI_HOST=https://<robot-hostname-or-ip>
export FRANKA_DESKAPI_USER=<username>
export FRANKA_DESKAPI_PASSWORD=<password>
```

The setup default disables TLS certificate verification for self-signed robot
certificates. Use `franka setup --secure` if the NUC trusts the robot
certificate, or pass `--secure` for one command.

## Run

```sh
franka --help
franka status
franka system --help
franka safety --help
```

## Examples

```sh
# Current system state. Use --json for the raw Desk API response.
franka system state

# One-screen robot and CLI token summary
franka status

# Convenience workflows
franka on      # unlock arm if needed, then activate FCI
franka lock    # deactivate FCI if needed, then lock arm

# Watch system state over server-sent events
franka system watch

# Take SPoC control token and save it for later commands.
# Sends {"owner":"<hostname>","timeout":1} by default. Token value is hidden.
franka control take

# Show the token only when you explicitly need to copy it elsewhere.
franka control take --show-token

# Or set the owner explicitly
franka control take --owner robot-nuc

# Wait longer for another user to grant control, or omit the API timeout.
franka control take --request --wait 30
franka control take --request --wait none

# Show token state
franka control state

# Low-level unlock and lock joints
franka arm unlock
franka arm lock

# Start an arm motion with an API-specific JSON body.
franka arm motion-start --body @motion.json

# End effector power
franka end-effector power
franka end-effector power-on
franka end-effector power-off

# FCI
franka fci state
franka fci activate
franka fci deactivate

# Self tests
franka safety self-tests
franka safety execute-self-tests

# Recovery status and recovery operations
franka safety recovery
franka safety recovery-start --type JointLimitViolation
franka safety recovery-confirm --type JointLimitViolation

# Low-level escape hatch
franka raw GET /api/system
franka raw PATCH /api/configuration --body @configuration.patch.json
```

Shutdown and reboot require confirmation:

```sh
franka system reboot
franka system reboot --yes
franka system shutdown --yes
```

The CLI intentionally does not expose a factory-reset command.

## Activate FCI From A NUC

If the NUC is connected to the Franka C2/shop-floor port and can reach the
robot Desk API:

```sh
./franka control take
./franka on
./franka fci state
```

`franka on` is equivalent to `franka arm unlock` followed by
`franka fci activate`, with idempotent state checks. `franka lock` runs
`franka fci deactivate` followed by `franka arm lock`.

If `fci activate` returns `ActionUnavailable` with `BrakesClosed`, run
`arm unlock` first. By default, `control take` uses the NUC hostname as the Desk
API `owner`. If another owner already holds the token, `control take` reports
the current owner and exits without waiting; use `--request --wait SECONDS` to
request a transfer and wait longer. The SPoC token from `control take` is saved under
`~/.config/franka-deskapi/control-token` and reused automatically.

## SPoC Control Token

`franka control take` stores the returned token in
`~/.config/franka-deskapi/control-token` when it can identify the token field in
the JSON response. It also stores the token ID beside it, so a repeated
`control take` can tell when the saved token already matches the robot's active
token. Later commands automatically add the token as `X-Control-Token`.

Token values are hidden by default. Use `control take --show-token` or
`franka --json control take` only when the token value is needed.

The default control-token request timeout can be changed with:

```sh
export FRANKA_DESKAPI_CONTROL_TAKE_TIMEOUT=5
```

You can also pass a token explicitly:

```sh
franka --control-token "$TOKEN" arm unlock
```

or disable token-file loading:

```sh
franka --no-token-file arm unlock
```

Commands that require SPoC check the current token state first. If the local
token is missing or stale, they report who currently owns control and suggest
the next command instead of failing with only an HTTP error.

Idempotent commands such as `arm lock`, `arm unlock`, `fci activate`,
`fci deactivate`, and end-effector power commands check current state first and
report `already ...` when no robot action is needed.

## Request Bodies

Commands that accept JSON request bodies use `--body`. The body is passed
directly to `curl` as JSON:

```sh
franka config patch --body '{"network":{...}}'
franka config initial --body @initial-config.json
franka raw POST /api/system/operating-mode:change --body @mode.json
```

Use `--body -` to read JSON from standard input.

## Recovery Motions

Recovery motion endpoints require close supervision at the robot. The CLI
provides direct commands for start, continue, and stop:

```sh
franka safety joint-motion-start --body @joint-motion.json
franka safety joint-motion-continue --token "$CONTINUATION_TOKEN"
franka safety joint-motion-stop
```

If your Desk API response uses a different continuation-token JSON field, pass
`--token-key`, or provide the exact payload with `--body`.

For the Desk API 500 ms continuation-token requirement, prefer scripting around
`raw` or direct commands on a low-latency network and keep the external enabling
device procedure under manual control as described by Franka.
