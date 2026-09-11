defmodule XylonSimpleSecretStore.Router do
  @moduledoc """
  Localhost REST for tenant shared-secret CRUD (ops bearer optional).

  ## What problem this solves

  Operators and lab scripts need to provision, rotate, list, and revoke tenant
  secrets over HTTP without embedding Elixir. This Plug router exposes `/v1/tenants`
  against `Store`, redacts by default, optionally reveals with `?reveal=1`, and
  can require `Authorization: Bearer` when `ops_token` is configured.

  ## RFCs

  - [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) (HTTP methods and status codes)
  - [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) (JSON bodies)
  - [RFC 6750](https://www.rfc-editor.org/rfc/rfc6750) (Bearer ops token when configured)
  """

  use Plug.Router

  alias XylonSimpleSecretStore.{Record, Store}

  plug :match
  plug :fetch_query_params

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Jason

  plug :maybe_auth
  plug :dispatch

  get "/healthz" do
    json(conn, 200, %{ok: true})
  end

  get "/v1/tenants" do
    tenants =
      Store.list()
      |> Enum.map(&stringify_keys/1)
      |> Enum.sort_by(& &1["tenant_id"])

    json(conn, 200, %{tenants: tenants})
  end

  get "/v1/tenants/:tid" do
    reveal? = Map.get(conn.query_params, "reveal") in ["1", "true"]

    case Store.get(tid) do
      {:ok, rec} ->
        cond do
          reveal? and allow_reveal?() ->
            json(conn, 200, stringify_keys(Map.put(Record.to_map(rec), :tenant_id, tid)))

          reveal? and not allow_reveal?() ->
            json(conn, 403, %{error: "reveal_disabled"})

          true ->
            json(conn, 200, stringify_keys(Map.put(Record.redact(rec), :tenant_id, tid)))
        end

      {:error, :not_found} ->
        json(conn, 404, %{error: "not_found"})
    end
  end

  put "/v1/tenants/:tid" do
    attrs = body_map(conn)

    case Store.put(tid, attrs) do
      :ok ->
        {:ok, rec} = Store.get(tid)
        json(conn, 200, stringify_keys(Map.put(Record.redact(rec), :tenant_id, tid)))

      {:error, :empty_current} ->
        json(conn, 400, %{error: "empty_current"})
    end
  end

  patch "/v1/tenants/:tid" do
    attrs = body_map(conn)
    current = Map.get(attrs, "current") || Map.get(attrs, :current)
    grace = Map.get(attrs, "grace_sec") || Map.get(attrs, :grace_sec)

    cond do
      not is_binary(current) or current == "" ->
        json(conn, 400, %{error: "empty_current"})

      not is_integer(grace) or grace < 1 ->
        json(conn, 400, %{error: "invalid_grace_sec"})

      true ->
        case Store.rotate(tid, current, grace) do
          {:ok, rec} ->
            json(conn, 200, stringify_keys(Map.put(Record.redact(rec), :tenant_id, tid)))

          {:error, :not_found} ->
            json(conn, 404, %{error: "not_found"})

          {:error, :empty_current} ->
            json(conn, 400, %{error: "empty_current"})
        end
    end
  end

  delete "/v1/tenants/:tid" do
    case Store.delete(tid) do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(204, "")

      {:error, :not_found} ->
        json(conn, 404, %{error: "not_found"})
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp maybe_auth(%Plug.Conn{path_info: ["healthz"]} = conn, _opts), do: conn

  defp maybe_auth(conn, _opts) do
    case ops_token() do
      token when is_binary(token) and token != "" ->
        if bearer_matches?(conn, token) do
          conn
        else
          conn
          |> json(401, %{error: "unauthorized"})
          |> halt()
        end

      _ ->
        conn
    end
  end

  defp bearer_matches?(conn, token) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> rest] -> rest == token
      ["bearer " <> rest] -> rest == token
      _ -> false
    end
  end

  defp ops_token do
    Application.get_env(:xylon_simple_secret_store, :ops_token)
  end

  defp allow_reveal? do
    Application.get_env(:xylon_simple_secret_store, :allow_reveal, true) == true
  end

  defp body_map(%Plug.Conn{body_params: params}) when is_map(params), do: params
  defp body_map(_), do: %{}

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_value(v)}
      {k, v} -> {to_string(k), stringify_value(v)}
    end)
  end

  defp stringify_value(%{} = m), do: stringify_keys(m)
  defp stringify_value(v), do: v
end
