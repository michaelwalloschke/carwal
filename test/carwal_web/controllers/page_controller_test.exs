defmodule CarWalWeb.PageControllerTest do
  use CarWalWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "CarWal"
  end
end
