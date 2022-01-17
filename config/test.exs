import Config

config :bolt_sips, Bolt,
  hostname: 'localhost',
  basic_auth: [username: "", password: ""],
  port: 7687,
  pool_size: 5,
  max_overflow: 1

config :ecto_neo4j, Ecto.Adapters.Neo4j,
  chunk_size: 10_000,
  batch: false,
  bolt_role: :direct

config :logger, :console, level: :error
