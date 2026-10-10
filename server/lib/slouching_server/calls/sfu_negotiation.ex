defmodule SlouchingServer.Calls.SfuNegotiation do
  @moduledoc """
  Builds an ExWebRTC answer for one call member and its MLS-authorized remote
  audio sources. The caller must verify the roster against local call MLS state
  before passing it here.
  """

  alias ExWebRTC.{MediaStreamTrack, PeerConnection, SessionDescription}

  @max_sdp_bytes 128 * 1024
  @max_remote_sources 255

  @doc """
  Answers a client's offer with one receive-only microphone section and one
  send-only audio section for each remote source key, preserving roster order.
  """
  def answer_offer(peer_connection, offer_sdp, remote_source_keys)
      when is_pid(peer_connection) and is_binary(offer_sdp) and is_list(remote_source_keys) do
    with :ok <- validate_offer(offer_sdp, remote_source_keys),
         :ok <-
           PeerConnection.set_remote_description(
             peer_connection,
             %SessionDescription{type: :offer, sdp: offer_sdp}
           ),
         {:ok, transceivers} <-
           audio_transceivers(peer_connection, length(remote_source_keys) + 1),
         {:ok, outbound_track_ids} <-
           add_outbound_sources(peer_connection, transceivers, remote_source_keys),
         {:ok, answer} <- PeerConnection.create_answer(peer_connection),
         :ok <- PeerConnection.set_local_description(peer_connection, answer) do
      {:ok, %{sdp: answer.sdp, outbound_track_ids: outbound_track_ids}}
    end
  end

  def answer_offer(_peer_connection, _offer_sdp, _remote_source_keys),
    do: {:error, :invalid_offer}

  defp validate_offer(offer_sdp, remote_source_keys) do
    cond do
      byte_size(offer_sdp) == 0 or byte_size(offer_sdp) > @max_sdp_bytes ->
        {:error, :invalid_sdp_size}

      length(remote_source_keys) == 0 or length(remote_source_keys) > @max_remote_sources ->
        {:error, :invalid_remote_source_count}

      not valid_source_keys?(remote_source_keys) ->
        {:error, :invalid_remote_source_keys}

      true ->
        validate_audio_sections(offer_sdp, length(remote_source_keys) + 1)
    end
  end

  defp valid_source_keys?(keys) do
    Enum.all?(keys, &(is_binary(&1) and byte_size(&1) == 32)) and
      length(Enum.uniq(keys)) == length(keys)
  end

  defp validate_audio_sections(offer_sdp, expected_count) do
    with {:ok, sdp} <- ExSDP.parse(offer_sdp) do
      audio_sections = Enum.filter(sdp.media, &(&1.type == :audio))
      unsupported_sections = Enum.reject(sdp.media, &(&1.type in [:audio, :application]))

      cond do
        unsupported_sections != [] ->
          {:error, :unsupported_media_section}

        length(audio_sections) != expected_count ->
          {:error, :audio_section_count_mismatch}

        ExWebRTC.SDPUtils.get_media_direction(hd(audio_sections)) not in [:sendrecv, :sendonly] ->
          {:error, :microphone_track_required}

        Enum.any?(tl(audio_sections), &(ExWebRTC.SDPUtils.get_media_direction(&1) != :recvonly)) ->
          {:error, :remote_audio_sections_must_be_recvonly}

        true ->
          :ok
      end
    else
      {:error, _reason} -> {:error, :invalid_sdp}
    end
  end

  defp audio_transceivers(peer_connection, expected_count) do
    transceivers =
      peer_connection
      |> PeerConnection.get_transceivers()
      |> Enum.filter(&(&1.kind == :audio))

    if length(transceivers) == expected_count do
      {:ok, transceivers}
    else
      {:error, :audio_transceiver_count_mismatch}
    end
  end

  defp add_outbound_sources(peer_connection, [_microphone | output_transceivers], source_keys) do
    Enum.zip(output_transceivers, source_keys)
    |> Enum.reduce_while({:ok, %{}}, fn {transceiver, source_key}, {:ok, tracks} ->
      track = MediaStreamTrack.new(:audio, [MediaStreamTrack.generate_stream_id()])

      with :ok <-
             PeerConnection.set_transceiver_direction(peer_connection, transceiver.id, :sendonly),
           :ok <- PeerConnection.replace_track(peer_connection, transceiver.sender.id, track) do
        {:cont, {:ok, Map.put(tracks, source_key, track.id)}}
      else
        {:error, reason} -> {:halt, {:error, {:outbound_track_setup_failed, reason}}}
      end
    end)
  end
end
