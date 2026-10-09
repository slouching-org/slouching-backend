import Config

config :slouching_server, start_server: config_env() != :test
