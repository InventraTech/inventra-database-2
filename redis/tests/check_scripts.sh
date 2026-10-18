#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

container="inventra-redis-scripts-ci-$$"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "$container" \
  -v "$PWD/redis:/repo/redis:ro" \
  redis:7 >/dev/null

for _ in $(seq 1 30); do
  if docker exec "$container" redis-cli ping 2>/dev/null | grep -q PONG; then
    break
  fi
  sleep 1
done

if ! docker exec "$container" redis-cli ping | grep -q PONG; then
  echo "Redis did not become ready" >&2
  exit 1
fi

redis() {
  docker exec "$container" redis-cli --raw "$@"
}

eval_script() {
  local path="$1"
  shift
  docker exec "$container" redis-cli --raw --eval "/repo/redis/scripts/$path" "$@"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

prefix="inventra:test:product-registration"
lock="$prefix:consumer-lock"
ready="$prefix:ready"
pending="$prefix:pending"
errors="$prefix:errors"
token="test-owner"

redis SET "$lock" "$token" EX 30 >/dev/null

for event in e1 e2; do
  result="$(eval_script product-queue/enqueue.lua \
    "$ready" "$pending" "$prefix:sequence" "$prefix:job:$event" "$lock" , \
    "$event" "{\"eventId\":\"$event\",\"status\":\"QUEUED\"}")"
  assert_eq "1" "$result" "enqueue must accept a new event"
done

first="$(redis RPOP "$ready:$token")"
assert_eq "e1" "$first" "LPUSH/BRPOP contract must remain FIFO"

recovered="$(eval_script product-queue/recover.lua \
  "$lock" "$ready:$token" "$pending" "$ready" , "$token")"
assert_eq "2" "$recovered" "recovery must rebuild every pending event"
assert_eq "e1" "$(redis RPOP "$ready:$token")" "recovery must preserve FIFO order"

updated="$(eval_script product-queue/update.lua \
  "$lock" "$prefix:job:e1" "$pending" "$errors" , \
  "$token" e1 '{"eventId":"e1","status":"COMPLETED"}' 1 0)"
assert_eq "1" "$updated" "completion must update state atomically"
assert_eq "" "$(redis ZSCORE "$pending" e1)" "completed event must leave the pending set"

redis SET "$prefix:job:e2" '{' >/dev/null
quarantined="$(eval_script product-queue/quarantine.lua \
  "$lock" "$prefix:job:e2" "$pending" "$errors" , "$token" e2 'invalid-json')"
assert_eq "1" "$quarantined" "invalid payload must be quarantined"
assert_eq "1" "$(redis LLEN "$errors")" "quarantine must append one DLQ entry"

errors_ttl="$(redis TTL "$errors")"
if (( errors_ttl <= 0 || errors_ttl > 604800 )); then
  echo "DLQ TTL must be positive and at most seven days; got $errors_ttl" >&2
  exit 1
fi

assert_eq "0" "$(eval_script product-queue/lease.lua "$lock" "$ready:$token" , wrong-token 30)" \
  "a foreign token must not renew the lease"
assert_eq "1" "$(eval_script product-queue/lease.lua "$lock" "$ready:$token" , "$token" 30)" \
  "the owner must renew the lease"
assert_eq "1" "$(eval_script product-queue/lease.lua "$lock" "$ready:$token" , "$token" 0)" \
  "the owner must release the lease"
assert_eq "0" "$(redis EXISTS "$lock")" "lease release must delete the lock"

ranking="inventra:test:ranking:{kitchen-1}"
temporary="$ranking:build:1"
replaced="$(eval_script ranking/replace.lua "$ranking" "$temporary" , \
  60 '~empty' 0000000012 20002 0000000010 20000 0000000002 20000)"
assert_eq "1" "$replaced" "ranking publication must succeed"
assert_eq $'0000000002\n0000000010\n0000000012' "$(redis ZRANGE "$ranking" 0 2)" \
  "ranking must order by score and break ties lexicographically"

ranking_ttl="$(redis TTL "$ranking")"
if (( ranking_ttl <= 0 || ranking_ttl > 60 )); then
  echo "Ranking TTL must be positive and at most 60 seconds; got $ranking_ttl" >&2
  exit 1
fi

eval_script ranking/replace.lua "$ranking" "$ranking:build:2" , 60 '~empty' 99 10 >/dev/null
assert_eq $'99\n~empty' "$(redis ZRANGE "$ranking" 0 -1)" \
  "a refresh must replace the complete published ranking"

invalid_output="$(eval_script ranking/replace.lua "$ranking" "$ranking:build:3" , \
  60 '~empty' broken not-a-number 2>&1 || true)"
if [[ "$invalid_output" != *"Invalid ranking score"* ]]; then
  echo "Ranking script did not reject an invalid score: $invalid_output" >&2
  exit 1
fi
assert_eq $'99\n~empty' "$(redis ZRANGE "$ranking" 0 -1)" \
  "an invalid refresh must preserve the published ranking"

echo "Redis Lua scripts are valid"
