defmodule XylonSimpleSecretStore do
  @moduledoc """
  Disposable shared-secret store for Xylon lab demos.

  ## What problem this solves

  Xylon Control HMAC auth needs a `get(tenant_id)` style lookup for per-tenant
  shared secrets (provision, rotate with grace, revoke). Production hosts use
  Redis or another durable store. Lab demos need something that starts with the
  BEAM, holds secrets in ETS, and exposes localhost REST so operators and
  [xylon](https://github.com/Lazarus404/xylon) can provision without standing up
  infrastructure.

  This package is that store: not durable across restarts, bindable to loopback,
  optional ops bearer, and safe to omit when a real secrets adapter is configured.

  ## Main modules

  - `XylonSimpleSecretStore` -- OTP app facade (this module)
  - `XylonSimpleSecretStore.Application` -- Internal supervisor + Bandit
  - `XylonSimpleSecretStore.Record` -- secret record validate / rotate / redact
  - `XylonSimpleSecretStore.Store` -- GenServer + ETS `tenant_id` map
  - `XylonSimpleSecretStore.Router` -- Plug REST API

  ## RFCs

  - [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) (HTTP semantics for the REST API)
  - [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) (JSON request and response bodies)
  - [RFC 6750](https://www.rfc-editor.org/rfc/rfc6750) (optional `Authorization: Bearer` ops token)
  - No media or WebRTC RFCs; secrets are application credentials for Control auth
  """
end
