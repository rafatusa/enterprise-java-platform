#!/usr/bin/env bash
# Deployment validation suite.
#
# Verifies every item in the deployment contract against the LIVE host:
#   1. /actuator/health          5. Nginx reverse proxy
#   2. /actuator/info            6. JWT authentication
#   3. Swagger UI                7. Smoke test of the task API
#   4. PostgreSQL connectivity
#
# Credentials come from the environment (APP_AUTH_USER / APP_AUTH_PASSWORD).
# There is deliberately NO inline fallback: a default credential baked into a
# validation script is how a default credential survives into production.
#
# Usage: APP_AUTH_PASSWORD=... smoke-test.sh <base-url>
set -uo pipefail

BASE_URL="${1:?usage: smoke-test.sh <base-url>}"
AUTH_USER="${APP_AUTH_USER:-operator}"

PASS=0
FAIL=0
RESULTS=()

pass() { echo "  PASS  $1"; RESULTS+=("PASS|$1|"); PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1 — $2"; RESULTS+=("FAIL|$1|$2"); FAIL=$((FAIL + 1)); }

echo "Deployment validation against ${BASE_URL}"
echo "=========================================================="

# --- 1. Health endpoint ------------------------------------------------------
echo ""
echo "[1/7] Actuator health"
if HEALTH=$(curl --fail --silent --show-error --max-time 15 \
  --retry 10 --retry-delay 10 --retry-all-errors \
  "${BASE_URL}/actuator/health" 2>&1) && echo "$HEALTH" | grep -q '"status":"UP"'; then
  pass "/actuator/health reports UP"
else
  fail "/actuator/health" "did not report UP"
fi

# --- 2. Info endpoint --------------------------------------------------------
echo ""
echo "[2/7] Actuator info"
if curl --fail --silent --max-time 10 --output /dev/null "${BASE_URL}/actuator/info"; then
  pass "/actuator/info is served"
else
  fail "/actuator/info" "not reachable"
fi

# --- 3. Swagger UI + OpenAPI -------------------------------------------------
echo ""
echo "[3/7] Swagger UI and OpenAPI document"
DOCS_CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 \
  "${BASE_URL}/v3/api-docs")
if [ "$DOCS_CODE" = "200" ]; then
  pass "OpenAPI document served at /v3/api-docs"
else
  fail "/v3/api-docs" "HTTP ${DOCS_CODE}"
fi

SWAGGER_CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 -L \
  "${BASE_URL}/swagger-ui/index.html")
if [ "$SWAGGER_CODE" = "200" ]; then
  pass "Swagger UI reachable"
else
  fail "Swagger UI" "HTTP ${SWAGGER_CODE}"
fi

# --- 4. PostgreSQL connectivity ---------------------------------------------
# The actuator db health indicator issues a real validation query, so an UP db
# component proves the application can reach PostgreSQL with its credentials.
echo ""
echo "[4/7] PostgreSQL connectivity"
DB_STATUS=$(curl --fail --silent --max-time 10 "${BASE_URL}/actuator/health" 2>/dev/null \
  | grep -o '"db":{"status":"[A-Z]*"' | grep -o '[A-Z]*"$' | tr -d '"')
if [ "$DB_STATUS" = "UP" ]; then
  pass "PostgreSQL reachable (db health indicator UP)"
else
  fail "PostgreSQL connectivity" "db health indicator is '${DB_STATUS:-absent}'"
fi

# --- 5. Nginx reverse proxy --------------------------------------------------
# The app binds 127.0.0.1:8080, so a successful response on port 80 proves the
# proxy is doing the forwarding.
echo ""
echo "[5/7] Nginx reverse proxy"
SERVER_HEADER=$(curl --silent --head --max-time 10 "${BASE_URL}/actuator/health" \
  | grep -i '^server:' | tr -d '\r')
if echo "$SERVER_HEADER" | grep -qi nginx; then
  pass "Nginx is fronting the application"
else
  fail "Nginx reverse proxy" "unexpected Server header: '${SERVER_HEADER:-none}'"
fi

# --- 6. JWT authentication ---------------------------------------------------
echo ""
echo "[6/7] JWT authentication"
UNAUTH_CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 \
  "${BASE_URL}/api/v1/tasks")
if [ "$UNAUTH_CODE" = "401" ]; then
  pass "Protected endpoint rejects unauthenticated requests (401)"
else
  fail "JWT protection" "expected 401 without a token, got ${UNAUTH_CODE}"
fi

BAD_CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 \
  -H "Authorization: Bearer invalid.token.value" "${BASE_URL}/api/v1/tasks")
if [ "$BAD_CODE" = "401" ]; then
  pass "Forged token rejected (401)"
else
  fail "JWT validation" "expected 401 for a forged token, got ${BAD_CODE}"
fi

TOKEN=""
if [ -z "${APP_AUTH_PASSWORD:-}" ]; then
  fail "JWT issuance" "APP_AUTH_PASSWORD not set — cannot verify the login flow"
else
  LOGIN_BODY=$(printf '{"username":"%s","password":"%s"}' "$AUTH_USER" "$APP_AUTH_PASSWORD")
  TOKEN=$(curl --silent --max-time 15 -X POST "${BASE_URL}/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    --data-binary "$LOGIN_BODY" \
    | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  unset LOGIN_BODY

  if [ -n "$TOKEN" ]; then
    pass "Login issued a JWT"
  else
    fail "JWT issuance" "login did not return a token"
  fi
fi

# --- 7. Smoke test of the task API ------------------------------------------
echo ""
echo "[7/7] Task API smoke test"
if [ -z "$TOKEN" ]; then
  fail "Task API smoke test" "skipped — no token available"
else
  AUTH="Authorization: Bearer ${TOKEN}"

  LIST_CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 \
    -H "$AUTH" "${BASE_URL}/api/v1/tasks")
  if [ "$LIST_CODE" = "200" ]; then
    pass "GET /api/v1/tasks returns 200 with a valid token"
  else
    fail "GET /api/v1/tasks" "HTTP ${LIST_CODE}"
  fi

  CREATE_BODY=$(curl --silent --max-time 15 -X POST "${BASE_URL}/api/v1/tasks" \
    -H "$AUTH" -H 'Content-Type: application/json' \
    -d '{"title":"smoke-test","description":"created by deployment validation","priority":3}')
  TASK_ID=$(echo "$CREATE_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

  if [ -n "$TASK_ID" ]; then
    pass "POST /api/v1/tasks created task ${TASK_ID} (write path + DB insert)"

    GET_CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 \
      -H "$AUTH" "${BASE_URL}/api/v1/tasks/${TASK_ID}")
    if [ "$GET_CODE" = "200" ]; then
      pass "GET /api/v1/tasks/${TASK_ID} round-tripped from PostgreSQL"
    else
      fail "Task read-back" "HTTP ${GET_CODE}"
    fi

    DEL_CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 \
      -X DELETE -H "$AUTH" "${BASE_URL}/api/v1/tasks/${TASK_ID}")
    if [ "$DEL_CODE" = "204" ]; then
      pass "DELETE /api/v1/tasks/${TASK_ID} cleaned up the smoke-test record"
    else
      fail "Task delete" "HTTP ${DEL_CODE}"
    fi
  else
    fail "POST /api/v1/tasks" "no task id returned"
  fi
fi

# --- Summary -----------------------------------------------------------------
echo ""
echo "=========================================================="
echo "Deployment validation: ${PASS} passed, ${FAIL} failed"

mkdir -p reports/deployment
{
  echo "# Deployment Validation Summary"
  echo ""
  echo "- Target: ${BASE_URL}"
  echo "- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "- Result: ${PASS} passed, ${FAIL} failed"
  echo ""
  echo "| Result | Check | Detail |"
  echo "|--------|-------|--------|"
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r status name detail <<< "$r"
    echo "| ${status} | ${name} | ${detail:--} |"
  done
} > reports/deployment/deployment-summary.md

if [ "$FAIL" -gt 0 ]; then
  echo "SMOKE TESTS FAILED"
  exit 1
fi

echo "All deployment validation checks passed."
