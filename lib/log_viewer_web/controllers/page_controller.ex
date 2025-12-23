defmodule LogViewerWeb.PageController do
  use LogViewerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
