# Example: how one fault became a 14-hour stall (and which guard now stops each link)

A real cascade, anonymised, to show how faults chain and why every guard exists.

1. **18:00** A delivery's critical run failed with "the stack did not start". Docker had left an undeletable network behind
   from an earlier verification run, so the verification stack name could never start again.
   *Guard: a fresh stack name per run, stuck names skipped, always torn down (`critical-e2e.sh`).*
2. The failure was reported as `CRITICAL-E2E-FAILED`, the same word as a real test failure, so the fix loop (3 attempts per
   story) burned all attempts on three stories and parked them as `DELIVERY-FAILED`.
   *Guard: stack-start failures are distinguishable (exit 2) and the stall watchdog clears the counters; counters renew.*
3. Nobody looked. The coordinator only reacted when the owner asked for status, hours later.
   *Guard: `health.sh` every 30 minutes, acted on without asking; `RELEASE_STALL_MIN` watchdog alerts on its own.*
4. Meanwhile "release first" scheduling paused every new build while three fix runs existed, so development stopped too.
   *Guard: a bound on the fix loop (`PARK_AFTER_MIN`) - parked stories release the queue.*
5. After the fix of the stack names, a mass failure of 45 browser tests ("Target crashed") appeared: the new fresh-name scheme
   left every verification stack running and the VM ran out of memory.
   *Guard: stop leftover verification stacks before and after every run; capacity formula in `factory doctor`.*
6. A "pause the agents during the critical run" measure froze the agent processes but not the test containers they had
   started, so the "idle" machine ran a 570%-CPU suite beside the release.
   *Guard: containers are throttled while paused (`quiet.sh`).*
7. The supervisor's parking rule killed an entire lane, because it matched processes by name and the lane's command line
   listed the parked story.
   *Guard: pid files only; never match by name.*
8. The network went down for 20 minutes at night; the runs returned API errors, which were counted as failed attempts.
   *Guard: `INFRA` results are retried without counting.*

Lesson: each repair was reasonable alone, and several caused the next fault because none was exercised under real load before
being relied on. Hence `selftest.sh`, "run one real delivery after any pipeline change", and the catalog (`08`).
