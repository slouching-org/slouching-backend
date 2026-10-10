defmodule Slouching.V1.ClientHello do
  @moduledoc false

  use Protobuf,
    full_name: "slouching.v1.ClientHello",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:protocol_version, 1, type: :uint32, json_name: "protocolVersion")
  field(:device_public_key, 2, type: :bytes, json_name: "devicePublicKey")
end

defmodule Slouching.V1.ServerHello do
  @moduledoc false

  use Protobuf,
    full_name: "slouching.v1.ServerHello",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:protocol_version, 1, type: :uint32, json_name: "protocolVersion")
  field(:server_role, 2, type: :string, json_name: "serverRole")
  field(:identity_available, 3, type: :bool, json_name: "identityAvailable")
  field(:messaging_available, 4, type: :bool, json_name: "messagingAvailable")
  field(:calls_available, 5, type: :bool, json_name: "callsAvailable")
  field(:auth_nonce, 6, type: :bytes, json_name: "authNonce")
end

defmodule Slouching.V1.VersionError do
  @moduledoc false

  use Protobuf,
    full_name: "slouching.v1.VersionError",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:supported_version, 1, type: :uint32, json_name: "supportedVersion")
end

defmodule Slouching.V1.AuthProof do
  @moduledoc false

  use Protobuf,
    full_name: "slouching.v1.AuthProof",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:signature, 1, type: :bytes)
end

defmodule Slouching.V1.Authenticated do
  @moduledoc false

  use Protobuf,
    full_name: "slouching.v1.Authenticated",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:device_public_key, 1, type: :bytes, json_name: "devicePublicKey")
  field(:application_routes_available, 2, type: :bool, json_name: "applicationRoutesAvailable")
end

defmodule Slouching.V1.SfuCallJoin do
  @moduledoc false
  use Protobuf, full_name: "slouching.v1.SfuCallJoin", syntax: :proto3
  field(:call_id, 1, type: :bytes, json_name: "callId")
  field(:group_id, 2, type: :bytes, json_name: "groupId")
  field(:epoch, 3, type: :uint64)
  field(:roster, 4, repeated: true, type: :bytes)
  field(:roster_signature, 5, type: :bytes, json_name: "rosterSignature")
end

defmodule Slouching.V1.SfuCallOffer do
  @moduledoc false
  use Protobuf, full_name: "slouching.v1.SfuCallOffer", syntax: :proto3
  field(:call_id, 1, type: :bytes, json_name: "callId")
  field(:sdp, 2, type: :bytes)
end

defmodule Slouching.V1.SfuIceCandidate do
  @moduledoc false
  use Protobuf, full_name: "slouching.v1.SfuIceCandidate", syntax: :proto3
  field(:call_id, 1, type: :bytes, json_name: "callId")
  field(:candidate, 2, type: :string)
  field(:sdp_mid, 3, type: :string, json_name: "sdpMid")
  field(:sdp_m_line_index, 4, type: :uint32, json_name: "sdpMLineIndex")
  field(:username_fragment, 5, type: :string, json_name: "usernameFragment")
end

defmodule Slouching.V1.SfuCallLeave do
  @moduledoc false
  use Protobuf, full_name: "slouching.v1.SfuCallLeave", syntax: :proto3
  field(:call_id, 1, type: :bytes, json_name: "callId")
end

defmodule Slouching.V1.SfuCallJoined do
  @moduledoc false
  use Protobuf, full_name: "slouching.v1.SfuCallJoined", syntax: :proto3
  field(:call_id, 1, type: :bytes, json_name: "callId")
  field(:roster, 2, repeated: true, type: :bytes)
end

defmodule Slouching.V1.SfuCallAnswer do
  @moduledoc false
  use Protobuf, full_name: "slouching.v1.SfuCallAnswer", syntax: :proto3
  field(:call_id, 1, type: :bytes, json_name: "callId")
  field(:sdp, 2, type: :bytes)
end

defmodule Slouching.V1.SfuCallError do
  @moduledoc false
  use Protobuf, full_name: "slouching.v1.SfuCallError", syntax: :proto3
  field(:call_id, 1, type: :bytes, json_name: "callId")
  field(:code, 2, type: :string)
  field(:message, 3, type: :string)
end

defmodule Slouching.V1.ClientFrame do
  @moduledoc false

  use Protobuf,
    full_name: "slouching.v1.ClientFrame",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof(:payload, 0)

  field(:hello, 1, type: Slouching.V1.ClientHello, oneof: 0)
  field(:auth_proof, 2, type: Slouching.V1.AuthProof, json_name: "authProof", oneof: 0)
  field(:sfu_call_join, 3, type: Slouching.V1.SfuCallJoin, json_name: "sfuCallJoin", oneof: 0)
  field(:sfu_call_offer, 4, type: Slouching.V1.SfuCallOffer, json_name: "sfuCallOffer", oneof: 0)

  field(:sfu_ice_candidate, 5,
    type: Slouching.V1.SfuIceCandidate,
    json_name: "sfuIceCandidate",
    oneof: 0
  )

  field(:sfu_call_leave, 6, type: Slouching.V1.SfuCallLeave, json_name: "sfuCallLeave", oneof: 0)
end

defmodule Slouching.V1.ServerFrame do
  @moduledoc false

  use Protobuf,
    full_name: "slouching.v1.ServerFrame",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof(:payload, 0)

  field(:hello, 1, type: Slouching.V1.ServerHello, oneof: 0)
  field(:version_error, 2, type: Slouching.V1.VersionError, json_name: "versionError", oneof: 0)
  field(:authenticated, 3, type: Slouching.V1.Authenticated, oneof: 0)

  field(:sfu_call_joined, 4,
    type: Slouching.V1.SfuCallJoined,
    json_name: "sfuCallJoined",
    oneof: 0
  )

  field(:sfu_call_answer, 5,
    type: Slouching.V1.SfuCallAnswer,
    json_name: "sfuCallAnswer",
    oneof: 0
  )

  field(:sfu_ice_candidate, 6,
    type: Slouching.V1.SfuIceCandidate,
    json_name: "sfuIceCandidate",
    oneof: 0
  )

  field(:sfu_call_error, 7, type: Slouching.V1.SfuCallError, json_name: "sfuCallError", oneof: 0)
end
