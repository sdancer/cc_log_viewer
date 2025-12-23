defmodule LogViewer.LogStore do
  @moduledoc """
  ETS-backed log storage with GenServer supervision.
  Survives LiveView crashes and reconnects.
  """
  use GenServer

  @table :log_store
  @max_logs 1000
  @topic "logs"

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def add_log(log) do
    GenServer.cast(__MODULE__, {:add_log, log})
  end

  def get_logs do
    case :ets.info(@table) do
      :undefined -> []
      _ ->
        @table
        |> :ets.tab2list()
        |> Enum.sort_by(fn {ts, _} -> ts end, :desc)
        |> Enum.map(fn {_, log} -> log end)
    end
  end

  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  # Server callbacks

  @impl true
  def init(_) do
    table = :ets.new(@table, [:ordered_set, :named_table, :public, read_concurrency: true])
    # Subscribe to log events to store them
    Phoenix.PubSub.subscribe(LogViewer.PubSub, @topic)
    {:ok, %{table: table, pending: %{}}}
  end

  @impl true
  def handle_cast({:add_log, log}, state) do
    store_log(log)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(@table)
    {:noreply, %{state | pending: %{}}}
  end

  @impl true
  def handle_info({:new_log, log}, state) do
    {state, log} = process_and_merge(log, state)
    store_log(log)
    # Re-broadcast the potentially merged log for LiveViews
    Phoenix.PubSub.broadcast(LogViewer.PubSub, "logs:stored", {:stored_log, log})
    {:noreply, state}
  end

  # Merge request/response by correlation_id
  defp process_and_merge(%{correlation_id: nil} = log, state), do: {state, log}

  defp process_and_merge(%{correlation_id: cid, type: "request"} = log, state) do
    # Store pending request
    {%{state | pending: Map.put(state.pending, cid, log)}, log}
  end

  defp process_and_merge(%{correlation_id: cid, type: "response"} = response, state) do
    case Map.pop(state.pending, cid) do
      {nil, pending} ->
        {%{state | pending: pending}, response}

      {request, pending} ->
        # Merge and remove old request from ETS
        merged = merge_request_response(request, response)
        delete_log(request.id)
        {%{state | pending: pending}, merged}
    end
  end

  defp process_and_merge(log, state), do: {state, log}

  defp merge_request_response(request, response) do
    %{
      id: request.id,
      correlation_id: request.correlation_id,
      timestamp: request.timestamp,
      response_timestamp: response.timestamp,
      type: "merged",
      method: request.method,
      url: request.url,
      headers: request.headers,
      response_headers: Map.get(response, :response_headers, %{}),
      body_preview: request.body_preview,
      response_body: response.response_body,
      status: response.status,
      status_text: response.status_text
    }
  end

  defp store_log(log) do
    # Use timestamp + id as key for ordering
    key = {log.timestamp, log.id}
    :ets.insert(@table, {key, log})
    prune_old_logs()
  end

  defp delete_log(id) do
    # Find and delete by id
    match_spec = [{{:"$1", :"$2"}, [{:==, {:element, 2, :"$2"}, id}], [:"$1"]}]
    case :ets.select(@table, match_spec) do
      [key | _] -> :ets.delete(@table, key)
      [] -> :ok
    end
  end

  defp prune_old_logs do
    size = :ets.info(@table, :size)
    if size > @max_logs do
      # Delete oldest entries
      to_delete = size - @max_logs
      @table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {ts, _} -> ts end)
      |> Enum.take(to_delete)
      |> Enum.each(fn {key, _} -> :ets.delete(@table, key) end)
    end
  end
end
