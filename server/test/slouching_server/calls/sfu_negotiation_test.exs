defmodule SlouchingServer.Calls.SfuNegotiationTest do
  use ExUnit.Case, async: true

  alias ExWebRTC.{MediaStreamTrack, PeerConnection, SessionDescription}
  alias SlouchingServer.Calls.SfuNegotiation

  test "answers one microphone and two MLS-authorized remote audio sections" do
    with_peer_connections(fn client, server ->
      assert {:ok, _microphone} =
               PeerConnection.add_track(client, MediaStreamTrack.new(:audio))

      assert {:ok, _first_remote} =
               PeerConnection.add_transceiver(client, :audio, direction: :recvonly)

      assert {:ok, _second_remote} =
               PeerConnection.add_transceiver(client, :audio, direction: :recvonly)

      assert {:ok, _channel} = PeerConnection.create_data_channel(client, "call-chat")
      {:ok, offer} = PeerConnection.create_offer(client)
      assert :ok = PeerConnection.set_local_description(client, offer)

      first_source = :binary.copy(<<1>>, 32)
      second_source = :binary.copy(<<2>>, 32)

      assert {:ok, answer} =
               SfuNegotiation.answer_offer(server, offer.sdp, [first_source, second_source])

      assert %{^first_source => first_track, ^second_source => second_track} =
               answer.outbound_track_ids

      assert is_integer(first_track)
      assert is_integer(second_track)
      assert first_track != second_track

      assert :ok =
               PeerConnection.set_remote_description(
                 client,
                 %SessionDescription{type: :answer, sdp: answer.sdp}
               )

      assert Enum.map(PeerConnection.get_transceivers(server), & &1.direction) ==
               [:recvonly, :sendonly, :sendonly]
    end)
  end

  test "rejects an offer with the wrong number or direction of remote audio sections" do
    with_peer_connections(fn client, server ->
      assert {:ok, _microphone} =
               PeerConnection.add_track(client, MediaStreamTrack.new(:audio))

      {:ok, offer} = PeerConnection.create_offer(client)
      assert :ok = PeerConnection.set_local_description(client, offer)
      sources = [:binary.copy(<<3>>, 32)]

      assert {:error, :audio_section_count_mismatch} =
               SfuNegotiation.answer_offer(server, offer.sdp, sources)
    end)
  end

  test "rejects malformed SDP and invalid or duplicate source keys" do
    with_peer_connections(fn _client, server ->
      valid_source = :binary.copy(<<4>>, 32)

      assert {:error, :invalid_sdp_size} =
               SfuNegotiation.answer_offer(server, String.duplicate("x", 128 * 1024 + 1), [
                 valid_source
               ])

      assert {:error, :invalid_remote_source_keys} =
               SfuNegotiation.answer_offer(server, "v=0", [valid_source, valid_source])

      assert {:error, :invalid_remote_source_count} =
               SfuNegotiation.answer_offer(server, "v=0", [])
    end)
  end

  defp with_peer_connections(fun) do
    {:ok, client} = PeerConnection.start_link(ice_servers: [])
    {:ok, server} = PeerConnection.start_link(ice_servers: [])

    try do
      fun.(client, server)
    after
      if Process.alive?(client), do: PeerConnection.close(client)
      if Process.alive?(server), do: PeerConnection.close(server)
    end
  end
end
