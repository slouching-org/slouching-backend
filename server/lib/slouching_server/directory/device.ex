defmodule SlouchingServer.Directory.Device do
  @moduledoc """
  Persisted public signing key for a device. Enrollment and authorization are
  separate, unimplemented protocol steps; this schema is not a trust claim.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "devices" do
    field(:signing_public_key, :binary)
    field(:revoked_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  @doc "Validates a candidate Ed25519 public key without authorizing enrollment."
  def enrollment_changeset(device, attrs) do
    device
    |> cast(attrs, [:signing_public_key])
    |> validate_required([:signing_public_key])
    |> validate_change(:signing_public_key, fn :signing_public_key, key ->
      if byte_size(key) == 32,
        do: [],
        else: [signing_public_key: "must be exactly 32 bytes"]
    end)
    |> unique_constraint(:signing_public_key)
  end
end
