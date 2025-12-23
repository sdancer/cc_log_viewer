defmodule LogViewerWeb.LogController do
  use LogViewerWeb, :controller

  @topic "logs"

  def create(conn, params) do
    log = %{
      id: generate_id(),
      correlation_id: params["correlationId"] || params["correlation_id"],
      timestamp: params["timestamp"] || DateTime.utc_now() |> DateTime.to_iso8601(),
      type: params["type"] || "request",
      method: params["method"],
      url: params["url"],
      headers: params["headers"] || %{},
      body_preview: params["bodyPreview"] || params["body_preview"],
      response_body: params["responseBody"] || params["response_body"],
      status: params["status"],
      status_text: params["statusText"] || params["status_text"]
    }

    Phoenix.PubSub.broadcast(LogViewer.PubSub, @topic, {:new_log, log})

    conn
    |> put_status(:ok)
    |> json(%{status: "ok", id: log.id})
  end

  # Batch endpoint for multiple logs
  def batch(conn, %{"logs" => logs}) when is_list(logs) do
    ids =
      Enum.map(logs, fn params ->
        log = %{
          id: generate_id(),
          correlation_id: params["correlationId"] || params["correlation_id"],
          timestamp: params["timestamp"] || DateTime.utc_now() |> DateTime.to_iso8601(),
          type: params["type"] || "request",
          method: params["method"],
          url: params["url"],
          headers: params["headers"] || %{},
          body_preview: params["bodyPreview"] || params["body_preview"],
          response_body: params["responseBody"] || params["response_body"],
          status: params["status"],
          status_text: params["statusText"] || params["status_text"]
        }

        Phoenix.PubSub.broadcast(LogViewer.PubSub, @topic, {:new_log, log})
        log.id
      end)

    conn
    |> put_status(:ok)
    |> json(%{status: "ok", count: length(ids), ids: ids})
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
