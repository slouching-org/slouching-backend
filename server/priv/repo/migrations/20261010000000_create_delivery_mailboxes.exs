defmodule SlouchingServer.Repo.Migrations.CreateDeliveryMailboxes do
  use Ecto.Migration

  def change do
    create table(:delivery_copies) do
      add(:event_id, :binary, size: 16, null: false)
      add(:author_device, :binary, size: 32, null: false)
      add(:recipient_device, :binary, size: 32, null: false)
      add(:payload, :binary, null: false)
      add(:size_bytes, :integer, null: false)
      add(:expires_at_unix, :bigint, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:delivery_copies, [:recipient_device, :event_id]))
    create(index(:delivery_copies, [:recipient_device, :id]))
    create(index(:delivery_copies, [:expires_at_unix]))

    create table(:delivery_mailbox_usage, primary_key: false) do
      add(:recipient_device, :binary, primary_key: true, size: 32)
      add(:used_bytes, :bigint, null: false, default: 0)
      add(:event_count, :integer, null: false, default: 0)
    end

    create table(:delivery_request_nonces, primary_key: false) do
      add(:device_public_key, :binary, primary_key: true, size: 32)
      add(:nonce, :binary, primary_key: true, size: 32)
      add(:expires_at_unix, :bigint, null: false)
    end

    create(index(:delivery_request_nonces, [:expires_at_unix]))
  end
end
