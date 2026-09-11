# Xylon simple secret store

Disposable shared-secret store for [Xylon](https://github.com/Lazarus404/xylon)
lab demos. Holds `tenant_id ->` secret records in ETS and serves localhost REST
for provision, rotate, and revoke.

Not durable across restarts. Safe to omit from production when using Redis or
another store behind Xylon's `get(tenant_id)` adapter.

## What problem this solves

Control HMAC auth needs per-tenant shared secrets. Lab setups should not require
a durable secrets service. This package starts with the BEAM, stores secrets in
ETS, and exposes a small HTTP API (and in-process `Store` calls) for operators
and Xylon's local secrets adapter.

## Main modules

- `XylonSimpleSecretStore` -- OTP app facade
- `XylonSimpleSecretStore.Record` -- validate / rotate / redact
- `XylonSimpleSecretStore.Store` -- GenServer + ETS
- `XylonSimpleSecretStore.Router` -- Plug REST API
- `XylonSimpleSecretStore.Application` -- Internal supervisor + Bandit

## RFCs

- [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) (HTTP semantics)
- [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) (JSON bodies)
- [RFC 6750](https://www.rfc-editor.org/rfc/rfc6750) (optional Bearer ops token)

## Run

```bash
mix deps.get
iex -S mix
```

Default listen: `127.0.0.1:8091`.

## Config

Application env `:xylon_simple_secret_store`:

| Key | Default | Meaning |
| --- | --- | --- |
| `ip` | `{127, 0, 0, 1}` | Bind address |
| `port` | `8091` | HTTP port |
| `ops_token` | `nil` | If set, require `Authorization: Bearer <token>` (except `/healthz`) |
| `allow_reveal` | `true` | Allow `?reveal=1` to return raw secrets |
| `start_http` | `true` | Start Bandit (false in test) |

## Record

```json
{
  "current": "required-non-empty",
  "previous": null,
  "previous_expires_at": null,
  "disabled?": false,
  "flags": {}
}
```

## HTTP API

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/healthz` | `{"ok":true}` |
| PUT | `/v1/tenants/:tid` | Upsert; 400 if `current` empty |
| PATCH | `/v1/tenants/:tid` | `{ "current", "grace_sec" }` rotate |
| DELETE | `/v1/tenants/:tid` | Revoke; 204 |
| GET | `/v1/tenants/:tid` | Redacted by default |
| GET | `/v1/tenants/:tid?reveal=1` | Full secrets when `allow_reveal` |
| GET | `/v1/tenants` | Redacted list |

Redacted responses omit raw `current` / `previous` and include
`current_present`, `previous_present`, `current_length`, `previous_expires_at`,
`disabled?`, `flags`.

### Examples

```bash
curl -s -X PUT http://127.0.0.1:8091/v1/tenants/acme \
  -H 'content-type: application/json' \
  -d '{"current":"lab-secret","flags":{}}'

curl -s http://127.0.0.1:8091/v1/tenants/acme

curl -s 'http://127.0.0.1:8091/v1/tenants/acme?reveal=1'

curl -s -X PATCH http://127.0.0.1:8091/v1/tenants/acme \
  -H 'content-type: application/json' \
  -d '{"current":"lab-secret-2","grace_sec":900}'

curl -s -X DELETE http://127.0.0.1:8091/v1/tenants/acme -o /dev/null -w '%{http_code}\n'
```

With ops token:

```bash
curl -s http://127.0.0.1:8091/v1/tenants \
  -H 'authorization: Bearer ops-secret'
```

## Elixir API

`XylonSimpleSecretStore.Store.put/2`, `get/1`, `delete/1`, `rotate/3`, `list/0`
for in-process use when the app is started in the same BEAM.
