defmodule SlouchingServer.Delivery.Mailbox do
  @moduledoc false

  import Ecto.Query

  alias SlouchingServer.{Delivery.Copy, Delivery.MailboxUsage, Delivery.Wire}

  @max_copy_bytes 96 * 1024
  @max_mailbox_bytes 64 * 1024 * 1024
  @max_mailbox_events 4_096
  @max_page_size 16

  def store(payload, now \\ System.system_time(:second))

  def store(payload, now)
      when is_binary(payload) and byte_size(payload) <= @max_copy_bytes do
    with {:ok, metadata} <- Wire.parse(payload, now) do
      repo().transaction(fn ->
        expire_for_recipient(metadata.recipient_device, now)

        case repo().get_by(Copy,
               recipient_device: metadata.recipient_device,
               event_id: metadata.event_id
             ) do
          %Copy{payload: ^payload} ->
            :already_stored

          %Copy{} ->
            repo().rollback(:event_conflict)

          nil ->
            reserve_and_insert(payload, metadata)
        end
      end)
      |> unwrap_transaction()
    end
  end

  def store(_payload, _now), do: {:error, :invalid_envelope}

  def list(
        recipient,
        after_id \\ 0,
        limit \\ @max_page_size,
        now \\ System.system_time(:second)
      )

  def list(recipient, after_id, limit, now)
      when is_binary(recipient) and is_integer(after_id) and after_id >= 0 and is_integer(limit) do
    page_size = min(max(limit, 1), @max_page_size)

    repo().transaction(fn ->
      expire_for_recipient(recipient, now)

      rows =
        repo().all(
          from(c in Copy,
            where: c.recipient_device == ^recipient and c.id > ^after_id,
            order_by: [asc: c.id],
            limit: ^(page_size + 1)
          )
        )

      has_more = length(rows) > page_size
      page = Enum.take(rows, page_size)
      next_after_id = if has_more, do: List.last(page).id, else: nil

      %{
        copies:
          Enum.map(
            page,
            &%{
              id: &1.id,
              event_id: &1.event_id,
              expires_at_unix: &1.expires_at_unix,
              payload: &1.payload
            }
          ),
        next_after_id: next_after_id
      }
    end)
    |> unwrap_transaction()
  end

  def list(_recipient, _after_id, _limit, _now), do: {:error, :invalid_cursor}

  def acknowledge(recipient, event_id, now \\ System.system_time(:second))

  def acknowledge(recipient, event_id, now)
      when is_binary(recipient) and is_binary(event_id) and byte_size(event_id) == 16 do
    repo().transaction(fn ->
      expire_for_recipient(recipient, now)

      case repo().get_by(Copy, recipient_device: recipient, event_id: event_id) do
        nil ->
          :ok

        copy ->
          repo().delete!(copy)
          adjust_usage(recipient, -copy.size_bytes, -1)
          :ok
      end
    end)
    |> unwrap_transaction()
  end

  def acknowledge(_recipient, _event_id, _now), do: {:error, :invalid_event_id}

  def expire_all(now \\ System.system_time(:second)) do
    repo().transaction(fn ->
      recipients =
        repo().all(
          from(c in Copy,
            where: c.expires_at_unix <= ^now,
            distinct: true,
            order_by: c.recipient_device,
            select: c.recipient_device
          )
        )

      # Use the same recipient lock as upload/list/ACK, in a stable order.
      Enum.reduce(recipients, 0, fn recipient, total ->
        total + expire_for_recipient(recipient, now)
      end)
    end)
    |> unwrap_transaction()
  end

  defp reserve_and_insert(payload, metadata) do
    size = byte_size(payload)

    repo().insert_all(
      MailboxUsage,
      [%{recipient_device: metadata.recipient_device, used_bytes: 0, event_count: 0}],
      on_conflict: :nothing,
      conflict_target: [:recipient_device]
    )

    {reserved, _} =
      repo().update_all(
        from(u in MailboxUsage,
          where:
            u.recipient_device == ^metadata.recipient_device and
              u.used_bytes + ^size <= ^@max_mailbox_bytes and u.event_count < ^@max_mailbox_events
        ),
        inc: [used_bytes: size, event_count: 1]
      )

    if reserved == 0 do
      repo().rollback(:quota_exceeded)
    end

    attrs = %{
      event_id: metadata.event_id,
      author_device: metadata.author_device,
      recipient_device: metadata.recipient_device,
      payload: payload,
      size_bytes: size,
      expires_at_unix: metadata.expires_at_unix
    }

    case %Copy{} |> Copy.changeset(attrs) |> repo().insert() do
      {:ok, _copy} -> :stored
      {:error, _changeset} -> repo().rollback(:event_conflict)
    end
  end

  defp expire_for_recipient(recipient, now) do
    lock_recipient(recipient)

    expired =
      repo().all(
        from(c in Copy,
          where: c.recipient_device == ^recipient and c.expires_at_unix <= ^now,
          select: {c.id, c.size_bytes}
        )
      )

    if expired != [] do
      ids = Enum.map(expired, &elem(&1, 0))
      bytes = Enum.reduce(expired, 0, fn {_id, size}, sum -> sum + size end)
      repo().delete_all(from(c in Copy, where: c.id in ^ids))
      adjust_usage(recipient, -bytes, -length(expired))
    end

    length(expired)
  end

  # SQLite's single connection already serializes these transactions. PostgreSQL
  # needs a row shared by every operation, including an empty mailbox. Keep usage
  # rows after expiry/ACK so the lock identity remains stable.
  defp lock_recipient(recipient) do
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      repo().insert_all(
        MailboxUsage,
        [%{recipient_device: recipient, used_bytes: 0, event_count: 0}],
        on_conflict: :nothing,
        conflict_target: [:recipient_device]
      )

      repo().one!(
        from(u in MailboxUsage, where: u.recipient_device == ^recipient, lock: "FOR UPDATE")
      )
    end
  end

  defp adjust_usage(recipient, byte_delta, event_delta) do
    repo().update_all(
      from(u in MailboxUsage, where: u.recipient_device == ^recipient),
      inc: [used_bytes: byte_delta, event_count: event_delta]
    )
  end

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}

  defp repo, do: Application.fetch_env!(:slouching_server, :repo_module)
end
