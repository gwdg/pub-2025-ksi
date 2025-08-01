#!/usr/bin bash
set -euo pipefail

# Location of the real binary.  Change if you moved it elsewhere.
REAL=/usr/local/bin/nerdctl.real

# Log file
LOG_FILE="$HOME/nerdctl-wrapper.log"

log_cmd() {
  qcmd=$(printf "%q " "$@")
  printf "nerdctl %s\n" "$qcmd" >> "$LOG_FILE"
}

log_cmd "$@"

# No sub-command given? -> just exec the real binary.
[[ $# -eq 0 ]] && exec "$REAL"

# $1 is the sub-command (‘run’, ‘pull’, ‘container ls’, …)
if [[ "$1" == "run" ]]; then
    # Insert the annotation immediately after the sub-command.
    shift
    filtered_args=()
    skip_next=0
    for arg in "$@"; do
        # If the previous argument was "--security-opt", skip the value too
        if (( skip_next )); then
            skip_next=0
            continue
        fi

        case "$arg" in
            # Two-token form:  --security-opt  seccomp=unconfined
          --security-opt)
            skip_next=1         # suppress the following token
            continue            # suppress this token, too
            ;;
            # One-token form:  --security-opt=seccomp=unconfined
          --security-opt=seccomp=unconfined)
            continue            # suppress this token
            ;;
        esac

        # Anything else: keep it
        filtered_args+=("$arg")
    done

    qcmd=$(printf "%q " "${filtered_args[@]}")
    printf "[WRAPPER] RUN COMMAND detected - altering to:\n[WRAPPER] nerdctl run --annotation nerdctl/bypass4netns=true --annotation nerdctl/bypass4netns-ignore-bind=true --security-opt apparmor=unconfined %s\n" "$qcmd" >> "$LOG_FILE"
    exec "$REAL" "run" "--annotation" "nerdctl/bypass4netns=true" "--annotation" "nerdctl/bypass4netns-ignore-bind=true" "--security-opt" "apparmor=unconfined" "${filtered_args[@]}"
else
    # Any other nerdctl invocation: pass through unchanged.
    exec "$REAL" "$@"
fi
