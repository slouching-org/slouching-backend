defmodule SlouchingServer.StatusTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  test "diagnostic contract exposes no unimplemented capabilities" do
    response = conn(:get, "/api/status") |> SlouchingServer.Router.call([])
    assert response.status == 200
    assert get_resp_header(response, "content-type") == ["application/json; charset=utf-8"]

    assert Jason.decode!(response.resp_body) == %{
             "contract_version" => 1,
             "backend" => "elixir_scaffold",
             "identity" => "not_implemented",
             "messaging" => "not_implemented",
             "calls" => "available",
             "peer_connections" => 0
           }
  end

  test "health reports only process availability" do
    response = conn(:get, "/health") |> SlouchingServer.Router.call([])
    assert response.status == 200
    assert response.resp_body == "ok"
  end
end
