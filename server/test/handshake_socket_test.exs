defmodule SlouchingServer.HandshakeSocketTest do
  use ExUnit.Case, async: true

  alias Slouching.V1.{AuthProof, Authenticated, ClientFrame, ClientHello, ServerFrame}
  alias SlouchingServer.HandshakeSocket

  test "v1 handshake challenges and authenticates possession of device key" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    request = hello(public_key)
    {:ok, initial} = HandshakeSocket.init(:await_hello)

    assert {:push, {:binary, response}, active} =
             HandshakeSocket.handle_in(
               {ClientFrame.encode(request), opcode: :binary},
               initial
             )

    assert %ServerFrame{payload: {:hello, hello}} = ServerFrame.decode(response)
    assert hello.protocol_version == 2
    assert hello.server_role == "elixir"
    assert byte_size(hello.auth_nonce) == 32
    refute hello.identity_available
    refute hello.messaging_available
    refute hello.calls_available

    signed =
      "slouching/gateway-auth/v1\0" <> <<2::unsigned-big-32>> <> public_key <> hello.auth_nonce

    signature = :crypto.sign(:eddsa, :none, signed, [private_key, :ed25519])
    proof = %ClientFrame{payload: {:auth_proof, %AuthProof{signature: signature}}}

    assert {:push, {:binary, authenticated_response}, authenticated} =
             HandshakeSocket.handle_in(
               {ClientFrame.encode(proof), opcode: :binary},
               active
             )

    assert %ServerFrame{payload: {:authenticated, %Authenticated{} = result}} =
             ServerFrame.decode(authenticated_response)

    assert result.device_public_key == public_key
    refute result.application_routes_available
    assert authenticated.phase == :active

    assert {:stop, :heartbeat_timeout, {1001, "heartbeat timeout"}, ^authenticated} =
             HandshakeSocket.handle_info(
               {:socket_timeout, :heartbeat, authenticated.generation},
               authenticated
             )
  end

  test "unsupported version receives supported version in binary frame" do
    request = %ClientFrame{payload: {:hello, %ClientHello{protocol_version: 1}}}
    {:ok, initial} = HandshakeSocket.init(:await_hello)

    assert {:stop, :normal, 1000, {:binary, response}, ^initial} =
             HandshakeSocket.handle_in(
               {ClientFrame.encode(request), opcode: :binary},
               initial
             )

    assert %ServerFrame{payload: {:version_error, error}} = ServerFrame.decode(response)
    assert error.supported_version == 2
  end

  test "ping refreshes heartbeat deadline and stale timer cannot close the session" do
    {:ok, initial} = HandshakeSocket.init(:await_hello)
    active = authenticate(initial)

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

  test "rejects an invalid signature and times out pending authentication" do
    {public_key, _private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {:ok, initial} = HandshakeSocket.init(:await_hello)

    assert {:push, {:binary, _response}, pending} =
             HandshakeSocket.handle_in(
               {ClientFrame.encode(hello(public_key)), opcode: :binary},
               initial
             )

    bad_proof = %ClientFrame{payload: {:auth_proof, %AuthProof{signature: <<0::512>>}}}

    assert {:stop, :invalid_authentication, {1008, _}, ^pending} =
             HandshakeSocket.handle_in(
               {ClientFrame.encode(bad_proof), opcode: :binary},
               pending
             )

    assert {:stop, :authentication_timeout, {1008, "authentication timeout"}, ^pending} =
             HandshakeSocket.handle_info(
               {:socket_timeout, :authentication, pending.generation},
               pending
             )
  end

  test "hello deadline closes a socket without a handshake" do
    {:ok, initial} = HandshakeSocket.init(:await_hello)

    assert {:stop, :hello_timeout, {1001, "hello timeout"}, ^initial} =
             HandshakeSocket.handle_info({:socket_timeout, :hello, 0}, initial)
  end

  test "verifies the Rust Iroh gateway authentication vector" do
    public_key =
      Base.decode16!("a7f6dfaf8f38b89ba8ce649b594f91e4d01fdc57f9c9493df43b5e50a9987367",
        case: :lower
      )

    signature =
      Base.decode16!(
        "a984b78474ab94d7ccf35fd00276c9922c9a5b1e8baa69c6d303c49fc6db501de202b9a31ca6e3675059a6b09c4e71906ff111bb59a37ad5ac554b45a444c404",
        case: :lower
      )

    nonce = :binary.copy(<<0x74>>, 32)
    payload = "slouching/gateway-auth/v1\0" <> <<2::unsigned-big-32>> <> public_key <> nonce

    assert :crypto.verify(:eddsa, :none, payload, signature, [public_key, :ed25519])
  end

  defp hello(public_key, protocol_version \\ 2) do
    %ClientFrame{
      payload:
        {:hello, %ClientHello{protocol_version: protocol_version, device_public_key: public_key}}
    }
  end

  defp authenticate(initial) do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    assert {:push, {:binary, hello_response}, pending} =
             HandshakeSocket.handle_in(
               {ClientFrame.encode(hello(public_key)), opcode: :binary},
               initial
             )

    %ServerFrame{payload: {:hello, server_hello}} = ServerFrame.decode(hello_response)

    signed =
      "slouching/gateway-auth/v1\0" <>
        <<2::unsigned-big-32>> <> public_key <> server_hello.auth_nonce

    proof = %ClientFrame{
      payload:
        {:auth_proof,
         %AuthProof{signature: :crypto.sign(:eddsa, :none, signed, [private_key, :ed25519])}}
    }

    assert {:push, {:binary, _response}, active} =
             HandshakeSocket.handle_in(
               {ClientFrame.encode(proof), opcode: :binary},
               pending
             )

    active
  end
end
