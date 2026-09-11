defmodule XylonSimpleSecretStore.Application do
  @moduledoc """
  Internal OTP application for the simple secret store.

  ## What problem this solves

  The store needs a supervised ETS GenServer and, outside tests, an HTTP listener
  on configurable `ip` / `port`. This module starts `Store` always and Bandit with
  `Router` when `start_http` is true (default).

  ## Internal

  Prefer `XylonSimpleSecretStore.Store` and the HTTP API from host code; do not
  call `start/2` directly.

  ## RFCs

  - [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) (HTTP server via Bandit/Plug)
  - Packaging / supervision only beyond that
  """

  use Application

  @doc false
  @impl true
  def start(_type, _args) do
    children =
      [
        XylonSimpleSecretStore.Store
      ] ++ http_child()

    opts = [strategy: :one_for_one, name: XylonSimpleSecretStore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp http_child do
    if Application.get_env(:xylon_simple_secret_store, :start_http, true) do
      ip = Application.get_env(:xylon_simple_secret_store, :ip, {127, 0, 0, 1})
      port = Application.get_env(:xylon_simple_secret_store, :port, 8091)

      [
        {Bandit,
         plug: XylonSimpleSecretStore.Router,
         scheme: :http,
         port: port,
         ip: ip}
      ]
    else
      []
    end
  end
end
