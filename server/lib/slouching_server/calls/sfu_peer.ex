defmodule SlouchingServer.Calls.SfuPeer do
  @moduledoc """
  Owns one ExWebRTC PeerConnection for a device already admitted to an MLS
  call. The coordinator must validate `remote_source_keys` against that call's
  current authenticated MLS state before starting this process.
  """

  use GenServer, restart: :temporary

  alias ExWebRTC.{DataChannel, ICECandidate, PeerConnection}
  alias SlouchingServer.Calls.{SfuForwarder, SfuNegotiation}

  @offer_timeout 15_000
  @initial_offer_timeout_ms 15_000
  @max_ice_port_span 4_095

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def answer_offer(peer, sdp), do: GenServer.call(peer, {:answer_offer, sdp}, @offer_timeout)

  def add_ice_candidate(peer, %ICECandidate{} = candidate) do
    GenServer.call(peer, {:add_ice_candidate, candidate})
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, device_key} <- fetch_device_key(opts),
         {:ok, source_keys} <- fetch_source_keys(opts),
         {:ok, initial_offer_timeout_ms} <- fetch_initial_offer_timeout(opts),
         forwarder when not is_nil(forwarder) <- Keyword.get(opts, :forwarder),
         signaling_owner when is_pid(signaling_owner) <- Keyword.get(opts, :signaling_owner),
         {:ok, ice_options} <- sfu_ice_options(),
         {:ok, peer_connection} <-
           PeerConnection.start_link(
             Keyword.merge(Keyword.get(opts, :peer_connection_options, []), ice_options)
           ) do
      monitor = Process.monitor(peer_connection)
      # Keep the ownership link: trapped PC exits are handled by the monitor,
      # while a forced peer shutdown must also kill its PC and transports.
      offer_timer = Process.send_after(self(), :initial_offer_timeout, initial_offer_timeout_ms)

      {:ok,
       %{
         device_key: device_key,
         source_keys: source_keys,
         forwarder: forwarder,
         signaling_owner: signaling_owner,
         peer_connection: peer_connection,
         peer_connection_monitor: monitor,
         offer_timer: offer_timer,
         call_id: Keyword.get(opts, :call_id),
         active?: false,
         inbound_audio_track: nil,
         data_channel_ref: nil,
         data_channel_open?: false
       }}
    else
      {:error, reason} -> {:stop, reason}
      nil -> {:stop, :missing_forwarder}
      _ -> {:stop, :invalid_sfu_peer_options}
    end
  end

  @impl true
  def handle_call({:answer_offer, _sdp}, _from, %{active?: true} = state),
    do: {:reply, {:error, :offer_already_applied}, state}

  def handle_call({:answer_offer, sdp}, _from, state) do
    case safe_answer_offer(state.peer_connection, sdp, state.source_keys) do
      {:ok, negotiation} ->
        outbound_tracks =
          Map.new(negotiation.outbound_track_ids, fn {source_key, track_id} ->
            {source_key, %{audio: track_id}}
          end)

        case safe_add_participant(
               state.forwarder,
               state.device_key,
               state.peer_connection,
               outbound_tracks
             ) do
          :ok ->
            cancel_timer(state.offer_timer)
            {:reply, {:ok, negotiation}, %{state | active?: true, offer_timer: nil}}

          {:error, :forwarder_unavailable} ->
            {:stop, {:shutdown, :forwarder_unavailable}, {:error, :call_unavailable}, state}

          {:error, reason} ->
            {:reply, {:error, {:room_rejected_peer, reason}}, state}
        end

      {:peer_crashed, reason} ->
        {:stop, {:shutdown, :peer_connection_failed}, {:error, reason}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:add_ice_candidate, candidate}, _from, %{active?: true} = state) do
    try do
      {:reply, PeerConnection.add_ice_candidate(state.peer_connection, candidate), state}
    catch
      :exit, _reason ->
        {:stop, {:shutdown, :peer_connection_failed}, {:error, :invalid_ice_candidate}, state}
    end
  end

  def handle_call({:add_ice_candidate, _candidate}, _from, state),
    do: {:reply, {:error, :offer_not_applied}, state}

  @impl true
  def handle_info(
        {:ex_webrtc, peer_connection, {:ice_candidate, candidate}},
        %{peer_connection: peer_connection} = state
      ) do
    send(
      state.signaling_owner,
      {:sfu_peer_ice_candidate, state.call_id, state.device_key, candidate}
    )

    {:noreply, state}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:connection_state_change, connection_state}},
        %{peer_connection: peer_connection} = state
      ) do
    send(
      state.signaling_owner,
      {:sfu_peer_connection_state, state.call_id, state.device_key, connection_state}
    )

    if connection_state in [:failed, :closed] do
      {:stop, {:shutdown, {:peer_connection, connection_state}}, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:track, %{kind: :audio, id: track_id}}},
        %{peer_connection: peer_connection, active?: true} = state
      ) do
    case SfuForwarder.register_source_track(state.forwarder, state.device_key, :audio, track_id) do
      :ok -> {:noreply, %{state | inbound_audio_track: track_id}}
      {:error, reason} -> {:stop, {:shutdown, {:track_rejected, reason}}, state}
    end
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:rtp, track_id, _rid, packet}},
        %{peer_connection: peer_connection, active?: true, inbound_audio_track: track_id} = state
      ) do
    :ok = SfuForwarder.forward(state.forwarder, state.device_key, :audio, track_id, packet)
    {:noreply, state}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data_channel, %DataChannel{} = channel}},
        %{peer_connection: peer_connection, active?: true, data_channel_ref: nil} = state
      ) do
    if valid_call_data_channel?(channel) do
      if channel.ready_state == :open do
        case SfuForwarder.register_data_channel(state.forwarder, state.device_key, channel.ref) do
          :ok ->
            {:noreply, %{state | data_channel_ref: channel.ref, data_channel_open?: true}}

          {:error, reason} ->
            {:stop, {:shutdown, {:data_channel_rejected, reason}}, state}
        end
      else
        {:noreply, %{state | data_channel_ref: channel.ref}}
      end
    else
      PeerConnection.close_data_channel(peer_connection, channel.ref)
      {:stop, {:shutdown, :invalid_call_data_channel}, state}
    end
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data_channel, %DataChannel{ref: channel_ref}}},
        %{peer_connection: peer_connection, active?: true} = state
      ) do
    PeerConnection.close_data_channel(peer_connection, channel_ref)
    {:stop, {:shutdown, :duplicate_call_data_channel}, state}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data_channel_state_change, channel_ref, :open}},
        %{
          peer_connection: peer_connection,
          active?: true,
          data_channel_ref: channel_ref,
          data_channel_open?: false
        } = state
      ) do
    case SfuForwarder.register_data_channel(state.forwarder, state.device_key, channel_ref) do
      :ok -> {:noreply, %{state | data_channel_open?: true}}
      {:error, reason} -> {:stop, {:shutdown, {:data_channel_rejected, reason}}, state}
    end
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data_channel_state_change, channel_ref, :closed}},
        %{
          peer_connection: peer_connection,
          data_channel_ref: channel_ref,
          data_channel_open?: true
        } = state
      ) do
    :ok = SfuForwarder.unregister_data_channel(state.forwarder, state.device_key, channel_ref)
    {:noreply, %{state | data_channel_ref: nil, data_channel_open?: false}}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data, channel_ref, data}},
        %{peer_connection: peer_connection, active?: true, data_channel_ref: channel_ref} = state
      ) do
    case SfuForwarder.forward_data(state.forwarder, state.device_key, channel_ref, data) do
      :ok -> {:noreply, state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  def handle_info(:initial_offer_timeout, %{active?: false} = state) do
    {:stop, {:shutdown, :offer_timeout}, %{state | offer_timer: nil}}
  end

  def handle_info(:initial_offer_timeout, state) do
    {:noreply, %{state | offer_timer: nil}}
  end

  def handle_info(
        {:DOWN, monitor, :process, peer_connection, reason},
        %{peer_connection_monitor: monitor, peer_connection: peer_connection} = state
      ) do
    {:stop, {:shutdown, {:peer_connection_down, reason}}, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cancel_timer(state.offer_timer)

    if state.active? do
      safe_call(fn -> SfuForwarder.remove_participant(state.forwarder, state.device_key) end)
    end

    if Process.alive?(state.peer_connection) do
      safe_call(fn -> PeerConnection.stop(state.peer_connection) end)
    end

    :ok
  end

  defp safe_answer_offer(peer_connection, sdp, source_keys) do
    SfuNegotiation.answer_offer(peer_connection, sdp, source_keys)
  catch
    :exit, _reason -> {:peer_crashed, :invalid_sdp}
  end

  defp safe_add_participant(forwarder, device_key, peer_connection, outbound_tracks) do
    SfuForwarder.add_participant(forwarder, device_key, peer_connection, outbound_tracks)
  catch
    :exit, _reason -> {:error, :forwarder_unavailable}
  end

  defp safe_call(fun) do
    _ = fun.()
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp fetch_device_key(opts) do
    case Keyword.get(opts, :device_key) do
      key when is_binary(key) and byte_size(key) == 32 -> {:ok, key}
      _ -> {:error, :invalid_device_key}
    end
  end

  defp fetch_source_keys(opts) do
    keys = Keyword.get(opts, :remote_source_keys)

    if is_list(keys) and length(keys) in 1..255 and
         Enum.all?(keys, &(is_binary(&1) and byte_size(&1) == 32)) and
         length(Enum.uniq(keys)) == length(keys) do
      {:ok, keys}
    else
      {:error, :invalid_remote_source_keys}
    end
  end

  defp fetch_initial_offer_timeout(opts) do
    case Keyword.get(opts, :initial_offer_timeout_ms, @initial_offer_timeout_ms) do
      timeout when is_integer(timeout) and timeout > 0 -> {:ok, timeout}
      _ -> {:error, :invalid_initial_offer_timeout}
    end
  end

  defp cancel_timer(timer_ref) when is_reference(timer_ref) do
    _ = Process.cancel_timer(timer_ref, async: true, info: false)
    :ok
  end

  defp cancel_timer(_timer_ref), do: :ok

  defp valid_call_data_channel?(%DataChannel{
         label: "slouching-call-v1",
         ordered: :ordered,
         max_packet_life_time: nil,
         max_retransmits: nil
       }),
       do: true

  defp valid_call_data_channel?(_channel), do: false

  defp sfu_ice_options do
    public_ip = System.get_env("SLOUCHING_SFU_PUBLIC_IP")
    port_range = System.get_env("SLOUCHING_SFU_UDP_PORT_RANGE")
    ice_options(public_ip, port_range)
  end

  @doc false
  def ice_options(public_ip, port_range) do
    with {:ok, public_ip} <- parse_public_ip(public_ip),
         {:ok, port_range} <- parse_udp_port_range(port_range) do
      options =
        if port_range do
          [ice_port_range: port_range]
        else
          []
        end

      options =
        if public_ip do
          mapper = fn host_ip ->
            if tuple_size(host_ip) == tuple_size(public_ip), do: public_ip, else: nil
          end

          Keyword.put(options, :host_to_srflx_ip_mapper, mapper)
        else
          options
        end

      {:ok, options}
    end
  end

  defp parse_public_ip(nil), do: {:ok, nil}
  defp parse_public_ip(""), do: {:ok, nil}

  defp parse_public_ip(value) when is_binary(value) do
    case :inet.parse_address(String.to_charlist(String.trim(value))) do
      {:ok, address} -> {:ok, address}
      {:error, _reason} -> {:error, :invalid_sfu_public_ip}
    end
  end

  defp parse_udp_port_range(nil), do: {:ok, nil}
  defp parse_udp_port_range(""), do: {:ok, nil}

  defp parse_udp_port_range(value) when is_binary(value) do
    case String.split(String.trim(value), "-", parts: 2) do
      [first, last] ->
        with {first, ""} <- Integer.parse(first),
             {last, ""} <- Integer.parse(last),
             true <-
               first in 1..65_535 and last in first..65_535 and
                 last - first <= @max_ice_port_span do
          {:ok, first..last}
        else
          _ -> {:error, :invalid_sfu_udp_port_range}
        end

      _ ->
        {:error, :invalid_sfu_udp_port_range}
    end
  end

  defp parse_udp_port_range(_value), do: {:error, :invalid_sfu_udp_port_range}
end
