defmodule LogViewerWeb.ProxyEndpoint do
  use Plug.Router

  @topic "logs"

  plug Plug.Logger
  plug :read_body_for_logging
  plug :match
  plug :dispatch

  # Read and cache the request body before proxying
  defp read_body_for_logging(conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    correlation_id = generate_id()

    # Broadcast request log
    log = %{
      id: generate_id(),
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      type: "request",
      method: conn.method,
      url: build_request_url(conn),
      headers: Enum.into(conn.req_headers, %{}),
      body_preview: truncate_body(body),
      status: nil,
      status_text: nil
    }

    Phoenix.PubSub.broadcast(LogViewer.PubSub, @topic, {:new_log, log})

    conn
    |> Plug.Conn.assign(:raw_body, body)
    |> Plug.Conn.assign(:correlation_id, correlation_id)
  end

  # Proxy all requests to upstream with response callback
  match _ do
    upstream = Application.get_env(:log_viewer, :proxy_upstream, "https://api.anthropic.com")
    correlation_id = conn.assigns[:correlation_id]

    opts = ReverseProxyPlug.init(
      upstream: upstream,
      response_mode: :buffer,
      client_options: [recv_timeout: 120_000]
    )

    conn = ReverseProxyPlug.call(conn, opts)

    # Broadcast response log
    response_body = get_response_body(conn)

    response_headers = conn.resp_headers |> Enum.into(%{})

    response_log = %{
      id: generate_id(),
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      type: "response",
      method: conn.method,
      url: build_request_url(conn),
      headers: %{},
      response_headers: response_headers,
      body_preview: nil,
      response_body: truncate_body(response_body),
      status: conn.status,
      status_text: Plug.Conn.Status.reason_phrase(conn.status || 200)
    }

    Phoenix.PubSub.broadcast(LogViewer.PubSub, @topic, {:new_log, response_log})

    conn
  end

  defp build_request_url(conn) do
    query = if conn.query_string != "", do: "?#{conn.query_string}", else: ""
    "#{conn.request_path}#{query}"
  end

  defp get_response_body(conn) do
    raw_body = case conn.resp_body do
      nil -> ""
      body when is_binary(body) -> body
      body when is_list(body) -> IO.iodata_to_binary(body)
      _ -> ""
    end

    # Check if response is gzip-compressed and decompress
    content_encoding = Plug.Conn.get_resp_header(conn, "content-encoding") |> List.first() || ""
    content_type = Plug.Conn.get_resp_header(conn, "content-type") |> List.first() || ""

    decompressed = cond do
      String.contains?(content_encoding, "gzip") ->
        try do
          :zlib.gunzip(raw_body)
        rescue
          _ -> "[binary data - could not decompress]"
        end

      String.valid?(raw_body) ->
        raw_body

      true ->
        "[binary data]"
    end

    # Check if SSE and rebuild message
    if String.contains?(content_type, "text/event-stream") do
      try do
        rebuild_sse_message(decompressed)
      rescue
        e -> "[SSE parse error: #{inspect(e)}]\n\n#{decompressed}"
      end
    else
      decompressed
    end
  end

  # Parse SSE stream and rebuild into a structured message
  defp rebuild_sse_message(sse_data) do
    # Parse all events
    events = parse_sse_events(sse_data)

    # If no events parsed, return raw
    if events == [] do
      sse_data
    else
      do_rebuild_sse_message(events)
    end
  end

  defp do_rebuild_sse_message(events) do

    # Extract message info
    message_start = Enum.find(events, fn {type, _} -> type == "message_start" end)
    message_delta = Enum.find(events, fn {type, _} -> type == "message_delta" end)

    # Collect content blocks
    content_blocks = rebuild_content_blocks(events)

    # Build final message structure
    message = %{
      "type" => "message",
      "content" => content_blocks
    }

    # Add metadata from message_start
    message = case message_start do
      {_, %{"message" => msg}} ->
        message
        |> Map.put("id", msg["id"])
        |> Map.put("model", msg["model"])
        |> Map.put("role", msg["role"])
      _ -> message
    end

    # Add stop reason and final usage from message_delta
    message = case message_delta do
      {_, %{"delta" => delta, "usage" => usage}} ->
        message
        |> Map.put("stop_reason", delta["stop_reason"])
        |> Map.put("usage", usage)
      _ -> message
    end

    Jason.encode!(message, pretty: true)
  end

  defp parse_sse_events(sse_data) do
    # Split on double newlines, handling various line ending styles
    sse_data
    |> String.replace("\r\n", "\n")
    |> String.split(~r/\n\n+/)
    |> Enum.flat_map(fn chunk ->
      chunk = String.trim(chunk)
      lines = String.split(chunk, "\n")

      event_type = Enum.find_value(lines, fn line ->
        case Regex.run(~r/^event:\s*(.+)$/, String.trim(line)) do
          [_, type] -> String.trim(type)
          _ -> nil
        end
      end)

      data = Enum.find_value(lines, fn line ->
        case Regex.run(~r/^data:\s*(.+)$/, String.trim(line)) do
          [_, json] ->
            case Jason.decode(String.trim(json)) do
              {:ok, parsed} -> parsed
              _ -> nil
            end
          _ -> nil
        end
      end)

      if event_type && data, do: [{event_type, data}], else: []
    end)
  end

  defp rebuild_content_blocks(events) do
    # Group events by content block index
    events
    |> Enum.reduce(%{}, fn
      {"content_block_start", %{"index" => idx, "content_block" => block}}, acc ->
        Map.put(acc, idx, %{"type" => block["type"], "content" => ""})

      {"content_block_delta", %{"index" => idx, "delta" => delta}}, acc ->
        case delta do
          %{"type" => "thinking_delta", "thinking" => text} ->
            update_in(acc, [idx, "content"], &((&1 || "") <> text))

          %{"type" => "text_delta", "text" => text} ->
            update_in(acc, [idx, "content"], &((&1 || "") <> text))

          %{"type" => "signature_delta"} ->
            acc  # Skip signatures

          _ -> acc
        end

      _, acc -> acc
    end)
    |> Enum.sort_by(fn {idx, _} -> idx end)
    |> Enum.map(fn {_, block} ->
      case block["type"] do
        "thinking" -> %{"type" => "thinking", "thinking" => block["content"]}
        "text" -> %{"type" => "text", "text" => block["content"]}
        other -> %{"type" => other, "content" => block["content"]}
      end
    end)
  end

  defp truncate_body(body) when is_binary(body) do
    max_size = 100_000
    if byte_size(body) > max_size do
      String.slice(body, 0, max_size) <> "\n... [truncated]"
    else
      body
    end
  end
  defp truncate_body(_), do: ""

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
