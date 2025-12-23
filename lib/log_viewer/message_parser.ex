defmodule LogViewer.MessageParser do
  @moduledoc """
  Parses /v1/messages request bodies into structured data.
  """

  alias LogViewer.ToolCache

  @doc """
  Parse a request body JSON string into structured components.
  Returns a map with :messages, :system, :tools, :model, :metadata, etc.
  """
  def parse(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> parse_data(data)
      {:error, _} -> nil
    end
  end

  def parse(_), do: nil

  defp parse_data(data) when is_map(data) do
    tools = Map.get(data, "tools", [])
    tool_refs = if tools != [], do: ToolCache.store_tools(tools), else: []

    %{
      model: Map.get(data, "model"),
      max_tokens: Map.get(data, "max_tokens"),
      stream: Map.get(data, "stream", false),
      messages: parse_messages(Map.get(data, "messages", [])),
      system: parse_system(Map.get(data, "system")),
      tool_refs: tool_refs,
      tool_count: length(tools),
      metadata: Map.get(data, "metadata"),
      temperature: Map.get(data, "temperature"),
      top_p: Map.get(data, "top_p"),
      top_k: Map.get(data, "top_k")
    }
  end

  defp parse_data(_), do: nil

  defp parse_messages(messages) when is_list(messages) do
    Enum.map(messages, &parse_message/1)
  end
  defp parse_messages(_), do: []

  defp parse_message(%{"role" => role, "content" => content}) do
    %{
      role: role,
      content: parse_content(content)
    }
  end
  defp parse_message(msg), do: %{role: "unknown", content: [%{type: "raw", data: msg}]}

  defp parse_content(content) when is_binary(content) do
    [%{type: "text", text: content}]
  end

  defp parse_content(content) when is_list(content) do
    Enum.map(content, &parse_content_block/1)
  end

  defp parse_content(_), do: []

  defp parse_content_block(%{"type" => "text", "text" => text}) do
    %{type: "text", text: text}
  end

  defp parse_content_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    %{type: "tool_use", id: id, name: name, input: input}
  end

  defp parse_content_block(%{"type" => "tool_result", "tool_use_id" => id, "content" => content}) do
    %{type: "tool_result", tool_use_id: id, content: extract_text_content(content)}
  end

  defp parse_content_block(%{"type" => "thinking", "thinking" => thinking}) do
    %{type: "thinking", thinking: thinking}
  end

  defp parse_content_block(%{"type" => "image"} = block) do
    %{type: "image", source: Map.get(block, "source")}
  end

  defp parse_content_block(block) do
    %{type: "unknown", data: block}
  end

  defp parse_system(nil), do: nil
  defp parse_system(system) when is_binary(system), do: [%{type: "text", text: system}]
  defp parse_system(system) when is_list(system) do
    Enum.map(system, fn
      %{"type" => "text", "text" => text} -> %{type: "text", text: text}
      %{"type" => type} = block -> %{type: type, data: block}
      other -> %{type: "unknown", data: other}
    end)
  end
  defp parse_system(_), do: nil

  defp extract_text_content(content) when is_binary(content), do: content
  defp extract_text_content(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      other -> inspect(other)
    end)
    |> Enum.join("\n")
  end
  defp extract_text_content(_), do: ""
end
