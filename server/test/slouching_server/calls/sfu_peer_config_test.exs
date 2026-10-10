defmodule SlouchingServer.Calls.SfuPeerConfigTest do
  use ExUnit.Case, async: true

  alias SlouchingServer.Calls.SfuPeer

  test "public IPv4 maps matching host candidates and bounds ICE UDP ports" do
    assert {:ok, options} = SfuPeer.ice_options("203.0.113.12", "50000-50100")
    assert options[:ice_port_range] == 50_000..50_100
    mapper = options[:host_to_srflx_ip_mapper]

    assert mapper.({10, 0, 0, 4}) == {203, 0, 113, 12}
    assert mapper.({0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}) == nil
  end

  test "invalid public address and oversized or malformed port ranges fail closed" do
    assert {:error, :invalid_sfu_public_ip} = SfuPeer.ice_options("not-an-ip", nil)
    assert {:error, :invalid_sfu_udp_port_range} = SfuPeer.ice_options(nil, "0-65535")
    assert {:error, :invalid_sfu_udp_port_range} = SfuPeer.ice_options(nil, "50000")
  end

  test "without public endpoint overrides, ExWebRTC keeps its defaults" do
    assert {:ok, []} = SfuPeer.ice_options(nil, nil)
  end
end
