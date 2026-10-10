defmodule SlouchingServer.Delivery.Expiry do
  @moduledoc false
  use GenServer

  @interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    Process.send_after(self(), :expire, @interval_ms)
    {:ok, nil}
  end

  @impl true
  def handle_info(:expire, state) do
    try do
      _ = SlouchingServer.Delivery.Mailbox.expire_all()
    rescue
      _ -> :ok
    end

    Process.send_after(self(), :expire, @interval_ms)
    {:noreply, state}
  end
end
