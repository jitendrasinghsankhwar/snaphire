# Plan: SnapHire — AI-Powered Job Application Assistant

> Source PRD: https://github.com/jitendrasinghsankhwar/snaphire/issues/1

## Architectural decisions

Durable decisions that apply across all phases:

- **Routes**: `POST /auth/login`, `GET/PUT /profile`, `POST /profile/resume`, `GET /jobs/matches`, `GET /jobs/matches/{id}/resume`, `PUT /jobs/matches/{id}/status`, `GET/PUT /schedule`, `GET /notifications` (SSE), `GET /history`
- **Schema**: PostgreSQL tables — `users`, `profiles`, `jobs`, `matches`, `tailored_resumes`, `schedules`, `notifications`. JSONB columns for semi-structured data (parsed_data, preferences, payload).
- **Key models**: User, Profile, Job, Match (keyword_score, embedding_score, llm_score, final_score), TailoredResume, Schedule, Notification
- **Auth**: AWS Cognito → LinkedIn + Google OAuth → JWT → Quarkus `quarkus-oidc`
- **External services**: SerpAPI (job discovery), AWS Bedrock Haiku/Sonnet (LLM), Bedrock Titan Embeddings (vectors), AWS SES (email), AWS S3 (file storage)
- **Backend**: Quarkus (Java) REST API
- **AI pipeline**: Python microservice
- **MCP server**: JobForge (Python) — thin wrapper over AI pipeline
- **Frontend**: React SPA (Vite + Tailwind + shadcn/ui) hosted on S3 + CloudFront
- **Deployment (MVP)**: Single EC2 t3.micro, Docker Compose (Quarkus + Python + PostgreSQL + Nginx)

---

## Phase 1: Project Scaffolding & Docker Compose

**User stories**: None directly — infrastructure foundation

### What to build

Set up the monorepo structure with three services: Quarkus backend, Python AI service, and React frontend. Create a Docker Compose configuration that runs all three services plus PostgreSQL and Nginx as a reverse proxy. Verify that a health check endpoint on each service responds through Nginx. Set up the PostgreSQL schema migration tooling (Flyway for Quarkus). Establish CI basics (lint, build, test commands).

### Acceptance criteria

- [ ] Monorepo structure: `backend/` (Quarkus), `ai-service/` (Python), `frontend/` (React), `docker/`
- [ ] `docker-compose up` starts all services and PostgreSQL
- [ ] Quarkus health endpoint (`GET /health`) returns 200 through Nginx
- [ ] Python service health endpoint returns 200 through Nginx
- [ ] React app loads in browser through Nginx
- [ ] Flyway runs initial migration creating all schema tables (empty)
- [ ] README documents local development setup

---

## Phase 2: User Auth (Cognito + OAuth)

**User stories**: 1, 2

### What to build

Integrate AWS Cognito as the identity provider with LinkedIn and Google as social login options. The React frontend shows a login page with "Sign in with LinkedIn" and "Sign in with Google" buttons. On successful OAuth, Cognito issues a JWT. The Quarkus backend validates the JWT via `quarkus-oidc` and creates a `users` record on first login. A protected endpoint (`GET /profile`) returns 401 without a valid token and the user's basic info with one.

### Acceptance criteria

- [ ] Login page renders with LinkedIn and Google OAuth buttons
- [ ] Successful LinkedIn OAuth redirects back with a valid JWT
- [ ] Successful Google OAuth redirects back with a valid JWT
- [ ] First login creates a `users` row (cognito_sub, email, name)
- [ ] `GET /profile` returns 401 without token
- [ ] `GET /profile` returns user info with valid token
- [ ] JWT refresh flow works (token expiry → silent refresh)

---

## Phase 3: Resume Upload & Profile Parsing

**User stories**: 3, 4, 5, 6

### What to build

Authenticated users can upload a resume (PDF or DOCX) via the dashboard. The file is stored in S3. The Python AI service parses the resume into structured data (skills, experience, education, contact info) and stores it in the `profiles` table as JSONB. The dashboard displays the parsed profile and allows the user to edit any field or add missing information manually. Edits are saved via `PUT /profile`.

### Acceptance criteria

- [ ] `POST /profile/resume` accepts PDF and DOCX uploads (rejects other formats)
- [ ] Uploaded file is stored in S3 with a user-scoped key
- [ ] Python service parses PDF into structured profile data
- [ ] Python service parses DOCX into structured profile data
- [ ] Parsed data is stored in `profiles.parsed_data` (JSONB)
- [ ] Dashboard displays parsed profile with editable fields
- [ ] User can manually add/edit skills, experiences, education
- [ ] `PUT /profile` saves manual edits and merges with parsed data
- [ ] Re-uploading a resume overwrites previous parsed data (manual edits preserved)

---

## Phase 4: Job Discovery Pipeline

**User stories**: 7, 8, 13, 16, 31

### What to build

Users configure target roles and locations in their profile preferences. The Python AI service queries SerpAPI with Google dorking (`site:linkedin.com/jobs`, `site:naukri.com`, `site:indeed.com`) for each role+location combination. Results are parsed, deduplicated by title+company+location hash, and stored in the `jobs` table. Jobs the user has already seen are excluded from future notifications. A manual trigger endpoint allows testing the pipeline before scheduling is built.

### Acceptance criteria

- [ ] User can set target roles and locations via `PUT /profile` preferences
- [ ] Python service queries SerpAPI for each role+location+source combination
- [ ] Job results are parsed into structured `Job` records (title, company, location, source, url, description)
- [ ] Duplicate jobs (same title+company+location) are deduplicated across sources
- [ ] Jobs are stored in `jobs` table with source metadata and dedup_hash
- [ ] Previously seen jobs are not returned in subsequent runs
- [ ] Manual trigger endpoint (`POST /jobs/discover`) runs the pipeline on demand
- [ ] Discovery works across LinkedIn, Naukri, and Indeed via Google dorking

---

## Phase 5: Keyword Matching (Funnel Stage 1)

**User stories**: 14, 15

### What to build

After job discovery, the first matching stage extracts keywords from the user's profile (skills, titles, technologies) and compares them against each job description. Jobs with low keyword overlap are filtered out. Surviving jobs get a `keyword_score` stored in the `matches` table. The matching reason (which keywords matched) is stored for explainability.

### Acceptance criteria

- [ ] Keywords are extracted from user profile (skills, job titles, technologies)
- [ ] Each discovered job is scored by keyword overlap with the profile
- [ ] Jobs below a configurable keyword threshold are filtered out
- [ ] `matches` records are created with `keyword_score` for surviving jobs
- [ ] Match reason (matched keywords) is stored for each match
- [ ] ~200 jobs reduced to ~50 after this stage

---

## Phase 6: Embedding Matching (Funnel Stage 2)

**User stories**: 14, 15

### What to build

Jobs surviving Stage 1 are scored using vector similarity. The user's profile and each job description are converted to embeddings via AWS Bedrock Titan Embeddings. Cosine similarity is computed between profile and job vectors. Jobs below a similarity threshold are filtered out. The `embedding_score` is added to existing `matches` records.

### Acceptance criteria

- [ ] User profile is converted to an embedding via Bedrock Titan Embeddings
- [ ] Each surviving job description is converted to an embedding
- [ ] Cosine similarity is computed between profile and job embeddings
- [ ] Jobs below a configurable similarity threshold are filtered out
- [ ] `matches.embedding_score` is updated for surviving jobs
- [ ] ~50 jobs reduced to ~15 after this stage

---

## Phase 7: LLM Scoring (Funnel Stage 3)

**User stories**: 14, 15

### What to build

Top candidates from Stage 2 are deeply evaluated by sending the full profile + full job description to Bedrock Claude Sonnet. The LLM returns a relevance score (0-100) with detailed reasoning explaining why the candidate is or isn't a good fit. The `llm_score` and reasoning are stored. A `final_score` is computed as a weighted combination of all three stages.

### Acceptance criteria

- [ ] Each surviving job is evaluated by Claude Sonnet with full profile + JD
- [ ] LLM returns a score (0-100) and textual reasoning
- [ ] `matches.llm_score` is updated for each evaluated job
- [ ] Match reasoning is stored for display to the user
- [ ] `final_score` is computed as weighted combination of keyword, embedding, and LLM scores
- [ ] Matches are ranked by `final_score` descending

---

## Phase 8: Job Matches Dashboard

**User stories**: 21, 22, 32, 33

### What to build

The React dashboard displays matched jobs sorted by `final_score`. Each job card shows title, company, location, source, score, and match reasoning. Users can filter by score range, date, source, or company. Users can mark each job as "applied", "skipped", or "saved" via `PUT /jobs/matches/{id}/status`. Company information from the job listing is displayed alongside each match.

### Acceptance criteria

- [ ] `GET /jobs/matches` returns paginated matches sorted by `final_score`
- [ ] Dashboard renders job cards with title, company, location, source, score
- [ ] Match reasoning is displayed (why this job matched)
- [ ] Filter controls for score range, date, source, company
- [ ] User can mark a job as "applied", "skipped", or "saved"
- [ ] Status changes persist via `PUT /jobs/matches/{id}/status`
- [ ] Company info is displayed on each job card

---

## Phase 9: Resume Tailoring & PDF Generation

**User stories**: 17, 19, 20

### What to build

For any matched job, the user can request a tailored resume. The Python AI service sends the user's profile + job description to Bedrock Claude Sonnet, which generates resume content emphasizing relevant experience and skills. The content is rendered to PDF and stored in S3. The dashboard shows a preview and a download button. The `tailored_resumes` table tracks generated resumes.

### Acceptance criteria

- [ ] `GET /jobs/matches/{id}/resume` triggers tailored resume generation if not already generated
- [ ] Claude Sonnet generates resume content tailored to the specific job
- [ ] Resume is rendered as PDF and stored in S3
- [ ] `tailored_resumes` record is created linking match to S3 key
- [ ] Dashboard shows resume preview for each match
- [ ] User can download the tailored resume as PDF
- [ ] Subsequent requests for the same match return the cached version

---

## Phase 10: Cover Letter Generation

**User stories**: 18

### What to build

Alongside the tailored resume, users can generate a cover letter for any matched job. The Python AI service sends profile + JD to Bedrock Claude Haiku, which generates a personalized cover letter. The cover letter is stored as PDF in S3 and downloadable from the dashboard.

### Acceptance criteria

- [ ] User can request a cover letter for any matched job
- [ ] Claude Haiku generates a personalized cover letter based on profile + JD
- [ ] Cover letter is rendered as PDF and stored in S3
- [ ] Cover letter is downloadable from the dashboard alongside the tailored resume
- [ ] Subsequent requests return the cached version

---

## Phase 11: User-Configurable Scheduling

**User stories**: 9, 10, 11, 12

### What to build

Users configure their job search schedule via the dashboard: time of day, frequency, and active days. The schedule is stored as a cron expression in the `schedules` table. Quarkus `@Scheduled` periodically checks for due schedules and triggers the full pipeline (discovery → matching → tailoring for top matches). Users can pause/resume their schedule. Salary range preference is added to profile for filtering.

### Acceptance criteria

- [ ] Dashboard shows schedule configuration (time, days, frequency)
- [ ] `PUT /schedule` saves a cron expression to `schedules` table
- [ ] Quarkus scheduler detects due schedules and triggers the pipeline
- [ ] Full pipeline runs: discovery → keyword → embedding → LLM → tailoring
- [ ] User can pause schedule (sets `active = false`)
- [ ] User can resume schedule (sets `active = true`)
- [ ] Salary range preference can be set and is used to filter jobs
- [ ] `schedules.last_run` and `next_run` are updated after each execution

---

## Phase 12: Email Digest Notifications

**User stories**: 24

### What to build

After a scheduled pipeline run completes, an email digest is sent to the user via AWS SES. The digest summarizes how many jobs were found, top matches with scores, and links to the dashboard. Email is only sent if new matches were found.

### Acceptance criteria

- [ ] After pipeline run, email digest is sent via SES if new matches exist
- [ ] Email contains: match count, top matches (title, company, score), dashboard link
- [ ] No email sent if zero new matches
- [ ] Email uses a clean HTML template
- [ ] SES sender identity is verified and configured

---

## Phase 13: In-App Notifications (SSE)

**User stories**: 25

### What to build

When the user is on the dashboard, real-time notifications appear as new matches are found. The Quarkus backend exposes `GET /notifications` as an SSE endpoint using `Multi<>`. The React frontend connects via `EventSource` and displays a notification badge/toast when new matches arrive. Notifications are stored in the `notifications` table and marked as read when viewed.

### Acceptance criteria

- [ ] `GET /notifications` returns an SSE stream
- [ ] New match events are pushed to connected clients in real-time
- [ ] React frontend connects via `EventSource` and shows notification badge
- [ ] Toast/popup appears when new matches arrive
- [ ] Notifications are stored in `notifications` table
- [ ] User can mark notifications as read
- [ ] SSE connection auto-reconnects on disconnect

---

## Phase 14: Application History & Tracking

**User stories**: 23

### What to build

A dedicated history page on the dashboard shows all jobs the user has interacted with — applied, skipped, or saved — with timestamps, scores, and links to the tailored resume. `GET /history` returns paginated results filterable by status.

### Acceptance criteria

- [ ] `GET /history` returns paginated application history
- [ ] History includes: job title, company, status, score, date, tailored resume link
- [ ] Filterable by status (applied, skipped, saved)
- [ ] Sortable by date or score
- [ ] Dashboard renders history page with all interactions

---

## Phase 15: JobForge MCP Server

**User stories**: 26, 27, 28, 29, 30

### What to build

A Python MCP server (JobForge) that exposes the AI pipeline as tools usable from Kiro, Claude, Cursor, or any MCP-compatible client. Tools: `search_jobs` (triggers discovery), `match_profile` (scores a specific job), `tailor_resume` (generates tailored resume), `get_matches` (returns current matches). Authenticated via API key per user. Shares the same Python AI modules as the web app backend.

### Acceptance criteria

- [ ] MCP server starts and registers tools: `search_jobs`, `match_profile`, `tailor_resume`, `get_matches`
- [ ] `search_jobs(roles, locations)` triggers job discovery and returns results
- [ ] `match_profile(job_id)` returns match score with reasoning
- [ ] `tailor_resume(job_id)` generates and returns tailored resume
- [ ] `get_matches()` returns current matched jobs with scores
- [ ] Each tool authenticates via user API key
- [ ] Profile changes in web app are reflected in MCP tool results
- [ ] MCP server is configurable in Kiro's `mcp.json`

---

## Phase 16: Account Management & Data Deletion

**User stories**: 34

### What to build

Users can delete their account from the dashboard. Deletion removes all data: user record, profile, matches, tailored resumes (from S3 and DB), schedules, notifications. A confirmation dialog prevents accidental deletion. Cognito user is also deleted.

### Acceptance criteria

- [ ] Dashboard shows "Delete Account" option in settings
- [ ] Confirmation dialog requires explicit user action
- [ ] `DELETE /profile` removes all user data from PostgreSQL
- [ ] All user files are deleted from S3 (uploaded resumes, generated PDFs)
- [ ] Cognito user record is deleted
- [ ] Schedule is deactivated before deletion
- [ ] User is logged out and redirected to landing page after deletion
