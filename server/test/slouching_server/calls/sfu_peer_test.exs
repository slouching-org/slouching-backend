defmodule SlouchingServer.Calls.SfuPeerTest do
  use ExUnit.Case, async: true

  alias ExWebRTC.{MediaStreamTrack, PeerConnection, SessionDescription}
  alias SlouchingServer.Calls.{SfuForwarder, SfuPeer}

  test "answers a call member offer and registers only its authorized roster routes" do
    local_key = :binary.copy(<<0x11>>, 32)
    remote_key = :binary.copy(<<0x22>>, 32)
    {:ok, forwarder} = SfuForwarder.start_link(members: [local_key, remote_key])
    {:ok, client} = PeerConnection.start_link(ice_servers: [])

    {:ok, peer} =
      SfuPeer.start_link(
        device_key: local_key,
        remote_source_keys: [remote_key],
        forwarder: forwarder,
        signaling_owner: self()
      )

    try do
      assert {:ok, _microphone} = PeerConnection.add_track(client, MediaStreamTrack.new(:audio))

      assert {:ok, _remote_audio} =
               PeerConnection.add_transceiver(client, :audio, direction: :recvonly)

      assert {:ok, _channel} =
               PeerConnection.create_data_channel(client, "slouching-call-v1", ordered: :ordered)

      assert {:ok, offer} = PeerConnection.create_offer(client)
      assert :ok = PeerConnection.set_local_description(client, offer)
      assert {:ok, answer} = SfuPeer.answer_offer(peer, offer.sdp)
      assert %{^remote_key => track_id} = answer.outbound_track_ids
      assert is_integer(track_id)

      assert :ok =
               PeerConnection.set_remote_description(
                 client,
                 %SessionDescription{type: :answer, sdp: answer.sdp}
               )

      assert {:error, :offer_already_applied} = SfuPeer.answer_offer(peer, offer.sdp)
    after
      if Process.alive?(peer), do: GenServer.stop(peer)
      if Process.alive?(client), do: PeerConnection.stop(client)
      if Process.alive?(forwarder), do: GenServer.stop(forwarder)
    end
  end

  test "the room roster rejects a peer that was not admitted to the call" do
    admitted_key = :binary.copy(<<0x33>>, 32)
    rejected_key = :binary.copy(<<0x44>>, 32)

    {:ok, forwarder} =
      SfuForwarder.start_link(members: [admitted_key, :binary.copy(<<0x55>>, 32)])

    {:ok, client} = PeerConnection.start_link(ice_servers: [])

    assert {:error, :unauthorized_member} =
             SfuForwarder.add_participant(forwarder, rejected_key, client, %{})

    if Process.alive?(client), do: PeerConnection.stop(client)
    if Process.alive?(forwarder), do: GenServer.stop(forwarder)
  end

  test "stops an idle joined peer when no initial SDP offer arrives before the deadline" do
    local_key = :binary.copy(<<0x66>>, 32)
    remote_key = :binary.copy(<<0x77>>, 32)
    {:ok, forwarder} = SfuForwarder.start_link(members: [local_key, remote_key])

    try do
      {:ok, idle_peer} =
        start_supervised(
          {SfuPeer,
           device_key: local_key,
           remote_source_keys: [remote_key],
           forwarder: forwarder,
           signaling_owner: self(),
           initial_offer_timeout_ms: 1_000}
        )

      idle_pc = :sys.get_state(idle_peer).peer_connection
      peer_ref = Process.monitor(idle_peer)
      pc_ref = Process.monitor(idle_pc)

      assert_receive {:DOWN, ^peer_ref, :process, ^idle_peer, {:shutdown, :offer_timeout}}, 2_000
      assert_receive {:DOWN, ^pc_ref, :process, ^idle_pc, _reason}, 300

      {:ok, client} = PeerConnection.start_link(ice_servers: [])

      {:ok, _} = PeerConnection.add_track(client, MediaStreamTrack.new(:audio))
      {:ok, _} = PeerConnection.add_transceiver(client, :audio, direction: :recvonly)
      {:ok, offer} = PeerConnection.create_offer(client)

      {:ok, active_peer} =
        SfuPeer.start_link(
          device_key: local_key,
          remote_source_keys: [remote_key],
          forwarder: forwarder,
          signaling_owner: self()
        )

      try do
        offer_timer = :sys.get_state(active_peer).offer_timer
        assert {:ok, %{sdp: _}} = SfuPeer.answer_offer(active_peer, offer.sdp)

        assert Process.read_timer(offer_timer) == false
        # A timeout already queued before cancellation must not stop an active peer.
        send(active_peer, :initial_offer_timeout)
        assert %{active?: true, offer_timer: nil} = :sys.get_state(active_peer)
      after
        if Process.alive?(active_peer), do: GenServer.stop(active_peer)
        if Process.alive?(client), do: PeerConnection.stop(client)
      end
    after
      if Process.alive?(forwarder), do: GenServer.stop(forwarder)
    end
  end
end
