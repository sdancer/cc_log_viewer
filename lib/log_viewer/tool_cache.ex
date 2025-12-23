defmodule LogViewer.ToolCache do
  @moduledoc """
  ETS-backed cache for tools by content hash.
  Avoids storing duplicate tool definitions.
  """
  use GenServer

  @table :tool_cache

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Store tools and return list of {hash, name} tuples"
  def store_tools(tools) when is_list(tools) do
    Enum.map(tools, fn tool ->
      hash = hash_tool(tool)
      name = get_in(tool, ["name"]) || "unknown"
      :ets.insert(@table, {hash, tool})
      %{hash: hash, name: name}
    end)
  end

  @doc "Get a tool by hash"
  def get_tool(hash) do
    case :ets.lookup(@table, hash) do
      [{^hash, tool}] -> tool
      [] -> nil
    end
  end

  @doc "Get all cached tools"
  def all_tools do
    :ets.tab2list(@table)
    |> Enum.map(fn {hash, tool} -> %{hash: hash, tool: tool} end)
  end

  def clear do
    :ets.delete_all_objects(@table)
  end

  # Server

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  defp hash_tool(tool) do
    :crypto.hash(:sha256, Jason.encode!(tool))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 12)
  end
end
