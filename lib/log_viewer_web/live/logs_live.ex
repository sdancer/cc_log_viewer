defmodule LogViewerWeb.LogsLive do
  use LogViewerWeb, :live_view

  @topic "logs:stored"
  @max_logs 500
  @default_excluded_domains ["statsig.anthropic.com"]

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(LogViewer.PubSub, @topic)
    end

    # Load existing logs from ETS store
    existing_logs = LogViewer.LogStore.get_logs() |> Enum.take(@max_logs)

    {:ok,
     socket
     |> assign(:logs, existing_logs)
     |> assign(:filter, "")
     |> assign(:filter_type, "all")
     |> assign(:hide_statsig, true)
     |> assign(:paused, false)
     |> assign(:selected_log, nil)}
  end

  def handle_event("toggle_pause", _, socket) do
    {:noreply, assign(socket, :paused, !socket.assigns.paused)}
  end

  def handle_event("clear", _, socket) do
    LogViewer.LogStore.clear()
    {:noreply, assign(socket, :logs, [])}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, :filter, filter)}
  end

  def handle_event("filter_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :filter_type, type)}
  end

  def handle_event("toggle_statsig", _, socket) do
    {:noreply, assign(socket, :hide_statsig, !socket.assigns.hide_statsig)}
  end

  def handle_event("select_log", %{"id" => id}, socket) do
    log = Enum.find(socket.assigns.logs, &(&1.id == id))
    {:noreply, assign(socket, :selected_log, log)}
  end

  def handle_event("close_detail", _, socket) do
    {:noreply, assign(socket, :selected_log, nil)}
  end

  def handle_info({:stored_log, log}, socket) do
    if socket.assigns.paused do
      {:noreply, socket}
    else
      # LogStore handles merging - just update our list
      logs = update_or_prepend_log(socket.assigns.logs, log)
      {:noreply, assign(socket, :logs, Enum.take(logs, @max_logs))}
    end
  end

  # Update existing log (for merges) or prepend new one
  defp update_or_prepend_log(logs, log) do
    case Enum.find_index(logs, &(&1.id == log.id)) do
      nil -> [log | logs]
      idx -> List.replace_at(logs, idx, log)
    end
  end

  defp filtered_logs(logs, filter, filter_type, hide_statsig) do
    logs
    |> filter_by_type(filter_type)
    |> filter_by_text(filter)
    |> filter_excluded_domains(hide_statsig)
  end

  defp filter_by_type(logs, "all"), do: logs
  defp filter_by_type(logs, "request"), do: Enum.filter(logs, &(&1.type == "request"))
  defp filter_by_type(logs, "response"), do: Enum.filter(logs, &(&1.type == "response"))
  defp filter_by_type(logs, "merged"), do: Enum.filter(logs, &(&1.type == "merged"))
  defp filter_by_type(logs, "api"), do: Enum.filter(logs, &String.contains?(&1.url || "", "api.anthropic.com"))

  defp filter_excluded_domains(logs, false), do: logs
  defp filter_excluded_domains(logs, true) do
    Enum.reject(logs, fn log ->
      url = log.url || ""
      Enum.any?(@default_excluded_domains, &String.contains?(url, &1))
    end)
  end

  defp filter_by_text(logs, ""), do: logs
  defp filter_by_text(logs, filter) do
    filter_down = String.downcase(filter)
    Enum.filter(logs, fn log ->
      String.contains?(String.downcase(log.url || ""), filter_down) ||
      String.contains?(String.downcase(log.body_preview || ""), filter_down)
    end)
  end

  defp format_time(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%H:%M:%S.%f") |> String.slice(0..11)
      _ -> timestamp
    end
  end

  defp type_badge_color("request"), do: "badge-primary"
  defp type_badge_color("response"), do: "badge-secondary"
  defp type_badge_color("merged"), do: "badge-accent"
  defp type_badge_color(_), do: "badge-ghost"

  defp method_color("GET"), do: "badge-info"
  defp method_color("POST"), do: "badge-success"
  defp method_color("PUT"), do: "badge-warning"
  defp method_color("DELETE"), do: "badge-error"
  defp method_color(_), do: "badge-ghost"

  defp status_color(status) when status >= 200 and status < 300, do: "text-success"
  defp status_color(status) when status >= 400 and status < 500, do: "text-warning"
  defp status_color(status) when status >= 500, do: "text-error"
  defp status_color(_), do: ""

  defp truncate_url(url, max \\ 80) do
    if String.length(url || "") > max do
      String.slice(url, 0, max) <> "..."
    else
      url
    end
  end

  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-base-200">
      <!-- Header -->
      <div class="navbar bg-base-100 shadow-lg">
        <div class="flex-1">
          <span class="text-xl font-bold px-4">🔍 LLM Request Viewer</span>
          <span class="badge badge-primary"><%= length(@logs) %> logs</span>
        </div>
        <div class="flex-none gap-2">
          <input
            type="text"
            placeholder="Filter..."
            class="input input-bordered input-sm w-48"
            value={@filter}
            phx-keyup="filter"
            phx-value-filter={@filter}
          />
          <select class="select select-bordered select-sm" phx-change="filter_type">
            <option value="all" selected={@filter_type == "all"}>All</option>
            <option value="merged" selected={@filter_type == "merged"}>Merged</option>
            <option value="request" selected={@filter_type == "request"}>Requests</option>
            <option value="response" selected={@filter_type == "response"}>Responses</option>
            <option value="api" selected={@filter_type == "api"}>API Only</option>
          </select>
          <button class={"btn btn-sm " <> if(@hide_statsig, do: "btn-primary", else: "btn-ghost")} phx-click="toggle_statsig">
            <%= if @hide_statsig, do: "Statsig hidden", else: "Show all" %>
          </button>
          <button class={"btn btn-sm " <> if(@paused, do: "btn-warning", else: "btn-ghost")} phx-click="toggle_pause">
            <%= if @paused, do: "▶ Resume", else: "⏸ Pause" %>
          </button>
          <button class="btn btn-sm btn-ghost" phx-click="clear">🗑 Clear</button>
        </div>
      </div>

      <!-- Main content -->
      <div class="flex-1 flex overflow-hidden">
        <!-- Log list -->
        <div class={"overflow-auto p-2 " <> if(@selected_log, do: "w-1/2", else: "flex-1")} style={if @selected_log, do: "min-width: 200px;", else: ""}>
          <table class="table table-xs table-zebra w-full">
            <thead class="sticky top-0 bg-base-100">
              <tr>
                <th class="w-24">Time</th>
                <th class="w-20">Type</th>
                <th class="w-16">Method</th>
                <th class="w-28">Model</th>
                <th>URL</th>
                <th class="w-16">Status</th>
              </tr>
            </thead>
            <tbody>
              <%= for log <- filtered_logs(@logs, @filter, @filter_type, @hide_statsig) do %>
                <tr
                  class={"hover cursor-pointer " <> if(@selected_log && @selected_log.id == log.id, do: "bg-primary/20", else: "")}
                  phx-click="select_log"
                  phx-value-id={log.id}
                >
                  <td class="font-mono text-xs opacity-70"><%= format_time(log.timestamp) %></td>
                  <td>
                    <span class={"badge badge-xs " <> type_badge_color(log.type)}>
                      <%= log.type %>
                    </span>
                  </td>
                  <td>
                    <span class={"badge badge-xs " <> method_color(log.method)}><%= log.method %></span>
                  </td>
                  <td class="text-xs">
                    <%= if log[:parsed] && log.parsed[:model] do %>
                      <span class="badge badge-xs badge-primary"><%= short_model(log.parsed.model) %></span>
                    <% end %>
                  </td>
                  <td class="font-mono text-xs truncate max-w-md" title={log.url}>
                    <%= truncate_url(log.url) %>
                  </td>
                  <td class={"font-mono " <> status_color(log.status)}>
                    <%= log.status %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <!-- Splitter -->
        <%= if @selected_log do %>
          <div id="splitter" phx-hook="Splitter" class="w-1 bg-base-300 hover:bg-primary cursor-col-resize flex-shrink-0"></div>
        <% end %>

        <!-- Detail panel -->
        <%= if @selected_log do %>
          <div class="flex-1 min-w-[300px] border-l border-base-300 bg-base-100 overflow-auto">
            <div class="sticky top-0 bg-base-100 p-3 border-b flex justify-between items-center">
              <span class="font-bold">Request Details</span>
              <button class="btn btn-xs btn-ghost" phx-click="close_detail">✕</button>
            </div>
            <div class="p-4 space-y-4">
              <div>
                <h3 class="font-semibold text-sm opacity-70">URL</h3>
                <code class="text-xs break-all"><%= @selected_log.url %></code>
              </div>

              <div>
                <h3 class="font-semibold text-sm opacity-70">Method / Status</h3>
                <span class={"badge " <> method_color(@selected_log.method)}><%= @selected_log.method %></span>
                <%= if @selected_log.status do %>
                  <span class={"ml-2 " <> status_color(@selected_log.status)}><%= @selected_log.status %> <%= @selected_log.status_text %></span>
                <% end %>
              </div>

              <%= if @selected_log.headers && map_size(@selected_log.headers) > 0 do %>
                <details class="collapse collapse-arrow bg-base-200">
                  <summary class="collapse-title text-sm font-semibold min-h-0 py-2">
                    Request Headers (<%= map_size(@selected_log.headers) %>)
                  </summary>
                  <div class="collapse-content">
                    <div class="text-xs font-mono overflow-x-auto">
                      <%= for {k, v} <- @selected_log.headers do %>
                        <div><span class="text-primary"><%= k %>:</span> <%= truncate_url(v, 100) %></div>
                      <% end %>
                    </div>
                  </div>
                </details>
              <% end %>

              <%= if @selected_log[:response_headers] && map_size(@selected_log[:response_headers] || %{}) > 0 do %>
                <details class="collapse collapse-arrow bg-base-200">
                  <summary class="collapse-title text-sm font-semibold min-h-0 py-2">
                    Response Headers (<%= map_size(@selected_log[:response_headers] || %{}) %>)
                  </summary>
                  <div class="collapse-content">
                    <div class="text-xs font-mono overflow-x-auto">
                      <%= for {k, v} <- (@selected_log[:response_headers] || %{}) do %>
                        <div><span class="text-secondary"><%= k %>:</span> <%= truncate_url(v, 100) %></div>
                      <% end %>
                    </div>
                  </div>
                </details>
              <% end %>

              <%= if @selected_log[:parsed] do %>
                <!-- Parsed API Request -->
                <div class="space-y-3">
                  <!-- Model & Settings -->
                  <div class="flex flex-wrap gap-2 text-xs">
                    <span class="badge badge-primary"><%= @selected_log.parsed.model %></span>
                    <span class="badge badge-ghost">max: <%= @selected_log.parsed.max_tokens %></span>
                    <%= if @selected_log.parsed.stream do %>
                      <span class="badge badge-info badge-outline">stream</span>
                    <% end %>
                    <%= if @selected_log.parsed.tool_count > 0 do %>
                      <span class="badge badge-secondary"><%= @selected_log.parsed.tool_count %> tools</span>
                    <% end %>
                  </div>

                  <!-- System Prompt -->
                  <%= if @selected_log.parsed.system do %>
                    <details class="collapse collapse-arrow bg-base-200">
                      <summary class="collapse-title text-sm font-semibold min-h-0 py-2">
                        System Prompt
                      </summary>
                      <div class="collapse-content">
                        <%= for block <- @selected_log.parsed.system do %>
                          <div class="text-xs whitespace-pre-wrap"><%= block.text || inspect(block) %></div>
                        <% end %>
                      </div>
                    </details>
                  <% end %>

                  <!-- Tools -->
                  <%= if @selected_log.parsed.tool_refs != [] do %>
                    <details class="collapse collapse-arrow bg-base-200">
                      <summary class="collapse-title text-sm font-semibold min-h-0 py-2">
                        Tools (<%= length(@selected_log.parsed.tool_refs) %>)
                      </summary>
                      <div class="collapse-content">
                        <div class="flex flex-wrap gap-1">
                          <%= for ref <- @selected_log.parsed.tool_refs do %>
                            <span class="badge badge-outline badge-sm cursor-pointer" title={ref.hash}>
                              <%= ref.name %>
                            </span>
                          <% end %>
                        </div>
                      </div>
                    </details>
                  <% end %>

                  <!-- Messages -->
                  <div>
                    <h3 class="font-semibold text-sm opacity-70 mb-2">Messages (<%= length(@selected_log.parsed.messages) %>)</h3>
                    <div class="space-y-2 max-h-96 overflow-y-auto">
                      <%= for msg <- @selected_log.parsed.messages do %>
                        <div class={"rounded p-2 text-xs " <> message_bg(msg.role)}>
                          <div class="font-semibold mb-1 opacity-70"><%= msg.role %></div>
                          <%= for block <- msg.content do %>
                            <%= render_content_block(block) %>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% else %>
                <%= if @selected_log.body_preview do %>
                  <details class="collapse collapse-arrow bg-base-200">
                    <summary class="collapse-title text-sm font-semibold min-h-0 py-2">
                      Request Body
                    </summary>
                    <div class="collapse-content">
                      <pre class="text-xs overflow-x-auto whitespace-pre-wrap max-h-96"><%= format_json(@selected_log.body_preview) %></pre>
                    </div>
                  </details>
                <% end %>
              <% end %>

              <%= if @selected_log[:response_body] do %>
                <details class="collapse collapse-arrow bg-base-200" open>
                  <summary class="collapse-title text-sm font-semibold min-h-0 py-2">
                    Response
                  </summary>
                  <div class="collapse-content">
                    <pre class="text-xs overflow-x-auto whitespace-pre-wrap max-h-96"><%= format_json(@selected_log.response_body) %></pre>
                  </div>
                </details>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_json(str) do
    case Jason.decode(str) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      _ -> str
    end
  end

  defp message_bg("user"), do: "bg-blue-900/30 border-l-2 border-blue-500"
  defp message_bg("assistant"), do: "bg-green-900/30 border-l-2 border-green-500"
  defp message_bg(_), do: "bg-base-300"

  defp short_model(nil), do: ""
  defp short_model(model) do
    model
    |> String.replace("claude-", "")
    |> String.replace("-20251001", "")
    |> String.replace("-20251101", "")
    |> String.replace("-20250219", "")
    |> String.replace("-latest", "")
  end

  defp render_content_block(%{type: "text", text: text}) do
    assigns = %{text: text}
    ~H"""
    <div class="whitespace-pre-wrap"><%= @text %></div>
    """
  end

  defp render_content_block(%{type: "tool_use", name: name, input: input}) do
    assigns = %{name: name, input: input}
    ~H"""
    <div class="bg-base-300 rounded p-1 my-1">
      <span class="badge badge-warning badge-xs">tool_use</span>
      <span class="font-mono text-warning"><%= @name %></span>
      <pre class="text-xs opacity-70 mt-1 max-h-32 overflow-auto"><%= Jason.encode!(@input, pretty: true) %></pre>
    </div>
    """
  end

  defp render_content_block(%{type: "tool_result", tool_use_id: id, content: content}) do
    assigns = %{id: id, content: content}
    ~H"""
    <div class="bg-base-300 rounded p-1 my-1">
      <span class="badge badge-success badge-xs">tool_result</span>
      <span class="font-mono text-xs opacity-50"><%= @id %></span>
      <pre class="text-xs mt-1 max-h-32 overflow-auto whitespace-pre-wrap"><%= @content %></pre>
    </div>
    """
  end

  defp render_content_block(%{type: "thinking", thinking: thinking}) do
    assigns = %{thinking: thinking}
    ~H"""
    <details class="bg-base-300 rounded p-1 my-1">
      <summary class="cursor-pointer text-xs opacity-70">
        <span class="badge badge-ghost badge-xs">thinking</span>
        <%= String.slice(@thinking || "", 0, 50) %>...
      </summary>
      <pre class="text-xs mt-1 whitespace-pre-wrap"><%= @thinking %></pre>
    </details>
    """
  end

  defp render_content_block(%{type: "image"}) do
    assigns = %{}
    ~H"""
    <div class="badge badge-outline badge-xs">image</div>
    """
  end

  defp render_content_block(block) do
    assigns = %{block: block}
    ~H"""
    <pre class="text-xs opacity-50"><%= inspect(@block) %></pre>
    """
  end
end
