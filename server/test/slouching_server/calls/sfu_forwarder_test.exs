defmodule SlouchingServer.Calls.SfuForwarderTest do
  use ExUnit.Case, async: true

  alias SlouchingServer.Calls.SfuForwarder

  defmodule CapturePeer do
    use GenServer

    def start_link(owner), do: GenServer.start_link(__MODULE__, owner)

    @impl true
    def init(owner), do: {:ok, owner}

    @impl true
    def handle_cast({:send_rtp, track_id, packet, _opts}, owner) do
      send(owner, {:forwarded_rtp, track_id, packet})
      {:noreply, owner}
    end

    def handle_cast(_message, owner), do: {:noreply, owner}
  end

  test "forwards opaque RTP only to negotiated subscribers of that source" do
    {:ok, room} = SfuForwarder.start_link([])
    source_key = :binary.copy(<<1>>, 32)
    first_subscriber_key = :binary.copy(<<2>>, 32)
    second_subscriber_key = :binary.copy(<<3>>, 32)
    {:ok, source_pc} = CapturePeer.start_link(self())
    {:ok, first_subscriber_pc} = CapturePeer.start_link(self())
    {:ok, second_subscriber_pc} = CapturePeer.start_link(self())

    assert :ok = SfuForwarder.add_participant(room, source_key, source_pc, %{})

    source_routes = %{audio: 41, video: 42}

    assert :ok =
             SfuForwarder.add_participant(
               room,
               first_subscriber_key,
               first_subscriber_pc,
               %{source_key => source_routes}
             )

    assert :ok =
             SfuForwarder.add_participant(
               room,
               second_subscriber_key,
               second_subscriber_pc,
               %{
                 source_key => %{audio: 51, video: 52},
                 first_subscriber_key => %{audio: 53, video: 54}
               }
             )

    assert :ok = SfuForwarder.register_source_track(room, source_key, :audio, 11)

    encrypted_payload = <<0x53, 0x46, 0x52, 0x41, 0x4D, 0x45, 0, 255, 99>>
    packet = ExRTP.Packet.new(encrypted_payload)

    assert :ok = SfuForwarder.forward(room, source_key, :audio, 11, packet)

    assert_receive {:forwarded_rtp, 41, ^packet}
    assert_receive {:forwarded_rtp, 51, ^packet}
    refute_receive {:forwarded_rtp, _track_id, _packet}

    assert :ok =
             SfuForwarder.set_outbound_track(
               room,
               first_subscriber_key,
               second_subscriber_key,
               :audio,
               63
             )

    assert :ok = SfuForwarder.register_source_track(room, second_subscriber_key, :audio, 21)
    second_packet = ExRTP.Packet.new(<<0x53, 0x46, 0x52, 0x41, 0x4D, 0x45, 1, 2>>)
    assert :ok = SfuForwarder.forward(room, second_subscriber_key, :audio, 21, second_packet)
    assert_receive {:forwarded_rtp, 63, ^second_packet}

    assert :ok = SfuForwarder.remove_participant(room, first_subscriber_key)
    assert :ok = SfuForwarder.forward(room, second_subscriber_key, :audio, 21, second_packet)
    refute_receive {:forwarded_rtp, _track_id, _packet}
  end

  test "ignores unknown and unregistered inbound track IDs" do
    {:ok, room} = SfuForwarder.start_link([])
    source_key = :binary.copy(<<4>>, 32)
    subscriber_key = :binary.copy(<<5>>, 32)
    {:ok, source_pc} = CapturePeer.start_link(self())
    {:ok, subscriber_pc} = CapturePeer.start_link(self())

    assert :ok = SfuForwarder.add_participant(room, source_key, source_pc, %{})

    assert :ok =
             SfuForwarder.add_participant(
               room,
               subscriber_key,
               subscriber_pc,
               %{source_key => %{audio: 1, video: 2}}
             )

    packet = ExRTP.Packet.new(<<1, 2, 3>>)
    assert :ok = SfuForwarder.forward(room, source_key, :audio, 99, packet)
    refute_receive {:forwarded_rtp, _track_id, _packet}

    assert {:error, :invalid_source_track} =
             SfuForwarder.register_source_track(room, source_key, :data, 99)
  end

  test "rejects a participant that supplies tracks for an unjoined source" do
    {:ok, room} = SfuForwarder.start_link([])
    participant_key = :binary.copy(<<6>>, 32)
    unknown_source = :binary.copy(<<7>>, 32)
    {:ok, pc} = CapturePeer.start_link(self())

    assert {:error, :invalid_outbound_tracks} =
             SfuForwarder.add_participant(
               room,
               participant_key,
               pc,
               %{unknown_source => %{audio: 1, video: 2}}
             )
  end

  test "adds a negotiated source track when a participant joins later" do
    {:ok, room} = SfuForwarder.start_link([])
    source_key = :binary.copy(<<9>>, 32)
    subscriber_key = :binary.copy(<<10>>, 32)
    {:ok, source_pc} = CapturePeer.start_link(self())
    {:ok, subscriber_pc} = CapturePeer.start_link(self())
    assert :ok = SfuForwarder.add_participant(room, source_key, source_pc, %{})

    assert :ok =
             SfuForwarder.add_participant(room, subscriber_key, subscriber_pc, %{
               source_key => %{audio: 1, video: 2}
             })

    assert :ok = SfuForwarder.set_outbound_track(room, subscriber_key, source_key, :audio, 3)
    assert :ok = SfuForwarder.register_source_track(room, source_key, :audio, 4)
    packet = ExRTP.Packet.new(<<0x53, 0x46, 0x52, 0x41, 0x4D, 0x45, 7>>)
    assert :ok = SfuForwarder.forward(room, source_key, :audio, 4, packet)
    assert_receive {:forwarded_rtp, 3, ^packet}
  end

  test "removes a participant when its peer connection exits" do
    {:ok, room} = SfuForwarder.start_link([])
    device_key = :binary.copy(<<8>>, 32)
    {:ok, pc} = CapturePeer.start_link(self())
    assert :ok = SfuForwarder.add_participant(room, device_key, pc, %{})

    GenServer.stop(pc)

    assert eventually(fn ->
             SfuForwarder.remove_participant(room, device_key) == {:error, :unknown_participant}
           end)
  end

  test "drops media for a peer connection with an overloaded mailbox" do
    {:ok, room} = SfuForwarder.start_link([])
    source_key = :binary.copy(<<11>>, 32)
    subscriber_key = :binary.copy(<<12>>, 32)
    {:ok, source_pc} = CapturePeer.start_link(self())
    {:ok, subscriber_pc} = CapturePeer.start_link(self())
    assert :ok = SfuForwarder.add_participant(room, source_key, source_pc, %{})

    assert :ok =
             SfuForwarder.add_participant(room, subscriber_key, subscriber_pc, %{
               source_key => %{audio: 1, video: 2}
             })

    assert :ok = SfuForwarder.register_source_track(room, source_key, :audio, 3)
    :ok = :sys.suspend(subscriber_pc)
    Enum.each(1..100, fn _ -> GenServer.cast(subscriber_pc, :load) end)
    assert {:message_queue_len, 100} = Process.info(subscriber_pc, :message_queue_len)

    packet = ExRTP.Packet.new(<<0x53, 0x46, 0x52, 0x41, 0x4D, 0x45, 8>>)
    assert :ok = SfuForwarder.forward(room, source_key, :audio, 3, packet)
    refute_receive {:forwarded_rtp, _track_id, _packet}
    assert :ok = :sys.resume(subscriber_pc)
  end

  defp eventually(fun, attempts \\ 20)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(5)
      eventually(fun, attempts - 1)
    end
  end
end
