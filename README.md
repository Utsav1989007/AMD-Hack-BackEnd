# ATLAS Backend — FastAPI · LangChain · Ollama · FAISS

The AI backend for the **ATLAS** AIOps dashboard. It loads your 13 infrastructure
CSVs into a topology graph, layers deterministic telemetry on top, and exposes a
REST API that powers every view of the frontend — plus a **local, private** AI
stack (Ollama for the LLM + embeddings, FAISS for retrieval) driving the chat
assistant and the autonomous RCA / remediation agent.

Nothing leaves your machine: the model runs in Ollama, the vector index is a
local FAISS file.

---

## Architecture

```
                 ┌──────────────────────────────────────────────┐
   13 CSVs  ───► │ data_loader → Graph (363 nodes, 888 edges)    │
                 │ telemetry  → seeded metrics / logs / spikes   │
                 └───────────────┬──────────────────────────────┘
                                 │
        ┌────────────────────────┼─────────────────────────────┐
        ▼                        ▼                              ▼
  analytics                graph_service                   incidents
  (z-score spikes,         (blast radius,                  (RCA facts,
   forecast, risk)          lineage, subgraph)              remediation plan)
        │                        │                              │
        └──────────┬─────────────┴──────────────┬───────────────┘
                   ▼                             ▼
            FastAPI routers              vectorstore (FAISS)  ◄── Ollama embeddings
            /api/...                            │
                   │                            ▼
                   │                       rag_chat  ──────────► Ollama LLM
                   │                       rca_agent (LangChain create_agent + tools)
                   ▼
            React frontend  (frontend_api_client.js)
```

### Maps to the 7 product requirements
| # | Requirement | Backend surface |
|---|-------------|-----------------|
| 1 | Dashboard of logs & spikes | `/api/overview`, `/api/logs`, `/api/spikes`, `/api/metrics/{id}` |
| 2 | Flag issues via email | `/api/incidents/alert` (real SMTP), `/api/incidents/{id}/alert-preview` |
| 3 | Predict issues from history | `/api/predict/forecast`, `/api/risk` |
| 4 | RCA + remediation | `/api/incidents/rca` (LangChain agent), `/api/incidents/remediate` |
| 5 | Neo4j-like graph | `/api/graph/topology`, `/api/graph/blast/{id}`, `/api/graph/node/{id}` |
| 6 | Chat about infra | `/api/assistant/chat` (RAG: FAISS + Ollama) |
| 7 | Rich UI | served by the React app; this is its data plane |

---

## Setup

### 1. Install & start Ollama
```bash
# https://ollama.com  — then pull the two models:
ollama pull llama3.1          # reasoning / chat (tool-capable)
ollama pull nomic-embed-text  # embeddings for FAISS
ollama serve                  # if not already running
```

### 2. Run the backend
```bash
cp .env.example .env          # adjust if needed
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
# or simply:  ./run.sh
```

Open **http://localhost:8000/docs** for interactive Swagger docs.
On startup the server builds the FAISS index (once) and caches it under
`faiss_index/`. Rebuild any time with `POST /api/assistant/reindex`.

### 3. Wire the frontend
Copy `frontend_api_client.js` into the React app as `src/api.js`, set
`VITE_ATLAS_API=http://localhost:8000`, and replace the in-browser `RAW`
computations with `await api.overview()`, `await api.chat(...)`, etc. CORS for
`localhost:5173` / `localhost:3000` is already enabled (configurable via
`CORS_ORIGINS`).

---

## Configuration (`.env`)
| Key | Default | Purpose |
|-----|---------|---------|
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Ollama endpoint |
| `OLLAMA_LLM_MODEL` | `llama3.1` | chat / agent model |
| `OLLAMA_EMBED_MODEL` | `nomic-embed-text` | embedding model |
| `FAISS_INDEX_DIR` | `./faiss_index` | persisted vector index |
| `TELEMETRY_SEED` | `20260614` | deterministic telemetry (matches frontend) |
| `SMTP_HOST` … | *(empty)* | set to send real alert emails; empty = dry-run |
| `REMEDIATION_DRY_RUN` | `true` | simulate remediation; see below |

---

## What is real vs simulated (read this)

**Real, computed from your CSVs / locally:**
- the dependency graph, lineage traversal and blast-radius propagation;
- anomaly detection (rolling z-score), forecasting, service-risk scoring;
- the FAISS vector index and semantic retrieval;
- the LLM reasoning — a genuine local model via Ollama (chat + tool-using agent);
- email sending — real SMTP when `SMTP_HOST` is configured.

**Simulated by design (and clearly labelled in responses):**
- **Telemetry.** Your CSVs describe topology but contain no time-series logs, so
  metrics/logs/incidents are generated from a fixed seed. Swap `telemetry.py` for
  a Prometheus/Loki client (same interface) to go live.
- **Remediation execution.** `remediation.py` runs in `DRY_RUN` and returns a
  structured result without touching infra. The executor has clearly marked
  insertion points for `kubectl` / Kubernetes API / Ansible. With `DRY_RUN=false`
  it deliberately refuses until you implement those, rather than pretending.

This honesty is intentional: the service never claims an action happened that
didn't.

---

## Going to production
- **Telemetry** → implement a `Telemetry`-shaped adapter over Prometheus / Loki / OTel.
- **Graph** → optionally back `graph_service` with Neo4j (Cypher) instead of in-memory.
- **Alerting** → set SMTP, or extend `email_alert.py` with PagerDuty / Slack webhooks.
- **Remediation** → fill in the executors in `remediation.py` and flip `REMEDIATION_DRY_RUN=false`.
- **Models** → swap `OLLAMA_LLM_MODEL` for any tool-capable Ollama model; the
  embeddings model just needs to be pulled.

---

## Project layout
```
atlas-backend/
├── app/
│   ├── main.py            FastAPI app + lifespan (graph/telemetry/FAISS warmup)
│   ├── config.py          settings (.env)
│   ├── data_loader.py     CSV → topology graph + lineage maps
│   ├── telemetry.py       seeded metrics / logs / spikes
│   ├── analytics.py       z-score spikes · forecast · risk · domain health
│   ├── graph_service.py   blast radius · lineage · subgraph export
│   ├── incidents.py       incident + RCA construction + remediation plans
│   ├── llm.py             Ollama LLM + embeddings factory + health check
│   ├── vectorstore.py     FAISS build/load from nodes + logs + incidents
│   ├── rag_chat.py        hybrid RAG chat (structured facts + retrieval + LLM)
│   ├── rca_agent.py       LangChain agent (create_agent) with grounded tools
│   ├── remediation.py     remediation executors (pluggable, dry-run)
│   ├── email_alert.py     SMTP alerting
│   ├── schemas.py         pydantic request models
│   └── routers/           graph · telemetry · predict · incidents · assistant
├── data/                  the 13 CSVs
├── requirements.txt
├── .env.example
├── run.sh
└── frontend_api_client.js
```
