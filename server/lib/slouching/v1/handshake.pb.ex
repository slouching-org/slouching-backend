defmodule Slouching.V1.ClientHello do
  @moduledoc false

  use Protobuf,
    full_name: "slouching.v1.ClientHello",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:protocol_version, 1, type: :uint32, json_name: "protocolVersion")
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
end

defmodule Slouching.V1.VersionError do
  @moduledoc false

  use Protobuf,
    full_name: "slouching.v1.VersionError",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:supported_version, 1, type: :uint32, json_name: "supportedVersion")
end

defmodule Slouching.V1.ClientFrame do
  @moduledoc false

  use Protobuf,
    full_name: "slouching.v1.ClientFrame",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof(:payload, 0)

  field(:hello, 1, type: Slouching.V1.ClientHello, oneof: 0)
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
end
