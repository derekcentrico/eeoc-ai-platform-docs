# ARC Developer Remediation Runbook
**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

## How to Use This Runbook

This is the execution document for the remediation defined in
`ARC_Modernization_Audit_and_Phased_Plan.md`. The audit explains *what* is wrong
and *why*. This runbook tells you *exactly what to type* and *how to prove the
fix worked*.

Rules for everyone working from this document:

1. **Do the tasks in the order given.** Each Phase 0 task lists what it depends
   on. A task is not ready until its dependencies are marked Done.
2. **A task is not Done until its Verify step passes.** "I changed the file" is
   not Done. "I ran the Verify command and got the expected output" is Done.
3. **Do not improvise.** If a step does not match what you see, stop and escalate
   in the `#arc-remediation` channel. Do not guess, do not work around it, do not
   comment out a failing check.
4. **Never replace one hardcoded secret with another hardcoded secret.** Every
   credential goes to Azure Key Vault. No exceptions.
5. **Work on a branch, open a PR, get one review.** Branch naming:
   `fix/<repo>-<task-id>` (example: `fix/federalhearings-p0-05`).
6. **One task, one PR** where practical. Small PRs are reviewable. A 40-file PR
   is not.

The `eeoc-arc-payloads/` directory is a read-only reference of the audited
source. You do not commit to it. You work in the real ARC repositories.

---

## 1. Before You Start

### 1.1 Access and tooling

Confirm you have all of the following before picking up any task. If you are
missing one, request it first - do not start and get blocked halfway.

| Requirement | How to confirm |
|---|---|
| Azure CLI logged in to the ARC subscription | `az account show` shows the correct subscription |
| Key Vault `set`/`get` permission | `az keyvault secret list --vault-name <VAULT>` returns without error |
| Write access to the target ARC repo | `git push` to a test branch succeeds |
| `gitleaks` v8.18+ installed | `gitleaks version` |
| `pre-commit` installed | `pre-commit --version` |
| Java 21 JDK + Maven (for Java repos) | `java -version`, `mvn -version` |
| `bfg.jar` available (for history scrub only) | file present, `java -jar bfg.jar --version` |

### 1.2 Fill in these values once

Every command below uses these placeholders. Get the real values from the
infrastructure team or the deployment readiness plan and keep them in front of
you. Do not paste secrets into chat or tickets.

| Placeholder | Meaning | Where to get it |
|---|---|---|
| `<VAULT>` | ARC Key Vault name | Infra team / Configuration Management Plan |
| `<RG>` | Resource group for ARC AKS | Infra team |
| `<AKS>` | AKS cluster name | Infra team |
| `<NAMESPACE>` | Kubernetes namespace for the service | `kubectl get ns` |

### 1.3 Confirm the Key Vault secret-delivery mechanism

Ask the infrastructure team one question before starting task P0-09:
**"Is the Azure Key Vault CSI driver add-on enabled on the cluster?"**

- **Yes** → you may migrate Kubernetes secret manifests to `SecretProviderClass`
  now (see P0-09, Option B).
- **No** → use the Spring Boot Key Vault starter for application secrets
  (P0-09, Option A). The CSI driver is provisioned later in Phase 4. Either way,
  the hardcoded YAML files are deleted in Phase 0.

---

## 2. Task Card Conventions

Every Phase 0 task is a numbered card with the same fields. Read all fields
before you touch a file.

- **ID / Title** - the task identifier and one-line name.
- **Severity / Week / Repos / Depends on** - priority, the week it belongs to,
  the repositories it touches, and the task IDs that must be Done first.
- **Why** - one or two lines. Read it; it tells you what breaks if you get this
  wrong.
- **Steps** - exact, in order. Commands are copy-paste. Code blocks show
  `// BEFORE` and `// AFTER`.
- **Do NOT** - the specific mistakes that have to be avoided on this task.
- **Done when** - the acceptance criteria. All boxes must be true.
- **Verify** - the exact command to run and the output that proves success.

Severity maps to risk: **CRITICAL** = exploitable now, do first. **HIGH** =
serious gap, same sprint. Source references (for example "Audit §3.1") point to
the section of the audit that documents the finding.

---

## 3. Phase 0 - Emergency Security Hardening (Weeks 1-4)

Nothing in this phase is optional. Every item is either exploitable today or an
active compliance violation. Target: all tasks Done and verified within four
weeks.

### 3.1 Execution order

Do Week 1 credential and configuration work first. History scrub (P0-10) only
runs *after* every credential is rotated (P0-01 through P0-04), because the
scrub is what makes the old leaked values safe to abandon.

```
Week 1   Per credential, in this order (see Zero-downtime rotation rule below):
         (a) write the CURRENT value into Key Vault
         (b) deploy the Key Vault reference config, verify the service connects
         (c) rotate the value at the source + update Key Vault, restart, verify
         P0-01 DB passwords      ┐
         P0-02 OAuth/svc pwds    ┤ each runs (a) -> (b) -> (c)
         P0-03 auth signing keys ┤
         P0-04 other credentials ┘
         P0-05 fix CORS wildcards (+ localhost via dev profile)
         P0-06 reduce session timeouts
         P0-07 add .gitignore rules
         P0-08 install pre-commit hooks
Week 2   P0-09 delete dead secret files + migrate k8s manifests  (cutover already live)
         P0-10 git history scrub - scoped, with code freeze       (needs P0-01..04, P0-09)
         P0-11 re-enable CSRF
Week 2-3 P0-12 add security headers
Week 3   P0-13 PII log redaction
Week 4   buffer + exit gate verification (Section 3.4)
```

**Zero-downtime rotation rule - read before P0-01 through P0-04.** Never change a
live credential at its source until the running service is already reading that
credential from Key Vault and you have confirmed it works. The order for every
secret is:

1. Write the **current** value into Key Vault.
2. Deploy the config that points the service at the Key Vault reference, and
   confirm the service starts and authenticates while the value is still the old
   one. This is the cutover; it carries no risk because nothing has changed yet.
3. **Only then** rotate the value at its source (Oracle, the OAuth provider, the
   registry) and update the Key Vault secret to the new value. Restart and verify.

If you skip to step 3 - rotate at the source while the service still reads the
old value from its manifest or properties file - the next restart boots with a
dead credential and fails to authenticate. That is a self-inflicted outage. The
hardcoded files are deleted in P0-09 *after* every service is reading from Key
Vault.

---

### P0-01 - Rotate production database passwords

| | |
|---|---|
| **Severity** | CRITICAL |
| **Week** | 1 |
| **Repos** | `azure-extmgmt-helm` (config source); Oracle DB; Key Vault |
| **Depends on** | none - but follow the Zero-downtime rotation rule (cut over to Key Vault before rotating) |
| **Source** | Audit §3.1 |

**Why:** Six production Oracle passwords are committed in plaintext (base64) in
`azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml`. Anyone with repo
access has production database access right now. The service currently reads these
passwords from the Kubernetes secret built from that YAML - so the password
cannot be changed in Oracle until the service has been pointed at Key Vault
first, or the next pod restart boots with a dead credential.

**Steps** (per database account - do not change the Oracle password before step 4)

1. Coordinate a maintenance window with the DBA team. These are production
   accounts; the cutover and rotation both restart pods.
2. Read the current value only to confirm which account it is - do not paste it
   anywhere:
   ```bash
   grep IMS_DATABASE_SERVICE_USER_PASSWORD \
     azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml
   echo "<base64-value>" | base64 -d   # confirm account, then clear your scrollback
   ```
3. **Cut over to Key Vault first (no password change yet).** Write the *current*
   password into Key Vault, deploy the Key Vault reference config to the service
   (P0-09, Option A or B), restart, and confirm the service connects to Oracle
   reading from Key Vault:
   ```bash
   az keyvault secret set --vault-name <VAULT> \
     --name arcdb-s-admin-password --value "<current_password>"
   # deploy KV-reference config, then:
   kubectl -n <NAMESPACE> rollout restart deployment <deployment>
   # confirm healthy BEFORE proceeding
   ```
4. Generate a new password (24+ chars, mixed case, numbers, symbols):
   ```bash
   python3 -c "import secrets; print(secrets.token_urlsafe(24))"
   ```
5. Rotate at the source and update Key Vault in the same window (DBA runs the
   SQL):
   ```sql
   ALTER USER s_ims IDENTIFIED BY "<new_password>";
   ```
   ```bash
   az keyvault secret set --vault-name <VAULT> \
     --name arcdb-s-admin-password --value "<new_password>"
   ```
6. Restart the affected pods and confirm healthy:
   ```bash
   kubectl -n <NAMESPACE> rollout restart deployment <deployment>
   ```
7. Repeat 3-6 for all six passwords:
   `IMS_DATABASE_SERVICE_USER_PASSWORD`, `IMS_DATABASE_REPORT_USER_PASSWORD`,
   `IMS_DATABASE_FEDSEP_USER_PASSWORD`, `FEDSEP_AWSDB_PASSWORD`,
   `FEDSEP_BODDB_PASSWORD`, `FEDSEP_DATABASE_PASSWORD`.

**Do NOT**
- **Do not run the `ALTER USER` in Oracle before the service is reading from Key
  Vault (step 3).** This is the P0-01/P0-09 race: rotate-first means the next
  restart reads the old password from the still-present YAML and fails auth.
- Do not edit the YAML file to hold the new password. The file gets deleted in
  P0-09. The new password lives in Key Vault only.
- Do not rotate all six at once without confirming each service comes back
  healthy between rotations.

**Done when**
- [ ] All six DB passwords changed in Oracle and stored in Key Vault.
- [ ] Each affected service returns healthy after restart.
- [ ] No new value was written back into any source file.

**Verify**
```bash
# each secret exists and has a fresh version timestamp
az keyvault secret show --vault-name <VAULT> --name arcdb-s-admin-password \
  --query "attributes.created"
# service health
kubectl -n <NAMESPACE> get pods   # all Running, READY n/n
```

---

### P0-02 - Rotate OAuth and service passwords in properties files

| | |
|---|---|
| **Severity** | CRITICAL |
| **Week** | 1 |
| **Repos** | `FederalHearings`, `FepaGateway`, `EmailWebService` |
| **Depends on** | none |
| **Source** | Audit §3.1 |

**Why:** Live OAuth and database passwords are hardcoded in
`application.properties` files, including values like `password123` and
`prepa2019`.

**Steps**

1. Locate each hardcoded credential:
   - `FederalHearings-ims-aks/src/main/resources/application.properties:75`
     (`app.oauth.password`) and `:77` (`app.oauth.client.password`)
   - `FepaGateway-ims-aks/src/main/resources/application.properties` - 9 OAuth
     passwords starting at line 62
   - `EmailWebService-ims-aks-test/src/main/resources/application-LOCAL.properties:14-16`
     (database passwords)
2. For each one, follow the Zero-downtime rotation rule. **First** move the
   *current* value into Key Vault and switch the property to a Key Vault
   reference, then deploy and confirm the service still authenticates:
   ```properties
   # BEFORE:
   app.oauth.password=password123
   # AFTER:
   app.oauth.password=${arc-federalhearings-oauth-password}
   ```
   ```bash
   az keyvault secret set --vault-name <VAULT> \
     --name arc-federalhearings-oauth-password --value "<current_value>"
   ```
   **Then** rotate at the source (OAuth provider / DB) and update the Key Vault
   secret to the new value; restart and confirm. Do not rotate at the source
   while the service still reads the literal from the properties file.
3. Add the Key Vault starter if the service does not have it yet (see P0-09).

**Do NOT**
- Do not move a password from `application.properties` into
  `application-LOCAL.properties`. That is the same problem in a different file.

**Done when**
- [ ] Every listed property references a Key Vault secret, not a literal value.
- [ ] Each new secret exists in Key Vault.
- [ ] Service starts and authenticates against its OAuth provider / DB.

**Verify**
```bash
# no literal passwords remain in these files
grep -rnE 'password\s*=\s*[A-Za-z0-9]' \
  FederalHearings-ims-aks/src/main/resources/application.properties \
  FepaGateway-ims-aks/src/main/resources/application.properties \
  EmailWebService-ims-aks-test/src/main/resources/application-LOCAL.properties \
  | grep -v '\${'    # expect: no output
```

---

### P0-03 - Rotate the 14 private keys in AuthorizationService

| | |
|---|---|
| **Severity** | CRITICAL |
| **Week** | 1 |
| **Repos** | `AuthorizationService` |
| **Depends on** | none |
| **Source** | Audit §3.1 (most dangerous single finding) |

**Why:** 14 RSA private keys for the OAuth authorization server are committed
across environment YAML files. These keys sign and validate every auth token in
the system. One key forges tokens for any user, including admins.

**Steps**

1. The keys are here:
   - `AuthorizationService-ims-aks/src/main/resources/application-DEV.yaml:3`
   - `...application-TEST.yaml:3`
   - `...application-UAT.yaml:3`
   - `...application-TRAIN.yaml:3`
   - `...application.yaml:92`
2. Generate a new key pair per environment:
   ```bash
   openssl genrsa -out private-DEV.pem 2048
   openssl rsa -in private-DEV.pem -pubout -out public-DEV.pem
   ```
3. Store each private key in Key Vault:
   ```bash
   az keyvault secret set --vault-name <VAULT> \
     --name arc-auth-signing-key-dev --file private-DEV.pem
   ```
4. Replace the YAML value with a Key Vault reference. The YAML must contain no
   key material.
5. Distribute the new public keys to every service that validates tokens
   (resource servers reading JWKS). Confirm each can validate a freshly issued
   token.
6. Securely delete local key files:
   ```bash
   shred -u private-*.pem public-*.pem
   ```

**Do NOT**
- Do not reuse the same key pair across environments.
- Do not roll DEV/TEST/UAT/TRAIN and PROD in one change. Validate non-prod
  token issuance and validation end-to-end first, then do PROD.

**Done when**
- [ ] New key pair generated for each environment.
- [ ] All private keys in Key Vault; zero key material in any YAML file.
- [ ] Token issuance and validation confirmed in each environment.
- [ ] Local key files shredded.

**Verify**
```bash
# no PEM blocks remain in source
grep -rn 'BEGIN RSA PRIVATE KEY\|BEGIN PRIVATE KEY' \
  AuthorizationService-ims-aks/src/main/resources/   # expect: no output
```

---

### P0-04 - Rotate remaining committed credentials

| | |
|---|---|
| **Severity** | CRITICAL |
| **Week** | 1 |
| **Repos** | `azure-extmgmt-helm`, `EmailWebService` |
| **Depends on** | none |
| **Source** | Audit §3.1 |

**Why:** Registry, email, storage, and monitoring credentials are also in
source: usable for image pushes, sending mail as EEOC, reading storage, and
log ingestion.

**Steps** - for each item: regenerate at the source, store in Key Vault, remove
from source.

1. **ACR token** - `azure-extmgmt-helm-master/configs/DEV/dockerconfig.yaml`.
   Regenerate the registry credential in Azure, store as
   `arc-acr-pull-secret`.
2. **SendGrid API tokens** -
   `EmailWebService-ims-aks-test/src/test/resources/application.properties` and
   `.../application-LOCAL.properties`. Revoke in SendGrid, issue new, store as
   `arc-sendgrid-api-key`.
3. **Azure Storage account key** -
   `azure-extmgmt-helm-master/configs/prod/prod-birt-reports-storage.yaml`.
   Rotate the storage key, store as `arc-birt-storage-key`.
4. **Application Insights connection string** -
   `azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml`. Rotate the
   instrumentation key, store as `arc-appinsights-connection-string`.

**Done when**
- [ ] All four credential types regenerated, stored in Key Vault, removed from
      source.
- [ ] Image pull, email send, BIRT storage read, and telemetry ingest all
      confirmed working.

**Verify**
```bash
gitleaks detect --source ./azure-extmgmt-helm-master --no-git --redact \
  --report-path /tmp/p0-04-helm.json
gitleaks detect --source ./EmailWebService-ims-aks-test --no-git --redact \
  --report-path /tmp/p0-04-email.json
# expect: "leaks found: 0" on both
```

---

### P0-05 - Fix CORS wildcards (5 services)

| | |
|---|---|
| **Severity** | CRITICAL |
| **Week** | 1 |
| **Repos** | `FederalHearings`, `EmployerWebService`, `SearchDataWebService`, `ECMService`, `AzureAdService` |
| **Depends on** | none |
| **Source** | Audit §4.5 |

**Why:** Five services send `Access-Control-Allow-Origin: *`, letting any website
on the internet make authenticated cross-origin requests to EEOC APIs. FepaGateway
is already configured correctly - copy its pattern.

**Steps**

1. **FederalHearings** -
   `src/main/java/gov/eeoc/hearing/config/SecurityConfig.java:75`:
   ```java
   // BEFORE:
   configuration.setAllowedOrigins(List.of("*"));
   // AFTER:
   configuration.setAllowedOrigins(List.of(
       "https://hearings.eeoc.gov",
       "https://hearings-uat.eeoc.gov"));
   ```
2. **EmployerWebService** -
   `src/main/java/gov/eeoc/employer/ws/resource/es/EmployerElasticResource.java:45`:
   ```java
   // BEFORE: @CrossOrigin(origins = "*")
   // AFTER:  @CrossOrigin(origins = {"https://eeoc.gov", "https://*.eeoc.gov"})
   ```
3. Same change for:
   - `SearchDataWebService-ims-aks-test-es8/src/main/java/gov/eeoc/searchws/resource/HearingSearchResource.java:39`
   - `ECMService-ims-aks-test/src/main/java/gov/eeoc/ecm/resource/ContentManagementResource.java:56`
   - `AzureAdService-main/src/main/java/gov/eeoc/azure/ad/resource/AzureAdResource.java:31`

**Reference (correct implementation):**
`FepaGateway-ims-aks/src/main/java/gov/eeoc/bff/fepa/security/OAuth2ResourceServerSecurityConfiguration.java`
- scopes to `https://*.eeoc.gov` plus localhost for development.

**Local development - do not skip this.** The explicit origins above will block
local frontends and break every developer's environment the moment this ships.
Add local origins (for example `http://localhost:4200` for an Angular dev server)
through the service's **dev/local Spring profile only**, never in the production
config:
```java
// application-local.properties / @Profile("local") bean only
configuration.setAllowedOrigins(List.of(
    "https://hearings.eeoc.gov", "https://hearings-uat.eeoc.gov",
    "http://localhost:4200"));   // local profile ONLY
```
Profile-gating keeps localhost out of the production CORS policy while keeping
local development working. Do this for all five services.

**Do NOT**
- Do not "fix" a wildcard by adding `setAllowCredentials(false)` and leaving the
  `*`. Remove the wildcard.
- Do not put `localhost` in the production origin list. Local origins live in the
  dev/local profile only.

**Done when**
- [ ] All five services list explicit `eeoc.gov` origins, no `*`.
- [ ] Each service builds and starts.

**Verify**
```bash
grep -rnE '@CrossOrigin\(origins = "\*"\)|setAllowedOrigins\(List\.of\("\*"\)\)' \
  FederalHearings-ims-aks EmployerWebService-ims-aks-test \
  SearchDataWebService-ims-aks-test-es8 ECMService-ims-aks-test \
  AzureAdService-main   # expect: no output
# runtime check
curl -s -I -H "Origin: https://evil.example.com" https://<service-url>/<endpoint> \
  | grep -i 'access-control-allow-origin'   # expect: not "*"
```

---

### P0-06 - Reduce session timeouts to 30 minutes

| | |
|---|---|
| **Severity** | HIGH |
| **Week** | 1 |
| **Repos** | `ImsNXG`, `FedSep` |
| **Depends on** | none |
| **Source** | Audit §4.11 (NIST 800-53 AC-12) |

**Why:** ImsNXG holds sessions for 5 hours, FedSep for 3. Federal systems require
idle termination; the standard is 30 minutes.

**Steps**

1. `ImsNXG-master/ImsNXG/WebContent/WEB-INF/web.xml:91`:
   ```xml
   <!-- BEFORE: <session-timeout>300</session-timeout> -->
   <session-timeout>30</session-timeout>
   ```
2. `FedSep-ims-aks-test/WebContent/WEB-INF/web.xml:99`:
   ```xml
   <!-- BEFORE: <session-timeout>180</session-timeout> -->
   <session-timeout>30</session-timeout>
   ```

**Done when**
- [ ] Both `web.xml` files set `<session-timeout>30</session-timeout>`.

**Verify**
```bash
grep -n 'session-timeout' \
  ImsNXG-master/ImsNXG/WebContent/WEB-INF/web.xml \
  FedSep-ims-aks-test/WebContent/WEB-INF/web.xml   # both show 30
```

---

### P0-07 - Add `.gitignore` secret-blocking rules

| | |
|---|---|
| **Severity** | HIGH |
| **Week** | 1 |
| **Repos** | every active repo missing these rules |
| **Depends on** | none |
| **Source** | Audit §0.9 |

**Why:** Without these rules, the next secret file gets committed the same way
the last ones did.

**Steps** - append to `.gitignore` in each repo (copy from
`eeoc-arc-integration-api/.gitignore` and `eeoc-ofs-adr/.gitignore`):
```
# Secrets and credentials
*-secrets.yaml
*.pem
*.key
*.p12
*.jks
*.pfx
application-LOCAL.properties
application-DEV.properties
.env
.env.*
```

**Done when**
- [ ] Every active repo's `.gitignore` contains these patterns.

**Verify**
```bash
grep -q '\*-secrets.yaml' <repo>/.gitignore && echo OK || echo MISSING
```

---

### P0-08 - Install pre-commit hooks on every repo

| | |
|---|---|
| **Severity** | HIGH |
| **Week** | 1 |
| **Repos** | all 48 |
| **Depends on** | none |
| **Source** | Audit §0.10 |

**Why:** This is the single most effective preventive control. A gitleaks
pre-commit hook would have stopped every secret in §3.1 before it reached the
repo.

**Steps** - per repo:
```bash
cd <repo-directory>
pip install pre-commit
cp ../eeoc-arc-integration-api/.pre-commit-config.yaml .
pre-commit install
pre-commit run --all-files
```
For Java repos, swap the `ruff` hooks for:
```yaml
- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: v4.5.0
  hooks:
    - id: trailing-whitespace
    - id: end-of-file-fixer
    - id: check-yaml
    - id: check-added-large-files
```

**Reference:** `eeoc-arc-integration-api/.pre-commit-config.yaml` (gitleaks +
lint/format + 508 lint).

**Done when**
- [ ] `.pre-commit-config.yaml` present and hooks installed in every repo.
- [ ] `pre-commit run --all-files` exits 0 (fix or document any finding first).

**Verify**
```bash
pre-commit run --all-files   # exit code 0
```

---

### P0-09 - Remove secrets files and switch to Key Vault references

| | |
|---|---|
| **Severity** | CRITICAL |
| **Week** | 2 |
| **Repos** | `azure-extmgmt-helm`, `azure-extmgmt-test`, affected services |
| **Depends on** | P0-01, P0-02, P0-03, P0-04 |
| **Source** | Audit §0.2 |

**Why:** This task owns the Key Vault reference config (Options A/B below) and the
deletion of the dead hardcoded files. The config cutover is applied to each
service *during* its rotation (P0-01 through P0-04, per the Zero-downtime rotation
rule), so by the time you reach this task every service is already reading from
Key Vault. What remains here is deleting the now-dead files and migrating any
remaining Kubernetes secret manifests. Do not keep the old files "because the
values are old now."

**Steps**

1. Delete these files (only after confirming every service reads from Key Vault):
   ```
   azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml
   azure-extmgmt-helm-master/configs/prod/eml-prod-secrets.yaml
   azure-extmgmt-helm-master/configs/prod/prod-birt-reports-storage.yaml
   azure-extmgmt-helm-master/configs/TEST/ims-test-secrets.yaml
   azure-extmgmt-helm-master/configs/TEST/ims-uat-secrets.yaml
   azure-extmgmt-helm-master/configs/DEV/dockerconfig.yaml
   azure-extmgmt-test-master/cicd/secrets.tf
   azure-extmgmt-test-master/tmf_app/tmf_aks/tmf-secrets.yaml
   ```
2. **Option A - application-level (use if CSI driver is not enabled).** Add the
   Spring Boot Key Vault starter to each affected service:
   ```xml
   <dependency>
       <groupId>com.azure.spring</groupId>
       <artifactId>spring-cloud-azure-starter-keyvault</artifactId>
   </dependency>
   ```
   ```properties
   spring.cloud.azure.keyvault.secret.property-sources[0].endpoint=https://<VAULT>.vault.azure.net/
   spring.datasource.password=${arcdb-s-admin-password}
   ```
3. **Option B - infrastructure-level (use if CSI driver is enabled).** Replace
   Kubernetes secret manifests with a `SecretProviderClass`:
   ```yaml
   apiVersion: secrets-store.csi.x-k8s.io/v1
   kind: SecretProviderClass
   metadata:
     name: ims-secrets
   spec:
     provider: azure
     parameters:
       keyvaultName: "<VAULT>"
       objects: |
         array:
           - |
             objectName: arcdb-s-admin-password
             objectType: secret
   ```

**Reference (config with no secret defaults):**
`eeoc-arc-integration-api/app/config/__init__.py` - all settings come from the
environment; secrets have empty defaults and fail explicitly if unset.

**Do NOT**
- Do not delete a secrets file before its credentials are rotated (P0-01..04).
- Do not commit a `SecretProviderClass` that hardcodes a value instead of a
  Key Vault object name.

**Done when**
- [ ] All listed files deleted from HEAD.
- [ ] Every affected service resolves its secrets from Key Vault at startup.
- [ ] Services start and pass health checks.

**Verify**
```bash
ls azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml 2>&1   # No such file
# service comes up healthy
kubectl -n <NAMESPACE> get pods   # all READY
```

---

### P0-10 - Scrub credentials from git history

| | |
|---|---|
| **Severity** | CRITICAL |
| **Week** | 2 |
| **Repos** | high-risk repos (start with `azure-extmgmt-helm`, `AuthorizationService`) |
| **Depends on** | P0-01..04 (rotated), P0-09 (files deleted) |
| **Source** | Audit §0.3 |

**Why:** Deleting a file from HEAD leaves it in history. Anyone who clones can
check out an old commit and read every password. Scrub only after rotation, so
that even a leaked history copy holds dead credentials.

**Steps**

1. **Scope the work first.** Only repos where gitleaks finds secrets in *history*
   need a rewrite. Repos whose secrets were only at HEAD are already handled by
   P0-04 and P0-09 - do not rewrite their history. Build the list from the scans
   below; in practice this is a handful of repos (start with `azure-extmgmt-helm`
   and `AuthorizationService`), not all 32 active repos.
   ```bash
   gitleaks detect --source ./azure-extmgmt-helm-master --redact \
     --report-path gitleaks-helm.json
   gitleaks detect --source ./AuthorizationService-ims-aks --redact \
     --report-path gitleaks-auth.json
   ```
2. **Declare a code freeze for each repo you will rewrite, and drain it first.**
   Announce the freeze window, merge or close every open PR, and record any
   feature branches that must survive (they will be re-created or rebased onto
   the rewritten history afterward). A history rewrite invalidates every existing
   clone, PR, and branch ref on that repo - nothing in flight survives it.
3. Back up, then scrub with BFG:
   ```bash
   cp -r azure-extmgmt-helm-master azure-extmgmt-helm-master-backup
   java -jar bfg.jar --delete-files '*-secrets.yaml' azure-extmgmt-helm-master
   cd azure-extmgmt-helm-master && \
     git reflog expire --expire=now --all && \
     git gc --prune=now --aggressive
   ```
4. Force-push the rewritten history during the freeze window. Then every
   developer deletes their local clone and re-clones; preserved branches are
   re-created or rebased. Lift the freeze only after re-clones are confirmed.
5. Document every file scrubbed, the exposure date range, and the commit hashes
   that held credentials. Send to the security team.

**Do NOT**
- Do not scrub before rotation is confirmed. A scrub of live credentials still
  leaves them live anywhere the history was already cloned.
- Do not force-push without coordinating - it breaks every outstanding clone.
- Do not rewrite a repo's history while it has open PRs or unmerged feature
  branches you intend to keep. Drain the freeze first (step 2).

**Done when**
- [ ] History rewritten on all high-risk repos.
- [ ] `gitleaks detect` (with history) returns 0 on each.
- [ ] Exposure documentation delivered to security.

**Verify**
```bash
gitleaks detect --source ./azure-extmgmt-helm-master --redact \
  --report-path /tmp/p0-10.json   # expect: leaks found: 0
```

---

### P0-11 - Re-enable CSRF on browser-facing services

| | |
|---|---|
| **Severity** | HIGH |
| **Week** | 2 |
| **Repos** | `IntakeCollectionsService`, plus review `EmailWebService`, `FepaGateway`, `MessagingPoc`, `FederalHearings` |
| **Depends on** | none |
| **Source** | Audit §4.6 |

**Why:** CSRF is disabled on services that serve browser clients with cookies,
which exposes them to cross-site request forgery.

**Steps**

1. **IntakeCollectionsService** -
   `src/main/java/gov/eeoc/foi/config/SecurityConfig.java:56`:
   ```java
   // BEFORE:
   .csrf(csrf -> csrf.disable())
   // AFTER (browser-facing):
   .csrf(csrf -> csrf
       .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
       .ignoringRequestMatchers("/api/webhooks/**", "/actuator/**"))
   ```
2. For a service that is genuinely backend-to-backend only (bearer token, never
   a browser with cookies), CSRF-disable is acceptable - but you must add a
   comment stating why:
   ```java
   // CSRF disabled: called only by backend services via bearer token,
   // never by browser clients with cookies.
   .csrf(csrf -> csrf.disable())
   ```
3. Review the other four services and apply whichever case is true for each.

**Do NOT**
- Do not leave a browser-facing service with CSRF disabled and no justification.

**Done when**
- [ ] IntakeCollectionsService enforces CSRF for browser endpoints.
- [ ] Every remaining `csrf.disable()` has a one-line justification comment.

**Verify**
```bash
grep -rn 'csrf.*disable' <repo>/src/main/java   # each hit has a justification comment above it
```

---

### P0-12 - Add security headers

| | |
|---|---|
| **Severity** | HIGH |
| **Week** | 2-3 |
| **Repos** | all 19 deployable services |
| **Depends on** | none |
| **Source** | Audit §4.10 (NIST 800-53 SC-8) |

**Why:** Zero of 19 services set Content-Security-Policy or HSTS. There is a
working reference to copy.

**Steps**

1. **Spring Boot services** - add to `SecurityConfig`:
   ```java
   @Bean
   public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
       http.headers(headers -> headers
           .contentTypeOptions(Customizer.withDefaults())
           .frameOptions(frame -> frame.deny())
           .httpStrictTransportSecurity(hsts -> hsts
               .includeSubDomains(true)
               .maxAgeInSeconds(31536000))
           .contentSecurityPolicy(csp -> csp
               .policyDirectives("default-src 'self'; script-src 'self'; style-src 'self'"))
           .referrerPolicy(referrer -> referrer
               .policy(ReferrerPolicyHeaderWriter.ReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN)));
       return http.build();
   }
   ```
2. **JBoss services** (EEOCWebService, ImsNXG, FedSep, RespondentPortal,
   DocumentGeneratorAdapter) - create `SecurityHeadersFilter.java` that sets the
   same headers on every response, register it in `web.xml`.

**Reference:** `eeoc-arc-integration-api/app/middleware/security_headers.py`.

**Done when**
- [ ] Every service returns CSP, HSTS, X-Frame-Options, X-Content-Type-Options,
      and Referrer-Policy.

**Verify**
```bash
curl -s -I https://<service-url>/<endpoint> | grep -iE \
  'content-security-policy|strict-transport-security|x-frame-options|x-content-type-options|referrer-policy'
# expect: all five present
```

---

### P0-13 - Redact PII from logs

| | |
|---|---|
| **Severity** | HIGH |
| **Week** | 3 |
| **Repos** | `FederalHearings` (then sweep others) |
| **Depends on** | none |
| **Source** | Audit §7 (NIST 800-53), platform PII rule |

**Why:** FederalHearings logs email addresses and participant data at INFO level.
PII never goes to logs in any form.

**Steps**

1. Fix the known sites:
   - `FederalHearings-ims-aks/.../service/DocumentUploadMessageProcessorService.java:226`
     (logs `userEmail` with case number)
   - `FederalHearings-ims-aks/.../service/HearingCaseService.java:399`
     (logs `emailRecipients`)
   - `FederalHearings-ims-aks/.../service/common/email/EmailManagementService.java:255`
     (logs full `emailRequestVO.toString()`)
2. Redact or hash:
   ```java
   // BEFORE:
   log.info("Sending email to {} for case {}", userEmail, caseNumber);
   // AFTER (redact):
   log.info("Sending email to [REDACTED] for case {}", caseNumber);
   // OR (hash, when you need correlation):
   log.info("Sending email to hash={} for case {}",
       DigestUtils.sha256Hex(userEmail).substring(0, 8), caseNumber);
   ```

**Do NOT**
- Do not log the full request/VO object as a workaround. `toString()` re-exposes
  the PII you just removed.

**Done when**
- [ ] All three sites redacted or hashed.
- [ ] A grep sweep finds no `log.*` statement passing email/ssn/phone/name.

**Verify**
```bash
grep -rnE 'log\.(info|debug|warn|error).*\b(email|ssn|phone|name)\b' \
  FederalHearings-ims-aks/src/main/java   # expect: no PII passed to logger
```

---

### 3.4 Phase 0 exit gate

Phase 0 is complete only when **every** box below is checked and verified. This
is the evidence handed to the security team.

- [ ] All credentials rotated and confirmed working in every environment
      (P0-01..04).
- [ ] `gitleaks detect` returns 0 on HEAD of all repos (P0-04, P0-09).
- [ ] `gitleaks detect` returns 0 on full history of high-risk repos (P0-10).
- [ ] CORS wildcards eliminated on all five services (P0-05).
- [ ] Session timeouts at 30 minutes (P0-06).
- [ ] `.gitignore` secret rules present in every active repo (P0-07).
- [ ] Pre-commit hooks installed and passing on all 48 repos (P0-08).
- [ ] All hardcoded-secret files deleted; services read from Key Vault (P0-09).
- [ ] CSRF enforced on browser-facing services; disables justified (P0-11).
- [ ] Security headers present on all services (P0-12).
- [ ] PII redaction verified in logs (P0-13).

---

## 4. Phases 1-4 - Forward Outline

Phase 0 stops the bleeding. Phases 1-4 fix the conditions that produced the
findings. Each phase below gives the objective, the workstreams, sequencing
guidance, and the evidence gate that closes it. Developer-level task cards for
these phases get written at the start of each phase, the same way Section 3
breaks down Phase 0.

### 4.1 Phase 1 - Dependency Modernization and JBoss Retirement (Months 2-6)

**Objective:** Eliminate every end-of-life runtime. Land on one supported stack.

**Workstreams**

- **1.1 Retire JBoss EAP 7.4 (5 services).** Migrate or replace, smallest first
  to prove the process:

  | Service | Endpoints | Target | Note |
  |---|---|---|---|
  | DocumentGeneratorAdapter | minimal | Java 21 / Spring Boot 4.0 | Smallest - do first. Fix `getRealPath()` path traversal. |
  | EEOCWebService | 226 | Java 21 / Spring Boot 4.0 | Largest and most critical - do second. |
  | ImsNXG | 196 | Retire - ImsNXG-NG replaces | NG near complete; validate and cut over. |
  | FedSep | 166 | Retire - FedSep-NG replaces | Accelerate NG; build new API layer. |
  | RespondentPortal | 18 | Angular 19 + SB 4.0 API | New frontend; replace `DesEncrypter` with AES-256-GCM. |

  Per-service sequence: inventory endpoints → scaffold Spring Boot project (copy
  `FederalHearings-ims-aks` as the template) → replace `javax.*` with `jakarta.*`
  package by package, testing between each → replace `createNativeQuery()` string
  concatenation with parameterized `@Query` / Spring Data repositories → cut over.
  Do **not** migrate all five at once.
- **1.2 Spring Boot 2.x → 4.0 (the EOL services).** Bring the EOL Spring Boot
  services to a supported version on Java 21+.
- **1.3 Replace deprecated Docker base images.**
- **1.4 Replace broken cryptography.** Swap `PBEWithMD5AndDES` (`DesEncrypter` in
  FedSep and RespondentPortal) for AES-256-GCM with a per-secret random salt and
  a modern KDF. Migrate stored values with a **dual-read, lazy re-encryption**
  strategy, not an offline batch: during a transition window the service reads
  both the legacy DES format and the new AES format, and re-encrypts each stored
  secret to AES on the next successful use. There is no maintenance outage, and a
  concurrent login neither locks the user out nor corrupts the row - a login
  reads the old format, validates, and writes back the new one. A background job
  sweeps any values not re-encrypted naturally by the end of the window; retire
  DES read support only after the sweep confirms zero legacy rows remain.
- **1.5 Platform conformance.** Add `local-ci.sh` and Key-Vault-backed config to
  every service.
- **1.6 New-work language standard.** New services and rewrites use Python 3.13 /
  Flask or FastAPI with managed identity; modernized Java services stay Java.

**Evidence gate:** All services on Java 21+ and Spring Boot 3.2+ (or retired).
Zero JBoss. `DesEncrypter` gone. Every service builds in CI on a supported
runtime.

### 4.2 Phase 2 - Security Architecture (Months 4-9)

**Objective:** Put a controlled, authorized, observable boundary in front of ARC.

**Workstreams**

- **2.1 Deploy an API gateway** - single ingress, rate limiting, central CORS and
  logging, instead of 18 independent `SecurityConfig` files.
- **2.2 Authentication and authorization overhaul** - add method-level
  authorization (`@PreAuthorize` / app-role scopes) to the 918 endpoints that
  lack it; close `IntakeCollectionsService` `permitAll()`.
- **2.3 XXE remediation** - set `disallow-doctype-decl` (or disable DTD support)
  on all 42 XML parser instantiations.
- **2.4 SQL injection remediation** - parameterize the native-query sites
  (ImsNXG `SharedGroupsManager`, `Lookup`, etc.).
- **2.5 Input validation** - `@Valid`/`@Validated` on the 593 unvalidated query
  params and 945 path variables.
- **2.6 Supply-chain security (EO 14028)** - SBOM generation, image signing,
  provenance, scanning in CI.
- **2.7 OpenAPI + RFC 7807** - published specs and standardized error responses
  on every supported endpoint.
- **2.8 Platform conformance** - feature flags on every outbound integration;
  HMAC-signed audit logging on cross-system operations.

**Evidence gate:** Gateway routing all traffic. Rate limiting active.
Method-level authorization on every endpoint. XXE protections on all 42 parsers.
OpenAPI published for all 19 services.

### 4.3 Phase 3 - Frontend Modernization and 508 Compliance (Months 6-12)

**Objective:** Retire the legacy frontends and reach WCAG 2.1 AA.

**Workstreams**

- **3.1 Complete the NG migrations** - finish ImsNXG-NG and FedSep-NG; retire the
  JSP frontends that hold the 863 keyboard-inaccessible handlers.
- **3.2 Angular 19 alignment** - move ImsNXG-NG and FedSep-NG off Angular 16
  (EOL); replace deprecated `@angular/flex-layout` with CSS Grid.
- **3.3 USWDS adoption** - standardize on the federal design system.
- **3.4 508 remediation** - keyboard access, `lang` on all 300 pages without it,
  `alt` on the 104 images missing it, color contrast.
- **3.5 Cross-app navigation** consistent with the DAES applications.
- **3.6 508 enforcement in CI** - axe-core automated tests plus manual
  keyboard-path checks as a release gate.

**Evidence gate:** All JSP frontends retired. All Angular apps on version 19.
axe-core passing in CI. Keyboard-path checks documented.

### 4.4 Phase 4 - Consolidation and Continuous Security (Months 10-18)

**Objective:** Make the secured state the steady state.

**Workstreams**

- **4.1 Alfresco decision** - upgrade the EOL CMS (6.2.2) or replace it.
- **4.2 Infrastructure modernization** - IaC in Terraform/Bicep; add the Key
  Vault CSI driver for cluster-wide secret delivery (the Phase 4 half of P0-09).
- **4.3 Test coverage** - raise from the ~5% baseline toward 50%+.
- **4.4 Enterprise platform integration** - ARC consumed through the ARC
  Integration API and MCP Hub, not direct service or database calls.
- **4.5 Repository consolidation.**
- **4.6 Repository archival policy** - archive and lock the 42 dormant repos so
  their vulnerable code is not copied into new work.
- **4.7 Mandatory security tooling standard** - SCA, SAST, SBOM, license,
  secrets, and 508 gates in every active repo's pipeline.
- **4.8 Continuous compliance (steady state)** - zero Critical / zero High at
  every release point; secrets and PII-leak detection on every commit.

**Evidence gate:** Alfresco upgraded or replaced. IaC in Terraform/Bicep. Test
coverage at target. 42 dormant repos archived and locked. Every active repo runs
the full security gate set on every release.

---

## 5. Attestation

- [ ] Phase 0 task cards completed and each Verify step passed
- [ ] Phase 0 exit gate (Section 3.4) fully checked
- [ ] Credential exposure documentation delivered to the security team
- [ ] Phase 1 task cards drafted before Phase 1 work begins

**Authorized Official:** ________________________________
**Date:** ________________________________

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | June 2026 | Derek Gordon / OCIO | Initial developer remediation runbook - Phase 0 task cards, Phases 1-4 forward outline |
