import Config

config :xylon_simple_secret_store,
  ip: {127, 0, 0, 1},
  port: 8091,
  ops_token: nil,
  allow_reveal: true,
  start_http: true

if config_env() == :test do
  import_config "test.exs"
end
