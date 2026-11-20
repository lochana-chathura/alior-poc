# PoD demo guide: platform, resilience, operations and visibility

This guide covers our share of the PoD: **Platform and resilience** (sections 1, 4, 5, 8, 10, 15) and **Operations and visibility** (sections 2 and 7). Security and compliance (3, 6, 9, 11, 12) and the AI gateway (13, 14) are done by another team. For each item it says what the bank asks, how we do it in this environment, how to show it, and where the proof is.

How each section is presented:

| Section | Format |
|---|---|
| 1 Architecture in practice | Evidence presentation |
| 2 Control and data plane | Live demo |
| 4 API routing | Live demo |
| 5 Traffic management | Not for the PoD (WSO2 answer in the sheet). Explain only. |
| 7 Logs and metrics | Live demo |
| 8 Gradual migration | Not for the PoD (WSO2 answer in the sheet). Explain only. |
| 10 HA and disaster recovery | Evidence presentation |
| 15 Future capabilities | Evidence presentation |

Status words used here:

- **Ready**: tried in the deployment, there is a script or evidence, and it can be shown.
- **Partly ready**: the main part works, something is still missing.
- **To do**: not tried yet.
- **Waiting**: blocked on someone else (named in the item).
- **Presentation**: the bank asked for slides or evidence, not a live demo.
- **Not for the PoD**: WSO2 answered "Not for the PoD" or "No" in the sheet.

## The environment in one page

| What | Where |
|---|---|
| API entry point (Front Door + WAF) | `https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net/<context>/<version>/...` |
| Publisher, Dev Portal, Admin, Grafana A, Argo CD A | `https://pod-cp-eccmfmahgkevcqcy.a02.azurefd.net/{publisher,devportal,admin,grafana,argocd}/` |
| Grafana B, Argo CD B | `https://pod-ops-b-a3graqbqf9dvcxe8.a02.azurefd.net/{grafana,argocd}/` |
| Region A (cloud) | AKS `pod-a-aks` in polandcentral. Runs the control plane (APIM 4.7.0) and gateway `pod-a-gw`. |
| Region B (on-prem stand-in) | AKS `pod-b-aks` in westeurope. Runs gateway `pod-b-gw` only. |
| Backends | Mock services on the VM `pod-b-vm` (10.20.16.4): v1 on 8081, v2 on 8082, legacy on 8083. The mock answers with JSON that names its version, host, port and the path it received. |
| Proof scripts | `make test POD=<id>` runs `tests/pod-<id>.sh`. Output goes to `evidence/<id>/`. |

The gateways and the VM are not reachable from the Internet. Every call goes through Front Door. The environment runs 09:00 to 17:00 Colombo time on weekdays only.

APIs are created and deployed from the control plane (the Publisher or its REST API). This is the "top-down" approach. Argo CD only deploys the platform itself.

---

## 1. Architecture

### 1.1 Gateway inside one Kubernetes cluster
**Ask.** Deploy on Kubernetes and control calls between applications running in the same cluster.
**How we do it.** An API called `internal` points at a small mock running inside each cluster. The `jwt-auth` policy is attached. A test pod in the `apps` namespace calls the gateway's internal address, so the call never leaves the cluster.
**How to show it.** Run `make test POD=1.1`. A call without a token gets 401 from the gateway. A call with a token gets 200 from the in-cluster mock. This happens in both clusters.
**Proof.** `tests/pod-1.1.sh`, `evidence/1.1/`. Last passed 2026-11-02.
**Status.** Ready.

### 1.2 Dedicated gateway for untrusted zones, backend on a VM
**Ask.** A separate gateway cluster takes calls from an untrusted zone and sends them to a backend on another cluster or a standalone system.
**How we do it.** Region B is the dedicated gateway cluster. The API `legacy` points at the legacy mock on the VM (port 8083) and has `jwt-auth` attached. The Internet reaches it only through Front Door.
**How to show it.** Run `make test POD=1.2`. Without a token the gateway answers 401. With a token the VM answers 200 with `x-mock-version: legacy`. The test also shows that the gateway IPs and the VM can't be reached directly from the Internet.
**Proof.** `tests/pod-1.2.sh`, `evidence/1.2/`. Last passed 2026-11-02.
**Status.** Ready.

### 1.3 Protection of lower layers (WAF, anti-DDoS)
**Ask.** Protect exposed services with an external IPS or anti-DDoS solution, or a WAF.
**How we do it.** Azure Front Door Premium sits in front of both gateways with a WAF policy (`podwaf`) in Prevention mode. The gateways only accept traffic from Front Door.
**How to show it.** Send a request with a SQL injection pattern through Front Door. The WAF blocks it with 403 before it reaches the gateway.
**Proof.** Checked by `tests/gate.sh` and by `tests/health.sh` (WAF 403 seen again on 2026-11-19).
**Status.** Ready. WSO2 left the feasibility column empty in the sheet, so confirm the wording with the lead.

### 1.4 Gateway on premises and in the cloud
**Ask.** Deploy the gateway both on premises and in the cloud.
**How we do it.** The same gateway operator and the same `APIGateway` resource are used in both clusters. Region A plays the cloud and region B plays on premises. Only the control plane address differs between them.
**How to show it.** Show the two `APIGateway` resources side by side and both gateways registered in the Admin portal.
**Proof.** `evidence/1.4/` (the two resources and their diff).
**Status.** Ready.

### 1.5 Several gateway instances, high availability, no single point of failure
**Ask.** Run several cooperating gateway instances with HA and no single point of failure.
**How we do it.** Each region runs two gateway runtime pods behind its load balancer, and Front Door sends traffic to both regions.
**How to show it.** Run `make test POD=1.5`. It deletes all region A runtime pods while traffic is flowing. On the last run, 0 of 40 calls failed. **This test disrupts region A for a short time, so warn others before running it.**
**Proof.** `tests/pod-1.5.sh`, `evidence/1.5/`. Last passed 2026-11-02.
**Status.** Ready for the gateways. The control plane runs as a single instance by design (agreed with Gihan on 2026-10-30), so say this openly if asked.

### 1.6 Selective HTTP proxy for outbound calls
**Status.** Not for the PoD (WSO2 answer in the sheet).

---

## 2. Operations

### 2.1 General API Management configuration
**Ask.** Show the general setup.
**How we do it.** APIM 4.7.0 runs in region A, with its database on the `pod-a-db` VM (PostgreSQL 16). Both gateways are registered with it.
**How to show it.** Walk through the Admin portal (gateways, throttling policies) and the Publisher (API list).
**Proof.** Screenshots to add to `evidence/2.1/`.
**Status.** Ready to show. Screenshots still to take.

### 2.2 Gateways per environment or system
**Ask.** Manage gateways per environment or per system.
**How we do it.** The control plane manages two gateways, `pod-a-gw` (region A) and `pod-b-gw` (region B). Each API is deployed to the gateways we choose. The test API `system-a` is deployed to gateway A only, while `accounts` is deployed to both.
**How to show it.** Run `make test POD=2.2`. It lists the gateways and where each API is deployed. It then makes 8 calls through Front Door and looks up each call in the gateway logs. Calls that land on region A get 200. Calls that land on region B get 404, because `system-a` isn't deployed there. In the Publisher, show the API's Deployments page with only one gateway ticked.
**Proof.** `tests/pod-2.2.sh`, `evidence/2.2/`. Passed 2026-11-19 (5 calls answered by A with 200, 3 by B with 404).
**Status.** Ready.

### 2.3 New gateway and API versioning, by GUI and by pipeline
**Ask.** Deploy a new gateway and a new API version, once in the GUI and once with a CI/CD pipeline.
**How we do it (pipeline).** `tests/pod-2.3.sh` does what a pipeline job would do, all through the Publisher REST API. It copies `accounts` 1.0.0 to 2.0.0, points 2.0.0 at mock v2, creates a revision, deploys it to both gateways and publishes it. Old clients keep using 1.0.0 (mock v1), new clients use 2.0.0 (mock v2).
**How to show it (GUI).** In the Publisher, open `accounts` 1.0.0, click **Create New Version**, enter a version (for example 3.0.0), change the endpoint, then deploy and publish. Record this once.
**Proof.** `tests/pod-2.3.sh`, `evidence/2.3/`. Passed 2026-11-19.
**Status.** Partly ready. Versioning works by pipeline. The GUI recording is still to do. Adding a brand new gateway means a new `APIGateway` resource through Argo CD, which needs access to Minura's repo (see open points).

### 2.4 Permissions per gateway or domain
**Status.** To do.
**What we know so far (checked 2026-11-19).**
- Each gateway in the Admin portal has a visibility setting. Today both are `PUBLIC`, meaning every publisher can deploy to them. It can be limited to chosen roles.
- To show it, we need a second Publisher user with a limited role. Creating that user is a change we should agree on first.
**Plan.** Create a role such as `team-b` and a user with it. Limit `pod-b-gw` to that role. Show that a publisher without the role can't deploy to gateway B. On the Kubernetes side, show a role that can only touch the `wso2-gw` namespace (`kubectl auth can-i`).

### 2.5 Audit of configuration changes
**Ask.** Audit configuration changes, for example who added a route and when.
**How we do it (checked 2026-11-19).**
- APIM writes an audit log (`repository/logs/audit.log` in the control plane pod). API actions are logged with who did them, for example `{"performedBy":"...","action":"deployed","type":"API"}`.
- That file lives inside the pod. The pod restarts every morning with the office-hours schedule, so the log only covers the current day. For a real audit trail it would have to be shipped somewhere that lasts.
- Kubernetes audit logs are not collected. Neither cluster has diagnostic settings.
- The Publisher keeps a revision history per API, with dates, which also shows when a route changed.
**How to show it.** Change something on a test API (for example add a route on `routes`), then run `bash tests/pod-2.5.sh routes`. It prints every audit line for that API (time, user, action, gateway) and the Publisher's revision history.
**Proof.** `tests/pod-2.5.sh`, `evidence/2.5/`. On 2026-11-19 it listed 20 changes to `routes`, each with time, user (`admin`) and gateway.
**Status.** Ready, with one caveat to say out loud. All changes today were made with the `admin` account, so "who" always shows `admin`. With named users each person would appear. The log is kept for the current day only.

---

## 4. API routing

### 4.1 Client to microservice through the gateway
**Ask.** Route a client application to a microservice through the gateway.
**How we do it.** The API `accounts` (context `/accounts`, version `1.0.0`) points at mock v1 on the VM.
**How to show it.** Run `make test POD=4.1`, or call it with curl:
```bash
curl -si https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net/accounts/1.0.0/accounts
```
The answer is 200 from mock v1. A path that isn't published (`/nope/1.0.0/accounts`) gets 404 from the gateway.
**Why we know the gateway did it.**
- The API has a `set-headers` policy (API level) that adds `x-pod-gateway: wso2-api-platform-gateway` to every response. Neither the mock nor Front Door can add it.
- Each response has an `x-request-id`. The test finds that ID in the router access log of region A or region B, so it shows which gateway served each call.
**Proof.** `tests/pod-4.1.sh`, `evidence/4.1/`. Passed 2026-11-19 (the header was on every call, and the calls were served by both regions).
**Status.** Ready.

### 4.2 Microservice to microservice inside a cluster
**Status.** Waiting. WSO2 asked the bank for the exact use case. Until then, item 1.1 shows the same pattern.

### 4.3 Backend not answering, 30 second timeout
**Ask.** What the gateway does when the backend doesn't answer, and when the configured timeout (30 seconds) runs out.
**How we do it.**
- **Backend not there.** The test API `nobackend` points at a port where nothing listens. The gateway answers **503** straight away with `upstream connect error ... remote connection failure`.
- **Backend too slow.** The gateway's backend timeout is `route_timeout_ms`. We set it to **30 seconds** in both regions on 2026-11-20 (the chart default is 60). With a 35 second delay the gateway gives up after 30 seconds with **504** `upstream request timeout`. With a 5 second delay the call succeeds.
- **Front Door's own limit.** Front Door gives up on its own after its origin timeout. We raised it from 30 to 60 seconds, so it is always longer than the gateway's and the client sees the gateway's answer.
**Where the timeout is configured.** In Git, in `platform/gateway/region-a/gateway-values.yaml` (and region-b):
```yaml
        router:
          upstream:
            timeouts:
              route_timeout_ms: 30000
```
Argo CD applies the change and the gateway operator restarts the gateway pods one at a time, so traffic keeps flowing. On 2026-11-20 the change was live in both regions in about 2 minutes. The live value can be read in the cluster with `kubectl -n wso2-gw get cm pod-a-gw-gw-gateway-config -o yaml | grep route_timeout_ms`. Front Door's timeout is set in `infra/azure/frontdoor.sh`.
**How to show it.**
1. Show the setting in Git (GitHub, `gateway-values.yaml`).
2. Call through Front Door with the header `x-mock-delay-ms: 35000`. The answer is 504 `upstream request timeout` after 30 seconds, a plain text body with the gateway's `x-request-id`. An HTML page with `OriginTimeout` would mean Front Door answered instead.
3. Or run `make test POD=4.3` (about 40 seconds).
**Setting it per API.** Setting the timeout per API from the Publisher doesn't work in our version. We set the standard endpoint timeout (10 seconds) on a test API and the gateway ignored it. WSO2's gateway supports a per-API timeout (`resilience.timeout`), but APIM 4.7.0 GA did not pass it on. Not tested again on update 23.
**Proof.** `tests/pod-4.3.sh`, `evidence/4.3/`. The gateway's 30 second timeout was seen on 2026-11-20 (504 after 30.01 s, called inside region A).
**Status.** Ready.

### 4.4 Multi-cluster communication
**Status.** Presentation. The bank said a live setup is not required. Use the L0 and L1 diagrams.

### 4.5 DNS support
**Ask.** The gateway finds backends by DNS name.
**How we do it.** The API `internal` (item 1.1) already points at a DNS name, `mock.apps.svc.cluster.local`, which Kubernetes DNS resolves inside each cluster. The 1.1 test shows calls reaching that backend.
**Status.** Partly ready. Kubernetes DNS is shown by 1.1. A backend outside Kubernetes by name (for example the VM) would need an Azure private DNS zone linked to both networks. None exists today (checked 2026-11-19). It costs about half a dollar a month.

### 4.6 Strip prefix
**Ask.** Remove a path prefix before forwarding to the backend.
**How we do it.** The gateway removes the API context and version by default. The client calls `/accounts/1.0.0/accounts` and the backend receives `/accounts`.
**How to show it.** Run `make test POD=4.6`. Point at the `path` field in the mock's answer.
**Configured rewrite.** The API `accounts-rewrite` has the `request-rewrite` policy (API level) with `ReplacePrefixMatch` set to `/legacy/accounts`. The client calls `/accounts-rewrite/1.0.0/accounts` and the backend receives `/legacy/accounts`.
**Why the earlier try failed.** On 2026-11-13 the policy was saved with type `ReplaceFullPath` but the path in the `replacePrefixMatch` field. That type needs a `replaceFullPath` value, so the policy did nothing. It was fixed on 2026-11-19.
**Proof.** `tests/pod-4.6.sh`, `evidence/4.6/` (`backend-path.txt` for the default, `configured-rewrite.txt` for the policy). Passed 2026-11-19.
**Status.** Ready.

### 4.7 Route conflicts and priorities
**Ask.** What happens when routes overlap, for example `/transfers` and `/transfers/instant`.
**How we do it.** The test API `routes` has three overlapping operations: `POST /transfers`, `POST /transfers/instant` and the wildcard `POST /transfers/*`. The wildcard is listed first on purpose. An API-level `request-rewrite` replaces the start of whichever route matched with `/matched` and keeps the rest. So the path the mock receives shows which route won.
**What the test shows.**
- `/transfers/instant` reaches the backend as `/matched`, so the exact route won over the wildcard, even though the wildcard is listed first.
- `/transfers/other` reaches the backend as `/matched/other`, so it fell through to the wildcard.
- `/transfers/instant/x` reaches the backend as `/matched/instant/x`, so a deeper path goes to the wildcard.
In short, the most specific route wins and the order of routes doesn't matter.
**How to show it.** Run `make test POD=4.7`.
**Proof.** `tests/pod-4.7.sh`, `evidence/4.7/`. Passed 2026-11-19.
**Status.** Ready. A clearer version would send `/transfers/instant` to mock v2 and `/transfers` to mock v1. That needs operation-level policies, which wait for the control plane update.

### 4.8 Several routes to one microservice
**Ask.** More than one route leads to the same microservice.
**How we do it.** Three operations of `accounts` (`GET /accounts`, `POST /transfers`, `POST /transfers/instant`) and a second API with its own context (`/accounts-rewrite/1.0.0/accounts`) all point at mock v1.
**How to show it.** Run `make test POD=4.8`. All four answers come from the same backend (v1 on pod-b-vm:8081).
**Proof.** `tests/pod-4.8.sh`, `evidence/4.8/`.
**Status.** Ready.

### 4.9 Sticky sessions
**Status.** Not for the PoD. WSO2's answer: sticky sessions belong to the load balancer.

---

## 5. Traffic management (5.1 to 5.4)
**Status.** Not for the PoD. WSO2's answer: these policies are not offered out of the box today and can be built if WSO2 is selected.

---

## 7. Visibility

### 7.1 Logs and metrics per layer
**Ask.** Logs and metrics for each layer, including control plane and data plane.
**How we do it.** Each cluster runs Prometheus and Grafana. The gateway controller and policy engine expose metrics, and WSO2 dashboards show them. All components log JSON to standard output, and the router writes access logs.
**How to show it.** Open Grafana A and Grafana B, make a few calls, and show the counters move. Run `make test POD=7.1` for the scripted check.
**Proof.** `tests/pod-7.1.sh`, `evidence/7.1/`. Last passed 2026-11-02.
**Status.** Ready for the gateways. Control plane metrics are not collected yet.

### 7.2 Integration with Grafana and OpenTelemetry
**How we do it.** Gateway metrics go to Prometheus and are shown in Grafana. OpenTelemetry tracing was left out (agreed with Gihan on 2026-11-02).
**Status.** Ready for Grafana. OpenTelemetry is a presentation point only.

---

## 8. Migration

### 8.1 Gradual migration to a new gateway
**Status.** Not for the PoD (WSO2 answer in the sheet).

---

## 10. Disaster recovery and HA

### 10.1 DR approach, backup and restore
**Status.** To do.
**What we know so far (checked 2026-11-19).**
- The control plane database is backed up by a nightly `pg_dump` job on `pod-a-db` at 02:15, kept for 7 days in `/var/backups/pg`.
- **The last backup is from 2026-11-05.** Since the office-hours schedule started, the VM is switched off at 02:15, so the job no longer runs.
- The backups stay on the same VM, so they would be lost with it. A real DR setup copies them somewhere else.
- The platform itself (gateways, operator, monitoring) can be rebuilt from Git with Argo CD.
**Plan.** Fix the backup time so it runs while the VM is on, copy the dump off the VM, then show a restore and a gateway rebuild.

### 10.2 HA and scaling the gateway from 4 to 8 instances
**Status.** To do.
**What we know so far (checked 2026-11-19).**
- Today there are **4 gateway runtime instances**: 2 in region A and 2 in region B (`replicaCount: 2` in `platform/gateway/region-*/gateway-values.yaml`). Going to 8 means 4 per region.
- Each runtime asks for 0.25 CPU and 512 MB. The region A worker node has about 1.5 CPU free, so 2 more runtimes fit without a new node.
- The setting is deployed by Argo CD from Minura's repo. A change made by hand in the cluster would be put back by Argo CD, so the change has to go through that repo (see open points).
**Plan.** Change `replicaCount` from 2 to 4 in both regions, show 8 runtimes running and traffic still answering, then change it back.

---

## 15. Architecture presentation

### 15.1 API Management as a central layer across clusters and clouds
**Status.** Presentation. Use the L0 diagram: one control plane managing gateways in two regions.

### 15.2 Control plane and data plane, loss of connection
**How we do it.** The drill `make drill D=controller-restart` restarts the gateway controller and checks that deployed APIs keep working.
**Proof.** `evidence/15.2/`. The drill passed after the gateway upgrade on 2026-11-02.
**Status.** Partly ready. A recording of the drill is still to do.

### 15.3 Service mesh integration
**Status.** Presentation.

### 15.4 HA, scaling, DR and degraded mode
**Status.** Presentation, backed by 1.5, 10.1, 10.2 and 15.2.

---

## Test APIs created for the demo

These were created on 2026-11-19 through the Publisher REST API, so they don't touch the original APIs:

| API | Context | Backend | Used for |
|---|---|---|---|
| `routes` 1.0.0 | `/routes` | mock v1 | 4.7 (and 2.5 audit example) |
| `nobackend` 1.0.0 | `/nobackend` | closed port 10.20.16.4:8099 | 4.3 |
| `system-a` 1.0.0 | `/system-a` | mock v1, gateway A only | 2.2 |
| `accounts` 2.0.0 | `/accounts` | mock v2 | 2.3 |

`accounts` 1.0.0 got a new revision on 2026-11-19 so its `set-headers` policy went live (4.1). `accounts-rewrite` got its `request-rewrite` settings fixed (4.6).

## Open points

- **Control plane update.** Operation-level policies are lost on save in the PoD control plane. This happens in the Publisher and also through the REST API (checked 2026-11-19), so it is a server-side problem, not only the screen. A local APIM 4.7.0 at update level 23 does not have it. The PoD control plane runs 4.7.0 with no updates (its `updates` folder has no update record). API-level policies work fine, so 4.1 and 4.6 no longer depend on this. The clearer version of 4.7 does.
- **Repo access.** Argo CD follows Minura's repo, and Minura is away for a few weeks. Changes to the platform (for example scaling in 10.2) need either write access to that repo or Argo CD switched to our fork.
