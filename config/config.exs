# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :vivvo, :scopes,
  user: [
    default: true,
    module: Vivvo.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Vivvo.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :vivvo,
  ecto_repos: [Vivvo.Repo],
  generators: [timestamp_type: :utc_datetime]

# File upload configuration
config :vivvo, Vivvo.Files,
  max_file_size: 10_000_000,
  max_files_per_payment: 5,
  allowed_extensions: ~w(pdf jpg jpeg png gif bmp webp)

# Generic temp directory configuration (used by upload helpers and other features)
config :vivvo, :temp_dir, "tmp"

# Configure the endpoint
config :vivvo, VivvoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: VivvoWeb.ErrorHTML, json: VivvoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Vivvo.PubSub,
  live_view: [signing_salt: "czNPxYgd"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :vivvo, Vivvo.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  vivvo: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  vivvo: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban configuration
config :vivvo, Oban,
  engine: Oban.Engines.Basic,
  queues: [default: 10, rent_periods: 5],
  repo: Vivvo.Repo,
  shutdown_grace_period: :timer.seconds(30),
  plugins: [
    # Automatically delete completed, cancelled, and discarded jobs after 7 days
    # to prevent the oban_jobs table from growing indefinitely
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Rescue jobs left in executing state after node crashes or deployments
    # Moves orphan jobs back to available state after 30 minutes
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab: [
       # Run daily at 23:00 to update index histories from external APIs
       # This ensures fresh data is available before rent period updates run
       {"0 23 * * *", Vivvo.Workers.IndexHistoryWorker},
       # Run at 01:00 on the 1st of each month
       # Creates new rent periods for contracts whose current period ended
       {"0 1 1 * *", Vivvo.Workers.RentPeriodSchedulerWorker}
     ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
