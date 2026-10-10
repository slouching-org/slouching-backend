defmodule SlouchingServer.Delivery.RouterTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias SlouchingServer.{
    Delivery.Copy,
    Delivery.MailboxUsage,
    Delivery.RequestNonce,
    Repo,
    Router
  }

  alias SlouchingServer.Delivery.WireTest

  setup do
    Repo.delete_all(Copy)
    Repo.delete_all(MailboxUsage)
    Repo.delete_all(RequestNonce)
    :ok
  end

  test "uploads a delegated copy, lists it with a signed recipient request, then ACKs it" do
    now = System.system_time(:second)
    {_author, recipient, recipient_private, payload} = WireTest.signed_copy(now + 300)

    uploaded =
      conn(:post, "/api/delivery/copies", Jason.encode!(%{"copy" => Base.encode64(payload)}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(Router.init([]))

    assert uploaded.status == 201
    assert Jason.decode!(uploaded.resp_body) == %{"status" => "stored"}

    list_path = "/api/delivery/copies?after_id=0&limit=5"

    listed =
      conn(:get, list_path)
      |> signed_request("GET", list_path, recipient, recipient_private)
      |> Router.call(Router.init([]))

    assert listed.status == 200
    [copy] = Jason.decode!(listed.resp_body)["copies"]
    assert copy["copy"] == Base.encode64(payload)
    assert copy["event_id"] == Base.encode16(binary_part(payload, 6, 16), case: :lower)

    ack_path = "/api/delivery/copies/#{copy["event_id"]}/ack"

    acked =
      conn(:post, ack_path)
      |> signed_request("POST", ack_path, recipient, recipient_private)
      |> Router.call(Router.init([]))

    assert acked.status == 204

    listed_again =
      conn(:get, "/api/delivery/copies")
      |> signed_request("GET", "/api/delivery/copies", recipient, recipient_private)
      |> Router.call(Router.init([]))

    assert listed_again.status == 200
    assert Jason.decode!(listed_again.resp_body)["copies"] == []
  end

  defp signed_request(conn, method, path, public_key, private_key) do
    timestamp = Integer.to_string(System.system_time(:second))
    nonce = :crypto.strong_rand_bytes(32)

    signed =
      "slouching/delivery-http-request/v1\0" <>
        method <>
        "\n" <>
        path <>
        "\n" <>
        timestamp <>
        "\n" <>
        Base.encode16(nonce, case: :lower) <>
        "\n" <>
        :crypto.hash(:sha256, <<>>)

    signature = :crypto.sign(:eddsa, :none, signed, [private_key, :ed25519])

    conn
    |> put_req_header("x-slouching-device", Base.encode16(public_key, case: :lower))
    |> put_req_header("x-slouching-timestamp", timestamp)
    |> put_req_header("x-slouching-nonce", Base.encode16(nonce, case: :lower))
    |> put_req_header("x-slouching-signature", Base.encode16(signature, case: :lower))
  end
end
