defmodule XylonSimpleSecretStore.RecordTest do
  use ExUnit.Case, async: true

  alias XylonSimpleSecretStore.Record

  test "validate/1 accepts non-empty current" do
    assert {:ok, %Record{current: "s", previous: nil, flags: %{}}} =
             Record.validate(%{current: "s"})
  end

  test "validate/1 rejects empty current" do
    assert {:error, :empty_current} = Record.validate(%{current: ""})
    assert {:error, :empty_current} = Record.validate(%{})
  end

  test "rotate/3 demotes current to previous with grace expiry" do
    {:ok, rec} = Record.validate(%{current: "old", flags: %{"a" => true}})
    now = 1_700_000_000
    rotated = Record.rotate(rec, "new", 900, now)

    assert rotated.current == "new"
    assert rotated.previous == "old"
    assert rotated.previous_expires_at == now + 900
    assert rotated.flags == %{"a" => true}
  end

  test "redact/1 omits raw secrets" do
    {:ok, rec} =
      Record.validate(%{
        current: "secret",
        previous: "old",
        previous_expires_at: 99,
        disabled?: false,
        flags: %{}
      })

    redacted = Record.redact(rec)

    refute Map.has_key?(redacted, :current)
    refute Map.has_key?(redacted, :previous)
    assert redacted.current_present == true
    assert redacted.previous_present == true
    assert redacted.current_length == 6
    assert redacted.previous_expires_at == 99
  end
end
