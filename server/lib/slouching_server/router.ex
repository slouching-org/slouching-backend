defmodule SlouchingServer.Router do
  @moduledoc false
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/health" do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end

  get "/api/status" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(SlouchingServer.Status.snapshot()))
  end

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(SlouchingServer.HandshakeSocket, :await_hello,
      timeout: 20_000,
      max_frame_size: 1024
    )
    |> halt()
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
