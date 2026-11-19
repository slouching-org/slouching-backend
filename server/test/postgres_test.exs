defmodule SlouchingServer.PostgresTest do
  use ExUnit.Case, async: false

  alias SlouchingServer.PostgresRepo, as: Repo
  alias SlouchingServer.Directory.Device
  alias SlouchingServer.Delivery.{Copy, Mailbox, MailboxUsage, RequestNonce, Wire, WireTest}

  @moduletag skip: is_nil(System.get_env("SLOUCHING_TEST_DATABASE_URL"))

  setup do
    Repo.delete_all(Copy)
    Repo.delete_all(MailboxUsage)
    Repo.delete_all(RequestNonce)
    Repo.delete_all(Device)
    :ok
  end

  test "migrations are repeatable and preserve binary keys, timestamps and unique constraints" do
    assert Application.fetch_env!(:slouching_server, :ecto_repos) == [Repo]
    public_key = :crypto.strong_rand_bytes(32)
    changeset = Device.enrollment_changeset(%Device{}, %{signing_public_key: public_key})
    assert {:ok, device} = Repo.insert(changeset)
    assert {:error, %{errors: [signing_public_key: _]}} = Repo.insert(changeset)

    assert :ok = SlouchingServer.Release.migrate()
    assert :ok = SlouchingServer.Release.migrate()
    assert Repo.get!(Device, device.id) == device
    assert %DateTime{} = device.inserted_at
    assert %{rows: [[2]]} = Repo.query!("SELECT count(*) FROM schema_migrations")

    assert %{rows: rows} =
             Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")

    tables = List.flatten(rows)

    for table <- ~w(devices delivery_copies delivery_mailbox_usage delivery_request_nonces) do
      assert table in tables
    end

    now = System.system_time(:second)
    payload = WireTest.signed_copy_for_mailbox(now + 300)
    assert {:ok, :stored} = Mailbox.store(payload, now)
    [copy] = Repo.all(Copy)
    attrs = Map.from_struct(copy) |> Map.drop([:__meta__, :id])
    assert {:error, %{errors: [_ | _]}} = Repo.insert(Copy.changeset(%Copy{}, attrs))
    assert byte_size(copy.event_id) == 16
    assert byte_size(copy.recipient_device) == 32
    assert copy.payload == payload
    assert %DateTime{} = copy.inserted_at

    nonce = %{
      device_public_key: public_key,
      nonce: :crypto.strong_rand_bytes(32),
      expires_at_unix: now + 120
    }

    assert {1, _} = Repo.insert_all(RequestNonce, [nonce], on_conflict: :nothing)
    assert {0, _} = Repo.insert_all(RequestNonce, [nonce], on_conflict: :nothing)
  end

  test "concurrent duplicate uploads are idempotent and account only once" do
    now = System.system_time(:second)
    payload = WireTest.signed_copy_for_mailbox(now + 300)
    {:ok, metadata} = Wire.parse(payload, now)
    results = parallel(1..4, fn _ -> Mailbox.store(payload, now) end)
    assert Enum.count(results, &(&1 == {:ok, :stored})) == 1
    assert Enum.count(results, &(&1 == {:ok, :already_stored})) == 3
    assert_usage(metadata.recipient_device, byte_size(payload), 1)
  end

  test "concurrent ACKs decrement usage once" do
    now = System.system_time(:second)
    payload = WireTest.signed_copy_for_mailbox(now + 300)
    {:ok, metadata} = Wire.parse(payload, now)
    assert {:ok, :stored} = Mailbox.store(payload, now)

    assert parallel(1..4, fn _ ->
             Mailbox.acknowledge(metadata.recipient_device, metadata.event_id, now)
           end) ==
             List.duplicate({:ok, :ok}, 4)

    assert_usage(metadata.recipient_device, 0, 0)
    assert Repo.aggregate(Copy, :count) == 0
  end

  test "expiry racing ACK and list keeps usage nonnegative" do
    now = System.system_time(:second)
    payload = WireTest.signed_copy_for_mailbox(now + 1)
    {:ok, metadata} = Wire.parse(payload, now)
    assert {:ok, :stored} = Mailbox.store(payload, now)

    parallel([:expire, :expire, :ack, :list], fn
      :expire -> Mailbox.expire_all(now + 1)
      :ack -> Mailbox.acknowledge(metadata.recipient_device, metadata.event_id, now + 1)
      :list -> Mailbox.list(metadata.recipient_device, 0, 16, now + 1)
    end)

    assert_usage(metadata.recipient_device, 0, 0)
    assert Repo.aggregate(Copy, :count) == 0
  end

  test "concurrent uploads cannot overrun the event quota" do
    now = System.system_time(:second)
    {recipient, _} = keys = :crypto.generate_key(:eddsa, :ed25519)

    payloads =
      for _ <- 1..4 do
        {_, _, _, payload} = WireTest.signed_copy(now + 300, recipient: keys)
        payload
      end

    Repo.insert!(%MailboxUsage{recipient_device: recipient, used_bytes: 0, event_count: 4095})
    results = parallel(payloads, &Mailbox.store(&1, now))
    assert Enum.count(results, &(&1 == {:ok, :stored})) == 1
    assert Enum.count(results, &(&1 == {:error, :quota_exceeded})) == 3
    assert_usage(recipient, byte_size(hd(payloads)), 4096)
    assert Repo.aggregate(Copy, :count) == 1
  end

  test "byte quota rejection rolls back without storing a copy" do
    now = System.system_time(:second)
    payload = WireTest.signed_copy_for_mailbox(now + 300)
    {:ok, metadata} = Wire.parse(payload, now)

    Repo.insert!(%MailboxUsage{
      recipient_device: metadata.recipient_device,
      used_bytes: 64 * 1024 * 1024,
      event_count: 0
    })

    assert {:error, :quota_exceeded} = Mailbox.store(payload, now)
    assert_usage(metadata.recipient_device, 64 * 1024 * 1024, 0)
    assert Repo.aggregate(Copy, :count) == 0
  end

  defp assert_usage(recipient, bytes, events) do
    assert %{used_bytes: ^bytes, event_count: ^events} = Repo.get!(MailboxUsage, recipient)
  end

  defp parallel(inputs, fun) do
    inputs
    |> Task.async_stream(fun, max_concurrency: 4, timeout: 10_000)
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
