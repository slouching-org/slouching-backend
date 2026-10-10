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
    SfuCallAnswer,
    SfuCallError,
    SfuCallJoined,
    SfuIceCandidate,
    VersionError
  }

  alias ExWebRTC.ICECandidate
  alias SlouchingServer.Calls.SfuCallRooms

  @protocol_version 2
  @hello_timeout_ms 5_000
  @heartbeat_timeout_ms 15_000
  @auth_timeout_ms 5_000
  @auth_domain "slouching/gateway-auth/v1\0"

  @impl true
  def init(:await_hello) do
    schedule_timeout(:hello, 0, @hello_timeout_ms)

    {:ok,
     %{
       phase: :await_hello,
       generation: 0,
       call_id: nil,
       call_rooms: SfuCallRooms
     }}
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
                 calls_available: true,
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
                 application_routes_available: true
               }}
          }

          next_state = %{
            state
            | phase: :active,
              generation: state.generation + 1,
              call_id: nil,
              call_rooms: SlouchingServer.Calls.SfuCallRooms
          }

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

  def handle_in({payload, [opcode: :binary]}, %{phase: :active, call_id: nil} = state) do
    case ClientFrame.decode(payload) do
      %ClientFrame{payload: {:sfu_call_join, request}} -> join_call(request, state)
      _ -> call_error(<<>>, :join_required, state)
    end
  rescue
    Protobuf.DecodeError -> {:stop, :invalid_call_frame, {1002, "Invalid protobuf"}, state}
  end

  def handle_in({payload, [opcode: :binary]}, %{phase: :active} = state) do
    case ClientFrame.decode(payload) do
      %ClientFrame{payload: {:sfu_call_offer, %{call_id: call_id, sdp: sdp}}}
      when call_id == state.call_id ->
        answer_call_offer(sdp, state)

      %ClientFrame{
        payload:
          {:sfu_ice_candidate,
           %{
             call_id: call_id,
             candidate: candidate_text,
             sdp_mid: sdp_mid,
             sdp_m_line_index: m_line_index,
             username_fragment: username_fragment
           }}
      }
      when call_id == state.call_id ->
        add_call_candidate(candidate_text, sdp_mid, m_line_index, username_fragment, state)

      %ClientFrame{payload: {:sfu_call_leave, %{call_id: call_id}}}
      when call_id == state.call_id ->
        :ok = SfuCallRooms.leave(state.call_rooms, call_id, state.device_public_key)
        {:stop, :normal, {1000, "call left"}, %{state | call_id: nil}}

      _ ->
        call_error(state.call_id, :invalid_call_frame, state)
    end
  rescue
    Protobuf.DecodeError -> {:stop, :invalid_call_frame, {1002, "Invalid protobuf"}, state}
  end

  def handle_in({_payload, _opcode}, %{phase: :active} = state),
    do: {:stop, :unsupported_data, {1003, "Binary application frames required"}, state}

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

  def handle_info(
        {:sfu_call_ice_candidate, call_id, device_key, candidate},
        %{phase: :active, call_id: call_id, device_public_key: device_key} = state
      ) do
    message = %SfuIceCandidate{
      call_id: call_id,
      candidate: candidate.candidate,
      sdp_mid: candidate.sdp_mid || "",
      sdp_m_line_index: candidate.sdp_m_line_index || 0,
      username_fragment: candidate.username_fragment || ""
    }

    frame = %ServerFrame{payload: {:sfu_ice_candidate, message}}
    {:push, {:binary, ServerFrame.encode(frame)}, state}
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, %{call_id: call_id, device_public_key: device_key, call_rooms: rooms})
      when is_binary(call_id) do
    _ = SfuCallRooms.leave(rooms, call_id, device_key)
    :ok
  catch
    :exit, _reason -> :ok
  end

  def terminate(_reason, _state), do: :ok

  defp join_call(request, state) do
    %{
      call_id: call_id,
      group_id: group_id,
      epoch: epoch,
      roster: roster,
      roster_signature: signature
    } = request

    case SfuCallRooms.join(
           SfuCallRooms,
           call_id,
           group_id,
           epoch,
           roster,
           state.device_public_key,
           signature,
           self()
         ) do
      :ok ->
        frame = %ServerFrame{
          payload: {:sfu_call_joined, %SfuCallJoined{call_id: call_id, roster: Enum.sort(roster)}}
        }

        next_state = %{state | call_id: call_id, call_rooms: SfuCallRooms}
        {:push, {:binary, ServerFrame.encode(frame)}, next_state}

      {:error, reason} ->
        call_error(call_id, reason, state)
    end
  end

  defp answer_call_offer(sdp, state) when byte_size(sdp) in 1..(128 * 1024)//1 do
    case SfuCallRooms.answer_offer(state.call_rooms, state.call_id, state.device_public_key, sdp) do
      {:ok, answer} ->
        message = %SfuCallAnswer{call_id: state.call_id, sdp: answer.sdp}
        frame = %ServerFrame{payload: {:sfu_call_answer, message}}
        {:push, {:binary, ServerFrame.encode(frame)}, state}

      {:error, reason} ->
        call_error(state.call_id, reason, state)
    end
  end

  defp answer_call_offer(_sdp, state), do: call_error(state.call_id, :invalid_offer_size, state)

  defp add_call_candidate(candidate_text, sdp_mid, m_line_index, username_fragment, state)
       when byte_size(candidate_text) in 1..2_048 and byte_size(sdp_mid) <= 64 and
              byte_size(username_fragment) <= 256 do
    candidate = %ICECandidate{
      candidate: candidate_text,
      sdp_mid: if(sdp_mid == "", do: nil, else: sdp_mid),
      sdp_m_line_index: m_line_index,
      username_fragment: if(username_fragment == "", do: nil, else: username_fragment)
    }

    case SfuCallRooms.add_ice_candidate(
           state.call_rooms,
           state.call_id,
           state.device_public_key,
           candidate
         ) do
      :ok -> {:ok, state}
      {:error, reason} -> call_error(state.call_id, reason, state)
    end
  end

  defp add_call_candidate(_candidate, _mid, _index, _ufrag, state),
    do: call_error(state.call_id, :invalid_ice_candidate, state)

  defp call_error(call_id, reason, state) do
    message = %SfuCallError{
      call_id: call_id,
      code: reason |> error_code() |> Atom.to_string(),
      message: "SFU call request rejected"
    }

    frame = %ServerFrame{payload: {:sfu_call_error, message}}
    {:push, {:binary, ServerFrame.encode(frame)}, state}
  end

  defp error_code(reason) when is_atom(reason), do: reason
  defp error_code({:room_rejected_peer, reason}) when is_atom(reason), do: reason
  defp error_code(_reason), do: :call_request_failed

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
