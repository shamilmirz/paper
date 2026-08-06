#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_DIR="${INSTALL_DIR:-/home/server2/stage5g-schema-acceptance-harness}"

bash "$SCRIPT_DIR/install.sh"

TARGET="$INSTALL_DIR/run_acceptance.sh"
[[ -f "$TARGET" ]] || {
    printf 'missing installed harness: %s\n' "$TARGET" >&2
    exit 1
}

python3 - "$TARGET" <<'PY'
from pathlib import Path
import os
import sys
import tempfile

target = Path(sys.argv[1])
text = target.read_text(encoding="utf-8")
old = '''ACCEPTED_STAGE5G_BASE_SHA="$ACCEPTED_STAGE5G_BASE_SHA" \\
REQUIRED_SHA="$REQUIRED_SHA" \\
"$PYTHON" - <<'PY'\nimport os\nimport re\nimport subprocess\nfrom pathlib import Path\n\naccepted = os.environ["ACCEPTED_STAGE5G_BASE_SHA"]\nrequired = os.environ["REQUIRED_SHA"]\n'''
new = '''STAGE5G_ACCEPTED_BASE_SHA="$ACCEPTED_STAGE5G_BASE_SHA" \\
STAGE5G_REQUIRED_SHA="$REQUIRED_SHA" \\
"$PYTHON" - <<'PY'\nimport os\nimport re\nimport subprocess\nfrom pathlib import Path\n\naccepted = os.environ["STAGE5G_ACCEPTED_BASE_SHA"]\nrequired = os.environ["STAGE5G_REQUIRED_SHA"]\n'''

if text.count(old) != 1:
    raise SystemExit("expected readonly-conflict block not found exactly once")

patched = text.replace(old, new, 1)
fd, temporary = tempfile.mkstemp(prefix=".run_acceptance.sh.", dir=str(target.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
        handle.write(patched)
    os.chmod(temporary, 0o700)
    os.replace(temporary, target)
except BaseException:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
PY

printf '%s  %s\n' \
  'd60ddf74eed1fb6a0baca1c4ceb200280a5b29e2fb088708869315b85e29a53d' \
  "$TARGET" | sha256sum --check --strict -

bash -n "$TARGET"
printf 'Stage 5G server2 harness v3 installed: readonly environment collision fixed.\n'
