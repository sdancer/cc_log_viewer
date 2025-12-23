defmodule LogViewer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LogViewerWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:log_viewer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LogViewer.PubSub},
      # ETS-backed caches
      LogViewer.ToolCache,
      LogViewer.LogStore,
      # Start to serve requests, typically the last entry
      LogViewerWeb.Endpoint,
      # Proxy server on port 8080
      {Bandit, plug: LogViewerWeb.ProxyEndpoint, port: 8080}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LogViewer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LogViewerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
