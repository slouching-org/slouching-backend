defmodule SlouchingServer.HandshakeSocket do
  @moduledoc """
  Versioned protobuf handshake followed by a local transport heartbeat.
  The active socket does not accept application messages.
  """

  @behaviour WebSock

  alias Slouching.V1.{ClientFrame, ServerFrame, ServerHello, VersionError}

  @protocol_version 1
  @hello_timeout_ms 5_000
  @heartbeat_timeout_ms 15_000

  @impl true
  def init(:await_hello) do
    schedule_timeout(:hello, 0, @hello_timeout_ms)
    {:ok, %{phase: :await_hello, generation: 0}}
  end

  @impl true
  def handle_in({payload, [opcode: :binary]}, %{phase: :await_hello} = state) do
    case ClientFrame.decode(payload) do
      %ClientFrame{payload: {:hello, %{protocol_version: @protocol_version}}} ->
        reply =
          %ServerFrame{
            payload:
              {:hello,
               %ServerHello{
                 protocol_version: @protocol_version,
                 server_role: "elixir",
                 identity_available: false,
                 messaging_available: false,
                 calls_available: false
               }}
          }

        next_state = %{state | phase: :active, generation: state.generation + 1}
        schedule_timeout(:heartbeat, next_state.generation, @heartbeat_timeout_ms)
        {:push, {:binary, ServerFrame.encode(reply)}, next_state}

      %ClientFrame{payload: {:hello, _}} ->
        reply = %ServerFrame{payload: {:version_error, %VersionError{supported_version: 1}}}
        {:stop, :normal, 1000, {:binary, ServerFrame.encode(reply)}, state}

      _ ->
        {:stop, :invalid_handshake, {1002, "ClientHello required"}, state}
    end
  rescue
    Protobuf.DecodeError ->
      {:stop, :invalid_handshake, {1002, "Invalid protobuf"}, state}
  end

  def handle_in({_payload, [opcode: :text]}, %{phase: :await_hello} = state),
    do: {:stop, :invalid_handshake, {1003, "Binary frame required"}, state}

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
end
