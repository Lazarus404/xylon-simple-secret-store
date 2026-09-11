defmodule XylonSimpleSecretStore.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias XylonSimpleSecretStore.{Router, Store}

  @opts Router.init([])

  setup do
    Store.clear!()
    Application.put_env(:xylon_simple_secret_store, :ops_token, nil)
    Application.put_env(:xylon_simple_secret_store, :allow_reveal, true)
    :ok
  end

  defp json_conn(method, path, body \\ nil) do
    conn = conn(method, path)

    conn =
      if body do
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:body_params, body)
      else
        conn
      end

    Router.call(conn, @opts)
  end

  test "GET /healthz" do
    conn = json_conn(:get, "/healthz")
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"ok" => true}
  end

  test "PUT and GET redacted" do
    conn =
      json_conn(:put, "/v1/tenants/acme", %{
        "current" => "secret-a",
        "previous" => nil,
        "flags" => %{}
      })

    assert conn.status == 200

    conn = json_conn(:get, "/v1/tenants/acme")
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["current_present"] == true
    refute Map.has_key?(body, "current")
  end

  test "GET reveal=1 returns secrets when allow_reveal" do
    assert :ok = Store.put("acme", %{current: "secret-a"})

    conn = json_conn(:get, "/v1/tenants/acme?reveal=1")
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["current"] == "secret-a"
  end

  test "GET reveal=1 forbidden when allow_reveal false" do
    Application.put_env(:xylon_simple_secret_store, :allow_reveal, false)
    assert :ok = Store.put("acme", %{current: "secret-a"})

    conn = json_conn(:get, "/v1/tenants/acme?reveal=1")
    assert conn.status == 403
  end

  test "PUT empty current returns 400" do
    conn = json_conn(:put, "/v1/tenants/acme", %{"current" => ""})
    assert conn.status == 400
  end

  test "PATCH rotate" do
    assert :ok = Store.put("acme", %{current: "old"})

    conn = json_conn(:patch, "/v1/tenants/acme", %{"current" => "new", "grace_sec" => 900})
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["current_present"] == true
    assert body["previous_present"] == true

    assert {:ok, rec} = Store.get("acme")
    assert rec.current == "new"
    assert rec.previous == "old"
  end

  test "DELETE removes tenant" do
    assert :ok = Store.put("acme", %{current: "s"})
    conn = json_conn(:delete, "/v1/tenants/acme")
    assert conn.status == 204

    conn = json_conn(:get, "/v1/tenants/acme")
    assert conn.status == 404
  end

  test "GET /v1/tenants lists redacted" do
    assert :ok = Store.put("acme", %{current: "s"})
    conn = json_conn(:get, "/v1/tenants")
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_list(body["tenants"])
    assert hd(body["tenants"])["tenant_id"] == "acme"
    refute Map.has_key?(hd(body["tenants"]), "current")
  end

  test "ops_token requires bearer except healthz" do
    Application.put_env(:xylon_simple_secret_store, :ops_token, "ops-secret")

    conn = json_conn(:get, "/healthz")
    assert conn.status == 200

    conn = json_conn(:get, "/v1/tenants")
    assert conn.status == 401

    conn =
      conn(:get, "/v1/tenants")
      |> put_req_header("authorization", "Bearer ops-secret")
      |> Router.call(@opts)

    assert conn.status == 200
  end
end
