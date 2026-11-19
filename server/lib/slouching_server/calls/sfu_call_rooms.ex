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

  @shutdown_timeout_ms 1_000
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

  def answer_offer(server \\ __MODULE__, call_id, device_key, sdp)

  def answer_offer(server, call_id, device_key, sdp)
      when is_binary(sdp) and byte_size(sdp) in 1..@max_sdp_bytes do
    with {:ok, peer} <- GenServer.call(server, {:fetch_peer, call_id, device_key}) do
      try do
        SfuPeer.answer_offer(peer, sdp)
      catch
        :exit, _reason -> {:error, :peer_unavailable}
      end
    end
  end

  def answer_offer(_server, _call_id, _device_key, _sdp), do: {:error, :invalid_offer_size}

  def add_ice_candidate(server \\ __MODULE__, call_id, device_key, %ICECandidate{} = candidate) do
    with {:ok, peer} <- GenServer.call(server, {:fetch_peer, call_id, device_key}) do
      try do
        SfuPeer.add_ice_candidate(peer, candidate)
      catch
        :exit, _reason -> {:error, :peer_unavailable}
      end
    end
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
  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)
    {:ok, %{rooms: %{}, monitors: %{}, supervisor: supervisor}}
  end

  @impl true
  def handle_call(
        {:join, call_id, group_id, epoch, roster, device_key, signature, owner},
        _from,
        state
      ) do
    roster = if is_list(roster), do: Enum.sort(roster), else: roster

    with :ok <- validate_join(call_id, group_id, epoch, roster, device_key, signature, owner),
         :ok <- verify_roster_signature(call_id, group_id, epoch, roster, device_key, signature),
         {:ok, room, room_monitors, created?} <-
           fetch_or_create_room(state, call_id, group_id, epoch, roster) do
      with :ok <- ensure_room_member(room, device_key),
           {:ok, room, _participant, participant_monitors} <-
             start_participant(state.supervisor, room, call_id, device_key, roster, owner) do
        rooms = Map.put(state.rooms, call_id, room)

        monitors =
          state.monitors
          |> Map.merge(room_monitors)
          |> Map.merge(participant_monitors)

        {:reply, :ok, %{state | rooms: rooms, monitors: monitors}}
      else
        {:error, reason} ->
          if created? do
            Process.demonitor(room.forwarder_monitor, [:flush])
            stop_child(room.forwarder)
          end

          {:reply, {:error, reason}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:fetch_peer, call_id, device_key}, _from, state) do
    case fetch_participant(state, call_id, device_key) do
      {:ok, participant} -> {:reply, {:ok, participant.peer}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:leave, call_id, device_key}, from, state) do
    case begin_leave(state, call_id, device_key, from) do
      {:ok, next} -> {:noreply, next}
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

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    case Map.pop(state.monitors, monitor) do
      {nil, _monitors} ->
        {:noreply, state}

      {{:forwarder, call_id}, monitors} ->
        {:noreply, drop_room(%{state | monitors: monitors}, call_id, {:forwarder_down, reason})}

      {{:peer, call_id, device_key}, monitors} ->
        case fetch_participant(state, call_id, device_key) do
          {:ok, _participant} ->
            notify_participant(
              state,
              call_id,
              device_key,
              {:sfu_call_ended, call_id, device_key, reason}
            )

          _ ->
            :ok
        end

        case drop_participant(%{state | monitors: monitors}, call_id, device_key) do
          {:ok, next} -> {:noreply, next}
          :error -> {:noreply, %{state | monitors: monitors}}
        end

      {{:owner, call_id, device_key}, monitors} ->
        case begin_leave(%{state | monitors: monitors}, call_id, device_key, nil) do
          {:ok, next} -> {:noreply, next}
          :error -> {:noreply, %{state | monitors: monitors}}
        end
    end
  end

  def handle_info({:EXIT, supervisor, reason}, %{supervisor: supervisor} = state) do
    {:stop, reason, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.rooms, fn {_call_id, room} ->
      Enum.each(room.participants, fn {_device_key, participant} ->
        stop_child(participant.peer)
      end)

      stop_child(room.forwarder)
    end)

    if Process.alive?(state.supervisor) do
      try do
        Supervisor.stop(state.supervisor, :normal)
      catch
        :exit, _reason -> :ok
      end
    end

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
        {:ok, room, %{}, false}

      {:ok, _room} ->
        {:error, :call_roster_mismatch}

      :error when map_size(state.rooms) >= @max_rooms ->
        {:error, :call_service_at_capacity}

      :error ->
        case DynamicSupervisor.start_child(state.supervisor, {SfuForwarder, [members: roster]}) do
          {:ok, forwarder} ->
            forwarder_monitor = Process.monitor(forwarder)

            room = %{
              call_id: call_id,
              group_id: group_id,
              epoch: epoch,
              roster: roster,
              forwarder: forwarder,
              forwarder_monitor: forwarder_monitor,
              participants: %{}
            }

            {:ok, room, %{forwarder_monitor => {:forwarder, call_id}}, true}

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

  defp start_participant(supervisor, room, call_id, device_key, roster, owner) do
    opts = [
      device_key: device_key,
      remote_source_keys: List.delete(roster, device_key),
      forwarder: room.forwarder,
      signaling_owner: self(),
      call_id: call_id
    ]

    with {:ok, peer} <- DynamicSupervisor.start_child(supervisor, {SfuPeer, opts}) do
      owner_monitor = Process.monitor(owner)
      peer_monitor = Process.monitor(peer)

      participant = %{
        owner: owner,
        peer: peer,
        owner_monitor: owner_monitor,
        peer_monitor: peer_monitor,
        leaving?: false,
        leave_waiters: []
      }

      room = put_in(room.participants[device_key], participant)

      monitors = %{
        owner_monitor => {:owner, call_id, device_key},
        peer_monitor => {:peer, call_id, device_key}
      }

      {:ok, room, participant, monitors}
    end
  end

  defp fetch_participant(state, call_id, device_key) do
    with {:ok, room} <- Map.fetch(state.rooms, call_id),
         {:ok, %{leaving?: false} = participant} <- Map.fetch(room.participants, device_key) do
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

  # Keep admission reserved until DOWN. The caller waits for its own teardown,
  # but neither this coordinator nor the shared DynamicSupervisor waits for it.
  defp begin_leave(state, call_id, device_key, from) do
    with {:ok, room} <- Map.fetch(state.rooms, call_id),
         {:ok, participant} <- Map.fetch(room.participants, device_key) do
      unless participant.leaving?, do: stop_child(participant.peer)
      Process.demonitor(participant.owner_monitor, [:flush])
      waiters = if from, do: [from | participant.leave_waiters], else: participant.leave_waiters
      participant = %{participant | leaving?: true, leave_waiters: waiters}
      state = put_in(state.rooms[call_id].participants[device_key], participant)
      {:ok, %{state | monitors: Map.delete(state.monitors, participant.owner_monitor)}}
    else
      _ -> :error
    end
  end

  defp drop_participant(state, call_id, device_key) do
    with {:ok, room} <- Map.fetch(state.rooms, call_id),
         {:ok, participant} <- Map.fetch(room.participants, device_key) do
      Process.demonitor(participant.owner_monitor, [:flush])
      Process.demonitor(participant.peer_monitor, [:flush])
      Enum.each(participant.leave_waiters, &GenServer.reply(&1, :ok))

      monitors =
        state.monitors
        |> Map.delete(participant.owner_monitor)
        |> Map.delete(participant.peer_monitor)

      participants = Map.delete(room.participants, device_key)

      if map_size(participants) == 0 do
        Process.demonitor(room.forwarder_monitor, [:flush])
        monitors = Map.delete(monitors, room.forwarder_monitor)
        stop_child(room.forwarder)
        {:ok, %{state | rooms: Map.delete(state.rooms, call_id), monitors: monitors}}
      else
        room = %{room | participants: participants}
        {:ok, %{state | rooms: Map.put(state.rooms, call_id, room), monitors: monitors}}
      end
    else
      _ -> :error
    end
  end

  defp drop_room(state, call_id, reason) do
    case Map.pop(state.rooms, call_id) do
      {nil, _rooms} ->
        state

      {room, rooms} ->
        Process.demonitor(room.forwarder_monitor, [:flush])

        monitors =
          Enum.reduce(
            room.participants,
            Map.delete(state.monitors, room.forwarder_monitor),
            fn {device_key, participant}, acc ->
              unless participant.leaving?,
                do: send(participant.owner, {:sfu_call_ended, call_id, device_key, reason})

              Enum.each(participant.leave_waiters, &GenServer.reply(&1, :ok))
              Process.demonitor(participant.owner_monitor, [:flush])
              Process.demonitor(participant.peer_monitor, [:flush])
              stop_child(participant.peer)

              acc
              |> Map.delete(participant.owner_monitor)
              |> Map.delete(participant.peer_monitor)
            end
          )

        stop_child(room.forwarder)
        %{state | rooms: rooms, monitors: monitors}
    end
  end

  defp stop_child(pid) when is_pid(pid) do
    # Calling DynamicSupervisor.terminate_child here would serialize every room
    # behind a stalled child. Temporary children remove themselves on exit.
    Task.start(fn ->
      try do
        GenServer.stop(pid, :shutdown, @shutdown_timeout_ms)
      catch
        :exit, _reason -> Process.exit(pid, :kill)
      end
    end)

    :ok
  end
end
