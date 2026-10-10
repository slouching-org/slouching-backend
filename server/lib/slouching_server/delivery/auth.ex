defmodule SlouchingServer.Delivery.Auth do
  @moduledoc false

  import Ecto.Query

  alias SlouchingServer.{Repo, Delivery.RequestNonce, Delivery.Wire}

  @clock_skew_seconds 60
  @nonce_ttl_seconds 120

  def authenticate(method, path, body, headers, now \\ System.system_time(:second)) do
    with {:ok, device} <- decode_header(headers, "x-slouching-device", 64, 32),
         {:ok, timestamp_text} <- single_header(headers, "x-slouching-timestamp"),
         {:ok, timestamp} <- parse_timestamp(timestamp_text),
         true <- abs(now - timestamp) <= @clock_skew_seconds,
         {:ok, nonce} <- decode_header(headers, "x-slouching-nonce", 64, 32),
         {:ok, signature} <- decode_header(headers, "x-slouching-signature", 128, 64),
         true <-
           Wire.request_signature_valid?(
             device,
             signature,
             method,
             path,
             timestamp_text,
             nonce,
             body
           ),
         :ok <- consume_nonce(device, nonce, now) do
      {:ok, device}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp consume_nonce(device, nonce, now) do
    Repo.delete_all(from(n in RequestNonce, where: n.expires_at_unix <= ^now))

    {inserted, _} =
      Repo.insert_all(
        RequestNonce,
        [
          %{device_public_key: device, nonce: nonce, expires_at_unix: now + @nonce_ttl_seconds}
        ],
        on_conflict: :nothing,
        conflict_target: [:device_public_key, :nonce]
      )

    if inserted == 1, do: :ok, else: {:error, :replay}
  rescue
    _ -> {:error, :unauthorized}
  end

  defp single_header(headers, name) do
    case Enum.filter(headers, fn {key, _} -> key == name end) do
      [{^name, value}] -> {:ok, value}
      _ -> {:error, :invalid_header}
    end
  end

  defp decode_header(headers, name, hex_len, byte_len) do
    with {:ok, value} <- single_header(headers, name),
         true <- byte_size(value) == hex_len,
         {:ok, decoded} <- Base.decode16(value, case: :lower),
         true <- byte_size(decoded) == byte_len do
      {:ok, decoded}
    else
      _ -> {:error, :invalid_header}
    end
  end

  defp parse_timestamp(value) do
    case Integer.parse(value) do
      {timestamp, ""} when timestamp >= 0 -> {:ok, timestamp}
      _ -> {:error, :invalid_timestamp}
    end
  end
end
