import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

// ---------------------------------------------------------------------------
// Benchmark contract (these thresholds ARE the gate — k6 exits non-zero when
// any of them is breached, and scripts/ci/k6-gate.sh enforces that verdict):
//   * 200 concurrent users
//   * 15-minute sustained load
//   * p95 latency < 400 ms
//   * error rate < 1%
//   * throughput reported
//
// The HTML report is rendered locally (see renderHtml below) rather than by
// importing a remote bundle at runtime: an unpinned fetch from a third party is
// both a supply-chain risk and a way for a 15-minute benchmark to die on a
// network blip after the load has already been generated.
// ---------------------------------------------------------------------------

const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const USERNAME = __ENV.APP_AUTH_USER || 'operator';
const PASSWORD = __ENV.APP_AUTH_PASSWORD;

const errorRate = new Rate('business_errors');
const readDuration = new Trend('task_read_duration', true);
const writeDuration = new Trend('task_write_duration', true);
const throughput = new Counter('requests_completed');

export const options = {
  scenarios: {
    enterprise_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 200 },  // ramp to 200 concurrent users
        { duration: '15m', target: 200 }, // 15-minute steady-state load test
        { duration: '1m', target: 0 },    // graceful ramp-down
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    'http_req_duration': ['p(95)<400'],   // p95 latency < 400 ms
    'http_req_failed': ['rate<0.01'],     // error rate < 1%
    'business_errors': ['rate<0.01'],
    'task_read_duration': ['p(95)<300'],  // read path held to a tighter bound
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  noConnectionReuse: false,
  discardResponseBodies: false,
};

export function setup() {
  if (!PASSWORD) {
    throw new Error(
      'APP_AUTH_PASSWORD is not set. The benchmark authenticates as a real user; ' +
      'set the APP_AUTH_PASSWORD secret so the perf stage can obtain a token.'
    );
  }

  const res = http.post(
    `${BASE_URL}/api/v1/auth/login`,
    JSON.stringify({ username: USERNAME, password: PASSWORD }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'login' } }
  );

  if (res.status !== 200) {
    throw new Error(
      `Setup failed: login returned ${res.status}. The load test cannot run without a token.`
    );
  }

  return { token: res.json('token') };
}

export default function (data) {
  const authHeaders = {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${data.token}`,
    },
  };

  group('health probe', function () {
    const res = http.get(`${BASE_URL}/actuator/health`, { tags: { name: 'health' } });
    const ok = check(res, {
      'health returns 200': (r) => r.status === 200,
      'health reports UP': (r) => r.json('status') === 'UP',
    });
    errorRate.add(!ok);
    throughput.add(1);
  });

  group('read tasks', function () {
    const res = http.get(`${BASE_URL}/api/v1/tasks`, {
      ...authHeaders,
      tags: { name: 'list_tasks' },
    });
    readDuration.add(res.timings.duration);
    const ok = check(res, {
      'list returns 200': (r) => r.status === 200,
      'list returns an array': (r) => Array.isArray(r.json()),
    });
    errorRate.add(!ok);
    throughput.add(1);
  });

  group('read urgent tasks', function () {
    const res = http.get(`${BASE_URL}/api/v1/tasks/urgent`, {
      ...authHeaders,
      tags: { name: 'urgent_tasks' },
    });
    readDuration.add(res.timings.duration);
    errorRate.add(!check(res, { 'urgent returns 200': (r) => r.status === 200 }));
    throughput.add(1);
  });

  // Roughly one in five iterations exercises the write path, so the benchmark
  // reflects a read-heavy production mix rather than a pure read test.
  if (__ITER % 5 === 0) {
    group('create and complete a task', function () {
      const create = http.post(
        `${BASE_URL}/api/v1/tasks`,
        JSON.stringify({
          title: `perf-${__VU}-${__ITER}`,
          description: 'created by the k6 benchmark',
          priority: 3,
        }),
        { ...authHeaders, tags: { name: 'create_task' } }
      );
      writeDuration.add(create.timings.duration);

      const created = check(create, { 'create returns 201': (r) => r.status === 201 });
      errorRate.add(!created);
      throughput.add(1);

      if (created) {
        const id = create.json('id');
        const done = http.patch(
          `${BASE_URL}/api/v1/tasks/${id}/status?value=DONE`,
          null,
          { ...authHeaders, tags: { name: 'complete_task' } }
        );
        writeDuration.add(done.timings.duration);
        errorRate.add(!check(done, { 'transition returns 200': (r) => r.status === 200 }));
        throughput.add(1);

        const del = http.del(`${BASE_URL}/api/v1/tasks/${id}`, null, {
          ...authHeaders,
          tags: { name: 'delete_task' },
        });
        errorRate.add(!check(del, { 'delete returns 204': (r) => r.status === 204 }));
        throughput.add(1);
      }
    });
  }

  sleep(1);
}

function row(label, value, budget, passed) {
  const cls = passed === undefined ? '' : passed ? 'ok' : 'bad';
  const mark = passed === undefined ? '' : passed ? 'PASS' : 'FAIL';
  return `<tr class="${cls}"><td>${label}</td><td>${value}</td><td>${budget}</td><td>${mark}</td></tr>`;
}

function renderHtml(s, metrics) {
  const trend = (m) => (metrics[m] ? metrics[m].values : {});
  const req = trend('http_req_duration');

  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>k6 Performance Report — enterprise-java-platform</title>
<style>
 body{font-family:ui-sans-serif,system-ui,sans-serif;margin:0;background:#0f172a;color:#e2e8f0}
 .wrap{max-width:900px;margin:0 auto;padding:2.5rem 1.5rem}
 h1{font-size:1.6rem;margin:0 0 .25rem}.sub{color:#94a3b8;margin:0 0 2rem}
 table{width:100%;border-collapse:collapse;margin-bottom:2rem;font-size:.9rem}
 th,td{text-align:left;padding:.6rem .5rem;border-bottom:1px solid #334155}
 th{color:#94a3b8;font-weight:500}
 tr.ok td:last-child{color:#4ade80;font-weight:600}
 tr.bad td:last-child{color:#f87171;font-weight:600}
 h2{font-size:1.05rem;color:#38bdf8;margin:2rem 0 .75rem}
 .verdict{padding:1rem;border-radius:8px;font-weight:600;margin-bottom:2rem}
 .verdict.pass{background:rgba(74,222,128,.1);border:1px solid rgba(74,222,128,.35);color:#4ade80}
 .verdict.fail{background:rgba(248,113,113,.1);border:1px solid rgba(248,113,113,.35);color:#f87171}
</style></head><body><div class="wrap">
<h1>k6 Performance Report</h1>
<p class="sub">enterprise-java-platform &middot; 200 VUs &middot; 15-minute steady state &middot; ${new Date().toISOString()}</p>
<div class="verdict ${s.thresholds.p95_under_400ms && s.thresholds.error_rate_under_1pct ? 'pass' : 'fail'}">
  ${s.thresholds.p95_under_400ms && s.thresholds.error_rate_under_1pct
    ? 'All performance budgets met.'
    : 'Performance budget breached — see the failing rows below.'}
</div>
<h2>Budgets</h2>
<table><thead><tr><th>Metric</th><th>Measured</th><th>Budget</th><th></th></tr></thead><tbody>
${row('p95 latency', `${Number(s.p95_ms).toFixed(1)} ms`, '&lt; 400 ms', s.thresholds.p95_under_400ms)}
${row('Error rate', `${(Number(s.error_rate) * 100).toFixed(3)} %`, '&lt; 1 %', s.thresholds.error_rate_under_1pct)}
</tbody></table>
<h2>Latency distribution</h2>
<table><thead><tr><th>Statistic</th><th>Value</th><th></th><th></th></tr></thead><tbody>
${row('average', `${Number(req.avg).toFixed(1)} ms`, '', undefined)}
${row('median', `${Number(req.med).toFixed(1)} ms`, '', undefined)}
${row('p90', `${Number(req['p(90)']).toFixed(1)} ms`, '', undefined)}
${row('p95', `${Number(req['p(95)']).toFixed(1)} ms`, '', undefined)}
${row('p99', `${Number(req['p(99)']).toFixed(1)} ms`, '', undefined)}
${row('max', `${Number(req.max).toFixed(1)} ms`, '', undefined)}
</tbody></table>
<h2>Throughput</h2>
<table><thead><tr><th>Metric</th><th>Value</th><th></th><th></th></tr></thead><tbody>
${row('Requests completed', s.total_requests, '', undefined)}
${row('Throughput', `${Number(s.throughput_rps).toFixed(1)} req/s`, '', undefined)}
</tbody></table>
</div></body></html>`;
}

export function handleSummary(data) {
  const durations = data.metrics.http_req_duration ? data.metrics.http_req_duration.values : {};
  const failed = data.metrics.http_req_failed ? data.metrics.http_req_failed.values : {};
  const reqs = data.metrics.http_reqs ? data.metrics.http_reqs.values : {};

  const summary = {
    p95_ms: durations['p(95)'],
    p99_ms: durations['p(99)'],
    avg_ms: durations.avg,
    max_ms: durations.max,
    error_rate: failed.rate,
    total_requests: reqs.count,
    throughput_rps: reqs.rate,
    thresholds: {
      p95_under_400ms: durations['p(95)'] !== undefined && durations['p(95)'] < 400,
      error_rate_under_1pct: failed.rate !== undefined && failed.rate < 0.01,
    },
  };

  console.log('=== PERFORMANCE BENCHMARK ===');
  console.log(`p95 latency   : ${Number(summary.p95_ms).toFixed(1)} ms (budget 400 ms)`);
  console.log(`error rate    : ${(Number(summary.error_rate) * 100).toFixed(3)} % (budget 1 %)`);
  console.log(`throughput    : ${Number(summary.throughput_rps).toFixed(1)} req/s`);
  console.log(`total requests: ${summary.total_requests}`);

  return {
    'reports/performance/k6-summary.html': renderHtml(summary, data.metrics),
    'reports/performance/k6-summary.json': JSON.stringify(summary, null, 2),
    'reports/performance/k6-raw.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}
