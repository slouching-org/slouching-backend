defmodule SlouchingServer.HandshakeSocketTest do
  use ExUnit.Case, async: true

  alias Slouching.V1.{ClientFrame, ClientHello, ServerFrame}
  alias SlouchingServer.HandshakeSocket

  test "v1 binary frame receives honest Elixir ServerHello" do
    request = %ClientFrame{payload: {:hello, %ClientHello{protocol_version: 1}}}
    {:ok, initial} = HandshakeSocket.init(:await_hello)

    assert {:push, {:binary, response}, active} =
             HandshakeSocket.handle_in(
               {ClientFrame.encode(request), opcode: :binary},
               initial
             )

    assert %ServerFrame{payload: {:hello, hello}} = ServerFrame.decode(response)
    assert hello.protocol_version == 1
    assert hello.server_role == "elixir"
    refute hello.identity_available
    refute hello.messaging_available
    refute hello.calls_available
    assert active.phase == :active

    assert {:stop, :heartbeat_timeout, {1001, "heartbeat timeout"}, ^active} =
             HandshakeSocket.handle_info({:socket_timeout, :heartbeat, active.generation}, active)
  end

  test "unsupported version receives supported version in binary frame" do
    request = %ClientFrame{payload: {:hello, %ClientHello{protocol_version: 2}}}
    {:ok, initial} = HandshakeSocket.init(:await_hello)

    assert {:stop, :normal, 1000, {:binary, response}, ^initial} =
             HandshakeSocket.handle_in(
               {ClientFrame.encode(request), opcode: :binary},
               initial
             )

    assert %ServerFrame{payload: {:version_error, error}} = ServerFrame.decode(response)
    assert error.supported_version == 1
  end

  test "ping refreshes heartbeat deadline and stale timer cannot close the session" do
    request = %ClientFrame{payload: {:hello, %ClientHello{protocol_version: 1}}}
    {:ok, initial} = HandshakeSocket.init(:await_hello)

    assert {:push, {:binary, _response}, active} =
             HandshakeSocket.handle_in({ClientFrame.encode(request), opcode: :binary}, initial)

    assert {:ok, refreshed} = HandshakeSocket.handle_control({<<1>>, opcode: :ping}, active)
    assert refreshed.generation == active.generation + 1

    assert {:ok, ^refreshed} =
             HandshakeSocket.handle_info(
               {:socket_timeout, :heartbeat, active.generation},
               refreshed
             )

    assert {:stop, :heartbeat_timeout, {1001, "heartbeat timeout"}, ^refreshed} =
             HandshakeSocket.handle_info(
               {:socket_timeout, :heartbeat, refreshed.generation},
               refreshed
             )
  end

  test "hello deadline closes a socket without a handshake" do
    {:ok, initial} = HandshakeSocket.init(:await_hello)

    assert {:stop, :hello_timeout, {1001, "hello timeout"}, ^initial} =
             HandshakeSocket.handle_info({:socket_timeout, :hello, 0}, initial)
  end
end
