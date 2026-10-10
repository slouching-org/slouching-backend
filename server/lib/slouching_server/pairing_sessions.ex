defmodule SlouchingServer.PairingSessions do
  @moduledoc """
  Volatile rendezvous storage for one SPAKE2 pairing attempt.

  The service stores only the two bounded public SPAKE2 messages and key
  confirmation tags. The session ID is a bearer capability and must be shared
  only with the intended peer. This process does not authenticate contacts.
  """
  use GenServer

  @ttl_ms 120_000
  @sweep_ms 30_000
  @max_sessions 10_000
  @message_sizes %{spake2: 33, confirm: 32}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def create(server \\ __MODULE__), do: GenServer.call(server, :create)

  def put(server \\ __MODULE__, session_id, role, stage, message) do
    GenServer.call(server, {:put, session_id, role, stage, message})
  end

  def fetch(server \\ __MODULE__, session_id, role, stage) do
    GenServer.call(server, {:fetch, session_id, role, stage})
  end

  def delete(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:delete, session_id})
  end

  @impl true
  def init(:ok) do
    schedule_sweep()
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call(:create, _from, state) do
    sessions = prune_expired(state.sessions, now_ms())

    if map_size(sessions) >= @max_sessions do
      {:reply, {:error, :capacity}, %{state | sessions: sessions}}
    else
      session_id = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      session = %{expires_at: now_ms() + @ttl_ms, messages: %{}}
      {:reply, {:ok, session_id}, put_in(state.sessions[session_id], session)}
    end
  end

  def handle_call({:put, session_id, role, stage, message}, _from, state) do
    with {:ok, role} <- parse_role(role),
         {:ok, stage, expected_size} <- parse_stage(stage),
         :ok <- validate_message(message, expected_size),
         {:ok, session, sessions} <- active_session(state.sessions, session_id),
         :ok <- stage_ready?(session.messages, role, stage),
         :ok <- slot_empty?(session.messages, role, stage) do
      messages = Map.put(session.messages, {stage, role}, message)
      updated = %{session | messages: messages}
      {:reply, :ok, %{state | sessions: Map.put(sessions, session_id, updated)}}
    else
      {:error, :expired} -> {:reply, {:error, :expired}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:fetch, session_id, role, stage}, _from, state) do
    with {:ok, role} <- parse_role(role),
         {:ok, stage, _expected_size} <- parse_stage(stage),
         {:ok, session, sessions} <- active_session(state.sessions, session_id),
         :ok <- stage_ready?(session.messages, role, stage) do
      other_role = if role == :inviter, do: :invitee, else: :inviter
      result = Map.fetch(session.messages, {stage, other_role})
      {:reply, result, %{state | sessions: sessions}}
    else
      {:error, :expired} -> {:reply, {:error, :expired}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete, session_id}, _from, state) when is_binary(session_id) do
    {:reply, :ok, update_in(state.sessions, &Map.delete(&1, session_id))}
  end

  def handle_call({:delete, _session_id}, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info(:sweep, state) do
    schedule_sweep()
    {:noreply, %{state | sessions: prune_expired(state.sessions, now_ms())}}
  end

  defp active_session(sessions, session_id) when is_binary(session_id) do
    now = now_ms()

    case Map.fetch(sessions, session_id) do
      {:ok, %{expires_at: expires_at} = session} when expires_at > now ->
        {:ok, session, sessions}

      {:ok, _expired} ->
        {:error, :expired}

      :error ->
        {:error, :not_found}
    end
  end

  defp active_session(_sessions, _session_id), do: {:error, :not_found}

  defp parse_role(role) when role in [:inviter, :invitee], do: {:ok, role}

  defp parse_role(role) when role in ["inviter", "invitee"],
    do: {:ok, String.to_existing_atom(role)}

  defp parse_role(_role), do: {:error, :invalid_role}

  defp parse_stage(stage) when stage in [:spake2, :confirm],
    do: {:ok, stage, Map.fetch!(@message_sizes, stage)}

  defp parse_stage(stage) when stage in ["spake2", "confirm"],
    do: stage |> String.to_existing_atom() |> parse_stage()

  defp parse_stage(_stage), do: {:error, :invalid_stage}

  defp validate_message(message, expected_size)
       when is_binary(message) and byte_size(message) == expected_size,
       do: :ok

  defp validate_message(_message, _expected_size), do: {:error, :invalid_message_size}

  defp stage_ready?(_messages, _role, :spake2), do: :ok

  defp stage_ready?(messages, _role, :confirm) do
    if Map.has_key?(messages, {:spake2, :inviter}) and
         Map.has_key?(messages, {:spake2, :invitee}) do
      :ok
    else
      {:error, :spake2_incomplete}
    end
  end

  defp slot_empty?(messages, role, stage) do
    if Map.has_key?(messages, {stage, role}), do: {:error, :already_submitted}, else: :ok
  end

  defp prune_expired(sessions, now) do
    Map.reject(sessions, fn {_id, session} -> session.expires_at <= now end)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_ms)
end
