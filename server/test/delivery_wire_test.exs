defmodule SlouchingServer.Delivery.WireTest do
  use ExUnit.Case, async: true

  alias SlouchingServer.Delivery.Wire

  test "accepts a signed delegated copy with matching event metadata" do
    now = 1_800_000_000
    {author, _recipient, _recipient_private, payload} = signed_copy(now + 300)

    assert {:ok, copy} = Wire.parse(payload, now)
    assert copy.author_device == author
    assert copy.expires_at_unix == now + 300
  end

  test "rejects altered bytes, expired copies, and mismatched event metadata" do
    now = 1_800_000_000
    {_author, _recipient, _recipient_private, payload} = signed_copy(now + 300)
    <<head::binary-size(153), signature_byte, tail::binary>> = payload
    tampered = head <> <<Bitwise.bxor(signature_byte, 1)>> <> tail

    assert {:error, :invalid_signature} = Wire.parse(tampered, now)
    assert {:error, :invalid_envelope} = Wire.parse(payload, now + 301)
  end

  def signed_copy(expires_at) do
    {author, private} = :crypto.generate_key(:eddsa, :ed25519)
    {recipient, recipient_private} = :crypto.generate_key(:eddsa, :ed25519)
    event_id = :crypto.strong_rand_bytes(16)
    group_id = :crypto.strong_rand_bytes(16)
    epoch = 7
    ciphertext = <<1, 2, 3, 4, 5>>
    digest = :crypto.hash(:sha256, ciphertext)

    event =
      "SLME" <>
        <<1::unsigned-big-16>> <>
        event_id <>
        author <>
        <<16::unsigned-big-16>> <>
        group_id <>
        <<epoch::unsigned-big-64, expires_at::signed-big-64, 0::unsigned-big-8,
          0::unsigned-big-16, byte_size(ciphertext)::unsigned-big-32>> <>
        ciphertext

    signed =
      "slouching/delegated-mls-copy/v1" <>
        event_id <>
        author <>
        recipient <>
        group_id <>
        <<epoch::unsigned-big-64, expires_at::signed-big-64, 0::unsigned-big-32>> <>
        digest

    signature = :crypto.sign(:eddsa, :none, signed, [private, :ed25519])

    payload =
      "SLDG" <>
        <<1::unsigned-big-16>> <>
        event_id <>
        author <>
        recipient <>
        group_id <>
        <<epoch::unsigned-big-64, expires_at::signed-big-64, 0::unsigned-big-32>> <>
        digest <>
        signature <>
        <<byte_size(event)::unsigned-big-32>> <>
        event

    {author, recipient, recipient_private, payload}
  end

  def signed_copy_for_mailbox(expires_at) do
    {_author, _recipient, _recipient_private, payload} = signed_copy(expires_at)
    payload
  end
end
