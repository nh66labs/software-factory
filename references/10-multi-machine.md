# 10 - Scaling out: several machines

One machine is limited by two things: how many full stacks fit (memory/CPU) and the **single serial resource - the critical run
of each delivery**. More lanes on the same machine make every run slower and flakier; more machines make them parallel.

## Capacity formula (per machine)
parallel story stacks <= min(cores / 3, (RAM_GB - 2) / STACK_MEM_GB), plus one verification stack. `factory doctor` prints it.
Measure `STACK_MEM_GB` from a real stack (database + services + browser containers; 3-6 GB is typical). Disk: 200 GB+ NVMe,
build caches on it. Bare metal or a thin VM; no desktop environment; wired network; always on.

## Roles
| Role | Machine | Runs |
|---|---|---|
| **builder** | N machines | lane drivers + story stacks + gate (`VERIFY_MODE=remote`) |
| **verifier** | 1+ machines, quiet | `verifier-daemon.sh`: critical tests, nothing else running |
| **integrator** | 1 machine (can be a builder) | `deliver.sh` (rebase, merge, push, release), supervisor of record |
| **coordinator** | the interactive session | health loop, decisions |
The git remote is the only bus; machines never need to reach each other.

## Remote verification (implemented)
1. A builder's delivery rebases the story and offers the commit: `refs/factory/candidates/<sha>` pushed to the remote.
2. `verifier-daemon.sh` (on the verifier) fetches candidates, runs `record-critical.sh` locally (fresh stack, no retries),
   and answers: tag `e2e-critical/<sha>` on a pass, an annotated tag stored at `refs/factory/rejected/<sha>` whose message holds
   the failing tests on a failure.
3. The delivery waits (`VERIFY_TIMEOUT_MIN`), then merges and releases on a pass, or hands the rejection text to a fix run.
4. Builders therefore never run the critical set; their quiet-pause is unnecessary, and a delivery no longer stops other lanes.
Set `VERIFY_MODE=remote` on builders, `FACTORY_VERIFIER=1` and `VERIFY_MODE=local` on the verifier.

## Splitting work
Each builder machine gets its own `queues/` (lanes) of different epics (fewer conflicts). Only one machine integrates
(delivery lock lives in that checkout); the others push the story branch and call the integrator (`factory deliver <story>` over
SSH) or run the integrator role on a schedule. If two machines must deliver, give each its own clone but keep ONE writer of the
integration branch: use the remote's branch protection (non-fast-forward rejected) and let the loser rebase and retry.

## Provisioning checklist (Ubuntu Server, per machine)
- Ubuntu Server LTS, minimal install + OpenSSH; Docker Engine + compose plugin; git, python3, `gh`/the host CLI logged in;
  the agent CLI installed, logged in, and its trust dialog accepted in the project checkout; SSH key for the operator.
- Performance: CPU governor `performance`; test database data on tmpfs when throwaway (faster, spares the disk); swap small;
  `vm.max_map_count` etc. only if a service needs it; time sync on; unattended upgrades off during runs.
- Disk layout: one large volume; docker data-root on it; cron or systemd timers for the janitor if you do not use `factory start`.
- Services: `systemd` units for supervisor and janitor with `Restart=always` (example below).
- Security: dedicated user, no personal credentials on the box, firewall allowing only SSH from the operator network.
- Verify: `scripts/selftest.sh`, `factory doctor`, a real walking-skeleton delivery.

```
# /etc/systemd/system/factory-supervisor.service
[Unit] Description=software factory supervisor
After=network-online.target docker.service
[Service] User=factory
WorkingDirectory=/srv/project/.factory/bin
ExecStart=/srv/project/.factory/bin/supervisor.sh
Restart=always
RestartSec=10
[Install] WantedBy=multi-user.target
```
(Same for `janitor.sh`, and `verifier-daemon.sh` on the verifier.)

## Failure modes specific to farms
Clock skew (tags and "age" logic) - keep NTP on. Different image caches - a cold build on a new machine is slow; warm it once.
Two machines sharing one remote token hit rate limits - use a token per machine. A verifier that falls behind - alert when a
candidate waits > 30 minutes. Divergent tooling versions - the project carries its scripts (`.factory/bin`) and pins images.

## Estimating the gain
Throughput is roughly N builders until the verifier or the integration serialisation saturates; expect 60-80% scaling at 3
machines, less beyond until verification is parallelised across verifiers (several `verifier-daemon.sh` instances claim
different candidates by a ref lock - add when needed). Measure before promising.
