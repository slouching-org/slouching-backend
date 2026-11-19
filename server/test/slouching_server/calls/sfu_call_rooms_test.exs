defmodule SlouchingServer.Calls.SfuCallRoomsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ExWebRTC.{MediaStreamTrack, PeerConnection}
  alias SlouchingServer.Calls.{SfuCallRooms, SfuForwarder}

  test "each admitted device must sign the same canonical call roster" do
    {first_public, first_private} = :crypto.generate_key(:eddsa, :ed25519)
    {second_public, second_private} = :crypto.generate_key(:eddsa, :ed25519)
    call_id = :crypto.strong_rand_bytes(16)
    group_id = :crypto.strong_rand_bytes(16)
    roster = [first_public, second_public]
    {:ok, rooms} = SfuCallRooms.start_link([])

    first_signature = sign(call_id, group_id, 3, roster, first_private)
    second_signature = sign(call_id, group_id, 3, Enum.reverse(roster), second_private)

    assert :ok =
             SfuCallRooms.join(
               rooms,
               call_id,
               group_id,
               3,
               roster,
               first_public,
               first_signature,
               self()
             )

    assert :ok =
             SfuCallRooms.join(
               rooms,
               call_id,
               group_id,
               3,
               Enum.reverse(roster),
               second_public,
               second_signature,
               self()
             )

    assert {:error, :participant_already_joined} =
             SfuCallRooms.join(
               rooms,
               call_id,
               group_id,
               3,
               roster,
               first_public,
               first_signature,
               self()
             )

    assert :ok = SfuCallRooms.leave(rooms, call_id, first_public)
    assert :ok = SfuCallRooms.leave(rooms, call_id, second_public)
    GenServer.stop(rooms)
  end

  test "rejects a forged roster signature and a conflicting roster for one call ID" do
    {first_public, first_private} = :crypto.generate_key(:eddsa, :ed25519)
    {second_public, _second_private} = :crypto.generate_key(:eddsa, :ed25519)
    {third_public, third_private} = :crypto.generate_key(:eddsa, :ed25519)
    call_id = :crypto.strong_rand_bytes(16)
    group_id = :crypto.strong_rand_bytes(16)
    roster = [first_public, second_public]
    {:ok, rooms} = SfuCallRooms.start_link([])
    signature = sign(call_id, group_id, 1, roster, first_private)

    assert {:error, :invalid_signature} =
             SfuCallRooms.join(
               rooms,
               call_id,
               group_id,
               1,
               roster,
               first_public,
               sign(call_id, group_id, 2, roster, first_private),
               self()
             )

    assert :ok =
             SfuCallRooms.join(
               rooms,
               call_id,
               group_id,
               1,
               roster,
               first_public,
               signature,
               self()
             )

    conflicting_roster = [first_public, third_public]

    assert {:error, :call_roster_mismatch} =
             SfuCallRooms.join(
               rooms,
               call_id,
               group_id,
               1,
               conflicting_roster,
               first_public,
               sign(call_id, group_id, 1, conflicting_roster, first_private),
               self()
             )

    assert {:error, :device_not_in_roster} =
             SfuCallRooms.join(
               rooms,
               call_id,
               group_id,
               1,
               conflicting_roster,
               second_public,
               sign(call_id, group_id, 1, conflicting_roster, third_private),
               self()
             )

    SfuCallRooms.leave(rooms, call_id, first_public)
    GenServer.stop(rooms)
  end

  test "isolates a peer SDP crash so other active call rooms stay alive" do
    {:ok, rooms} = SfuCallRooms.start_link([])
    Process.unlink(rooms)

    {a1_pub, a1_priv} = :crypto.generate_key(:eddsa, :ed25519)
    {a2_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
    call_1 = :crypto.strong_rand_bytes(16)
    group_1 = :crypto.strong_rand_bytes(16)
    roster_1 = [a1_pub, a2_pub]

    assert :ok =
             SfuCallRooms.join(
               rooms,
               call_1,
               group_1,
               1,
               roster_1,
               a1_pub,
               sign(call_1, group_1, 1, roster_1, a1_priv),
               self()
             )

    room1 = :sys.get_state(rooms).rooms[call_1]
    room1_forwarder = room1.forwarder
    room1_peer = room1.participants[a1_pub].peer

    {b1_pub, b1_priv} = :crypto.generate_key(:eddsa, :ed25519)
    {b2_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
    call_2 = :crypto.strong_rand_bytes(16)
    group_2 = :crypto.strong_rand_bytes(16)
    roster_2 = [b1_pub, b2_pub]

    assert :ok =
             SfuCallRooms.join(
               rooms,
               call_2,
               group_2,
               1,
               roster_2,
               b1_pub,
               sign(call_2, group_2, 1, roster_2, b1_priv),
               self()
             )

    room2 = :sys.get_state(rooms).rooms[call_2]
    room2_forwarder = room2.forwarder
    room2_forwarder_monitor = Process.monitor(room2_forwarder)

    valid_sdp = build_valid_two_party_offer_sdp()

    extmaps =
      Enum.map_join(1..14, "\r\n", fn id ->
        "a=extmap:#{id} urn:ietf:params:rtp-hdrext:custom-#{id}"
      end)

    crashing_sdp =
      valid_sdp
      |> String.split("\r\n")
      |> Enum.reject(&String.starts_with?(&1, "a=extmap:"))
      |> Enum.join("\r\n")
      |> String.replace("a=rtcp-mux", "a=rtcp-mux\r\n" <> extmaps, global: false)

    capture_log(fn ->
      assert {:error, :invalid_sdp} =
               SfuCallRooms.answer_offer(rooms, call_2, b1_pub, crashing_sdp)
    end)

    assert_receive {:DOWN, ^room2_forwarder_monitor, :process, ^room2_forwarder, _reason}, 1_000
    assert Process.alive?(rooms)
    assert Process.alive?(room1_forwarder)
    assert Process.alive?(room1_peer)
    refute Map.has_key?(:sys.get_state(rooms).rooms, call_2)
    assert {:ok, %{sdp: answer_sdp}} = SfuCallRooms.answer_offer(rooms, call_1, a1_pub, valid_sdp)
    assert is_binary(answer_sdp) and byte_size(answer_sdp) > 0

    # Isolation must work in both directions: a PC crash cannot kill its room,
    # and a killed peer must not orphan the PC/ICE/DTLS it owns.
    pc = :sys.get_state(room1_peer).peer_connection
    pc_state = :sys.get_state(pc)
    descendants = [pc, pc_state.ice_pid, pc_state.dtls_transport]
    monitors = Enum.map(descendants, &{&1, Process.monitor(&1)})
    Process.exit(room1_peer, :kill)

    try do
      for {pid, ref} <- monitors do
        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      end
    after
      if Process.alive?(pc), do: PeerConnection.stop(pc)
      GenServer.stop(rooms)
    end
  end

  test "cleans up new forwarder and keeps existing rooms when participant startup fails" do
    {:ok, rooms} = SfuCallRooms.start_link([])
    Process.unlink(rooms)

    {a1_pub, a1_priv} = :crypto.generate_key(:eddsa, :ed25519)
    {a2_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
    call_1 = :crypto.strong_rand_bytes(16)
    group_1 = :crypto.strong_rand_bytes(16)
    roster_1 = [a1_pub, a2_pub]

    assert :ok =
             SfuCallRooms.join(
               rooms,
               call_1,
               group_1,
               1,
               roster_1,
               a1_pub,
               sign(call_1, group_1, 1, roster_1, a1_priv),
               self()
             )

    room1 = :sys.get_state(rooms).rooms[call_1]
    room1_forwarder = room1.forwarder
    room1_peer = room1.participants[a1_pub].peer
    before_forwarders = running_forwarders()

    {b1_pub, b1_priv} = :crypto.generate_key(:eddsa, :ed25519)
    {b2_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
    call_2 = :crypto.strong_rand_bytes(16)
    group_2 = :crypto.strong_rand_bytes(16)
    roster_2 = [b1_pub, b2_pub]

    System.put_env("SLOUCHING_SFU_PUBLIC_IP", "invalid-ip")

    try do
      assert {:error, :invalid_sfu_public_ip} =
               SfuCallRooms.join(
                 rooms,
                 call_2,
                 group_2,
                 1,
                 roster_2,
                 b1_pub,
                 sign(call_2, group_2, 1, roster_2, b1_priv),
                 self()
               )
    after
      System.delete_env("SLOUCHING_SFU_PUBLIC_IP")
    end

    assert Process.alive?(rooms)
    assert Process.alive?(room1_forwarder)
    assert Process.alive?(room1_peer)

    for forwarder <- MapSet.difference(running_forwarders(), before_forwarders) do
      monitor = Process.monitor(forwarder)
      assert_receive {:DOWN, ^monitor, :process, ^forwarder, _}, 1_000
    end

    assert MapSet.subset?(running_forwarders(), before_forwarders)

    GenServer.stop(rooms)
  end

  test "stalled peer offer in one room does not block signaling in another room" do
    {:ok, rooms} = SfuCallRooms.start_link([])

    {a1_pub, a1_priv} = :crypto.generate_key(:eddsa, :ed25519)
    {a2_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
    call_1 = :crypto.strong_rand_bytes(16)
    group_1 = :crypto.strong_rand_bytes(16)
    roster_1 = [a1_pub, a2_pub]

    {b1_pub, b1_priv} = :crypto.generate_key(:eddsa, :ed25519)
    {b2_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
    call_2 = :crypto.strong_rand_bytes(16)
    group_2 = :crypto.strong_rand_bytes(16)
    roster_2 = [b1_pub, b2_pub]

    assert :ok =
             SfuCallRooms.join(
               rooms,
               call_2,
               group_2,
               1,
               roster_2,
               b1_pub,
               sign(call_2, group_2, 1, roster_2, b1_priv),
               self()
             )

    room2_peer = :sys.get_state(rooms).rooms[call_2].participants[b1_pub].peer
    valid_sdp = build_valid_two_party_offer_sdp()

    :sys.suspend(room2_peer)

    stalled_offer =
      Task.async(fn ->
        SfuCallRooms.answer_offer(rooms, call_2, b1_pub, valid_sdp)
      end)

    try do
      wait_until_call_queued(room2_peer)

      caller = self()

      other_room_join =
        Task.async(fn ->
          result =
            SfuCallRooms.join(
              rooms,
              call_1,
              group_1,
              1,
              roster_1,
              a1_pub,
              sign(call_1, group_1, 1, roster_1, a1_priv),
              caller
            )

          {result, SfuCallRooms.answer_offer(rooms, call_1, a1_pub, valid_sdp)}
        end)

      assert {:ok, {:ok, {:ok, %{sdp: answer_sdp}}}} = Task.yield(other_room_join, 500)
      assert is_binary(answer_sdp) and byte_size(answer_sdp) > 0
    after
      :sys.resume(room2_peer)
    end

    assert {:ok, %{sdp: _}} = Task.await(stalled_offer, 5_000)
    GenServer.stop(rooms)
  end

  for teardown <- [:leave, :owner_exit, :forwarder_exit] do
    @teardown teardown
    test "#{teardown} of a stalled peer leaves other rooms and admission responsive" do
      {:ok, rooms} = SfuCallRooms.start_link([])

      owner =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      {call_id, key, peer, pc} = join_review_participant(rooms, owner)
      forwarder = :sys.get_state(rooms).rooms[call_id].forwarder
      {other_call, other_key, _other_peer, _other_pc} = join_review_participant(rooms)
      sdp = build_valid_two_party_offer_sdp()
      pc_state = :sys.get_state(pc)

      monitors =
        Enum.map(
          [peer, pc, pc_state.ice_pid, pc_state.dtls_transport],
          &{&1, Process.monitor(&1)}
        )

      :sys.suspend(pc)
      offer = Task.async(fn -> SfuCallRooms.answer_offer(rooms, call_id, key, sdp) end)
      wait_until_call_queued(pc)
      :erlang.trace(rooms, true, [:receive])

      leave =
        case @teardown do
          :leave ->
            Task.async(fn -> SfuCallRooms.leave(rooms, call_id, key) end)

          :owner_exit ->
            Process.exit(owner, :kill)
            nil

          :forwarder_exit ->
            Process.exit(forwarder, :kill)
            nil
        end

      try do
        case @teardown do
          :leave ->
            assert_receive {:trace, ^rooms, :receive,
                            {:"$gen_call", _, {:leave, ^call_id, ^key}}},
                           1_000

          :owner_exit ->
            assert_receive {:trace, ^rooms, :receive, {:DOWN, _, :process, ^owner, _}}, 1_000

          :forwarder_exit ->
            assert_receive {:trace, ^rooms, :receive, {:DOWN, _, :process, ^forwarder, _}}, 1_000
        end

        :erlang.trace(rooms, false, [:receive])
        owner = self()

        signaling =
          Task.async(fn ->
            {new_call, new_key, _, _} = join_review_participant(rooms, owner)

            {SfuCallRooms.answer_offer(rooms, other_call, other_key, sdp),
             SfuCallRooms.answer_offer(rooms, new_call, new_key, sdp)}
          end)

        assert {:ok, {{:ok, _}, {:ok, _}}} = Task.yield(signaling, 500)
        # Leave must eventually complete even though negotiation never resumes.
        if leave, do: assert(:ok = Task.await(leave, 3_000))

        for {pid, ref} <- monitors do
          assert_receive {:DOWN, ^ref, :process, ^pid, _}, 3_000
        end

        assert {:error, _} = Task.await(offer, 1_000)
      after
        if Process.alive?(pc), do: :sys.resume(pc)
        Task.shutdown(offer, :brutal_kill)
        if leave, do: Task.shutdown(leave, :brutal_kill)
        Process.exit(owner, :kill)
        GenServer.stop(rooms)
      end
    end
  end

  defp join_review_participant(rooms, owner \\ self()) do
    {key, secret} = :crypto.generate_key(:eddsa, :ed25519)
    {other, _} = :crypto.generate_key(:eddsa, :ed25519)
    call_id = :crypto.strong_rand_bytes(16)
    group = :crypto.strong_rand_bytes(16)
    roster = [key, other]

    assert :ok =
             SfuCallRooms.join(
               rooms,
               call_id,
               group,
               1,
               roster,
               key,
               sign(call_id, group, 1, roster, secret),
               owner
             )

    peer = :sys.get_state(rooms).rooms[call_id].participants[key].peer
    {call_id, key, peer, :sys.get_state(peer).peer_connection}
  end

  test "notifies the signaling owner when a participant peer exits asynchronously" do
    {:ok, rooms} = SfuCallRooms.start_link([])
    {first_pub, first_priv} = :crypto.generate_key(:eddsa, :ed25519)
    {second_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
    call_id = :crypto.strong_rand_bytes(16)
    group_id = :crypto.strong_rand_bytes(16)
    roster = [first_pub, second_pub]

    assert :ok =
             SfuCallRooms.join(
               rooms,
               call_id,
               group_id,
               1,
               roster,
               first_pub,
               sign(call_id, group_id, 1, roster, first_priv),
               self()
             )

    peer = :sys.get_state(rooms).rooms[call_id].participants[first_pub].peer
    GenServer.stop(peer, {:shutdown, {:peer_connection, :failed}})

    assert_receive {:sfu_call_ended, ^call_id, ^first_pub,
                    {:shutdown, {:peer_connection, :failed}}},
                   500

    GenServer.stop(rooms)
  end

  defp wait_until_call_queued(peer) do
    result =
      Enum.reduce_while(1..200, :waiting, fn _, :waiting ->
        {:messages, messages} = Process.info(peer, :messages)

        if Enum.any?(messages, &match?({:"$gen_call", _, _}, &1)) do
          {:halt, :queued}
        else
          Process.sleep(2)
          {:cont, :waiting}
        end
      end)

    assert result == :queued
  end

  defp build_valid_two_party_offer_sdp do
    {:ok, client} = PeerConnection.start_link(ice_servers: [])

    try do
      {:ok, _} = PeerConnection.add_track(client, MediaStreamTrack.new(:audio))
      {:ok, _} = PeerConnection.add_transceiver(client, :audio, direction: :recvonly)
      {:ok, offer} = PeerConnection.create_offer(client)
      offer.sdp
    after
      if Process.alive?(client), do: PeerConnection.stop(client)
    end
  end

  defp running_forwarders do
    Process.list()
    |> Enum.filter(fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} -> dict[:"$initial_call"] == {SfuForwarder, :init, 1}
        _ -> false
      end
    end)
    |> MapSet.new()
  end

  defp sign(call_id, group_id, epoch, roster, private_key) do
    payload = SfuCallRooms.roster_payload(call_id, group_id, epoch, roster)
    :crypto.sign(:eddsa, :none, payload, [private_key, :ed25519])
  end
end
