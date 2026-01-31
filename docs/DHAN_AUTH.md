# Dhan OAuth — access token lifecycle

Dhan uses **OAuth-style auth**: the access token is **user-bound** and is only issued after the user logs in. There is no server-only way to mint a token from API key + secret.

## Flow

1. **One-time login** — Visit `GET /auth/dhan/login`. You are redirected to Dhan; log in and approve.
2. **Callback** — Dhan redirects to `GET /auth/dhan/callback?code=...`. The app exchanges the code for an access token and stores it in `dhan_access_tokens`.
3. **Usage** — The DhanHQ client reads the token from the DB (injected in `config/initializers/dhanhq.rb`). No manual copy-paste.
4. **Expiry** — There is no refresh API. When the token expires, trading jobs raise and halt. Re-login at `/auth/dhan/login`.

## Environment

| Variable             | Purpose                                              |
| -------------------- | ---------------------------------------------------- |
| `DHAN_CLIENT_ID`     | App client ID (or `CLIENT_ID`)                       |
| `DHAN_CLIENT_SECRET` | App secret for token exchange (or `DHAN_API_SECRET`) |

**Redirect URI** — Register `https://<your-host>/auth/dhan/callback` in the Dhan developer console. For local dev use `http://localhost:<port>/auth/dhan/callback` where `<port>` is the port your Rails server uses (e.g. 5002 if you run `rails s -p 5002`). Nothing else must be bound to that port, or the callback will hit the wrong app and you may see a 404 (e.g. a “Whitelabel Error Page” from another stack).

## Jobs

Jobs that use Dhan are guarded by `ensure_dhan_token!` in `ApplicationJob`: if there is no valid token, the job raises and trading is halted. Jobs that do not use Dhan (e.g. `CsvImportJob`) skip this guard.

## Render / production

1. Set `DHAN_CLIENT_ID` and `DHAN_CLIENT_SECRET` in the Render dashboard.
2. Deploy.
3. Visit `https://<your-app>/auth/dhan/login` once and complete login.
4. Token is stored in the DB and used until expiry; then re-login as above.
