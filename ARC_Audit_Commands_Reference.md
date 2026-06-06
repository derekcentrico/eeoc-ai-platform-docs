# ARC Audit Commands Reference
**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

This document lists every command used during the ARC system security and
architecture audit (May 2026). Organized by audit phase in the order they
were run.

---

## 1. Repository Extraction and Inventory

```bash
# Extract all ZIP archives into working directories
for zip in *.zip; do unzip -qo "$zip"; done

# Count repos and total files
ls -d */ | wc -l
find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' \
  -not -path '*/target/*' -not -name '*.zip' | wc -l
```

## 2. Technology Stack Classification

```bash
# Identify tech stack per repo (Java version, Spring Boot version, framework)
for dir in */; do
  grep -oP '<java.version>\K[^<]+' "$dir/pom.xml" 2>/dev/null
  grep -A1 'spring-boot-starter-parent' "$dir/pom.xml" 2>/dev/null | grep version
done

# Count API endpoints across all Java services
grep -rn --include="*.java" \
  -E '@(Get|Post|Put|Delete|Patch|Request)Mapping' . | wc -l

# Identify frontend frameworks
grep -oP '"@angular/core"\s*:\s*"\K[^"]+' */package.json 2>/dev/null
grep -oP '"react"\s*:\s*"\K[^"]+' */package.json 2>/dev/null

# Count source files by language
find . -name '*.java' -not -path '*/node_modules/*' -not -path '*/target/*' | wc -l
find . \( -name '*.ts' -o -name '*.tsx' \) -not -path '*/node_modules/*' | wc -l
find . -name '*.jsp' -o -name '*.xhtml' | wc -l

# Identify Docker base images
grep -rn --include="Dockerfile*" "^FROM" . | sort -u

# Check javax vs jakarta namespace usage
grep -rn --include="*.java" '^import javax\.' . | wc -l
grep -rn --include="*.java" '^import jakarta\.' . | wc -l
```

## 3. Secrets Detection (Gitleaks)

```bash
# Full scan across all repos, JSON output for parsing
gitleaks detect --source . --no-git --redact \
  --report-path /tmp/gitleaks-report.json

# Parse results by rule type
python3 -c "
import json, collections
with open('/tmp/gitleaks-report.json') as f:
    data = json.load(f)
by_rule = collections.Counter(f['RuleID'] for f in data)
by_repo = collections.Counter(f['File'].split('/')[0] for f in data)
print(f'Total: {len(data)}')
for rule, count in by_rule.most_common(10):
    print(f'  {rule}: {count}')
"

# Manual credential scan for patterns gitleaks might miss
grep -rn --include="*.properties" --include="*.yml" --include="*.yaml" \
  --include="*.env" -iE 'password\s*[:=]\s*[A-Za-z0-9+/]{6,}' . | \
  grep -vi 'changeme\|example\|placeholder'

# Decode base64 values from Helm secret manifests
echo "BASE64_VALUE_HERE" | base64 -d
```

## 4. Vulnerability Scanning (Trivy)

```bash
# Filesystem scan, CRITICAL and HIGH only, JSON output
trivy fs --severity CRITICAL,HIGH --format json --quiet \
  -o /tmp/trivy-report.json .

# Parse results
python3 -c "
import json, collections
with open('/tmp/trivy-report.json') as f:
    data = json.load(f)
results = data.get('Results', [])
for r in results:
    for v in r.get('Vulnerabilities', []):
        if v.get('Severity') == 'CRITICAL':
            print(f\"{v['VulnerabilityID']} | {v['PkgName']} {v['InstalledVersion']}\")
"
```

## 5. Software Composition Analysis (Grype)

```bash
# Full directory scan, JSON output
grype dir:. --output json --file /tmp/grype-report.json

# Parse results by severity
python3 -c "
import json, collections
with open('/tmp/grype-report.json') as f:
    data = json.load(f)
matches = data.get('matches', [])
by_sev = collections.Counter(
    m['vulnerability']['severity'] for m in matches
)
print(f'Total: {len(matches)}')
for s in ['Critical','High','Medium','Low']:
    print(f'  {s}: {by_sev.get(s.lower(), 0)}')
"
```

## 6. Code-Level Security Analysis (grep patterns)

Each of these scans targets a specific vulnerability class. All were run
from the `eeoc-arc-payloads/` directory against all repos.

### Deserialization (RCE surface)

```bash
# ObjectInputStream usage
grep -rn --include="*.java" 'ObjectInputStream\|readObject()' .

# XStream usage
grep -rn --include="*.java" 'XStream\|xstream' .

# Jackson polymorphic deserialization
grep -rn --include="*.java" \
  'enableDefaultTyping\|@JsonTypeInfo.*As.CLASS' .
```

### XML External Entity (XXE)

```bash
# XML parser instantiations
grep -rn --include="*.java" \
  'DocumentBuilderFactory\|SAXParserFactory\|XMLInputFactory\|TransformerFactory' . | wc -l

# XXE protections (should match parser count; it was 0)
grep -rn --include="*.java" \
  'setFeature.*disallow-doctype-decl\|setFeature.*external-general-entities' . | wc -l
```

### Authentication and Authorization Gaps

```bash
# Endpoints without method-level auth
grep -rn --include="*.java" '@PreAuthorize\|@Secured\|@RolesAllowed' . | wc -l
# Compare against total endpoint count (1,177 - 259 = 918 unprotected)

# permitAll configurations
grep -rn --include="*.java" 'permitAll\|anyRequest.*permitAll' .

# CORS wildcards
grep -rn --include="*.java" \
  'CrossOrigin.*"\*"\|allowedOrigins.*List.of.*"\*"' .

# CSRF disabled
grep -rn --include="*.java" 'csrf.*disable\|csrf()\.disable' .
```

### Input Validation

```bash
# Unvalidated request parameters
grep -rn --include="*.java" '@RequestParam' . | wc -l
grep -rn --include="*.java" '@RequestParam.*@Valid\|@Validated.*@RequestParam' . | wc -l

# Unvalidated path variables
grep -rn --include="*.java" '@PathVariable' . | wc -l

# Unvalidated request bodies
grep -rn --include="*.java" '@RequestBody' . | wc -l
grep -rn --include="*.java" '@Valid.*@RequestBody\|@RequestBody.*@Valid' . | wc -l
```

### SQL Injection

```bash
# Native SQL with string concatenation
grep -rn --include="*.java" \
  'createNativeQuery\|createQuery.*\+' .
```

### Broken Cryptography

```bash
# DES / MD5 usage
grep -rn --include="*.java" 'PBEWithMD5AndDES\|DesEncrypter' .

# MD5 hashing
grep -rn --include="*.java" 'MD5\|getInstance.*MD5' .

# Weak random
grep -rn --include="*.java" 'java.util.Random\b' .
```

### Security Headers

```bash
# Check which services set CSP, HSTS, X-Frame-Options
grep -rn --include="*.java" --include="*.properties" --include="*.yml" \
  'Content-Security-Policy\|X-Frame-Options\|Strict-Transport' .
```

### Session Management

```bash
# Session timeout values
grep -rn --include="*.xml" 'session-timeout' .

# HttpSession usage count
grep -rn --include="*.java" 'HttpSession\|getSession()' . | wc -l
```

### PII Logging

```bash
grep -rn --include="*.java" \
  -E 'log\.(info|debug|warn|error).*\b(email|ssn|phone|name)\b' .
```

### Exception Handling

```bash
# Broad catch blocks
grep -rn --include="*.java" 'catch\s*(\s*Exception\b' . | wc -l

# printStackTrace (stack trace leakage)
grep -rn --include="*.java" 'printStackTrace()' . | wc -l
```

### Command Injection and Path Traversal

```bash
# Process execution
grep -rn --include="*.java" 'Runtime.getRuntime().exec\|ProcessBuilder' .

# Path traversal
grep -rn --include="*.java" 'getRealPath\|new File.*request' .
```

### SSRF Surface

```bash
# HTTP client usage count
grep -rn --include="*.java" \
  'RestTemplate\|WebClient\|HttpURLConnection\|OkHttpClient' . | wc -l
```

## 7. Section 508 / WCAG 2.1 AA Scanning

```bash
# Images without alt attributes
grep -rn --include="*.html" --include="*.jsp" --include="*.xhtml" \
  '<img ' . | grep -v 'alt=' | wc -l

# HTML documents missing lang attribute
grep -rn --include="*.html" --include="*.jsp" --include="*.xhtml" \
  '<html' . | grep -v 'lang=' | wc -l

# Inline onclick handlers (keyboard-inaccessible)
grep -rn --include="*.html" --include="*.jsp" --include="*.xhtml" \
  'onclick=' . | wc -l

# Form inputs vs labels
grep -rn --include="*.html" --include="*.jsp" --include="*.xhtml" '<input ' . | wc -l
grep -rn --include="*.html" --include="*.jsp" --include="*.xhtml" '<label' . | wc -l

# Tables and headers
grep -rn --include="*.html" --include="*.jsp" --include="*.xhtml" '<table' . | wc -l
grep -rn --include="*.html" --include="*.jsp" --include="*.xhtml" '<th' . | wc -l
```

## 8. Codebase Age Analysis

```bash
# Copyright notices with years
grep -rn --include="*.java" --include="*.jsp" --include="*.xml" \
  -i 'copyright.*20[0-9][0-9]' . | grep -oP '20[0-9]{2}' | sort | uniq -c

# Servlet API version in web.xml
grep 'web-app.*version' */WebContent/WEB-INF/web.xml 2>/dev/null

# JSF/PrimeFaces usage (dates the architecture era)
grep -rn --include="*.java" 'FacesContext\|ManagedBean\|SessionScoped' .

# Framework version markers
grep -rn --include="pom.xml" 'jboss-jsf-api' .
grep -rn --include="build.gradle" 'jboss-jsf-api' .
```

## 9. Deployment Verification

```bash
# Identify deployed services from production secrets script
cat azure-extmgmt-prod-master/arc/create-secrets.sh

# Check Helm production configs
find azure-extmgmt-helm-master/configs/prod/ -name "*.yaml" | sort

# Verify Docker images referenced in production
grep -rn --include="*.yaml" 'image:.*eus1' \
  azure-extmgmt-helm-master/ azure-extmgmt-prod-master/
```

## 10. Line Number Verification (4-Loop Pass)

```bash
# Verify specific file+line references cited in the audit document
sed -n '75p' FederalHearings-ims-aks/src/main/resources/application.properties
sed -n '45p' EmployerWebService-ims-aks-test/src/main/java/gov/eeoc/employer/ws/resource/es/EmployerElasticResource.java
sed -n '56p' IntakeCollectionsService-main/src/main/java/gov/eeoc/foi/config/SecurityConfig.java
# (repeated for every file+line cited in the document)
```

---

## Tools Required

All tools used in this audit are installed on the platform development
workstation. No external services, cloud scanning platforms, or paid
vendor tools were required.

| Tool | Purpose | Install |
|---|---|---|
| gitleaks | Secrets detection | `go install github.com/gitleaks/gitleaks/v8@latest` or binary release |
| trivy | Container and filesystem CVE scanning | Binary release from aquasecurity/trivy |
| grype | Software composition analysis | Binary release from anchore/grype |
| grep/find/sed | Pattern-based code analysis | Standard Linux utilities |
| python3 | JSON report parsing, data aggregation | System Python 3.12+ |
| base64 | Decoding Helm secret values | Standard Linux utility |
| unzip | Repository extraction | Standard Linux utility |

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | May 2026 | Derek Gordon / OCIO | Initial commands reference |
