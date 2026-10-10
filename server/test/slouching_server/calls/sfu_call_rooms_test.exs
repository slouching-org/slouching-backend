defmodule SlouchingServer.Calls.SfuCallRoomsTest do
  use ExUnit.Case, async: true

  alias SlouchingServer.Calls.SfuCallRooms

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

  defp sign(call_id, group_id, epoch, roster, private_key) do
    payload = SfuCallRooms.roster_payload(call_id, group_id, epoch, roster)
    :crypto.sign(:eddsa, :none, payload, [private_key, :ed25519])
  end
end
