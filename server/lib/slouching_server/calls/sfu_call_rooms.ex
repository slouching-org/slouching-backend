defmodule SlouchingServer.Calls.SfuCallRooms do
  @moduledoc """
  Coordinates ephemeral SFU call rooms. Each call member must sign the same
  roster statement with its authenticated device key before a peer connection
  is created. Clients derive that roster from their local call MLS group; this
  service does not possess MLS secrets and cannot independently verify MLS.
  """

  use GenServer

  alias ExWebRTC.ICECandidate
  alias SlouchingServer.Calls.{SfuForwarder, SfuPeer}

  @max_rooms 1_000
  @max_members 16
  @max_sdp_bytes 128 * 1024
  @roster_domain "slouching/sfu-roster/v1\0"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.take(opts, [:name]))
  end

  def join(server \\ __MODULE__, call_id, group_id, epoch, roster, device_key, signature, owner) do
    GenServer.call(
      server,
      {:join, call_id, group_id, epoch, roster, device_key, signature, owner}
    )
  end

  def answer_offer(server \\ __MODULE__, call_id, device_key, sdp) do
    GenServer.call(server, {:answer_offer, call_id, device_key, sdp}, 20_000)
  end

  def add_ice_candidate(server \\ __MODULE__, call_id, device_key, %ICECandidate{} = candidate) do
    GenServer.call(server, {:add_ice_candidate, call_id, device_key, candidate})
  end

  def leave(server \\ __MODULE__, call_id, device_key) do
    GenServer.call(server, {:leave, call_id, device_key})
  end

  @doc "Canonical signed bytes for the per-device roster attestation."
  def roster_payload(call_id, group_id, epoch, roster)
      when is_binary(call_id) and byte_size(call_id) == 16 and is_binary(group_id) and
             byte_size(group_id) == 16 and is_integer(epoch) and epoch >= 0 and
             epoch <= 0xFFFFFFFFFFFFFFFF and is_list(roster) do
    @roster_domain <>
      call_id <>
      group_id <>
      <<epoch::unsigned-big-64>> <>
      <<length(roster)::unsigned-big-16>> <>
      (roster |> Enum.sort() |> IO.iodata_to_binary())
  end

  def roster_payload(_call_id, _group_id, _epoch, _roster), do: <<>>

  @impl true
  def init(:ok), do: {:ok, %{rooms: %{}, monitors: %{}}}

  @impl true
  def handle_call(
        {:join, call_id, group_id, epoch, roster, device_key, signature, owner},
        _from,
        state
      ) do
    roster = if is_list(roster), do: Enum.sort(roster), else: roster

    with :ok <- validate_join(call_id, group_id, epoch, roster, device_key, signature, owner),
         :ok <- verify_roster_signature(call_id, group_id, epoch, roster, device_key, signature),
         {:ok, room} <- fetch_or_create_room(state, call_id, group_id, epoch, roster),
         :ok <- ensure_room_member(room, device_key),
         {:ok, room, _participant, new_monitors} <-
           start_participant(room, call_id, device_key, roster, owner) do
      rooms = Map.put(state.rooms, call_id, room)
      monitors = Map.merge(state.monitors, new_monitors)
      {:reply, :ok, %{state | rooms: rooms, monitors: monitors}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:answer_offer, call_id, device_key, sdp}, _from, state)
      when is_binary(sdp) and byte_size(sdp) in 1..@max_sdp_bytes do
    with {:ok, participant} <- fetch_participant(state, call_id, device_key),
         {:ok, answer} <- SfuPeer.answer_offer(participant.peer, sdp) do
      {:reply, {:ok, answer}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:answer_offer, _call_id, _device_key, _sdp}, _from, state),
    do: {:reply, {:error, :invalid_offer_size}, state}

  def handle_call({:add_ice_candidate, call_id, device_key, candidate}, _from, state) do
    with {:ok, participant} <- fetch_participant(state, call_id, device_key),
         :ok <- SfuPeer.add_ice_candidate(participant.peer, candidate) do
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:leave, call_id, device_key}, _from, state) do
    case drop_participant(state, call_id, device_key) do
      {:ok, next} -> {:reply, :ok, next}
      :error -> {:reply, {:error, :unknown_participant}, state}
    end
  end

  @impl true
  def handle_info({:sfu_peer_ice_candidate, call_id, device_key, candidate}, state) do
    notify_participant(
      state,
      call_id,
      device_key,
      {:sfu_call_ice_candidate, call_id, device_key, candidate}
    )

    {:noreply, state}
  end

  def handle_info({:sfu_peer_connection_state, call_id, device_key, connection_state}, state) do
    notify_participant(
      state,
      call_id,
      device_key,
      {:sfu_call_connection_state, call_id, device_key, connection_state}
    )

    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, monitor) do
      {nil, _monitors} ->
        {:noreply, state}

      {{call_id, device_key}, monitors} ->
        case drop_participant(%{state | monitors: monitors}, call_id, device_key) do
          {:ok, next} -> {:noreply, next}
          :error -> {:noreply, %{state | monitors: monitors}}
        end
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.rooms, fn {_call_id, room} ->
      Enum.each(room.participants, fn {_device_key, participant} ->
        if Process.alive?(participant.peer), do: GenServer.stop(participant.peer, :normal)
      end)

      if Process.alive?(room.forwarder), do: GenServer.stop(room.forwarder, :normal)
    end)

    :ok
  end

  defp validate_join(call_id, group_id, epoch, roster, device_key, signature, owner) do
    cond do
      not (is_binary(call_id) and byte_size(call_id) == 16) ->
        {:error, :invalid_call_id}

      not (is_binary(group_id) and byte_size(group_id) == 16) ->
        {:error, :invalid_group_id}

      not (is_integer(epoch) and epoch >= 0 and epoch <= 0xFFFFFFFFFFFFFFFF) ->
        {:error, :invalid_epoch}

      not valid_roster?(roster) ->
        {:error, :invalid_roster}

      not (is_binary(device_key) and byte_size(device_key) == 32) ->
        {:error, :invalid_device_key}

      device_key not in roster ->
        {:error, :device_not_in_roster}

      not (is_binary(signature) and byte_size(signature) == 64) ->
        {:error, :invalid_signature}

      not is_pid(owner) ->
        {:error, :invalid_owner}

      true ->
        :ok
    end
  end

  defp valid_roster?(roster) when is_list(roster) and length(roster) in 2..@max_members do
    Enum.all?(roster, &(is_binary(&1) and byte_size(&1) == 32)) and
      length(Enum.uniq(roster)) == length(roster)
  end

  defp valid_roster?(_roster), do: false

  defp verify_roster_signature(call_id, group_id, epoch, roster, device_key, signature) do
    payload = roster_payload(call_id, group_id, epoch, roster)

    if :crypto.verify(:eddsa, :none, payload, signature, [device_key, :ed25519]),
      do: :ok,
      else: {:error, :invalid_signature}
  rescue
    _error -> {:error, :invalid_signature}
  end

  defp fetch_or_create_room(state, call_id, group_id, epoch, roster) do
    case Map.fetch(state.rooms, call_id) do
      {:ok, %{group_id: ^group_id, epoch: ^epoch, roster: ^roster} = room} ->
        {:ok, room}

      {:ok, _room} ->
        {:error, :call_roster_mismatch}

      :error when map_size(state.rooms) >= @max_rooms ->
        {:error, :call_service_at_capacity}

      :error ->
        case SfuForwarder.start_link(members: roster) do
          {:ok, forwarder} ->
            Process.unlink(forwarder)

            {:ok,
             %{
               call_id: call_id,
               group_id: group_id,
               epoch: epoch,
               roster: roster,
               forwarder: forwarder,
               participants: %{}
             }}

          {:error, reason} ->
            {:error, {:call_service_start_failed, reason}}
        end
    end
  end

  defp ensure_room_member(room, device_key) do
    cond do
      Map.has_key?(room.participants, device_key) -> {:error, :participant_already_joined}
      map_size(room.participants) >= length(room.roster) -> {:error, :call_full}
      true -> :ok
    end
  end

  defp start_participant(room, call_id, device_key, roster, owner) do
    opts = [
      device_key: device_key,
      remote_source_keys: List.delete(roster, device_key),
      forwarder: room.forwarder,
      signaling_owner: self(),
      call_id: call_id
    ]

    with {:ok, peer} <- SfuPeer.start_link(opts) do
      Process.unlink(peer)
      owner_monitor = Process.monitor(owner)
      peer_monitor = Process.monitor(peer)

      participant = %{
        owner: owner,
        peer: peer,
        owner_monitor: owner_monitor,
        peer_monitor: peer_monitor
      }

      room = put_in(room.participants[device_key], participant)

      monitors = %{
        owner_monitor => {call_id, device_key},
        peer_monitor => {call_id, device_key}
      }

      {:ok, room, participant, monitors}
    end
  end

  defp fetch_participant(state, call_id, device_key) do
    with {:ok, room} <- Map.fetch(state.rooms, call_id),
         {:ok, participant} <- Map.fetch(room.participants, device_key) do
      {:ok, participant}
    else
      _ -> {:error, :unknown_participant}
    end
  end

  defp notify_participant(state, call_id, device_key, message) do
    with {:ok, room} <- Map.fetch(state.rooms, call_id) do
      case Map.fetch(room.participants, device_key) do
        {:ok, %{owner: owner}} -> send(owner, message)
        :error -> :ok
      end
    end
  end

  defp drop_participant(state, call_id, device_key) do
    with {:ok, room} <- Map.fetch(state.rooms, call_id),
         {:ok, participant} <- Map.fetch(room.participants, device_key) do
      Process.demonitor(participant.owner_monitor, [:flush])
      Process.demonitor(participant.peer_monitor, [:flush])
      if Process.alive?(participant.peer), do: GenServer.stop(participant.peer, :normal)

      monitors =
        state.monitors
        |> Map.delete(participant.owner_monitor)
        |> Map.delete(participant.peer_monitor)

      participants = Map.delete(room.participants, device_key)

      if map_size(participants) == 0 do
        if Process.alive?(room.forwarder), do: GenServer.stop(room.forwarder, :normal)
        {:ok, %{state | rooms: Map.delete(state.rooms, call_id), monitors: monitors}}
      else
        room = %{room | participants: participants}
        {:ok, %{state | rooms: Map.put(state.rooms, call_id, room), monitors: monitors}}
      end
    else
      _ -> :error
    end
  end
end
