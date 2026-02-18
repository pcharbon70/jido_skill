import Config

config :jido_skill,
  signal_bus_name: :jido_code_bus,
  signal_bus_middleware: [
    {Jido.Signal.Bus.Middleware.Logger, level: :debug}
  ],
  global_path: "~/.jido_code",
  local_path: ".jido_code",
  settings_path: ".jido_code/settings.json"
