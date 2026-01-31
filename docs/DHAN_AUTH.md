# Dhan API key auth — access token lifecycle

Dhan uses an **API Key & Secret** flow (auth.dhan.co): the access token is user-bound and is only issued after the user logs in in the browser. There is no server-only way to mint a token from API key + secret alone.

## Flow (3 steps)

1. **Login** — Visit `GET /auth/dhan/login`. The app calls Dhan to generate a consent session, then redirects you to **auth.dhan.co** to log in and approve.
2. **Callback** — After login, Dhan redirects to `GET /auth/dhan/callback?tokenId=...`. The app exchanges the tokenId for an access token and stores it in `dhan_access_tokens`.
3. **Usage** — The DhanHQ client reads the token from the DB (injected in `config/initializers/dhanhq.rb`). No manual copy-paste.
4. **Expiry** — When the token expires, trading jobs halt. Re-login at `/auth/dhan/login`.

## Environment

| Variable          | Purpose                                                                |
| ----------------- | ---------------------------------------------------------------------- |
| `DHAN_CLIENT_ID`  | App client ID (or `CLIENT_ID`). From Dhan when you create the app.     |
| `DHAN_API_KEY`    | **API Key** (app_id). From web.dhan.co → Access DhanHQ APIs → API key. |
| `DHAN_API_SECRET` | **API Secret** (app_secret). Same place as API Key.                    |

**Redirect URL** — When you create the API key on **web.dhan.co** (My Profile → Access DhanHQ APIs → API key), you must enter the **Redirect URL**. That is where Dhan sends the user after login (with `?tokenId=...`). It must match your app’s callback route exactly.

- **Production (Render):** `https://algo-trading-api.onrender.com/auth/dhan/callback` (no trailing slash)
- **Local:** `http://localhost:<port>/auth/dhan/callback` where `<port>` is your Rails server port.

## Secured token API

`GET /auth/dhan/token` returns the **latest active** Dhan access token (the one with the farthest expiry). Use it when another service needs the token without sharing your DB.

- **Auth:** `Authorization: Bearer <secret>` where `<secret>` is `DHAN_TOKEN_ACCESS_TOKEN` in env. If `DHAN_TOKEN_ACCESS_TOKEN` is not set, the endpoint responds with 503.
- **Success (200):** `{ "access_token": "...", "expires_at": "2026-02-01T12:00:00+05:30" }`
- **No valid token (404):** `{ "error": "No valid Dhan token. Re-login at /auth/dhan/login" }`
- **Unauthorized (401):** missing or wrong Bearer token.

Example:

```bash
curl -H "Authorization: Bearer YOUR_DHAN_TOKEN_ACCESS_TOKEN" https://algo-trading-api.onrender.com/auth/dhan/token
```

## Jobs

Jobs that use Dhan are guarded by `ensure_dhan_token!` in `ApplicationJob`: if there is no valid token, the job raises and trading is halted. Jobs that do not use Dhan (e.g. `CsvImportJob`) skip this guard.

## Render / production

1. Set `DHAN_CLIENT_ID`, `DHAN_API_KEY`, and `DHAN_API_SECRET` in the Render dashboard.
2. In Dhan (web.dhan.co), set the Redirect URL for your API key to `https://algo-trading-api.onrender.com/auth/dhan/callback`.
3. Deploy.
4. Visit `https://<your-app>/auth/dhan/login` **on production** once and complete login.
5. Token is stored in the **production** DB and used until expiry; then re-login as above.

**Local vs production:** Each environment has its own database. Logging in at localhost stores the token only in your local DB. For Telegram and jobs on Render to work, you must complete the login flow **on production** (open the production URL in a browser and log in there). One login per environment.
