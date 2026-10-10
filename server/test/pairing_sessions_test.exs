defmodule SlouchingServer.PairingSessionsTest do
  use ExUnit.Case, async: true

  alias SlouchingServer.{PairingSessions, Router}

  defp request(method, path, body \\ nil, session_id \\ nil) do
    conn = Plug.Test.conn(method, path, body || "")

    conn =
      if body do
        Plug.Conn.put_req_header(conn, "content-type", "application/json")
      else
        conn
      end

    conn =
      if session_id do
        Plug.Conn.put_req_header(conn, "authorization", "Bearer #{session_id}")
      else
        conn
      end

    Router.call(conn, Router.init([]))
  end

  test "HTTP rendezvous relays one bounded SPAKE2 and confirmation message per role" do
    created = request(:post, "/api/pairing-sessions")
    assert created.status == 201
    response = Jason.decode!(created.resp_body)
    assert response["expires_in_seconds"] == 120
    assert response["spake2_messages_per_role"] == 1
    assert response["confirmation_messages_per_role"] == 1
    assert response["attempts_per_session"] == 1
    session_id = response["session_id"]
    assert byte_size(session_id) == 64

    inviter_spake = :binary.copy(<<0x41>>, 33)
    invitee_spake = :binary.copy(<<0x53>>, 33)
    inviter_confirm = :binary.copy(<<0x11>>, 32)
    invitee_confirm = :binary.copy(<<0x22>>, 32)

    assert request(:get, "/api/pairing-sessions/inviter/spake2", nil, session_id).status == 202

    assert request(
             :post,
             "/api/pairing-sessions/inviter/spake2",
             Jason.encode!(%{message: Base.encode64(inviter_spake)}),
             session_id
           ).status == 204

    assert request(
             :post,
             "/api/pairing-sessions/inviter/confirm",
             Jason.encode!(%{message: Base.encode64(inviter_confirm)}),
             session_id
           ).status == 409

    assert request(
             :post,
             "/api/pairing-sessions/invitee/spake2",
             Jason.encode!(%{message: Base.encode64(invitee_spake)}),
             session_id
           ).status == 204

    for {role, message} <- [{"inviter", invitee_spake}, {"invitee", inviter_spake}] do
      response = request(:get, "/api/pairing-sessions/#{role}/spake2", nil, session_id)
      assert response.status == 200
      assert Jason.decode!(response.resp_body)["message"] == Base.encode64(message)
    end

    assert request(
             :post,
             "/api/pairing-sessions/inviter/identity",
             Jason.encode!(%{message: Base.encode64(:binary.copy(<<0x31>>, 128))}),
             session_id
           ).status == 409

    for {role, message} <- [{"inviter", inviter_confirm}, {"invitee", invitee_confirm}] do
      assert request(
               :post,
               "/api/pairing-sessions/#{role}/confirm",
               Jason.encode!(%{message: Base.encode64(message)}),
               session_id
             ).status == 204
    end

    inviter_identity = Base.encode64(:binary.copy(<<0x31>>, 128))
    invitee_identity = Base.encode64(:binary.copy(<<0x32>>, 128))

    for {role, message} <- [{"inviter", inviter_identity}, {"invitee", invitee_identity}] do
      assert request(
               :post,
               "/api/pairing-sessions/#{role}/identity",
               Jason.encode!(%{message: message}),
               session_id
             ).status == 204
    end

    assert request(:get, "/api/pairing-sessions/inviter/identity", nil, session_id)
           |> Map.fetch!(:resp_body)
           |> Jason.decode!()
           |> Map.fetch!("message") == invitee_identity

    assert request(
             :post,
             "/api/pairing-sessions/inviter/spake2",
             Jason.encode!(%{message: Base.encode64(inviter_spake)}),
             session_id
           ).status == 409

    assert request(:delete, "/api/pairing-sessions", nil, session_id).status == 204
  end

  test "HTTP endpoint rejects malformed encoding, sizes, roles, stages and session capabilities" do
    {:ok, session_id} = PairingSessions.create()

    invalid_encoding =
      request(
        :post,
        "/api/pairing-sessions/inviter/spake2",
        Jason.encode!(%{message: "not base64!"}),
        session_id
      )

    assert invalid_encoding.status == 400

    invalid_size =
      request(
        :post,
        "/api/pairing-sessions/inviter/spake2",
        Jason.encode!(%{message: Base.encode64("too short")}),
        session_id
      )

    assert invalid_size.status == 400
    assert request(:get, "/api/pairing-sessions/inviter/spake2").status == 404
    assert request(:get, "/api/pairing-sessions/unknown/spake2", nil, session_id).status == 400
    assert request(:get, "/api/pairing-sessions/inviter/unknown", nil, session_id).status == 400

    assert request(
             :get,
             "/api/pairing-sessions/inviter/spake2",
             nil,
             String.duplicate("0", 64)
           ).status == 404
  end

  test "expired sessions reject reads and writes" do
    server = start_supervised!(PairingSessions)
    {:ok, session_id} = PairingSessions.create(server)

    :sys.replace_state(server, fn state ->
      put_in(state.sessions[session_id].expires_at, System.monotonic_time(:millisecond) - 1)
    end)

    assert PairingSessions.fetch(server, session_id, :inviter, :spake2) == {:error, :expired}

    assert PairingSessions.put(server, session_id, :inviter, :spake2, :binary.copy(<<0>>, 33)) ==
             {:error, :expired}
  end

  test "cancellation deletes session messages" do
    server = start_supervised!(PairingSessions)
    {:ok, session_id} = PairingSessions.create(server)
    assert :ok = PairingSessions.delete(server, session_id)
    assert PairingSessions.fetch(server, session_id, :inviter, :spake2) == {:error, :not_found}
  end
end
