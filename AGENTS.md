# Software factory (for coding agents)

This repository is an agent skill. Read `SKILL.md` first; it is the entry point and lists the phases, the hard rules and where
everything else is. Short version: discovery with the human -> research and plan -> foundations -> walking skeleton -> run
the factory (`scripts/factory`) -> operate. Use `scripts/selftest.sh` to prove the scripts on this machine. Never put
project-specific or machine-specific content or secrets into this repository; project settings live in the target
project's `.factory/factory.conf`.
