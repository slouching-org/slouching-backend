defmodule SlouchingServer.Delivery.MailboxUsage do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:recipient_device, :binary, autogenerate: false}
  schema "delivery_mailbox_usage" do
    field(:used_bytes, :integer, default: 0)
    field(:event_count, :integer, default: 0)
  end
end
