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
end
