# GitHub Actions: graphics validation

Workflow: `.github/workflows/graphics.yml` (`Graphics validation`).

## Matrix

- **Browser / ubuntu-24.04:** pinned Nim 2.2.4 bootstrap, GCC + Node CPU tests,
  pure JS builds and hot-path codegen guards, Chromium WebGL1/2 GPU fixtures,
  five demo/fallback/fossil UI scenarios, lifecycle/input/resize tests,
  synthetic GPU autoscale and real timer-query smoke tests.
- **Native / ubuntu-24.04:** GCC and LLVM (Zig 0.13.0), patched Nim → cproc/QBE,
  CPU suites and real GLES2/3 ANGLE/SwiftShader pbuffer fixtures; release LLVM/QBE
  GPU fixtures; ARM64 cross-link and ELF-header check (NOT ARM execution).
- Logs, browser screenshots and timing report are retained as workflow artifacts
  for 14 days, including logs of failed stages. No binaries/toolchain archives
  or credentials are uploaded as artifacts.

This is software GPU testing, not physical/mobile GPU performance acceptance,
visible native-window testing, or complete Nim compiler regression testing.
Timing values have no performance threshold and do not prove a speedup.

## Triggers and permissions

Push to `main` or `arena/**`, pull requests, and manual workflow dispatch.
Only `contents: read` is granted to jobs. Checkout does not persist credentials;
there is no `pull_request_target`, PAT secret, elevated GitHub token, deployment,
release creation or automatic merge. Actions are pinned to resolved commit SHAs.
Dependencies/toolchain sources remain at the repository's documented pins.

A workflow_dispatch workflow normally needs to exist on the default branch to
appear in the Actions UI; the initial branch validation uses the push trigger.
Changes on the session branch do not modify main or establish branch protection.
Repository/organization policy may require enabling Actions or approving runs.

The Arena GitHub integration is used for git push and reading run results. Do not
paste credentials into chat or put them in workflow files. A disclosed PAT should
be revoked in GitHub settings; rotate it only through the platform's secure
connection flow if a replacement is actually needed.

## Caches / reproduction

Each job uses a separate toolchain cache keyed by OS/architecture, bootstrap
script and compiler patch. No broad restore-key fallback is used across patch
versions. A cold Nim bootstrap can take several minutes. Bootstrap skips an
existing usable compiler and checks pinned source revisions; cproc patch checking
is idempotent but an incompatible dirty checkout is rejected, not overwritten.

Native runner entry point is also usable locally after bootstrap:

```sh
./tools/bootstrap.sh nim
./tools/bootstrap.sh cproc
./tools/bootstrap.sh llvm
./tools/bootstrap.sh native-driver
./tools/ci_native.sh
```

Browser prerequisites/build commands are in README and `tools/test.sh`; the CI
step starts an HTTP server, waits for a successful response with a bounded check,
runs the tests, and terminates its own server on exit. It uses `pipefail` so tee
cannot hide failures. Native commands save individual logs and preserve exit codes.

## Initial rollout

Local `tools/ci_native.sh` passed before publication. Remote rollout status and
run link will be recorded after attempting the push; repository metadata access
does not by itself establish workflow-write permissions. Administrative Actions
settings were not changed (the integration returned 403 for reading that endpoint).
