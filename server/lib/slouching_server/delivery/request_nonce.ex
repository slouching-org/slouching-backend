defmodule SlouchingServer.Delivery.RequestNonce do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "delivery_request_nonces" do
    field(:device_public_key, :binary, primary_key: true)
    field(:nonce, :binary, primary_key: true)
    field(:expires_at_unix, :integer)
  end
end
