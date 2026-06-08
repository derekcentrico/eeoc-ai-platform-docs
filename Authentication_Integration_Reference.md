# Authentication Integration Reference
**Author:** Derek Gordon

## EEOC ADR Portal - Dual Identity Provider Architecture

This document describes how the EEOC ADR Portal authenticates two distinct user populations through separate identity providers. It is intended as a technical reference for teams evaluating similar patterns for EEOC applications.

---

## 1. Integration Design Decisions

The following decisions govern the authentication architecture. They are documented here because they frequently arise during cross-team integration discussions.

**Authentication protocol.** Both identity providers use standard OpenID Connect (OIDC) authorization code flow. There is no EEOC-provided broker, token relay, or custom handshake. Each provider is called directly by the application:

| Provider | Flow | Client Authentication |
|---|---|---|
| Microsoft Entra ID | Authorization code | Client secret (MSAL confidential client) |
| Login.gov | Authorization code + PKCE | `private_key_jwt` (RSA-signed JWT assertion) |

**Access restrictions.** Entra ID access is restricted at three layers, applied in sequence:

1. **Tenant** - The authority URL (`AAD_AUTHORITY`) is bound to the EEOC tenant ID. Users from other Entra tenants cannot authenticate.
2. **Domain** - The application routes only `@eeoc.gov` email addresses to Entra ID. All other domains route to Login.gov. The domain allowlist is a code-level constant, not a runtime configuration.
3. **Group membership** - After authentication, the application checks the user's membership in specific Entra ID security groups (via Graph API) to assign a role. Users who authenticate but belong to neither the admin nor mediator group receive the default `party` role.

**Callback architecture.** The application uses separate callback endpoints per provider (`/signin-oidc` for Entra ID, `/signin-oidc-logingov` for Login.gov). After each callback completes session population, both paths redirect to a single route (`index()`) that resolves the user's role and directs them to the appropriate dashboard. The callback endpoints are separate because the two providers return different token formats and require different validation logic, but the post-authentication experience is uniform.

---

## 2. User Populations

The ADR Portal serves two categories of users who authenticate through different systems:

- **Federal employees** (`@eeoc.gov` accounts) authenticate through **Microsoft Entra ID** (formerly Azure Active Directory). This covers mediators, supervisors, directors, and administrative staff.

- **External parties** (complainants, agency representatives, attorneys) authenticate through **Login.gov**, the federal government's shared sign-in service.

The application determines which provider to use based on the user's email domain. An `@eeoc.gov` address routes to Entra ID. All other addresses route to Login.gov.

---

## 3. Provider Routing

When a user enters their email on the login page, the application checks the domain against an internal allowlist.

**Routing logic** (`adr_webapp/auth/provider_router.py:31-61`):

```python
ENTRA_DOMAINS = frozenset(["eeoc.gov"])

def get_auth_provider_for_email(email: str) -> AuthProvider:
    domain = email.split("@")[1].lower()
    if domain in ENTRA_DOMAINS:
        return AuthProvider.ENTRA
    return AuthProvider.LOGINGOV
```

To onboard an additional federal agency (e.g., if EEOC began accepting respondent logins from another agency's Entra tenant), the agency's domain would be added to `ENTRA_DOMAINS` after configuring Azure B2B federation.

The login page presents two buttons: one for federal employees (Entra ID) and one for external parties (Login.gov). The Login.gov button only appears when the `LOGINGOV_ENABLED` environment variable is set to `true`.

---

## 4. Entra ID Integration (Federal Staff)

### 4.1 Protocol

OpenID Connect (OIDC) authorization code flow using MSAL (Microsoft Authentication Library) for Python. The application is registered as a confidential client in the EEOC Entra ID tenant.

### 4.2 Configuration

All credentials are stored in Azure Key Vault. No secrets appear in code or environment variables.

| Setting | Source | Purpose |
|---|---|---|
| `AAD-CLIENT-ID` | Key Vault | Application (client) ID from Entra app registration |
| `AAD-CLIENT-SECRET` | Key Vault | Client secret for confidential client auth |
| `AAD_AUTHORITY` | Environment variable | Entra ID authority URL (`https://login.microsoftonline.com/<tenant-id>`) |
| `AAD_REDIRECT_URI` | Environment variable | Callback URL registered in Entra (`https://<portal-domain>/signin-oidc`) |
| `MEDIATOR-GROUP-ID` | Key Vault | Entra security group containing mediator accounts |
| `ADMIN-GROUP-ID` | Key Vault | Entra security group containing admin accounts |

### 4.3 Scopes Requested

```python
SCOPE = ["User.Read", "User.Read.All", "GroupMember.Read.All", "Calendars.ReadWrite"]
```

`User.Read.All` and `GroupMember.Read.All` allow the application to look up group memberships after login, which determines the user's role within the portal.

### 4.4 Authentication Flow

1. User clicks "Federal Employee" login button.
2. Application generates a state parameter (UUID) for CSRF protection and redirects to Entra ID with `response_mode=form_post` (`mediation_app.py:1507-1549`).
3. User authenticates at Entra ID (MFA enforced by tenant policy, not the application).
4. Entra ID POSTs the authorization code back to `/signin-oidc`.
5. Application exchanges the code for tokens via MSAL (`mediation_app.py:3246-3250`).
6. Application validates the state parameter against the session value.

The `response_mode=form_post` setting is deliberate. The default `response_mode=query` places the authorization code in the URL, which can exceed length limits imposed by the Azure Application Gateway WAF. The authorization code from Entra ID is approximately 2,000 characters.

### 4.5 SameSite Cookie Handling

Because the Entra ID callback is a cross-site POST, browsers with `SameSite=Lax` cookies will not include the session cookie on the initial callback. The application handles this through a POST-Redirect-GET relay (`mediation_app.py:3173-3206`):

1. The POST callback stashes the authorization code in Redis (keyed by a relay UUID, TTL 120 seconds).
2. Sets a first-party relay cookie.
3. Redirects via GET to the same callback URL.
4. The GET handler reads the relay cookie, retrieves the stashed code from Redis, and proceeds with token exchange.

### 4.6 Role Resolution

After successful authentication, the application determines the user's role by checking Entra ID group memberships via the Microsoft Graph API (`mediation_app.py:2550-2626`):

```
POST https://graph.microsoft.com/v1.0/me/checkMemberGroups
{ "groupIds": ["<ADMIN-GROUP-ID>"] }
```

The checks proceed in order:

1. If the user is in `ADMIN-GROUP-ID` -> role is `admin`.
2. If the user is in `MEDIATOR-GROUP-ID` -> role is `mediator`, `supervisor`, or `director` (determined by staff assignment records in the application database).
3. If neither group matches -> role is `party` (fallback for EEOC staff accessing the portal as a participant).

Role and group information are stored in the server-side session (Redis). No role data is stored in cookies or tokens sent to the browser.

---

## 5. Login.gov Integration (External Parties)

### 5.1 Protocol

OpenID Connect (OIDC) authorization code flow with PKCE (Proof Key for Code Exchange) and `private_key_jwt` client authentication. This is Login.gov's required authentication method for server applications.

The full client implementation is in `adr_webapp/auth/logingov_client.py`.

### 5.2 Configuration

| Setting | Source | Purpose |
|---|---|---|
| `LOGINGOV_ENABLED` | Environment variable | Master toggle (`true`/`false`) |
| `LOGINGOV_AUTHORITY` | Environment variable | Login.gov base URL (`https://secure.login.gov` for production, `https://idp.int.identitysandbox.gov` for testing) |
| `LOGINGOV_CLIENT_ID` | Environment variable | URN-format client identifier (e.g., `urn:gov:gsa:openidconnect.profiles:sp:sso:eeoc:adr`) |
| `LOGINGOV-PRIVATE-KEY` | Key Vault | RSA private key (PKCS#8 PEM format) for signing client assertions |
| `LOGINGOV_REDIRECT_URI` | Environment variable | Callback URL (`https://<portal-domain>/signin-oidc-logingov`) |

### 5.3 Authentication Flow

1. User clicks "External Party" login button.
2. Application generates PKCE code verifier and challenge, state (UUID), and nonce (UUID). All three are stored in the session (`logingov_client.py:208-237`).
3. User is redirected to Login.gov with:
   - `code_challenge` (SHA-256 of the verifier, base64url-encoded)
   - `code_challenge_method=S256`
   - `acr_values=http://idmanagement.gov/ns/assurance/ial/1` (self-asserted identity; IAL2 for government-ID-verified identity is supported but not currently required)
   - `scope=openid email`
4. User authenticates at Login.gov (MFA enforced by Login.gov).
5. Login.gov redirects back to `/signin-oidc-logingov` with an authorization code.
6. Application exchanges the code for tokens.

### 5.4 Token Exchange

Login.gov does not accept client secrets. Instead, the application signs a JWT assertion with its RSA private key (`logingov_client.py:239-257`):

```python
claims = {
    "iss": client_id,
    "sub": client_id,
    "aud": f"{authority}/api/openid_connect/token",
    "jti": str(uuid.uuid4()),
    "exp": now + 300,
    "iat": now,
}
assertion = jwt.encode(claims, private_key, algorithm="RS256")
```

The token request includes:

```
POST {authority}/api/openid_connect/token

grant_type=authorization_code
code=<authorization_code>
redirect_uri=<callback_url>
code_verifier=<pkce_verifier>
client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
client_assertion=<signed_jwt>
```

### 5.5 ID Token Validation

The application validates the Login.gov ID token (`logingov_client.py:387-510`):

- **Signature**: RS256, verified against Login.gov's published JWKS (cached for 1 hour, with automatic refresh on key rotation)
- **Issuer**: Must match the configured Login.gov authority
- **Audience**: Must match the application's client ID
- **Nonce**: Must match the value stored in the session (prevents replay)
- **ACR**: Logged if lower than expected assurance level

### 5.6 Role Assignment

All Login.gov users receive the `party` role. Their case assignments are determined by looking up the authenticated email address in the `caseparticipants` table. If no cases are assigned to the email, the user is redirected to a page indicating no active cases.

---

## 6. Session Management

Both authentication paths result in a server-side session stored in Redis.

**Session configuration** (`mediation_app.py:652-669`):

| Setting | Value |
|---|---|
| Storage | Redis (TLS on port 6380) |
| Lifetime | 30 minutes default (configurable via `SESSION_TIMEOUT_MINUTES`, range 5-1440) |
| Cookie flags | `HttpOnly`, `Secure`, `SameSite=Lax` |
| CSRF time limit | None (bound to session lifetime instead) |

### 6.1 Session Fixation Protection

On both callback paths, the application clears the existing session before populating it with authenticated user data. Only the `_permanent` flag (and MSAL token cache for Entra users) are preserved. A fresh CSRF token is generated and the session is force-written to Redis.

### 6.2 Session Contents

After authentication, the session contains:

```python
session["user"] = {
    "oid": "...",                # Entra object ID or Login.gov subject UUID
    "name": "...",               # Display name
    "preferred_username": "...", # Email address
}
session["auth_provider"] = "entra" | "logingov"
session["user_role"] = "admin" | "mediator" | "director" | "supervisor" | "party"
session["session_id"] = "..."    # UUID for audit trail correlation
```

Entra ID sessions additionally contain `staff_role`, `office_id`, `sector`, and staff hierarchy data used for access control decisions within the application.

---

## 7. Key Files

| File | Contents |
|---|---|
| `adr_webapp/auth/provider_router.py` | Domain-based IdP routing |
| `adr_webapp/auth/logingov_client.py` | Login.gov OIDC + PKCE + private_key_jwt client |
| `adr_webapp/mediation_app.py` | Entra ID MSAL setup, both callback routes, role resolution, session config |
| `adr_webapp/graph_helpers.py` | Graph API group membership lookups |
| `adr_webapp/helpers/auth_decorators.py` | `@login_required` decorator |
| `adr_webapp/config.py` | Key Vault secret loading for Graph API credentials |

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | May 2026 | Derek Gordon / OIT | Initial release for ARC team reference |
