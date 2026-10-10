defmodule SlouchingServer.Delivery.AuthTest do
  use ExUnit.Case, async: false

  alias SlouchingServer.Delivery.Auth
  alias SlouchingServer.Delivery.RequestNonce
  alias SlouchingServer.Repo

  test "authenticates canonical Ed25519 requests once and rejects replay" do
    now = 1_800_000_000
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    nonce = :crypto.strong_rand_bytes(32)
    timestamp = Integer.to_string(now)
    path = "/api/delivery/copies?after_id=2&limit=8"
    body = <<>>

    signed =
      "slouching/delivery-http-request/v1\0GET\n" <>
        path <>
        "\n" <>
        timestamp <>
        "\n" <>
        Base.encode16(nonce, case: :lower) <>
        "\n" <>
        :crypto.hash(:sha256, body)

    signature = :crypto.sign(:eddsa, :none, signed, [private_key, :ed25519])

    headers = [
      {"x-slouching-device", Base.encode16(public_key, case: :lower)},
      {"x-slouching-timestamp", timestamp},
      {"x-slouching-nonce", Base.encode16(nonce, case: :lower)},
      {"x-slouching-signature", Base.encode16(signature, case: :lower)}
    ]

    assert {:ok, ^public_key} = Auth.authenticate("GET", path, body, headers, now)
    assert {:error, :unauthorized} = Auth.authenticate("GET", path, body, headers, now)

    assert %RequestNonce{} =
             Repo.get_by(RequestNonce, device_public_key: public_key, nonce: nonce)
  end

  test "rejects an expired request timestamp" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    timestamp = "1799999900"
    nonce = :crypto.strong_rand_bytes(32)

    signed =
      "slouching/delivery-http-request/v1\0GET\n/api/delivery/copies\n" <>
        timestamp <>
        "\n" <>
        Base.encode16(nonce, case: :lower) <>
        "\n" <>
        :crypto.hash(:sha256, <<>>)

    signature = :crypto.sign(:eddsa, :none, signed, [private_key, :ed25519])

    headers = [
      {"x-slouching-device", Base.encode16(public_key, case: :lower)},
      {"x-slouching-timestamp", timestamp},
      {"x-slouching-nonce", Base.encode16(nonce, case: :lower)},
      {"x-slouching-signature", Base.encode16(signature, case: :lower)}
    ]

    assert {:error, :unauthorized} =
             Auth.authenticate("GET", "/api/delivery/copies", <<>>, headers, 1_800_000_000)
  end
end
