import Config

config :bolt_sips, Bolt,
  hostname: 'localhost',
  basic_auth: [username: "", password: ""],
  port: 7687,
  pool_size: 5,
  max_overflow: 1
