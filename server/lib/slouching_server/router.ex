defmodule SlouchingServer.Router do
  @moduledoc false
  use Plug.Router

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason,
    length: 1024,
    read_length: 1024,
    read_timeout: 5_000
  )

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

  post "/api/pairing-sessions" do
    case SlouchingServer.PairingSessions.create() do
      {:ok, session_id} ->
        send_json(conn, 201, %{
          session_id: session_id,
          expires_in_seconds: 120,
          spake2_messages_per_role: 1,
          confirmation_messages_per_role: 1,
          attempts_per_session: 1
        })

      {:error, :capacity} ->
        send_error(conn, 503, "capacity", "pairing service is at capacity")
    end
  end

  post "/api/pairing-sessions/:role/:stage" do
    with {:ok, session_id} <- session_capability(conn),
         {:ok, message} <- decode_message(conn.body_params["message"]),
         :ok <-
           SlouchingServer.PairingSessions.put(
             session_id,
             role,
             stage,
             message
           ) do
      send_resp(conn, 204, "")
    else
      {:error, reason} -> pairing_error(conn, reason)
    end
  end

  get "/api/pairing-sessions/:role/:stage" do
    with {:ok, session_id} <- session_capability(conn) do
      case SlouchingServer.PairingSessions.fetch(session_id, role, stage) do
        {:ok, message} -> send_json(conn, 200, %{message: Base.encode64(message)})
        :error -> send_json(conn, 202, %{status: "pending"})
        {:error, reason} -> pairing_error(conn, reason)
      end
    else
      {:error, reason} -> pairing_error(conn, reason)
    end
  end

  delete "/api/pairing-sessions" do
    with {:ok, session_id} <- session_capability(conn) do
      :ok = SlouchingServer.PairingSessions.delete(session_id)
      send_resp(conn, 204, "")
    else
      {:error, reason} -> pairing_error(conn, reason)
    end
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

  defp decode_message(value) when is_binary(value) and byte_size(value) <= 128 do
    case Base.decode64(value) do
      {:ok, message} -> {:ok, message}
      :error -> {:error, :invalid_encoding}
    end
  end

  defp decode_message(_value), do: {:error, :invalid_encoding}

  defp session_capability(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> session_id]
      when byte_size(session_id) == 64 ->
        if Regex.match?(~r/\A[0-9a-f]{64}\z/, session_id),
          do: {:ok, session_id},
          else: {:error, :invalid_session}

      _ ->
        {:error, :invalid_session}
    end
  end

  defp pairing_error(conn, :not_found),
    do: send_error(conn, 404, "not_found", "pairing session not found")

  defp pairing_error(conn, :invalid_session),
    do: send_error(conn, 404, "not_found", "pairing session not found")

  defp pairing_error(conn, :expired),
    do: send_error(conn, 410, "expired", "pairing session expired")

  defp pairing_error(conn, :already_submitted),
    do: send_error(conn, 409, "already_submitted", "message already submitted for this stage")

  defp pairing_error(conn, :spake2_incomplete),
    do: send_error(conn, 409, "spake2_incomplete", "both SPAKE2 messages are required first")

  defp pairing_error(conn, :invalid_role),
    do: send_error(conn, 400, "invalid_role", "invalid participant role")

  defp pairing_error(conn, :invalid_stage),
    do: send_error(conn, 400, "invalid_stage", "invalid pairing stage")

  defp pairing_error(conn, :invalid_message_size),
    do: send_error(conn, 400, "invalid_message_size", "message has an invalid size")

  defp pairing_error(conn, :invalid_encoding),
    do: send_error(conn, 400, "invalid_encoding", "message must be bounded base64")

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end

  defp send_error(conn, status, code, message),
    do: send_json(conn, status, %{error: code, message: message})
end
