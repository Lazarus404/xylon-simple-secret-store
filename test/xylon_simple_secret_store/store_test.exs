defmodule XylonSimpleSecretStore.StoreTest do
  use ExUnit.Case, async: false

  alias XylonSimpleSecretStore.{Record, Store}

  setup do
    Store.clear!()
    :ok
  end

  test "put and get round-trip" do
    assert :ok = Store.put("acme", %{current: "secret-a"})
    assert {:ok, %Record{current: "secret-a"}} = Store.get("acme")
  end

  test "get missing returns not_found" do
    assert {:error, :not_found} = Store.get("missing")
  end

  test "put rejects empty current" do
    assert {:error, :empty_current} = Store.put("acme", %{current: ""})
  end

  test "delete removes tenant" do
    assert :ok = Store.put("acme", %{current: "s"})
    assert :ok = Store.delete("acme")
    assert {:error, :not_found} = Store.get("acme")
  end

  test "delete missing returns not_found" do
    assert {:error, :not_found} = Store.delete("nope")
  end

  test "list returns tenant ids with redacted records" do
    assert :ok = Store.put("acme", %{current: "secret"})
    assert :ok = Store.put("other", %{current: "x"})

    list = Store.list() |> Enum.sort_by(& &1.tenant_id)
    assert length(list) == 2
    assert Enum.all?(list, fn row -> Map.has_key?(row, :current_present) end)
    refute Enum.any?(list, fn row -> Map.has_key?(row, :current) end)
  end

  test "rotate demotes previous with grace" do
    assert :ok = Store.put("acme", %{current: "old"})
    now = 1_700_000_000
    assert {:ok, rec} = Store.rotate("acme", "new", 900, now)
    assert rec.current == "new"
    assert rec.previous == "old"
    assert rec.previous_expires_at == now + 900
  end

  test "rotate missing returns not_found" do
    assert {:error, :not_found} = Store.rotate("missing", "n", 60)
  end
end
