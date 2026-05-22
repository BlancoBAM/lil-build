#!/bin/bash
# uutils-coreutils wrapper with seamless fallback to GNU coreutils
# This wrapper provides Rust-based uutils commands while falling back
# to GNU coreutils seamlessly when errors occur.

set -e

# Map of uutils commands to their GNU counterparts
declare -A UTILS_MAP=(
    ["ls"]="lsd"
    ["cat"]="bat"
    ["dd"]="dd"
    ["df"]="df"
    ["du"]="du"
    ["echo"]="echo"
    ["env"]="env"
    ["false"]="false"
    ["groups"]="groups"
    ["hostid"]="hostid"
    ["hostname"]="hostname"
    ["id"]="id"
    ["link"]="link"
    ["ln"]="ln"
    ["mkdir"]="mkdir"
    ["mknod"]="mknod"
    ["mv"]="mv"
    ["nohup"]="nohup"
    ["pwd"]="pwd"
    ["rm"]="rm"
    ["rmdir"]="rmdir"
    ["sleep"]="sleep"
    ["sort"]="sort"
    ["stat"]="stat"
    ["sync"]="sync"
    ["touch"]="touch"
    ["true"]="true"
    ["uname"]="uname"
    ["uniq"]="uniq"
    ["wc"]="wc"
    ["whoami"]="whoami"
    ["cp"]="cp"
    ["chmod"]="chmod"
    ["chown"]="chown"
)

# Get the command name (without path)
CMD_NAME="$(basename "$0")"

# Special handling for ls -> lsd
if [ "$CMD_NAME" = "ls" ]; then
    if command -v lsd &> /dev/null; then
        exec lsd "$@"
    else
        exec /bin/ls "$@"
    fi
fi

# Special handling for cat -> bat
if [ "$CMD_NAME" = "cat" ]; then
    if command -v bat &> /dev/null; then
        exec bat "$@"
    else
        exec /bin/cat "$@"
    fi
fi

# For other commands, try uutils first, then fallback
CMD="${UTILS_MAP[$CMD_NAME]}"

if [ -n "$CMD" ]; then
    # Try uutils version first
    if command -v "u$CMD_NAME" &> /dev/null; then
        exec "u$CMD_NAME" "$@" 2>/dev/null || true
    fi
    
    # Try standalone binary if exists
    if command -v "$CMD_NAME.rust" &> /dev/null; then
        exec "$CMD_NAME.rust" "$@"
    fi
fi

# Fallback to GNU coreutils
exec "/bin/$CMD_NAME" "$@"
