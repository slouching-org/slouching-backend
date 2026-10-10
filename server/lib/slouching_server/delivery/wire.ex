defmodule SlouchingServer.Delivery.Wire do
  @moduledoc """
  Parser and signature verifier for the Rust `SLDG` delegated MLS-copy envelope.

  The helper validates authorization metadata and stores the original opaque
  envelope. It has no MLS keys and does not decrypt or interpret application data.
  """

  @copy_magic "SLDG"
  @copy_version 1
  @event_magic "SLME"
  @event_version 1
  @signature_domain "slouching/delegated-mls-copy/v1"
  @max_copy_bytes 96 * 1024
  @max_ciphertext_bytes 32 * 1024
  @max_checkpoint_bytes 16 * 1024
  @max_ttl_seconds 30 * 24 * 60 * 60

  @type copy :: %{
          event_id: binary(),
          author_device: binary(),
          recipient_device: binary(),
          expires_at_unix: integer()
        }

  @spec parse(binary(), integer()) :: {:ok, copy()} | {:error, atom()}
  def parse(payload, now \\ System.system_time(:second))

  def parse(payload, now) when is_binary(payload) and byte_size(payload) <= @max_copy_bytes do
    with {:ok, grant, event} <- parse_grant(payload),
         :ok <- validate_match(grant, event, now),
         :ok <- verify_signature(grant) do
      {:ok,
       %{
         event_id: grant.event_id,
         author_device: grant.author_device,
         recipient_device: grant.recipient_device,
         expires_at_unix: grant.expires_at_unix
       }}
    end
  end

  def parse(_payload, _now), do: {:error, :invalid_envelope}

  def request_signature_valid?(public_key, signature, method, path, timestamp, nonce, body)
      when is_binary(public_key) and byte_size(public_key) == 32 and is_binary(signature) and
             byte_size(signature) == 64 and is_binary(method) and is_binary(path) and
             is_binary(timestamp) and is_binary(nonce) and byte_size(nonce) == 32 and
             is_binary(body) do
    payload =
      "slouching/delivery-http-request/v1\0" <>
        method <>
        "\n" <>
        path <>
        "\n" <>
        timestamp <>
        "\n" <>
        Base.encode16(nonce, case: :lower) <>
        "\n" <>
        :crypto.hash(:sha256, body)

    :crypto.verify(:eddsa, :none, payload, signature, [public_key, :ed25519])
  rescue
    _error -> false
  end

  def request_signature_valid?(
        _public_key,
        _signature,
        _method,
        _path,
        _timestamp,
        _nonce,
        _body
      ),
      do: false

  defp parse_grant(
         <<@copy_magic, @copy_version::unsigned-big-16, event_id::binary-size(16),
           author_device::binary-size(32), recipient_device::binary-size(32),
           group_id::binary-size(16), epoch::unsigned-big-64, expires_at_unix::signed-big-64,
           checkpoint_len::unsigned-big-32, rest::binary>>
       ) do
    with true <- checkpoint_len <= @max_checkpoint_bytes,
         true <- checkpoint_len + 32 + 64 + 4 <= byte_size(rest),
         <<checkpoint::binary-size(^checkpoint_len), digest::binary-size(32),
           signature::binary-size(64), event_len::unsigned-big-32, event_bytes::binary>> <- rest,
         true <- event_len == byte_size(event_bytes),
         {:ok, event} <- parse_event(event_bytes) do
      {:ok,
       %{
         event_id: event_id,
         author_device: author_device,
         recipient_device: recipient_device,
         group_id: group_id,
         epoch: epoch,
         expires_at_unix: expires_at_unix,
         checkpoint: if(checkpoint_len == 0, do: nil, else: checkpoint),
         digest: digest,
         signature: signature
       }, event}
    else
      false -> {:error, :invalid_envelope}
      _ -> {:error, :invalid_envelope}
    end
  end

  defp parse_grant(_payload), do: {:error, :invalid_envelope}

  defp parse_event(
         <<@event_magic, @event_version::unsigned-big-16, event_id::binary-size(16),
           author_device::binary-size(32), group_len::unsigned-big-16, rest::binary>>
       ) do
    with true <- group_len == 16,
         true <- byte_size(rest) >= group_len + 8 + 8 + 1 + 2 + 4,
         <<group_id::binary-size(^group_len), epoch::unsigned-big-64,
           expires_at_unix::signed-big-64, has_checkpoint::unsigned-big-8,
           checkpoint_len::unsigned-big-16, ciphertext_len::unsigned-big-32, tail::binary>> <-
           rest,
         true <- checkpoint_len <= @max_checkpoint_bytes,
         true <- ciphertext_len > 0 and ciphertext_len <= @max_ciphertext_bytes,
         true <- checkpoint_len + ciphertext_len == byte_size(tail),
         <<checkpoint::binary-size(^checkpoint_len), ciphertext::binary-size(^ciphertext_len)>> <-
           tail,
         {:ok, checkpoint} <- decode_checkpoint(has_checkpoint, checkpoint_len, checkpoint) do
      {:ok,
       %{
         event_id: event_id,
         author_device: author_device,
         group_id: group_id,
         epoch: epoch,
         expires_at_unix: expires_at_unix,
         checkpoint: checkpoint,
         ciphertext: ciphertext
       }}
    else
      false -> {:error, :invalid_envelope}
      _ -> {:error, :invalid_envelope}
    end
  end

  defp parse_event(_event), do: {:error, :invalid_envelope}

  defp decode_checkpoint(0, 0, <<>>), do: {:ok, nil}
  defp decode_checkpoint(1, _length, checkpoint), do: {:ok, checkpoint}
  defp decode_checkpoint(_flag, _length, _checkpoint), do: {:error, :invalid_envelope}

  defp validate_match(grant, event, now) do
    valid =
      grant.author_device != :binary.copy(<<0>>, 32) and
        grant.recipient_device != :binary.copy(<<0>>, 32) and
        grant.event_id != :binary.copy(<<0>>, 16) and
        event.event_id == grant.event_id and
        event.author_device == grant.author_device and
        event.group_id == grant.group_id and
        event.epoch == grant.epoch and
        event.expires_at_unix == grant.expires_at_unix and
        event.checkpoint == grant.checkpoint and
        grant.expires_at_unix > now and
        grant.expires_at_unix <= now + @max_ttl_seconds and
        grant.epoch <= 9_223_372_036_854_775_807

    if valid, do: :ok, else: {:error, :invalid_envelope}
  end

  defp verify_signature(grant) do
    checkpoint = grant.checkpoint || <<>>

    signed =
      @signature_domain <>
        grant.event_id <>
        grant.author_device <>
        grant.recipient_device <>
        grant.group_id <>
        <<grant.epoch::unsigned-big-64, grant.expires_at_unix::signed-big-64,
          byte_size(checkpoint)::unsigned-big-32>> <>
        checkpoint <>
        grant.digest

    if :crypto.verify(:eddsa, :none, signed, grant.signature, [grant.author_device, :ed25519]),
      do: :ok,
      else: {:error, :invalid_signature}
  rescue
    _error -> {:error, :invalid_signature}
  end
end
