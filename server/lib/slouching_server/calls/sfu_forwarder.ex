defmodule SlouchingServer.Calls.SfuForwarder do
  @moduledoc """
  Forwards opaque RTP packets between already-authorized call participants.

  Admission, signaling, and transceiver negotiation are owned by the call
  coordinator. This process only accepts that coordinator's participant and
  per-source outbound-track map. It never parses or decrypts the RTP payload.
  """

  use GenServer

  alias ExWebRTC.PeerConnection

  @max_participants 256
  @max_peer_queue_length 100
  @max_data_message_bytes 16 * 1024
  @track_kinds [:audio, :video]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "Registers a call participant after the coordinator has verified admission."
  def add_participant(server, device_key, peer_connection, outbound_tracks) do
    GenServer.call(server, {:add_participant, device_key, peer_connection, outbound_tracks})
  end

  def remove_participant(server, device_key) do
    GenServer.call(server, {:remove_participant, device_key})
  end

  @doc "Adds an already-negotiated sender track for one call member to another."
  def set_outbound_track(server, subscriber_key, source_key, kind, track_id) do
    GenServer.call(server, {:set_outbound_track, subscriber_key, source_key, kind, track_id})
  end

  @doc "Registers the inbound media track ID reported by ExWebRTC for this sender."
  def register_source_track(server, device_key, kind, track_id) do
    GenServer.call(server, {:register_source_track, device_key, kind, track_id})
  end

  @doc "Registers the participant's open call DataChannel."
  def register_data_channel(server, device_key, channel_ref) when is_reference(channel_ref) do
    GenServer.call(server, {:register_data_channel, device_key, channel_ref})
  end

  def unregister_data_channel(server, device_key, channel_ref) do
    GenServer.call(server, {:unregister_data_channel, device_key, channel_ref})
  end

  @doc "Forwards one bounded opaque call DataChannel message to other members."
  def forward_data(server, device_key, channel_ref, data)
      when is_reference(channel_ref) and is_binary(data) and
             byte_size(data) in 1..@max_data_message_bytes do
    GenServer.call(server, {:forward_data, device_key, channel_ref, data})
  end

  def forward_data(_server, _device_key, _channel_ref, _data),
    do: {:error, :invalid_data_channel_message}

  @doc "Forwards to negotiated source tracks and skips peers with a full RTP queue."
  def forward(server, device_key, kind, track_id, %ExRTP.Packet{} = packet) do
    GenServer.call(server, {:forward, device_key, kind, track_id, packet})
  end

  @impl true
  def init(opts) do
    members = Keyword.get(opts, :members)

    if is_nil(members) or valid_roster?(members) do
      {:ok, %{participants: %{}, members: if(members, do: MapSet.new(members))}}
    else
      {:stop, :invalid_call_roster}
    end
  end

  @impl true
  def handle_call(
        {:add_participant, device_key, peer_connection, outbound_tracks},
        _from,
        state
      ) do
    cond do
      not valid_device_key?(device_key) ->
        {:reply, {:error, :invalid_device_key}, state}

      state.members && not MapSet.member?(state.members, device_key) ->
        {:reply, {:error, :unauthorized_member}, state}

      not is_pid(peer_connection) ->
        {:reply, {:error, :invalid_peer_connection}, state}

      not Process.alive?(peer_connection) ->
        {:reply, {:error, :invalid_peer_connection}, state}

      Map.has_key?(state.participants, device_key) ->
        {:reply, {:error, :participant_exists}, state}

      map_size(state.participants) >= @max_participants ->
        {:reply, {:error, :room_capacity}, state}

      not valid_outbound_tracks?(outbound_tracks, device_key, state.participants, state.members) ->
        {:reply, {:error, :invalid_outbound_tracks}, state}

      true ->
        monitor = Process.monitor(peer_connection)

        participant = %{
          peer_connection: peer_connection,
          monitor: monitor,
          inbound_tracks: %{},
          outbound_tracks: outbound_tracks,
          data_channel_ref: nil
        }

        {:reply, :ok, put_in(state.participants[device_key], participant)}
    end
  end

  def handle_call({:remove_participant, device_key}, _from, state) do
    if Map.has_key?(state.participants, device_key) do
      {:reply, :ok, drop_participant(state, device_key)}
    else
      {:reply, {:error, :unknown_participant}, state}
    end
  end

  def handle_call({:set_outbound_track, subscriber_key, source_key, kind, track_id}, _from, state)
      when kind in @track_kinds and is_integer(track_id) and track_id >= 0 do
    with {:ok, _subscriber} <- Map.fetch(state.participants, subscriber_key),
         {:ok, _source} <- Map.fetch(state.participants, source_key),
         false <- subscriber_key == source_key do
      updated =
        update_in(state.participants[subscriber_key].outbound_tracks, fn routes ->
          Map.update(routes, source_key, %{kind => track_id}, &Map.put(&1, kind, track_id))
        end)

      {:reply, :ok, updated}
    else
      _ -> {:reply, {:error, :invalid_outbound_track}, state}
    end
  end

  def handle_call({:set_outbound_track, _subscriber, _source, _kind, _track_id}, _from, state),
    do: {:reply, {:error, :invalid_outbound_track}, state}

  def handle_call({:register_source_track, device_key, kind, track_id}, _from, state) do
    case Map.fetch(state.participants, device_key) do
      {:ok, _participant} when kind in @track_kinds and is_integer(track_id) and track_id >= 0 ->
        next = put_in(state.participants[device_key].inbound_tracks[kind], track_id)
        {:reply, :ok, next}

      {:ok, _participant} ->
        {:reply, {:error, :invalid_source_track}, state}

      :error ->
        {:reply, {:error, :unknown_participant}, state}
    end
  end

  def handle_call({:register_data_channel, device_key, channel_ref}, _from, state) do
    case Map.fetch(state.participants, device_key) do
      {:ok, _participant} ->
        {:reply, :ok, put_in(state.participants[device_key].data_channel_ref, channel_ref)}

      :error ->
        {:reply, {:error, :unknown_participant}, state}
    end
  end

  def handle_call({:unregister_data_channel, device_key, channel_ref}, _from, state) do
    case Map.fetch(state.participants, device_key) do
      {:ok, %{data_channel_ref: ^channel_ref}} ->
        {:reply, :ok, put_in(state.participants[device_key].data_channel_ref, nil)}

      {:ok, _participant} ->
        {:reply, {:error, :unknown_data_channel}, state}

      :error ->
        {:reply, {:error, :unknown_participant}, state}
    end
  end

  def handle_call({:forward_data, device_key, channel_ref, data}, _from, state) do
    case Map.fetch(state.participants, device_key) do
      {:ok, %{data_channel_ref: ^channel_ref}} ->
        Enum.each(state.participants, fn
          {^device_key, _participant} ->
            :ok

          {_subscriber_key, %{data_channel_ref: nil}} ->
            :ok

          {_subscriber_key, subscriber} ->
            case Process.info(subscriber.peer_connection, :message_queue_len) do
              {:message_queue_len, queue_length} when queue_length < @max_peer_queue_length ->
                PeerConnection.send_data(
                  subscriber.peer_connection,
                  subscriber.data_channel_ref,
                  data,
                  :binary
                )

              _ ->
                :ok
            end
        end)

        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :unknown_data_channel}, state}
    end
  end

  @impl true
  def handle_call({:forward, device_key, kind, source_track_id, packet}, _from, state)
      when kind in @track_kinds do
    case Map.fetch(state.participants, device_key) do
      {:ok, %{inbound_tracks: %{^kind => ^source_track_id}}} ->
        Enum.each(state.participants, fn
          {^device_key, _participant} ->
            :ok

          {_subscriber_key, subscriber} ->
            case get_in(subscriber.outbound_tracks, [device_key, kind]) do
              track_id when is_integer(track_id) ->
                case Process.info(subscriber.peer_connection, :message_queue_len) do
                  {:message_queue_len, queue_length} when queue_length < @max_peer_queue_length ->
                    PeerConnection.send_rtp(subscriber.peer_connection, track_id, packet)

                  _ ->
                    :ok
                end

              _ ->
                :ok
            end
        end)

        {:reply, :ok, state}

      _ ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _peer_connection, _reason}, state) do
    case Enum.find(state.participants, fn {_key, participant} ->
           participant.monitor == monitor
         end) do
      {device_key, _participant} -> {:noreply, drop_participant(state, device_key)}
      nil -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp valid_device_key?(key), do: is_binary(key) and byte_size(key) == 32

  defp drop_participant(state, device_key) do
    participant = Map.fetch!(state.participants, device_key)
    Process.demonitor(participant.monitor, [:flush])

    participants =
      state.participants
      |> Map.delete(device_key)
      |> Map.new(fn {key, remaining} ->
        {key, %{remaining | outbound_tracks: Map.delete(remaining.outbound_tracks, device_key)}}
      end)

    %{state | participants: participants}
  end

  defp valid_roster?(members) when is_list(members) and length(members) in 2..256 do
    Enum.all?(members, &valid_device_key?/1) and length(Enum.uniq(members)) == length(members)
  end

  defp valid_roster?(_members), do: false

  defp valid_outbound_tracks?(tracks, local_key, participants, members) when is_map(tracks) do
    expected_sources =
      if members,
        do: MapSet.delete(members, local_key),
        else: Map.keys(participants) |> MapSet.new()

    supplied_sources = MapSet.new(Map.keys(tracks))

    valid_device_key?(local_key) and MapSet.subset?(supplied_sources, expected_sources) and
      (is_list(members) or supplied_sources == expected_sources) and
      Enum.all?(tracks, fn {source_key, media_tracks} ->
        valid_device_key?(source_key) and is_map(media_tracks) and
          Enum.all?(Map.to_list(media_tracks), fn
            {kind, track_id} when kind in @track_kinds -> is_integer(track_id) and track_id >= 0
            _ -> false
          end) and map_size(media_tracks) > 0
      end)
  end

  defp valid_outbound_tracks?(_tracks, _local_key, _participants, _members), do: false
end
