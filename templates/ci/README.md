Copy `check-e2e-marker.sh` to `deploy/` in the project and `deploy-workflow.yml` to `.github/workflows/deploy.yml` (or the
equivalent in another CI). Add a test of the guard (a fake tag repo: no tag -> refused; tag for another sha -> refused; passed 0
-> refused; good tag -> accepted; reason given -> allowed and printed). The deploy script itself is the project's; it must be
idempotent, run migrations forward-only, and end with a health check that fails the job when the new version is not serving.
