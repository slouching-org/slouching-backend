defmodule SlouchingServer.HandshakeSocket do
  @moduledoc """
  Versioned protobuf handshake with Ed25519 device proof, followed by a local
  transport heartbeat. Authentication proves key possession only; application
  routes remain unavailable until independently authorized and implemented.
  """

  @behaviour WebSock

  alias Slouching.V1.{
    Authenticated,
    AuthProof,
    ClientFrame,
    ServerFrame,
    ServerHello,
    VersionError
  }

  @protocol_version 2
  @hello_timeout_ms 5_000
  @heartbeat_timeout_ms 15_000
  @auth_timeout_ms 5_000
  @auth_domain "slouching/gateway-auth/v1\0"

  @impl true
  def init(:await_hello) do
    schedule_timeout(:hello, 0, @hello_timeout_ms)
    {:ok, %{phase: :await_hello, generation: 0}}
  end

  @impl true
  def handle_in({payload, [opcode: :binary]}, %{phase: :await_hello} = state) do
    case ClientFrame.decode(payload) do
      %ClientFrame{
        payload: {:hello, %{protocol_version: @protocol_version, device_public_key: public_key}}
      }
      when byte_size(public_key) == 32 ->
        nonce = :crypto.strong_rand_bytes(32)

        reply =
          %ServerFrame{
            payload:
              {:hello,
               %ServerHello{
                 protocol_version: @protocol_version,
                 server_role: "elixir",
                 identity_available: false,
                 messaging_available: false,
                 calls_available: false,
                 auth_nonce: nonce
               }}
          }

        next_state =
          Map.merge(state, %{
            phase: :await_auth_proof,
            generation: state.generation + 1,
            device_public_key: public_key,
            auth_nonce: nonce
          })

        schedule_timeout(:authentication, next_state.generation, @auth_timeout_ms)
        {:push, {:binary, ServerFrame.encode(reply)}, next_state}

      %ClientFrame{payload: {:hello, %{protocol_version: version}}}
      when version != @protocol_version ->
        reply = %ServerFrame{
          payload: {:version_error, %VersionError{supported_version: @protocol_version}}
        }

        {:stop, :normal, 1000, {:binary, ServerFrame.encode(reply)}, state}

      %ClientFrame{payload: {:hello, _}} ->
        {:stop, :invalid_handshake, {1008, "valid device public key required"}, state}

      _ ->
        {:stop, :invalid_handshake, {1002, "ClientHello required"}, state}
    end
  rescue
    Protobuf.DecodeError ->
      {:stop, :invalid_handshake, {1002, "Invalid protobuf"}, state}
  end

  def handle_in({payload, [opcode: :binary]}, %{phase: :await_auth_proof} = state) do
    case ClientFrame.decode(payload) do
      %ClientFrame{payload: {:auth_proof, %AuthProof{signature: signature}}}
      when byte_size(signature) == 64 ->
        signed = auth_payload(state.device_public_key, state.auth_nonce)

        if valid_device_proof?(state.device_public_key, signed, signature) do
          reply = %ServerFrame{
            payload:
              {:authenticated,
               %Authenticated{
                 device_public_key: state.device_public_key,
                 application_routes_available: false
               }}
          }

          next_state = %{state | phase: :active, generation: state.generation + 1}
          schedule_timeout(:heartbeat, next_state.generation, @heartbeat_timeout_ms)
          {:push, {:binary, ServerFrame.encode(reply)}, next_state}
        else
          {:stop, :invalid_authentication, {1008, "invalid device proof"}, state}
        end

      _ ->
        {:stop, :invalid_authentication, {1008, "valid device proof required"}, state}
    end
  rescue
    Protobuf.DecodeError -> {:stop, :invalid_authentication, {1002, "Invalid protobuf"}, state}
  end

  def handle_in({_payload, [opcode: :text]}, %{phase: :await_hello} = state),
    do: {:stop, :invalid_handshake, {1003, "Binary frame required"}, state}

  def handle_in({_payload, [opcode: :text]}, %{phase: :await_auth_proof} = state),
    do: {:stop, :invalid_authentication, {1003, "Binary frame required"}, state}

  def handle_in({_payload, _opcode}, %{phase: :active} = state),
    do: {:stop, :unsupported_data, {1003, "Application frames unavailable"}, state}

  @impl true
  def handle_control({_payload, [opcode: :ping]}, %{phase: :active} = state) do
    next_state = %{state | generation: state.generation + 1}
    schedule_timeout(:heartbeat, next_state.generation, @heartbeat_timeout_ms)
    {:ok, next_state}
  end

  def handle_control({_payload, _opcode}, state), do: {:ok, state}

  @impl true
  def handle_info({:socket_timeout, :hello, 0}, %{phase: :await_hello} = state),
    do: {:stop, :hello_timeout, {1001, "hello timeout"}, state}

  def handle_info(
        {:socket_timeout, :authentication, generation},
        %{phase: :await_auth_proof, generation: generation} = state
      ),
      do: {:stop, :authentication_timeout, {1008, "authentication timeout"}, state}

  def handle_info(
        {:socket_timeout, :heartbeat, generation},
        %{phase: :active, generation: generation} = state
      ),
      do: {:stop, :heartbeat_timeout, {1001, "heartbeat timeout"}, state}

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  defp schedule_timeout(kind, generation, interval_ms) do
    Process.send_after(self(), {:socket_timeout, kind, generation}, interval_ms)
  end

  defp auth_payload(public_key, nonce) do
    @auth_domain <> <<@protocol_version::unsigned-big-32>> <> public_key <> nonce
  end

  defp valid_device_proof?(public_key, payload, signature) do
    :crypto.verify(:eddsa, :none, payload, signature, [public_key, :ed25519])
  rescue
    _error -> false
  end
end
