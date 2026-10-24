#!/bin/bash
# Operator-run probe of the `security`-based Keychain read path (A10). Never run by a helper.
# Creates and deletes scratch items named limitaur-probe-<uuid> in the login keychain.
# Usage: scripts/keychain-acl-probe.sh [path-to-Limitaur-binary]
set -u
BIN="${1:-dist/Limitaur.app/Contents/MacOS/Limitaur}"
KC="$HOME/Library/Keychains/login.keychain-db"
SERVICES=()
FAILED=0

# Delete every tracked item, then verify each is gone (find-generic-password exits 44 for a missing item).
cleanup() {
    local service status
    [[ ${#SERVICES[@]} -gt 0 ]] || return 0
    for service in "${SERVICES[@]}"; do
        /usr/bin/security delete-generic-password -a "$USER" -s "$service" "$KC" >/dev/null 2>&1
    done
    for service in "${SERVICES[@]}"; do
        /usr/bin/security find-generic-password -a "$USER" -s "$service" "$KC" >/dev/null 2>&1
        status=$?
        if [[ $status -ne 44 ]]; then
            echo "cleanup: FAILED ($service still present or unverifiable, status $status)"; FAILED=1
        fi
    done
    SERVICES=()
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

newservice() { echo "limitaur-probe-$(uuidgen | tr 'A-Z' 'a-z')"; }

# read_expect STEP SERVICE EXPECTED_REGEX BOUND_SECONDS
read_expect() {
    local step="$1" service="$2" expected="$3" bound="$4" start got
    start=$SECONDS
    got="$("$BIN" --read-keychain-service "$service" 2>/dev/null)"
    if [[ "$got" =~ $expected && $((SECONDS - start)) -le "$bound" ]]; then
        echo "step $step: ok ($got)"
    else
        echo "step $step: FAILED (got: $got)"; FAILED=1
    fi
}

# create SERVICE JSON [extra security flags]; each service is tracked once, whatever the flags.
create() {
    local service="$1" json="$2" tracked="" known
    shift 2
    for known in ${SERVICES[@]+"${SERVICES[@]}"}; do [[ "$known" == "$service" ]] && tracked=1; done
    [[ -n "$tracked" ]] || SERVICES+=("$service")
    if ! /usr/bin/security add-generic-password -a "$USER" -s "$service" "$@" -w "$json" "$KC" >/dev/null 2>&1; then
        echo "create: FAILED (add-generic-password for $service)"; FAILED=1
    fi
}

JSON1='{"claudeAiOauth":{"accessToken":"probe-1","expiresAt":4102444800000}}'
JSON2='{"claudeAiOauth":{"accessToken":"probe-2","expiresAt":4102444800000}}'
JSON3=$'{"claudeAiOauth":\n{"accessToken":"probe-3","expiresAt":4102444800000}}'
JSON4='{"claudeAiOauth":{"accessToken":"probé","expiresAt":4102444800000}}'

# Step 0, before any item exists: a service outside the allowed names is refused (exit 2, nothing on stdout).
ERRFILE="$(mktemp)"
OUT0="$("$BIN" --read-keychain-service limitaur-other 2>"$ERRFILE")"; STATUS0=$?
ERR0="$(cat "$ERRFILE")"; rm -f "$ERRFILE"
if [[ $STATUS0 -eq 2 && -z "$OUT0" && "$ERR0" == *"unsupported service"* ]]; then
    echo "step 0: ok"
else
    echo "step 0: FAILED (status $STATUS0)"; FAILED=1
fi

S1="$(newservice)"
create "$S1" "$JSON1"
read_expect 1 "$S1" '^found 69$' 7
create "$S1" "$JSON2" -U
read_expect 2 "$S1" '^found 69$' 7

S3="$(newservice)"
create "$S3" "$JSON3"
read_expect 3 "$S3" '^found 70$' 7

S4="$(newservice)"
create "$S4" "$JSON4"
read_expect 4 "$S4" '^found 68$' 7

read_expect 5 "$(newservice)" '^notFound$' 7

S6="$(newservice)"
create "$S6" "$JSON1" -T /usr/bin/true
echo "Do not answer the Keychain dialog until the read result appears."
read_expect 6 "$S6" '^denied ' 7
printf 'Step 6: what happened to the Keychain dialog? (dialog: none | closed-with-child | stayed): '
if read -r ANSWER; then
    case "$ANSWER" in
        none|closed-with-child) echo "step 6 answer recorded: $ANSWER" ;;
        stayed)
            echo "step 6 answer recorded: $ANSWER"
            echo "Dismiss the dialog with Deny, then press return."
            if ! read -r _; then echo; echo "step 6: FAILED (no second read)"; FAILED=1; fi ;;
        *) echo "step 6: FAILED (unrecognised answer)"; FAILED=1 ;;
    esac
else
    echo; echo "step 6: FAILED (no answer)"; FAILED=1
fi

cleanup
if [[ $FAILED -eq 0 ]]; then echo "probe: passed"; exit 0; fi
echo "probe: FAILED"; exit 1
