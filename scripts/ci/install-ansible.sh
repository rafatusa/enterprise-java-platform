#!/usr/bin/env bash
# Ensure ansible-core and the collections this project uses are available ON
# PATH. Shared by the configure and verify stages so a fix reaches every caller.
#
# WHY THIS SCRIPT EXISTS (attempt 10 failed exactly here, exit 127):
#   The previous inline version ran
#       pipx install ansible-core
#       ~/.local/bin/ansible-galaxy collection install ...
#   GitHub's ubuntu-24.04 runner image ships ansible-core PRE-INSTALLED, in
#   /opt/pipx/venvs/ansible-core, with its binaries already on PATH. So:
#     - `pipx install ansible-core` correctly refused ("already seems to be
#       installed") and installed nothing;
#     - ~/.local/bin/ansible-galaxy — the path pipx uses only when IT performs
#       the install — never existed;
#     - the step died with "No such file or directory" / exit 127 even though a
#       perfectly good ansible was two directories away and on PATH.
#
#   THE RULE: invoke a tool through PATH. Hardcoding an installer's private
#   prefix couples you to WHERE a tool came from, and breaks the moment the
#   runner image already provides it. Install only if the binary is genuinely
#   missing, then let PATH resolve it.
set -euo pipefail

# --- ansible-core -----------------------------------------------------------
if command -v ansible-playbook >/dev/null 2>&1 && command -v ansible-galaxy >/dev/null 2>&1; then
  echo "ansible-core already present on PATH: $(command -v ansible-playbook)"
else
  echo "ansible-core not found on PATH — installing with pipx."
  pipx install ansible-core

  # pipx installs into ~/.local/bin, which is NOT always on PATH in a
  # non-interactive CI shell. Add it for this step and for every later step in
  # the job, then re-check rather than assuming success.
  export PATH="${HOME}/.local/bin:${PATH}"
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "${HOME}/.local/bin" >> "$GITHUB_PATH"
  fi
fi

# Fail LOUDLY and specifically if the tool still is not resolvable, rather than
# letting a later playbook step die with a bare 127.
for binary in ansible-playbook ansible-galaxy; do
  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "::error::${binary} is not on PATH after installation. Ansible cannot run."
    echo "Checked PATH: ${PATH}"
    exit 1
  fi
done

echo "ansible-playbook: $(command -v ansible-playbook)"
ansible-playbook --version | head -1

# --- collections ------------------------------------------------------------
# ansible-core ships NO third-party collections. The playbooks use
# community.general and community.postgresql, and ansible resolves every module
# BEFORE the first task runs — so a missing collection fails the whole play
# instantly with "couldn't resolve module/action", not partway through.
#
# --upgrade keeps this idempotent: if the runner image already carries a
# version, it is refreshed rather than erroring or being silently skipped.
echo "Installing Ansible collections."
ansible-galaxy collection install --upgrade community.general community.postgresql

echo "Installed collections:"
ansible-galaxy collection list 2>/dev/null | grep -E 'community\.(general|postgresql)' || true
