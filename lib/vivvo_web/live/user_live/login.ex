defmodule VivvoWeb.UserLive.Login do
  @moduledoc """
  LiveView for user login with modern UI.

  Handles both regular login via magic link and reauthentication
  for sensitive actions (sudo mode).
  """
  use VivvoWeb, :live_view

  alias Vivvo.Accounts

  # Auth method selector - thin wrapper around sliding_selector
  defp auth_method_selector(assigns) do
    ~H"""
    <.sliding_selector
      value={to_string(@value)}
      on_select="switch_method"
      class="bg-base-200 rounded-xl"
    >
      <:option value="magic">
        <.icon name="hero-envelope" class="w-4 h-4" /> Magic Link
      </:option>
      <:option value="password">
        <.icon name="hero-key" class="w-4 h-4" /> Password
      </:option>
    </.sliding_selector>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md space-y-4">
        <%!-- Login Card --%>
        <div class="bg-base-100 rounded-2xl shadow-lg border border-base-200 overflow-hidden">
          <%!-- Top Accent --%>
          <div class="h-1.5 bg-gradient-to-r from-primary via-primary/80 to-primary/60"></div>

          <div class="p-6 sm:p-8 space-y-6">
            <%!-- Header --%>
            <div class="text-center space-y-3">
              <div class="inline-flex items-center justify-center w-12 h-12 bg-primary/10 rounded-xl">
                <.icon name="hero-home" class="w-6 h-6 text-primary" />
              </div>
              <h1 class="text-2xl sm:text-3xl font-bold tracking-tight text-base-content">
                <%= if @current_scope do %>
                  Confirm your identity
                <% else %>
                  Welcome back
                <% end %>
              </h1>
              <p class="text-sm text-base-content/70">
                <%= if @current_scope do %>
                  Please reauthenticate to continue
                <% else %>
                  Sign in to manage your properties
                <% end %>
              </p>
            </div>

            <%!-- Local Mail Adapter Notice --%>
            <div :if={local_mail_adapter?()} class="alert alert-info alert-soft text-sm">
              <.icon name="hero-information-circle" class="size-5 shrink-0" />
              <span>
                Check sent emails at
                <.link
                  href="/dev/mailbox"
                  class="underline font-medium"
                >
                  the mailbox
                </.link>
              </span>
            </div>

            <%!-- Auth Method Tabs --%>
            <.auth_method_selector value={@auth_method} />

            <%!-- Forms --%>
            <div class="transition-all duration-300">
              <%= case @auth_method do %>
                <% :magic -> %>
                  <.magic_link_form
                    form={@form}
                    current_scope={@current_scope}
                    auth_method={@auth_method}
                  />
                <% :password -> %>
                  <.password_form
                    form={@form}
                    current_scope={@current_scope}
                    trigger_submit={@trigger_submit}
                    auth_method={@auth_method}
                  />
              <% end %>
            </div>

            <%!-- Footer --%>
            <%= if !@current_scope do %>
              <div class="text-center pt-4 border-t border-base-200">
                <p class="text-sm text-base-content/60">
                  Don't have an account?
                  <.link
                    navigate={~p"/users/register"}
                    class="font-medium text-primary hover:underline"
                  >
                    Sign up
                  </.link>
                </p>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Magic Link Form Component
  defp magic_link_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="login_form_magic"
      action={~p"/users/log-in?auth=#{@auth_method}"}
      phx-submit="submit_magic"
      class="flex flex-col gap-4"
    >
      <.input
        readonly={!!@current_scope}
        field={@form[:email]}
        type="email"
        label="Email address"
        placeholder="you@example.com"
        autocomplete="email"
        required
        phx-mounted={!@current_scope && JS.focus()}
      />
      <.button
        class="w-full btn btn-primary"
        phx-disable-with="Sending link..."
      >
        <span class="flex items-center justify-center gap-2">
          Send magic link <.icon name="hero-paper-airplane" class="w-4 h-4" />
        </span>
      </.button>
    </.form>
    """
  end

  # Password Form Component
  defp password_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="login_form_password"
      action={~p"/users/log-in?auth=#{@auth_method}"}
      phx-submit="submit_password"
      phx-trigger-action={@trigger_submit}
      class="flex flex-col gap-6"
    >
      <div class="flex flex-col">
        <.input
          readonly={!!@current_scope}
          field={@form[:email]}
          type="email"
          label="Email address"
          placeholder="you@example.com"
          autocomplete="email"
          required
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="current-password"
          required
        />

        <%!-- Remember Me Toggle --%>
        <label class="flex items-center gap-3 cursor-pointer group">
          <input
            type="checkbox"
            name={@form[:remember_me].name}
            value="true"
            checked={@form[:remember_me].value not in [false, "false"]}
            class="checkbox checkbox-primary checkbox-sm"
          />
          <span class="text-sm text-base-content/70 group-hover:text-base-content transition-colors">
            Remember this device
          </span>
        </label>
      </div>

      <.button
        class="w-full btn btn-primary"
        phx-disable-with="Signing in..."
      >
        <span class="flex items-center justify-center gap-2">
          Sign in <.icon name="hero-arrow-right" class="w-4 h-4" />
        </span>
      </.button>
    </.form>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    auth_method =
      case params["auth"] do
        "password" -> :password
        _ -> :magic
      end

    {:noreply, assign(socket, auth_method: auth_method)}
  end

  @impl true
  def handle_event("switch_method", %{"selected" => selected}, socket) do
    {:noreply, push_patch(socket, to: ~p"/users/log-in?auth=#{selected}")}
  end

  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:vivvo, Vivvo.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
