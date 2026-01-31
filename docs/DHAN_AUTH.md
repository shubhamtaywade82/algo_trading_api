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

## Jobs

Jobs that use Dhan are guarded by `ensure_dhan_token!` in `ApplicationJob`: if there is no valid token, the job raises and trading is halted. Jobs that do not use Dhan (e.g. `CsvImportJob`) skip this guard.

## Render / production

1. Set `DHAN_CLIENT_ID`, `DHAN_API_KEY`, and `DHAN_API_SECRET` in the Render dashboard.
2. In Dhan (web.dhan.co), set the Redirect URL for your API key to `https://algo-trading-api.onrender.com/auth/dhan/callback`.
3. Deploy.
4. Visit `https://<your-app>/auth/dhan/login` once and complete login.
5. Token is stored in the DB and used until expiry; then re-login as above.
