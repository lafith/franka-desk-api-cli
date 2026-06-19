#!/usr/bin/env bash
set -euo pipefail

MODE="user"
ACTION="install"
LINK_MODE="auto"
DRY_RUN=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FRANKA_SRC="$SCRIPT_DIR/franka"

usage() {
  cat <<'EOF'
usage: ./install.sh [options]

Options:
  --user              Install for the current user. Default.
  --system            Install systemwide for all users. Requires sudo.
  --uninstall         Remove installed CLI and completion.
  --symlink           Install CLI as a symlink to this checkout.
  --copy              Install CLI as a copied executable.
  --dry-run           Print actions without changing files.
  -h, --help          Show help.

Examples:
  ./install.sh --user
  ./install.sh --system --copy
  ./install.sh --uninstall --user
  ./install.sh --uninstall --system

Defaults:
  --user installs a symlink.
  --system installs a copy.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

check_source() {
  [[ -f "$FRANKA_SRC" ]] || die "franka not found next to install.sh"
  [[ -x "$FRANKA_SRC" ]] || die "franka is not executable"
  bash -n "$FRANKA_SRC"
}

install_user() {
  local bin_dir completion_dir target completion_target
  bin_dir="${HOME}/.local/bin"
  completion_dir="${HOME}/.local/share/bash-completion/completions"
  target="${bin_dir}/franka"
  completion_target="${completion_dir}/franka"

  run mkdir -p "$bin_dir" "$completion_dir"

  if [[ "$LINK_MODE" == "copy" ]]; then
    run install -m 0755 "$FRANKA_SRC" "$target"
  else
    run ln -sfn "$FRANKA_SRC" "$target"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+ %q completion bash > %q\n' "$FRANKA_SRC" "$completion_target"
  else
    "$FRANKA_SRC" completion bash > "$completion_target"
  fi

  printf 'installed franka for user: %s\n' "$USER"
  printf 'cli: %s\n' "$target"
  printf 'completion: %s\n' "$completion_target"
  printf 'configure connection settings with: franka setup\n'
  if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
    printf 'warning: %s is not on PATH; add this to ~/.bashrc:\n' "$bin_dir" >&2
    printf 'export PATH="$HOME/.local/bin:$PATH"\n' >&2
  fi
  printf 'open a new shell for completion to load\n'
}

install_system() {
  local target completion_target effective_link_mode
  target="/usr/local/bin/franka"
  completion_target="/etc/bash_completion.d/franka"
  effective_link_mode="$LINK_MODE"
  [[ "$effective_link_mode" == "auto" ]] && effective_link_mode="copy"

  printf 'warning: system install makes the CLI available to all users.\n' >&2
  printf 'warning: each user should run franka setup to create their own config.\n' >&2

  if [[ "$effective_link_mode" == "symlink" ]]; then
    run sudo ln -sfn "$FRANKA_SRC" "$target"
  else
    run sudo install -m 0755 "$FRANKA_SRC" "$target"
  fi

  run sudo mkdir -p "$(dirname "$completion_target")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+ %q completion bash | sudo tee %q >/dev/null\n' "$FRANKA_SRC" "$completion_target"
  else
    "$FRANKA_SRC" completion bash | sudo tee "$completion_target" >/dev/null
  fi

  printf 'installed franka systemwide\n'
  printf 'cli: %s\n' "$target"
  printf 'completion: %s\n' "$completion_target"
  printf 'configure connection settings with: franka setup\n'
  printf 'open a new shell for completion to load\n'
}

uninstall_user() {
  local target completion_target
  target="${HOME}/.local/bin/franka"
  completion_target="${HOME}/.local/share/bash-completion/completions/franka"
  run rm -f "$target" "$completion_target"
  printf 'removed user install for %s\n' "$USER"
}

uninstall_system() {
  local target completion_target
  target="/usr/local/bin/franka"
  completion_target="/etc/bash_completion.d/franka"
  run sudo rm -f "$target" "$completion_target"
  printf 'removed systemwide install\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) MODE="user"; shift ;;
    --system) MODE="system"; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --symlink) LINK_MODE="symlink"; shift ;;
    --copy) LINK_MODE="copy"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

if [[ "$ACTION" == "install" ]]; then
  check_source
fi

case "$ACTION:$MODE" in
  install:user) install_user ;;
  install:system) install_system ;;
  uninstall:user) uninstall_user ;;
  uninstall:system) uninstall_system ;;
  *) die "unsupported action/mode: $ACTION/$MODE" ;;
esac
