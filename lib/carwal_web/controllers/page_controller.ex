defmodule CarWalWeb.PageController do
  use CarWalWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
