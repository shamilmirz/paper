# Stage 5G server2 acceptance harness

This directory contains the verified, self-contained installer for the external Stage 5G PostgreSQL acceptance run.

## Fixed target

```text
Repository: shamilmirz/paper-trading-engine
Branch: stage/05-trading-core
Required SHA: 4c961194204be362f8847cb9421c6e2dff6b3d5c
PostgreSQL image: postgres:16.4
```

## Install

```bash
bash acceptance/stage5g-server2/install.sh
```

The installer creates:

```text
/home/server2/stage5g-schema-acceptance-harness/run_acceptance.sh
/home/server2/stage5g-schema-acceptance-harness/cleanup.sh
```

It verifies both generated files with SHA-256 and `bash -n` before installation.

Expected generated-file hashes:

```text
a3c41bec87b5b2a105cd107e3650420dfc0a6d78536120e54924b473e4521b2f  run_acceptance.sh
ec2d7982db1e2292305ca626bdc98d793911075d1da30b4e8672cbf025665d1d  cleanup.sh
```

## Run

```bash
cd /home/server2/stage5g-schema-acceptance-harness
./run_acceptance.sh
```

Do not edit the generated scripts. Do not run against production or `monitor-data`. The protected checkout `/home/server2/paper-trading-engine` must remain unchanged.
