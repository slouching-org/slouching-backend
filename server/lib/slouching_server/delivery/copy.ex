defmodule SlouchingServer.Delivery.Copy do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "delivery_copies" do
    field(:event_id, :binary)
    field(:author_device, :binary)
    field(:recipient_device, :binary)
    field(:payload, :binary)
    field(:size_bytes, :integer)
    field(:expires_at_unix, :integer)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(copy, attrs) do
    copy
    |> cast(attrs, [
      :event_id,
      :author_device,
      :recipient_device,
      :payload,
      :size_bytes,
      :expires_at_unix
    ])
    |> validate_required([
      :event_id,
      :author_device,
      :recipient_device,
      :payload,
      :size_bytes,
      :expires_at_unix
    ])
    |> validate_change(:event_id, fn :event_id, value ->
      validate_binary_size(:event_id, value, 16)
    end)
    |> validate_change(:author_device, fn :author_device, value ->
      validate_binary_size(:author_device, value, 32)
    end)
    |> validate_change(:recipient_device, fn :recipient_device, value ->
      validate_binary_size(:recipient_device, value, 32)
    end)
    |> validate_number(:size_bytes, greater_than: 0)
    |> unique_constraint([:recipient_device, :event_id])
  end

  defp validate_binary_size(_field, value, expected)
       when is_binary(value) and byte_size(value) == expected, do: []

  defp validate_binary_size(field, _value, _expected), do: [{field, "has invalid byte length"}]
end
