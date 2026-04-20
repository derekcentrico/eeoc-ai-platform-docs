# Vilulia Development Guide

## Project

Vilulia LLC — B2B SaaS platform for Alternative Dispute Resolution (mediation + arbitration). Pre-launch stabilization phase. Entity is always "Vilulia LLC" (never Inc.).

## Tech Stack

- **Backend**: Python 3 / Flask, PostgreSQL (RDS), Redis (ElastiCache), Celery workers
- **Frontend**: React / TypeScript (craco build), i18next (5 UI languages: en, es, fr, de, pt)
- **Infra**: AWS ECS Fargate, S3, CloudFront, ECR, Cognito, Bedrock, Secrets Manager, CloudTrail, WAF
- **AI**: AWS Bedrock (primary), OpenAI (secondary), Google Gemini (tertiary); xAI/Grok via OpenAI-compatible endpoint
- **Integrations**: Stripe, Postmark, Twilio, Daily.co, DocuSign, Polygon blockchain, Sentry

## Repository Layout

```
~/vilulia/vilulia-app/
├── app/
│   ├── models/          # SQLAlchemy models
│   ├── services/        # Business logic + AI services (app/services/ai/)
│   ├── blueprints/      # Flask route blueprints
│   ├── tasks/           # Celery async tasks
│   ├── middleware/       # Auth (auth.py), feature gates, rate limiting
│   ├── constants/       # Notification types, enums
│   └── extensions.py    # db, migrate, celery instances
├── frontend/src/        # React/TypeScript source
├── migrations/versions/ # Alembic migrations (sequential integer filenames)
├── .claude/agents/      # Subagent definitions (this directory)
└── CLAUDE.md            # This file
```

Marketing site: `~/vilulia/vilulia-marketing/` (Next.js, separate S3/CloudFront)

## AWS Environment

| Resource | Value |
|---|---|
| ECS Cluster | `adr-production-cluster` |
| App Service | `adr-production-app-service` |
| Celery Worker | `adr-production-celery-worker` |
| Celery Beat | `adr-production-celery-beat` |
| Flower | `adr-production-flower` |
| ECR | `624234316402.dkr.ecr.us-east-1.amazonaws.com/adr-production-app:latest` |
| Frontend S3 | `s3://adr-production-app-frontend/` |
| CloudFront (app) | `E1411FYUYJ4DQQ` |
| CloudFront (marketing) | `EOAV94YXX47BH` |
| Marketing S3 | `s3://adr-production-static-16f66e34/` |
| RDS | `adr-production-postgres` |
| VPC | `vpc-06560ed501d01bd50` |
| Cognito Pool | `us-east-1_URjWmZkcU` |
| Cognito Client | `1bf0ptsmh7m7p3ft2fe2ep6kbr` |
| Log Group | `/aws/ecs/adr-production` |
| CloudTrail | `adr-production-trail` |
| Secrets Rotation Lambda | `adr-production-rds-rotation` |

## Key URLs

- Production: `https://app.vilulia.com`
- API: `https://app.vilulia.com/api/v1/`
- Admin: `https://app.vilulia.com/admin/`
- Health: `https://app.vilulia.com/api/v1/health`

## Critical Rules

### Migration Rules (MUST follow for every migration)

1. Sequential integer filenames as both filename and alembic revision ID; always becomes new head
2. Only `op.execute("""...""")` with hardcoded literal SQL — no `text()` with named parameters, no f-strings, no loops, no helper functions
3. No `sa.Column()`, `op.alter_column()`, `op.add_column()` outside `DO $$ BEGIN...END $$` blocks
4. DDL safety: `ADD COLUMN IF NOT EXISTS` inside `DO $$ BEGIN...END $$`
5. No `ALTER TYPE` in same transaction as usage of new enum value — insert `op.execute("COMMIT")` between them
6. i18n migrations use `ui_translations` table with `ON CONFLICT (key, language_code)` — constraint is on `(key, language_code)` only, not namespace
7. Single quotes escaped as `''`; NULL not `'None'`
8. Reference migrations: 231, 234, 236
9. Pre-deploy: always run `grep -rn "ALTER TYPE" migrations/versions/*.py`
10. Participant roles are VARCHAR, not PostgreSQL enum — never use ALTER TYPE for role changes
11. **Single-head chain (CRITICAL)**: Before writing any migration, verify the chain has exactly one head by running: `grep -n "^down_revision = " migrations/versions/*.py | awk -F"'" '{print $2}' | sort | uniq -c | sort -rn | head -5` — if any `down_revision` value appears more than once, the chain is forked and MUST be fixed before adding new migrations. After writing a migration, verify your new migration's `down_revision` matches the previous single head. Two branches creating migrations with the same parent caused a production outage on 2026-04-20.
12. **Branch migration hygiene**: When working on a feature branch that creates migrations, always rebase or check `main` for new migrations before finalizing. If `main` advanced the head while your branch was open, update your first migration's `down_revision` to chain off the new head.

### Architecture Rules

- All frontend API calls must use shared `api` instance (not raw axios) for Cognito auth token injection
- Feature flags live in tenant `features` JSONB column via `has_feature()`/`enable_feature()`
- Webhook blueprint registered at both `/webhooks/` and `/api/v1/webhooks/` for backward compat
- CloudWatch filter patterns must use quoted strings: `'"ERROR"'` not `ERROR`
- Celery beat schedules must be in `CELERYBEAT_SCHEDULE` (uppercase) in `app/config.py`
- Support console: staff stay logged in as themselves; no case data/PHI access
- Demo tenant deletion requires `SET session_replication_role = 'replica'`

### AI Provider Patterns

- `_NO_TEMP_PREFIXES = ('o1', 'o3', 'o4', 'gpt-5')` for OpenAI temperature filtering
- Bedrock: `max_attempts=1`, `read_timeout=120`, `overall_timeout=300`; use `us.` inference profile prefix
- Empty content validation inside `_execute_with_failover` — empty responses trigger `continue` to next provider

### Code Change Workflow

1. Diagnose first — query production state via ECS execute-command + flask shell
2. Read existing files before writing (exact pattern matching)
3. Fix ALL known issues before deploying — no iterative hotfixes
4. All changes through Claude Code for uniformity
5. Batch everything into one clean deployment
6. **After implementation completes, ALWAYS run the mandatory post-implementation verification (see below)**

### Post-Implementation Verification (MANDATORY)

After completing ANY implementation task — before considering work done — you MUST execute all five verification passes. Do not skip any. Do not ask whether to run them. Run them automatically.

**Pass 1 — ForeignKey Integrity Audit**
Any new or changed ForeignKey requires a complete audit of all related models, queries, services, and cascades to ensure no breakage. Trace every FK relationship touched by your changes. Check ON DELETE behavior. Verify no orphaned references. If you added a column that other tables reference, verify those tables. If you modified a model, check every service that queries it.

**Pass 2 — i18n Compliance Check**
Every UI-visible string must use the i18n system. If you made ANY frontend changes, verify all user-facing text uses `t('namespace:key')`. New keys require a migration file inserting into `ui_translations` for all 5 languages (en, es, fr, de, pt) with `ON CONFLICT (key, language_code)`. Do not skip languages. Do not leave hardcoded English strings.

**Pass 3 — Migration File Audit**
Never modify existing migration files. If you created new migrations, verify:
- Sequential integer filename that becomes the new head (check `grep -n "^revision = " migrations/versions/*.py | sort -t: -k2 -n | tail -5`)
- No duplicate version numbers (we have had this error — it caused production problems)
- Follows exact pattern of migrations 231, 234, 236
- Only `op.execute("""...""")` with hardcoded literal SQL
- No `text()` with named parameters, no f-string interpolation, no helper functions, no loops, no abstractions
- Single quotes escaped as `''`, NULL not `'None'`
- This is the only pattern that works reliably with psycopg2 + Alembic + PostgreSQL `::jsonb` casts
- Run: `grep -rn "text(" migrations/versions/*.py` and `grep -rn "ALTER TYPE" migrations/versions/*.py` to catch violations
- **Single-head chain check (CRITICAL)**: Run `grep -n "^down_revision = " migrations/versions/*.py | awk -F"'" '{print $2}' | sort | uniq -c | sort -rn | head -5` — every count must be 1. A count of 2+ means two migrations share a parent and the chain is forked. This broke production on 2026-04-20.

**Pass 4 — Security Audit**
Review all code you wrote or modified for:
- SQL injection (must use parameterized queries or `db.text()` in app code; raw SQL only in migrations)
- Auth/authz: new endpoints have `@login_required` / `@role_required`; tenant scoping via `g.tenant_id`
- No hardcoded secrets, tokens, or credentials
- PHI exposure: any new data paths involving medical/case data must log to `phi_access_logs`
- Input validation on all new endpoints
- CORS and rate limiting where applicable
- Correct any deficiencies immediately

**Pass 5 — Four-Loop Functionality Audit**
Trace your changes through four complete loops of the affected workflow(s) to verify end-to-end correctness:
1. The exact feature/fix you implemented works as intended
2. Adjacent features that share code paths, models, or services still function
3. Upstream triggers (what calls your code) and downstream consumers (what your code calls) are intact
4. Edge cases: empty data, missing optional fields, role-based access variations, multi-tenant isolation

If this audit reveals deficiencies in code OUTSIDE the scope of your current task, fix them. Do not defer. Do not document them as "known issues." Fix them now.

## Deploy Commands

```bash
# Frontend
cd frontend && npm run build
aws s3 sync build/ s3://adr-production-app-frontend/ --delete
aws cloudfront create-invalidation --distribution-id E1411FYUYJ4DQQ --paths "/*"

# Backend (ECR login first)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 624234316402.dkr.ecr.us-east-1.amazonaws.com
docker buildx build --platform linux/arm64 -t 624234316402.dkr.ecr.us-east-1.amazonaws.com/adr-production-app:latest --push .

# Register new task definitions + deploy all services
for TASK_DEF in adr-production-app adr-production-celery-worker adr-production-celery-beat adr-production-flower; do
  aws ecs register-task-definition --cli-input-json "$(aws ecs describe-task-definition --task-definition $TASK_DEF --query 'taskDefinition' | jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')"
done
APP_REV=$(aws ecs describe-task-definition --task-definition adr-production-app --query "taskDefinition.revision" --output text)
WORKER_REV=$(aws ecs describe-task-definition --task-definition adr-production-celery-worker --query "taskDefinition.revision" --output text)
BEAT_REV=$(aws ecs describe-task-definition --task-definition adr-production-celery-beat --query "taskDefinition.revision" --output text)
FLOWER_REV=$(aws ecs describe-task-definition --task-definition adr-production-flower --query "taskDefinition.revision" --output text)
aws ecs update-service --cluster adr-production-cluster --service adr-production-app-service --task-definition adr-production-app:$APP_REV --force-new-deployment
aws ecs update-service --cluster adr-production-cluster --service adr-production-celery-worker --task-definition adr-production-celery-worker:$WORKER_REV --force-new-deployment
aws ecs update-service --cluster adr-production-cluster --service adr-production-celery-beat --task-definition adr-production-celery-beat:$BEAT_REV --force-new-deployment
aws ecs update-service --cluster adr-production-cluster --service adr-production-flower --task-definition adr-production-flower:$FLOWER_REV --force-new-deployment

# Migrations (after services stabilize)
TASK_ARN=$(aws ecs list-tasks --cluster adr-production-cluster --service-name adr-production-app-service --query 'taskArns[0]' --output text)
aws ecs execute-command --cluster adr-production-cluster --task $TASK_ARN --container app --interactive --command "flask db upgrade"

# Monitor
aws ecs describe-services --cluster adr-production-cluster \
  --services adr-production-app-service adr-production-celery-worker adr-production-celery-beat adr-production-flower \
  --query "services[].{name:serviceName,running:runningCount,desired:desiredCount,status:deployments[0].rolloutState}" \
  --output table
```

## Database Quick Reference

```bash
# Flask shell access
TASK_ARN=$(aws ecs list-tasks --cluster adr-production-cluster --service-name adr-production-app-service --query 'taskArns[0]' --output text)
aws ecs execute-command --cluster adr-production-cluster --task $TASK_ARN --container app --interactive --command "flask shell"

# In flask shell:
from app.extensions import db
db.session.execute(db.text("SELECT column_name FROM information_schema.columns WHERE table_name = 'TABLE' ORDER BY ordinal_position")).fetchall()
db.session.execute(db.text("SELECT version_num FROM alembic_version")).fetchall()
```

## User Roles

System: `super_admin`, `system_admin`, `support_agent`, `staff`
Tenant: `tenant_admin`, `mediator`, `arbitrator`, `case_manager`, `viewer`

## Subagents

This project uses specialized subagents in `.claude/agents/`. Claude Code automatically delegates tasks based on each agent's description. You can also invoke them explicitly:

```
Use the flask-developer agent to add a new endpoint for...
Have the database-engineer agent write a migration for...
Ask the aws-architect agent to check the ECS service health...
```

See `.claude/agents/` for all available agents.
