defmodule XylonSimpleSecretStore.Record do
  @moduledoc """
  Tenant shared-secret record: current key, optional previous with grace, flags.

  ## What problem this solves

  HMAC and similar Control adapters need a current shared secret, and during
  rotation they often accept the previous secret until a grace deadline so
  clients can roll keys without a hard cutover. This struct is the in-memory
  shape for that: validate on write, rotate with grace, redact for list/detail
  responses that must not leak raw material.

  ## RFCs

  - Application credential record only; not a wire protocol
  - JSON field names align with [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) HTTP bodies
  """

  @enforce_keys [:current]
  defstruct current: nil,
            previous: nil,
            previous_expires_at: nil,
            disabled?: false,
            flags: %{}

  @typedoc """
  One tenant's shared-secret material and metadata.

  ## Fields

  - `current` -- active shared secret (required, non-empty)
  - `previous` -- prior secret during grace, or nil
  - `previous_expires_at` -- unix seconds when previous stops being valid, or nil
  - `disabled?` -- when true, adapters should reject the tenant
  - `flags` -- opaque map for lab/host metadata
  """
  @type t :: %__MODULE__{
          current: binary(),
          previous: binary() | nil,
          previous_expires_at: integer() | nil,
          disabled?: boolean(),
          flags: map()
        }

  @doc """
  Builds a validated record from a map or keyword list.

  ## Examples

      iex> {:ok, rec} = XylonSimpleSecretStore.Record.validate(%{current: "s"})
      iex> rec.current
      "s"

      iex> XylonSimpleSecretStore.Record.validate(%{current: ""})
      {:error, :empty_current}
  """
  @spec validate(map() | keyword()) :: {:ok, t()} | {:error, :empty_current}
  def validate(attrs) when is_list(attrs), do: validate(Map.new(attrs))

  def validate(attrs) when is_map(attrs) do
    current = Map.get(attrs, :current) || Map.get(attrs, "current")

    if is_binary(current) and current != "" do
      previous = Map.get(attrs, :previous) || Map.get(attrs, "previous")
      previous = if previous == "", do: nil, else: previous

      expires =
        Map.get(attrs, :previous_expires_at) || Map.get(attrs, "previous_expires_at")

      disabled? =
        case Map.get(attrs, :disabled?) || Map.get(attrs, "disabled?") ||
               Map.get(attrs, "disabled") do
          true -> true
          _ -> false
        end

      flags =
        case Map.get(attrs, :flags) || Map.get(attrs, "flags") || %{} do
          f when is_map(f) -> f
          _ -> %{}
        end

      {:ok,
       %__MODULE__{
         current: current,
         previous: previous,
         previous_expires_at: expires,
         disabled?: disabled?,
         flags: flags
       }}
    else
      {:error, :empty_current}
    end
  end

  @doc """
  Installs a new current secret; demotes old current to previous with grace.

  ## Examples

      iex> {:ok, rec} = XylonSimpleSecretStore.Record.validate(%{current: "old"})
      iex> rotated = XylonSimpleSecretStore.Record.rotate(rec, "new", 900, 1_700_000_000)
      iex> {rotated.current, rotated.previous, rotated.previous_expires_at}
      {"new", "old", 1_700_000_900}
  """
  @spec rotate(t(), binary(), pos_integer(), integer()) :: t()
  def rotate(%__MODULE__{} = rec, new_current, grace_sec, now)
      when is_binary(new_current) and new_current != "" and is_integer(grace_sec) and
             grace_sec > 0 and is_integer(now) do
    %__MODULE__{
      rec
      | current: new_current,
        previous: rec.current,
        previous_expires_at: now + grace_sec
    }
  end

  @doc """
  Map safe for list/detail responses (no raw secret material).

  ## Examples

      iex> {:ok, rec} = XylonSimpleSecretStore.Record.validate(%{current: "secret"})
      iex> redacted = XylonSimpleSecretStore.Record.redact(rec)
      iex> {Map.has_key?(redacted, :current), redacted.current_present, redacted.current_length}
      {false, true, 6}
  """
  @spec redact(t()) :: map()
  def redact(%__MODULE__{} = rec) do
    %{
      current_present: is_binary(rec.current) and rec.current != "",
      previous_present: is_binary(rec.previous) and rec.previous != "",
      current_length: if(is_binary(rec.current), do: byte_size(rec.current), else: 0),
      previous_expires_at: rec.previous_expires_at,
      disabled?: rec.disabled?,
      flags: rec.flags
    }
  end

  @doc """
  JSON-friendly map including raw secrets (lab reveal).
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = rec) do
    %{
      current: rec.current,
      previous: rec.previous,
      previous_expires_at: rec.previous_expires_at,
      disabled?: rec.disabled?,
      flags: rec.flags
    }
  end
end
