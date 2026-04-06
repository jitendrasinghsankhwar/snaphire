# SnapHire

AI-powered job application assistant — auto-discovers jobs, matches your profile, and generates tailored resumes.

## Architecture

- **backend/** — Quarkus (Java 21, Gradle) REST API
- **ai-service/** — Python (FastAPI) AI pipeline
- **frontend/** — React (Vite + Tailwind + shadcn/ui) SPA
- **docker/** — Nginx config
- **plans/** — Implementation plans

## Local Development

### Prerequisites

- Docker & Docker Compose
- Java 21 (for backend development)
- Python 3.12+ (for AI service development)
- Node.js 22+ (for frontend development)

### Run everything

```bash
docker-compose up --build
```

Services:
- **http://localhost** — App (via Nginx)
- **http://localhost/api/** — Backend API (proxied)
- **http://localhost/ai/** — AI Service (proxied)
- **http://localhost:8080** — Backend (direct)
- **http://localhost:5000** — AI Service (direct)
- **http://localhost:3000** — Frontend (direct)

### Run tests

```bash
# Backend
cd backend && ./gradlew test

# AI Service
cd ai-service && pip install -r requirements.txt && pytest
```

## PRD

See [Issue #1](https://github.com/jitendrasinghsankhwar/snaphire/issues/1) for the full PRD.

## Implementation Plan

See [plans/snaphire-implementation.md](plans/snaphire-implementation.md) for the 16-phase tracer-bullet plan.
