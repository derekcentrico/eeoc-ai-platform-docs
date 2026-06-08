# Entra ID Authentication Handshake - Code Reference
**Author:** Derek Gordon

This document contains the exact code from the EEOC ADR Portal that implements the Entra ID (Azure AD) OIDC authentication flow. Each section includes the source code and an explanation of what it does and why.

---

## 1. Domain Routing

Before any Entra ID handshake occurs, the application determines which identity provider to use based on the user's email domain. Only `@eeoc.gov` users go to Entra ID. Everyone else goes to Login.gov.

**File:** `adr_webapp/auth/provider_router.py`

```python
class AuthProvider(Enum):
    ENTRA = "entra"
    LOGINGOV = "logingov"

# Only users at these domains are routed to Entra ID.
# To onboard a new agency, add its domain here after configuring the B2B tenant.
ENTRA_DOMAINS = frozenset(["eeoc.gov"])

def get_auth_provider_for_email(email: Optional[str]) -> AuthProvider:
    if not email:
        return AuthProvider.LOGINGOV

    normalized_email = email.lower().strip()
    parts = normalized_email.split("@")
    if len(parts) != 2 or not parts[0] or not parts[1]:
        return AuthProvider.LOGINGOV

    domain = parts[1]
    if domain in ENTRA_DOMAINS:
        return AuthProvider.ENTRA

    return AuthProvider.LOGINGOV
```

The `ENTRA_DOMAINS` frozenset is a code-level constant, not a runtime configuration. Adding a new agency requires a code change and redeployment, which is intentional - it forces a review step before granting Entra-based access.

---

## 2. Credential Loading from Key Vault

The application loads its Entra ID client credentials from Azure Key Vault at startup. No secrets appear in code, environment variables, or configuration files.

**File:** `adr_webapp/mediation_app.py` (startup block)

```python
CLIENT_ID = secret_client.get_secret("AAD-CLIENT-ID").value
CLIENT_SECRET = secret_client.get_secret("AAD-CLIENT-SECRET").value
MEDIATOR_GROUP_ID = secret_client.get_secret("MEDIATOR-GROUP-ID").value
ADMIN_GROUP_ID = secret_client.get_secret("ADMIN-GROUP-ID").value
```

**File:** `adr_webapp/mediation_app.py` (env vars)

```python
AAD_REDIRECT_URI = os.environ.get("AAD_REDIRECT_URI", "").strip() or None
SCOPE = ["User.Read", "User.Read.All", "GroupMember.Read.All", "Calendars.ReadWrite"]
GRAPH_ENDPOINT = os.environ.get("GRAPH_ENDPOINT", "https://graph.microsoft.com/v1.0")
```

| Setting | Source | Purpose |
|---|---|---|
| `AAD-CLIENT-ID` | Key Vault | The Entra ID app registration's Application (Client) ID |
| `AAD-CLIENT-SECRET` | Key Vault | Client secret for confidential client authentication |
| `AAD_AUTHORITY` | Env var | Authority URL: `https://login.microsoftonline.com/<tenant-id>` |
| `AAD_REDIRECT_URI` | Env var | Callback URL registered in the Entra app: `https://<portal>/signin-oidc` |
| `MEDIATOR-GROUP-ID` | Key Vault | Object ID of the Entra security group containing mediator accounts |
| `ADMIN-GROUP-ID` | Key Vault | Object ID of the Entra security group containing admin accounts |

The `SCOPE` array determines what Microsoft Graph permissions the token carries after login. `GroupMember.Read.All` is required for the post-login role check (Section 6 below).

---

## 3. MSAL Client Construction

The application uses Microsoft's MSAL (Microsoft Authentication Library) for Python as a confidential client. MSAL handles token acquisition, caching, and refresh.

**File:** `adr_webapp/mediation_app.py`

```python
def build_msal_app(cache=None):
    return msal.ConfidentialClientApplication(
        CLIENT_ID,
        authority=AUTHORITY,
        client_credential=CLIENT_SECRET,
        token_cache=cache,
    )
```

This is a confidential client (server-side application with a client secret). The `authority` parameter locks the application to the EEOC Entra tenant - users from other tenants cannot authenticate.

---

## 4. Authorization URL Generation (Step 1 of the Handshake)

When the user clicks "Federal Employee" on the login page, the application builds an authorization URL and redirects the browser to Entra ID.

**File:** `adr_webapp/mediation_app.py`

```python
def get_auth_url():
    session["state"] = str(uuid.uuid4())
    redirect_uri = AAD_REDIRECT_URI or url_for(
        "authorized", _external=True, _scheme="https"
    )
    auth_url = build_msal_app().get_authorization_request_url(
        SCOPE,
        state=session["state"],
        redirect_uri=redirect_uri,
        response_mode="form_post",
    )
    # MSAL 1.29.0 silently drops the response_mode kwarg.
    # Manually append it to prevent the auth code from landing in the URL
    # (which exceeds Azure Application Gateway WAF URL length limits).
    if "response_mode=" not in auth_url:
        separator = "&" if "?" in auth_url else "?"
        auth_url += f"{separator}response_mode=form_post"
    return auth_url
```

Three things happen here:

1. A random `state` parameter is generated and stored in the session. This prevents CSRF - the callback will reject any response whose `state` doesn't match.

2. `response_mode=form_post` tells Entra ID to return the authorization code via a self-submitting HTML form POST, not as a URL query parameter. This is necessary because the authorization code from Entra ID is approximately 2,000 characters, which exceeds the URL length limit imposed by the Azure Application Gateway WAF (resulting in a 403 if sent via query string).

3. MSAL 1.29.0 has a bug where it drops the `response_mode` parameter. The code detects this and appends it manually.

---

## 5. Callback Handler (Step 2 of the Handshake)

After the user authenticates at Entra ID, the browser is redirected back to `/signin-oidc` with an authorization code. The callback handler exchanges this code for tokens.

**File:** `adr_webapp/mediation_app.py`

```python
@app.route(REDIRECT_PATH, methods=["GET", "POST"])
@csrf.exempt  # state parameter provides CSRF protection
def authorized():
    # --- SameSite cookie workaround (POST → Redis → GET relay) ---
    # Entra's form_post callback is a cross-site POST. With SameSite=Lax,
    # the browser omits the session cookie, so the callback sees an empty
    # session and state validation fails.
    if request.method == "POST" and request.form.get("state"):
        relay_id = secrets.token_urlsafe(32)
        relay_key = f"{OIDC_RELAY_PREFIX}{relay_id}"
        redis_connection.setex(
            relay_key, OIDC_RELAY_TTL_SECONDS, json.dumps(dict(request.form))
        )
        resp = make_response(redirect(url_for("authorized")))
        resp.set_cookie(
            OIDC_RELAY_COOKIE, relay_id,
            max_age=OIDC_RELAY_TTL_SECONDS,
            httponly=True, secure=True, samesite="Lax",
        )
        return resp

    # On GET: retrieve the stashed POST data from Redis
    params = request.args
    relay_id = request.cookies.get(OIDC_RELAY_COOKIE)
    if relay_id:
        relay_key = f"{OIDC_RELAY_PREFIX}{relay_id}"
        relay_data = redis_connection.get(relay_key)
        if relay_data:
            redis_connection.delete(relay_key)
            params = json.loads(relay_data)

    # --- State validation ---
    if params.get("state") != session.get("state"):
        return redirect(url_for("login_page"))

    # --- Error check ---
    if "error" in params:
        flash(_("Login failed: %(error)s", error=params.get("error_description")), "danger")
        return redirect(url_for("login_page"))

    # --- Token exchange ---
    auth_code = params.get("code")
    callback_redirect_uri = AAD_REDIRECT_URI or url_for(
        "authorized", _external=True, _scheme="https"
    )
    cache = _load_cache()
    result = build_msal_app(cache=cache).acquire_token_by_authorization_code(
        auth_code, scopes=SCOPE, redirect_uri=callback_redirect_uri
    )
    _save_cache(cache)

    if "error" in result:
        flash(_("Could not acquire token: %(error)s", error=result.get("error_description")), "danger")
        return redirect(url_for("login_page"))

    # --- Session fixation protection ---
    old_session_data = dict(session)
    session.clear()
    for key in ["_permanent", "token_cache"]:
        if key in old_session_data:
            session[key] = old_session_data[key]

    # --- Populate session with user claims ---
    _claims = result.get("id_token_claims") or {}
    if "name" not in _claims:
        _claims["name"] = (
            _claims.get("preferred_username", "").split("@")[0].replace(".", " ").title()
            or "User"
        )
    session["user"] = _claims
    session["auth_provider"] = "entra"

    # --- Regenerate CSRF token ---
    session.pop("csrf_token", None)
    generate_csrf()
    session.modified = True
```

The callback proceeds through these stages:

1. **SameSite relay** - Because `SameSite=Lax` cookies are not sent on cross-site POSTs, the browser omits the session cookie when Entra ID POSTs the authorization code back. The handler stashes the POST payload in Redis (keyed by a random relay ID with 120-second TTL), sets a first-party relay cookie, and redirects as GET. The browser sends both cookies on the GET redirect, and the handler retrieves the stashed payload from Redis.

2. **State validation** - The `state` parameter from Entra ID must match the value stored in the session before the redirect. A mismatch indicates a CSRF attack or session expiry.

3. **Token exchange** - The authorization code is exchanged for an access token and ID token via MSAL's `acquire_token_by_authorization_code()`. The `redirect_uri` must exactly match the one used in the authorization request or Entra will reject it.

4. **Session fixation protection** - The session is cleared and rebuilt to prevent session fixation attacks. Only the `_permanent` flag and `token_cache` are preserved.

5. **CSRF token regeneration** - A fresh CSRF token is generated and the session is force-written to Redis.

---

## 6. Role Resolution (Step 3 - After the Handshake)

After the token exchange, the application determines the user's role by checking Entra ID security group memberships via the Microsoft Graph API.

**File:** `adr_webapp/mediation_app.py`

```python
access_token = get_token_from_cache(SCOPE)

if is_user_in_group(access_token, ADMIN_GROUP_ID, GRAPH_ENDPOINT):
    session["user_role"] = "admin"
    return redirect(url_for("admin.admin_dashboard"))

elif is_user_in_group(access_token, MEDIATOR_GROUP_ID, GRAPH_ENDPOINT):
    user_oid = session.get("user", {}).get("oid", "")
    assignment, subordinates, mediator_ids = _load_staff_hierarchy(user_oid)
    staff_role = (assignment.get("Role") or "").lower()
    session["staff_role"] = staff_role
    session["office_id"] = assignment.get("OfficeId", "")

    if staff_role in ("director", "supervisor"):
        session["user_role"] = staff_role
        return redirect(url_for("management.management_dashboard"))
    else:
        session["user_role"] = "mediator"
        return redirect(url_for("mediator.mediator_dashboard"))

else:
    session["user_role"] = "party"
```

**File:** `adr_webapp/graph_helpers.py`

```python
def is_user_in_group(access_token, target_group_id, graph_endpoint):
    if not access_token or not target_group_id:
        return False

    headers = {"Authorization": f"Bearer {access_token}"}
    params = {"groupIds": [target_group_id]}

    response = graph_client.post(
        f"{graph_endpoint}/me/checkMemberGroups",
        headers=headers, json=params,
    )
    groups_data = response.json().get("value", [])
    return target_group_id in groups_data
```

The role checks use Graph API's `checkMemberGroups` endpoint rather than reading group claims from the token. This approach works regardless of how the Entra tenant is configured (some tenants don't include group claims in tokens, or the token's groups claim can overflow for users in many groups).

The checks proceed in priority order:
1. Admin group → `admin` role → admin dashboard
2. Mediator group → role refined by staff assignment record (director, supervisor, or mediator) → appropriate dashboard
3. Neither group → `party` role (fallback for EEOC staff accessing the portal as case participants)

Role data is stored server-side in Redis. Nothing is sent to the browser.

---

## 7. Complete Handshake Flow Summary

```
Browser                     ADR Portal                      Entra ID
  |                            |                               |
  |--- Click "Federal" ------->|                               |
  |                            |-- build_msal_app()            |
  |                            |-- get_auth_url()              |
  |                            |   state = uuid4()             |
  |                            |   session["state"] = state    |
  |<-- 302 Redirect -----------|                               |
  |                                                            |
  |--- GET /authorize?client_id=...&state=...&response_mode=form_post --->|
  |                                                            |
  |                                    User authenticates (MFA)|
  |                                                            |
  |<-- POST /signin-oidc (code + state in form body) ----------|
  |                            |                               |
  |--- POST /signin-oidc ----->|                               |
  |                            |-- Stash in Redis (SameSite)   |
  |<-- 302 GET /signin-oidc ---|                               |
  |                            |                               |
  |--- GET /signin-oidc ------>|                               |
  |                            |-- Load from Redis             |
  |                            |-- Validate state              |
  |                            |-- acquire_token(code) ------->|
  |                            |<-- access_token + id_token ---|
  |                            |-- Clear session (fixation)    |
  |                            |-- session["user"] = claims    |
  |                            |-- checkMemberGroups(token) -->|
  |                            |<-- group membership ----------|
  |                            |-- session["user_role"] = role |
  |<-- 302 to dashboard -------|                               |
```

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | May 2026 | Derek Gordon / OIT | Initial release for ARC team reference |
