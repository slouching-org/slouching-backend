[
  inputs: [
    "{mix,.formatter}.exs",
    "config/*.exs",
    "lib/**/*.{ex,exs}",
    "priv/repo/migrations/*.exs",
    "test/**/*.{ex,exs}"
  ],
  import_deps: [:ecto_sql]
]
