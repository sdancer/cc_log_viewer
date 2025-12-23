defmodule LogViewerWeb.Router do
  use LogViewerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LogViewerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LogViewerWeb do
    pipe_through :browser

    live "/", LogsLive
    get "/old", PageController, :home
  end

  scope "/api", LogViewerWeb do
    pipe_through :api

    post "/logs", LogController, :create
    post "/logs/batch", LogController, :batch
  end
end
