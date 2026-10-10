defmodule SlouchingServer.Router do
  @moduledoc false
  use Plug.Router

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason,
    length: 140_000,
    read_length: 140_000,
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

  post "/api/delivery/copies" do
    with encoded when is_binary(encoded) <- conn.body_params["copy"],
         {:ok, payload} <- Base.decode64(encoded),
         true <- byte_size(payload) <= 96 * 1024 do
      case SlouchingServer.Delivery.Mailbox.store(payload) do
        {:ok, result} ->
          send_json(conn, 201, %{status: to_string(result)})

        {:error, :invalid_envelope} ->
          send_error(conn, 400, "invalid_copy", "copy envelope is invalid")

        {:error, :invalid_signature} ->
          send_error(conn, 400, "invalid_copy", "copy envelope is invalid")

        {:error, :event_conflict} ->
          send_error(conn, 409, "event_conflict", "event ID already has different content")

        {:error, :quota_exceeded} ->
          send_error(conn, 409, "quota_exceeded", "recipient mailbox quota is full")
      end
    else
      _ -> send_error(conn, 400, "invalid_copy", "copy must be bounded base64")
    end
  end

  get "/api/delivery/copies" do
    path = signed_path(conn)

    with {:ok, recipient} <- authenticate_delivery(conn, "GET", path, <<>>),
         {:ok, after_id} <- query_integer(conn, "after_id", 0),
         {:ok, limit} <- query_integer(conn, "limit", 16) do
      case SlouchingServer.Delivery.Mailbox.list(recipient, after_id, limit) do
        {:ok, result} ->
          copies =
            Enum.map(result.copies, fn copy ->
              %{
                event_id: Base.encode16(copy.event_id, case: :lower),
                expires_at_unix: copy.expires_at_unix,
                copy: Base.encode64(copy.payload)
              }
            end)

          send_json(conn, 200, %{copies: copies, next_after_id: result.next_after_id})

        {:error, reason} ->
          delivery_error(conn, reason)
      end
    else
      {:error, :unauthorized} ->
        send_error(conn, 401, "unauthorized", "device request signature is invalid or expired")

      {:error, :invalid_cursor} ->
        send_error(conn, 400, "invalid_cursor", "mailbox cursor is invalid")
    end
  end

  post "/api/delivery/copies/:event_id/ack" do
    path = conn.request_path

    with {:ok, recipient} <- authenticate_delivery(conn, "POST", path, <<>>),
         {:ok, event_id} <- decode_event_id(event_id),
         {:ok, :ok} <- SlouchingServer.Delivery.Mailbox.acknowledge(recipient, event_id) do
      send_resp(conn, 204, "")
    else
      {:error, :unauthorized} ->
        send_error(conn, 401, "unauthorized", "device request signature is invalid or expired")

      {:error, :invalid_event_id} ->
        send_error(conn, 400, "invalid_event_id", "event ID is invalid")

      {:error, reason} ->
        delivery_error(conn, reason)
    end
  end

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(SlouchingServer.HandshakeSocket, :await_hello,
      timeout: 20_000,
      max_frame_size: 140_000
    )
    |> halt()
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp decode_message(value) when is_binary(value) and byte_size(value) <= 256 do
    case Base.decode64(value) do
      {:ok, message} -> {:ok, message}
      :error -> {:error, :invalid_encoding}
    end
  end

  defp decode_message(_value), do: {:error, :invalid_encoding}

  defp authenticate_delivery(conn, method, path, body) do
    SlouchingServer.Delivery.Auth.authenticate(method, path, body, conn.req_headers)
  end

  defp signed_path(%Plug.Conn{query_string: ""} = conn), do: conn.request_path
  defp signed_path(conn), do: conn.request_path <> "?" <> conn.query_string

  defp query_integer(conn, key, default) do
    case conn.query_params[key] do
      nil ->
        {:ok, default}

      value ->
        case Integer.parse(value) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _ -> {:error, :invalid_cursor}
        end
    end
  end

  defp decode_event_id(value) when byte_size(value) == 32 do
    case Base.decode16(value, case: :lower) do
      {:ok, event_id} when byte_size(event_id) == 16 -> {:ok, event_id}
      _ -> {:error, :invalid_event_id}
    end
  end

  defp decode_event_id(_value), do: {:error, :invalid_event_id}

  defp delivery_error(conn, :invalid_envelope),
    do: send_error(conn, 400, "invalid_copy", "copy envelope is invalid")

  defp delivery_error(conn, :invalid_signature),
    do: send_error(conn, 400, "invalid_copy", "copy envelope is invalid")

  defp delivery_error(conn, :event_conflict),
    do: send_error(conn, 409, "event_conflict", "event ID already has different content")

  defp delivery_error(conn, :quota_exceeded),
    do: send_error(conn, 409, "quota_exceeded", "recipient mailbox quota is full")

  defp delivery_error(conn, _reason),
    do: send_error(conn, 500, "delivery_error", "delivery request failed")

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

  defp pairing_error(conn, :confirmation_incomplete),
    do:
      send_error(
        conn,
        409,
        "confirmation_incomplete",
        "both key confirmations are required first"
      )

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
