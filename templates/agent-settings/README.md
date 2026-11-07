Copy `claude-settings.example.json` to `<project>/.claude/settings.json` and `protect-rails.sh` to `<project>/.claude/hooks/`.
Then (a) replace `./run` with the project's wrapper, (b) make sure EVERY command the prompts use is allowed or has an allowed
equivalent - an "ask" entry is a trap for a headless run, (c) open the agent interactively once in the checkout and accept the
trust dialog (otherwise headless runs ignore this file), (d) install the git hooks with `.factory/bin/install-hooks.sh <repo>`
as the human operator, (e) dry-run each command class under the real settings. Other agent CLIs: translate the same intent into
their sandbox/approval configuration.
