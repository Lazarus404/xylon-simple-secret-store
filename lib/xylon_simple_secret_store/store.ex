defmodule XylonSimpleSecretStore.Store do
  @moduledoc """
  GenServer + ETS map of `tenant_id` to secret `Record`.

  ## What problem this solves

  Lab and in-process callers need put/get/delete/rotate/list without going
  through HTTP. This process owns a named ETS table so reads are concurrent and
  writes stay serialized. Data is lost on restart by design.

  ## RFCs

  - In-process API only; HTTP clients use `XylonSimpleSecretStore.Router`
  - Credential semantics match `XylonSimpleSecretStore.Record` (not a wire RFC)
  """

  use GenServer

  alias XylonSimpleSecretStore.Record

  @table __MODULE__

  @doc "Starts the store process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Upserts a validated record for `tenant_id`."
  @spec put(String.t(), map() | keyword() | Record.t()) :: :ok | {:error, :empty_current}
  def put(tenant_id, attrs) when is_binary(tenant_id) and tenant_id != "" do
    GenServer.call(__MODULE__, {:put, tenant_id, attrs})
  end

  @doc "Returns the full record or `:not_found`."
  @spec get(String.t()) :: {:ok, Record.t()} | {:error, :not_found}
  def get(tenant_id) when is_binary(tenant_id) do
    case :ets.lookup(@table, tenant_id) do
      [{^tenant_id, %Record{} = rec}] -> {:ok, rec}
      [] -> {:error, :not_found}
    end
  end

  @doc "Deletes a tenant row."
  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(tenant_id) when is_binary(tenant_id) do
    GenServer.call(__MODULE__, {:delete, tenant_id})
  end

  @doc "Rotates current secret for an existing tenant."
  @spec rotate(String.t(), binary(), pos_integer(), integer() | nil) ::
          {:ok, Record.t()} | {:error, :not_found | :empty_current}
  def rotate(tenant_id, new_current, grace_sec, now \\ nil)
      when is_binary(tenant_id) and is_binary(new_current) and is_integer(grace_sec) do
    GenServer.call(__MODULE__, {:rotate, tenant_id, new_current, grace_sec, now})
  end

  @doc "Redacted list of all tenants."
  @spec list() :: [map()]
  def list do
    :ets.foldl(
      fn {tid, %Record{} = rec}, acc ->
        [Map.put(Record.redact(rec), :tenant_id, tid) | acc]
      end,
      [],
      @table
    )
  end

  @doc """
  Clears all rows.

  ## Internal

  Test helper; not part of the ops HTTP surface.
  """
  @spec clear!() :: :ok
  def clear! do
    GenServer.call(__MODULE__, :clear)
  end

  @doc false
  @impl true
  def init(_opts) do
    table =
      case :ets.whereis(@table) do
        :undefined ->
          :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

        _ref ->
          :ets.delete_all_objects(@table)
          @table
      end

    {:ok, %{table: table}}
  end

  @doc false
  @impl true
  def handle_call({:put, tenant_id, %Record{} = rec}, _from, state) do
    :ets.insert(@table, {tenant_id, rec})
    {:reply, :ok, state}
  end

  def handle_call({:put, tenant_id, attrs}, _from, state) do
    case Record.validate(attrs) do
      {:ok, rec} ->
        :ets.insert(@table, {tenant_id, rec})
        {:reply, :ok, state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:delete, tenant_id}, _from, state) do
    reply =
      case :ets.lookup(@table, tenant_id) do
        [_] ->
          :ets.delete(@table, tenant_id)
          :ok

        [] ->
          {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:rotate, tenant_id, new_current, grace_sec, now}, _from, state) do
    now = now || System.system_time(:second)

    reply =
      cond do
        not is_binary(new_current) or new_current == "" ->
          {:error, :empty_current}

        true ->
          case :ets.lookup(@table, tenant_id) do
            [{^tenant_id, %Record{} = rec}] ->
              rotated = Record.rotate(rec, new_current, grace_sec, now)
              :ets.insert(@table, {tenant_id, rotated})
              {:ok, rotated}

            [] ->
              {:error, :not_found}
          end
      end

    {:reply, reply, state}
  end

  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end
end
