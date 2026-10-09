defmodule SlouchingServer.Directory.DeviceTest do
  use ExUnit.Case, async: true

  alias SlouchingServer.Directory.Device

  test "requires exactly 32 bytes for a candidate Ed25519 public key" do
    assert Device.enrollment_changeset(%Device{}, %{
             signing_public_key: :crypto.strong_rand_bytes(32)
           }).valid?

    refute Device.enrollment_changeset(%Device{}, %{signing_public_key: <<1>>}).valid?
    refute Device.enrollment_changeset(%Device{}, %{}).valid?
  end
end
