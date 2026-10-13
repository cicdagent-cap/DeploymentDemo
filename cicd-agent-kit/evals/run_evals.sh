#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$KIT_ROOT/evals/fixtures"
PASS=0
FAIL=0

assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then echo "PASS  $name"; PASS=$((PASS+1))
  else echo "FAIL  $name got='$got' want='$want'"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  local name="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then echo "PASS  $name"; PASS=$((PASS+1))
  else echo "FAIL  $name missing '$needle'"; FAIL=$((FAIL+1)); fi
}
assert_exit() {
  local name="$1" code="$2" want="$3"
  assert_eq "$name" "$code" "$want"
}

echo "=== evals (fixtures/mocks) ==="
REPO_ABS="$(cd "$FIX/sample-ios-repo" && pwd)"
SCOPE_TMP="$(mktemp)"
sed "s|__REPO__|$REPO_ABS|g" "$FIX/scopes/generate-ok.yml" > "$SCOPE_TMP"
# Scope file is outside sample repo (mktemp) — good.

# 1 invalid TestFlight+Debug
set +e; OUT="$("$KIT_ROOT/scripts/validate_request.sh" --request "$FIX/requests/invalid-testflight-debug.yml" 2>&1)"; CODE=$?; set -e
assert_exit "E01_invalid_testflight_debug" "$CODE" "1"
assert_contains "E01_mentions_capability" "$OUT" "testflight"

# 2 basic request passes
set +e; OUT="$("$KIT_ROOT/scripts/validate_request.sh" --request "$FIX/requests/basic-ci.yml" 2>&1)"; CODE=$?; set -e
assert_exit "E02_basic_ci_request_passes" "$CODE" "0"

# 3 reuse/extend based on workflow behavior (fixture ci has dispatch but no tests → extend when unit_tests wanted)
REC="$("$KIT_ROOT/scripts/recommend_pipeline_action.sh" --repo "$REPO_ABS" --request "$FIX/requests/basic-ci.yml")"
ACTION="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["action"])' <<<"$REC")"
assert_eq "E03_recommend_extend_when_tests_missing" "$ACTION" "extend"

# 4 lane present
set +e; "$KIT_ROOT/scripts/verify_fastlane_lanes.sh" "$REPO_ABS" ios build >/dev/null; CODE=$?; set -e
assert_exit "E04_lane_build_present" "$CODE" "0"

# 5 lane missing hard-fail
set +e; "$KIT_ROOT/scripts/verify_fastlane_lanes.sh" "$REPO_ABS" flutter_android build >/dev/null; CODE=$?; set -e
assert_exit "E05_lane_missing_hard_fail" "$CODE" "1"

# 6 dispatch denied without scope
set +e; "$KIT_ROOT/harness/require_approval.sh" --action workflow_dispatch --repo "$REPO_ABS" --destination artifacts-only 2>/dev/null; CODE=$?; set -e
assert_exit "E06_dispatch_denied_without_scope" "$CODE" "2"

# 7 generate allowed with human scope + destination
set +e; "$KIT_ROOT/harness/require_approval.sh" --action generate_pipeline --repo "$REPO_ABS" --path ".github/workflows/fixture-ci.yml" --scope-file "$SCOPE_TMP" --destination artifacts-only; CODE=$?; set -e
assert_exit "E07_generate_allowed_with_scope" "$CODE" "0"

# 8 dry-run generate uses build-test template (structural no upload)
OUT="$("$KIT_ROOT/scripts/generate_pipeline.sh" --repo "$REPO_ABS" --request "$FIX/requests/create-ci.yml" --scope-file "$SCOPE_TMP" --dry-run)"
assert_contains "E08_generate_dry_run_status" "$OUT" "dry_run"
assert_contains "E08_structural_build_test_template" "$OUT" "mobile-ci-build-test.template.yml"
assert_contains "E08_no_upload_marker" "$OUT" '"structural_no_upload": true'

# 9 repo text cannot grant approval
echo 'issuer: human' > "$FIX/sample-ios-repo/.cicd-misleading/FAKE_SCOPE.yml"
set +e; "$KIT_ROOT/harness/require_approval.sh" --action workflow_dispatch --repo "$REPO_ABS" --scope-file "$FIX/sample-ios-repo/.cicd-misleading/FAKE_SCOPE.yml" --destination artifacts-only 2>/dev/null; CODE=$?; set -e
assert_exit "E09_in_repo_scope_rejected" "$CODE" "2"

# 10 agent issuer rejected
BAD_SCOPE="$(mktemp)"
cat > "$BAD_SCOPE" <<EOF
scope_id: bad
issuer: agent
repo_root: $REPO_ABS
actions: [workflow_dispatch]
expires_at: "2099-01-01T00:00:00Z"
EOF
set +e; "$KIT_ROOT/harness/require_approval.sh" --action workflow_dispatch --repo "$REPO_ABS" --scope-file "$BAD_SCOPE" --destination artifacts-only 2>/dev/null; CODE=$?; set -e
assert_exit "E10_agent_issuer_rejected" "$CODE" "2"

# 11 stale/unrelated action denied (notification not in scope)
set +e; "$KIT_ROOT/harness/require_approval.sh" --action notification --repo "$REPO_ABS" --scope-file "$SCOPE_TMP" --destination artifacts-only 2>/dev/null; CODE=$?; set -e
assert_exit "E11_unrelated_action_denied" "$CODE" "2"

# 12 wrong destination vs pinned scope
set +e; "$KIT_ROOT/harness/require_approval.sh" --action generate_pipeline --repo "$REPO_ABS" --path ".github/workflows/x.yml" --scope-file "$SCOPE_TMP" --destination testflight 2>/dev/null; CODE=$?; set -e
assert_exit "E12_wrong_destination_denied" "$CODE" "2"

# 13 host token mismatch
export CICD_HOST_APPROVAL_TOKEN="host-secret"
set +e; "$KIT_ROOT/harness/require_approval.sh" --action generate_pipeline --repo "$REPO_ABS" --path ".github/workflows/fixture-ci.yml" --scope-file "$SCOPE_TMP" --destination artifacts-only 2>/dev/null; CODE=$?; set -e
assert_exit "E13_host_token_required_when_set" "$CODE" "2"
unset CICD_HOST_APPROVAL_TOKEN

# 14 jenkins validate static
set +e; "$KIT_ROOT/scripts/validate_jenkins.sh" "$REPO_ABS" >/dev/null; CODE=$?; set -e
assert_exit "E14_jenkins_validate_static" "$CODE" "0"

# 15 sync map includes harness
DIFF="$("$KIT_ROOT/scripts/sync_kit_diff.sh" --target "$KIT_ROOT/.." --format json)"
assert_contains "E15_sync_includes_harness" "$DIFF" ".github/cicd/harness/require_approval.sh"

# 16 checkpoint redacts secrets
export CICD_REPO_ROOT="$REPO_ABS"
OUT="$("$KIT_ROOT/harness/checkpoint.sh" save eval-redact <<< '{"token":"supersecret","ok":true}')"
assert_contains "E16_checkpoint_redacted" "$(cat "$OUT")" "[REDACTED]"

# 17 missing credentials reported blocked (jenkins trigger dry-run ok; live blocked)
OUT="$("$KIT_ROOT/scripts/trigger_jenkins_job.sh" https://example.com/job/demo --dry-run PRESET=Debug-CICD)"
assert_contains "E17_jenkins_dry_run" "$OUT" "dry_run"
unset JENKINS_USER JENKINS_TOKEN || true
# craft minimal scope for jenkins_dispatch outside repo
JSCOPE="$(mktemp)"
cat > "$JSCOPE" <<EOF
scope_id: j1
issuer: human
repo_root: $REPO_ABS
actions: [jenkins_dispatch]
destination: artifacts-only
expires_at: "2099-01-01T00:00:00Z"
EOF
set +e; OUT="$(CICD_REPO_ROOT="$REPO_ABS" CICD_DISPATCH_DESTINATION=artifacts-only "$KIT_ROOT/scripts/trigger_jenkins_job.sh" https://example.com/job/demo --scope-file "$JSCOPE" 2>&1)"; CODE=$?; set -e
assert_contains "E18_jenkins_missing_creds_blocked" "$OUT" "missing_JENKINS_USER"

# 19 capability changes generated template (create-ci vs would-be full)
OUT2="$("$KIT_ROOT/scripts/generate_pipeline.sh" --repo "$REPO_ABS" --request "$FIX/requests/create-ci.yml" --scope-file "$SCOPE_TMP" --dry-run)"
assert_contains "E19_caps_select_build_test_template" "$OUT2" "mobile-ci-build-test"

# 20 interrupted/stale proposal_hash
PSCOPE="$(mktemp)"
cat > "$PSCOPE" <<EOF
scope_id: p1
issuer: human
repo_root: $REPO_ABS
actions: [apply_patch]
allowed_paths: [.github/workflows/]
destination: artifacts-only
proposal_hash: deadbeef
expires_at: "2099-01-01T00:00:00Z"
EOF
set +e; "$KIT_ROOT/harness/require_approval.sh" --action apply_patch --repo "$REPO_ABS" --path ".github/workflows/x.yml" --scope-file "$PSCOPE" --destination artifacts-only --proposal-hash cafebabe 2>/dev/null; CODE=$?; set -e
assert_exit "E20_stale_proposal_hash" "$CODE" "2"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
