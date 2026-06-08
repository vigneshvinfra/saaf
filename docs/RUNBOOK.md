# Runbook — LLM latency / error spike → SLO breach

**Why this one.** The agent's latency and success are dominated by a single
synchronous dependency: the LLM call (Bedrock in prod, Anthropic in non-prod).
Spec data confirms it ("LLM calls dominate latency"). So the most likely
production incident is **upstream LLM degradation** — elevated latency or errors
from the model provider — surfacing as a p95 SLO breach and/or a spike in 502s.
Everything else (DB, S3) is fast and local; the model call is the fragile hop.

---

## 1. Alert

One of:
- `AgentP95LatencyHigh` — p95 end-to-end > 5s for 10m (SLO breach).
- `AgentLLMErrorRateHigh` — >5% of requests return 502 (LLM call failed) for 5m.

(Both defined in `deploy/platform/cluster-resources/templates/prometheus-rule.yaml`.)

## 2. Impact

- Loan officers see slow or failed item processing during a burst window
  (9–11am / 2–4pm ET). Items aren't lost — callers retry — but throughput drops
  and the SLO is breached. Risk: items not cleared before rate-lock expiry.

## 3. Triage (first 5 minutes)

```bash
# Is it the model, or us?
kubectl -n uw-prod logs -l app.kubernetes.io/name=underwriting-agent --tail=200 \
  | grep -E 'llm.failure|LLM call failed|502'

# p95 + error rate (Grafana: "underwriting-agent" dashboard) or PromQL:
#   histogram_quantile(0.95, sum by(le)(rate(http_server_duration_milliseconds_bucket[5m])))
#   sum(rate(...count{http_status_code="502"}[5m])) / sum(rate(...count[5m]))

# Are pods healthy (rule out our side)?
kubectl -n uw-prod get pods -l app.kubernetes.io/name=underwriting-agent
kubectl -n uw-prod top pods -l app.kubernetes.io/name=underwriting-agent
```

Decision tree:
- **CPU saturated / pods pending** → it's *us* (under-scaled), go to §4a.
- **CPU low, latency high, 502s from the model** → it's the *provider*, go to §4b.
- **Readiness failing / DB or S3 errors in logs** → not this incident; see
  "Related" below.

## 4. Mitigate

### 4a. We're under-scaled (rare — CPU-bound)
```bash
# Give HPA more ceiling and pre-warm; Karpenter will add nodes.
kubectl -n uw-prod scale deploy/underwriting-agent --replicas=10
kubectl -n uw-prod get hpa underwriting-agent
```
Raise `hpa.maxReplicas` in `values-prod.yaml` if the ceiling was the limit
(commit → Argo sync).

### 4b. Provider degradation (the usual cause)
1. **Confirm provider status** — Bedrock service health (AWS Health Dashboard) /
   Anthropic status page. Check if it's regional.
2. **Shed load gracefully** — the work is bursty and retriable; if the provider
   is throttling, adding replicas makes it worse. Instead:
   - Confirm client/SDK timeouts are sane so pods aren't blocked indefinitely
     (threads held on slow calls reduce effective capacity).
   - If a specific model/region is degraded in prod, **fail over the model**:
     bump `config.LLM_MODEL` (or region) in `values-prod.yaml` to a healthy
     Bedrock model and let Argo sync. This is config-only; no image rebuild.
3. **Protect the close-deadline items** — communicate to loan ops that the
   `large_deposit_explanation` / high-priority items may need manual handling
   during the window (these are exactly the agent's `escalate_to_human` path).

## 5. Verify recovery
```bash
kubectl -n uw-prod port-forward svc/underwriting-agent 8080:80 &
curl -s -XPOST localhost:8080/v1/items/process -H 'content-type: application/json' \
  -d @examples/sample_loan.json | jq '.latency_ms, .action.action_type'
```
Watch `AgentP95LatencyHigh` clear; confirm error rate < 1% for 15m.

## 6. Escalate
- Provider-side and not clearing in 30m → open a provider support case; page the
  ML team (they own model/prompt behaviour and the no-training agreement).
- SLO breach > RTO (30m) → incident commander, notify loan-ops leadership.

## 7. Prevent / follow-up
- Tune SDK timeouts + retry/backoff (the agent's `llm.py` — ML team).
- Multi-model / multi-region Bedrock failover as a first-class config.
- Consider async (SQS) so bursts queue instead of timing out under provider
  slowness — the documented evolution in `DESIGN.md`.
- Capacity review of `hpa.maxReplicas` vs. the 12-month 250 items/hr target.

---

### Related runbooks (not this incident)
- **DB connection exhaustion** → `AgentNoReadyPods` + `rds-connections-high`
  alarm: check RDS `DatabaseConnections`, recycle pods, review pool size.
- **Pod can't read secrets** → SecretProviderClass / Pod Identity association
  drift: `kubectl describe pod` for CSI mount errors.
