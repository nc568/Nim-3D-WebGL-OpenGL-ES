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
release creation or automatic merge. Actions are pinned to resolved commit SHAs with Node 24 runtimes. The test
application separately uses Node 22.
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

Local `tools/ci_native.sh` passed before publication. The first remote cold run
[40086402136](https://github.com/nc568/Nim-3D-WebGL-OpenGL-ES/actions/runs/40086402136)
on code commit `39ff34c86a8a350076403a00616dcaa087034cc8` **passed both jobs**:
native 7m24s, browser 10m17s. Artifacts `native-evidence` and `browser-evidence`
were uploaded successfully. The run warned that the original Actions v4 Node 20
runtimes were deprecated; action pins were then upgraded to current Node 24
versions for subsequent runs. See the branch Actions page for the latest run.

Push and Actions run/artifact metadata reads worked through the existing Arena
integration; the token disclosed in chat was not used or saved. Administrative
Actions settings were not changed (the integration returned 403 for reading that
endpoint). No additional permissions were needed for the tested push/read path.
Main has not been modified or merged.
