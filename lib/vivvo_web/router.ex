defmodule VivvoWeb.Router do
  use VivvoWeb, :router

  import VivvoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VivvoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", VivvoWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:vivvo, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: VivvoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", VivvoWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :shared,
      on_mount: [
        {VivvoWeb.UserAuth, :require_authenticated},
        {VivvoWeb.RoleHooks, :handle_role_changes}
      ] do
      live "/", HomeLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      # Tenant payment submission route
      live "/contracts/:contract_id/payments/new", PaymentLive.Form, :new
    end

    live_session :owner,
      on_mount: [
        {VivvoWeb.UserAuth, :require_authenticated},
        {VivvoWeb.RoleHooks, :handle_role_changes},
        {VivvoWeb.UserAuth, :require_owner_role}
      ] do
      live "/properties", PropertyLive.Index, :index
      live "/properties/new", PropertyLive.Form, :new
      live "/properties/:id", PropertyLive.Show, :show
      live "/properties/:id/edit", PropertyLive.Form, :edit

      # Contract routes
      live "/properties/:property_id/contracts/new", ContractLive.Form, :new
      live "/properties/:property_id/contracts/:id/edit", ContractLive.Form, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", VivvoWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{VivvoWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
