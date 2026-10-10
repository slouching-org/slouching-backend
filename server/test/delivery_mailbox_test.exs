defmodule SlouchingServer.Delivery.MailboxTest do
  use ExUnit.Case, async: false

  alias SlouchingServer.{Repo, Delivery.Mailbox, Delivery.MailboxUsage, Delivery.Copy}
  alias SlouchingServer.Delivery.WireTest

  setup do
    Repo.delete_all(Copy)
    Repo.delete_all(MailboxUsage)
    :ok
  end

  test "stores, paginates, deduplicates, and acknowledges opaque copies" do
    now = 1_800_000_000
    payload = WireTest.signed_copy_for_mailbox(now + 300)
    {:ok, metadata} = SlouchingServer.Delivery.Wire.parse(payload, now)

    assert {:ok, :stored} = Mailbox.store(payload, now)
    assert {:ok, :already_stored} = Mailbox.store(payload, now)

    assert {:ok, %{copies: [copy], next_after_id: nil}} =
             Mailbox.list(metadata.recipient_device, 0, 16, now)

    assert copy.payload == payload
    assert {:ok, :ok} = Mailbox.acknowledge(metadata.recipient_device, metadata.event_id, now)

    assert {:ok, %{copies: [], next_after_id: nil}} =
             Mailbox.list(metadata.recipient_device, 0, 16, now)

    assert {:ok, :ok} = Mailbox.acknowledge(metadata.recipient_device, metadata.event_id, now)
  end

  test "expires copies and decrements mailbox usage" do
    now = 1_800_000_000
    payload = WireTest.signed_copy_for_mailbox(now + 1)
    {:ok, metadata} = SlouchingServer.Delivery.Wire.parse(payload, now)
    assert {:ok, :stored} = Mailbox.store(payload, now)

    assert {:ok, %{copies: [], next_after_id: nil}} =
             Mailbox.list(metadata.recipient_device, 0, 16, now + 1)

    usage = Repo.get(MailboxUsage, metadata.recipient_device)
    assert usage.used_bytes == 0
    assert usage.event_count == 0
  end

  test "periodic expiry removes copies without recipient traffic" do
    now = 1_800_000_000
    payload = WireTest.signed_copy_for_mailbox(now + 1)
    {:ok, metadata} = SlouchingServer.Delivery.Wire.parse(payload, now)
    assert {:ok, :stored} = Mailbox.store(payload, now)

    assert {:ok, 1} = Mailbox.expire_all(now + 1)

    assert Repo.get_by(Copy,
             recipient_device: metadata.recipient_device,
             event_id: metadata.event_id
           ) == nil
  end
end
