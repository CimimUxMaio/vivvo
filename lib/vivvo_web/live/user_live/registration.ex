defmodule VivvoWeb.UserLive.Registration do
  @moduledoc """
  LiveView for user registration.

  Handles new user account creation with validation for
  email, personal information, and role selection.
  """
  use VivvoWeb, :live_view

  alias Vivvo.Accounts
  alias Vivvo.Accounts.User

  @role_options [
    %{
      value: :owner,
      label: "Property Owner",
      icon: "hero-home",
      variant: :primary
    },
    %{
      value: :tenant,
      label: "Tenant",
      icon: "hero-user",
      variant: :info
    }
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md space-y-4">
        <div class="bg-base-100 rounded-2xl shadow-lg border border-base-200 overflow-hidden">
          <div class="h-1.5 bg-gradient-to-r from-primary via-primary/80 to-primary/60"></div>

          <div class="p-6 sm:p-8 space-y-6">
            <div class="text-center space-y-3">
              <div class="inline-flex items-center justify-center">
                <.app_icon class="w-18 h-18" />
              </div>
              <h1 class="text-2xl sm:text-3xl font-bold tracking-tight text-base-content">
                Create your account
              </h1>
              <p class="text-sm text-base-content/70">
                Already have an account?
                <.link
                  navigate={~p"/users/log-in"}
                  class="font-semibold text-primary hover:underline"
                >
                  Sign in
                </.link>
              </p>
            </div>

            <.form
              for={@form}
              id="registration_form"
              phx-submit="save"
              phx-change="validate"
              class="flex flex-col gap-1"
            >
              <div class="grid grid-cols-2 gap-4">
                <.input
                  field={@form[:first_name]}
                  type="text"
                  label="First Name"
                  placeholder="John"
                  required
                  phx-mounted={JS.focus()}
                />
                <.input
                  field={@form[:last_name]}
                  type="text"
                  label="Last Name"
                  placeholder="Doe"
                  required
                />
              </div>

              <.input
                field={@form[:email]}
                type="email"
                label="Email Address"
                placeholder="you@example.com"
                autocomplete="email"
                required
              />

              <.input
                field={@form[:phone_number]}
                type="tel"
                label="Phone Number"
                placeholder="+1 (555) 000-0000"
                required
              />

              <.live_component
                module={MultiSelect}
                id="role-selector"
                field={@form[:preferred_roles]}
                label="I'm interested in using Vivvo as:"
                placeholder="Select your role(s)..."
                options={@role_options}
                required
              />

              <.button
                phx-disable-with="Creating your account..."
                variant="primary"
                class="w-full mt-2 mb-4"
              >
                <span class="flex items-center justify-center gap-2">
                  Create Account <.icon name="hero-arrow-right" class="w-5 h-5" />
                </span>
              </.button>

              <p class="text-center text-xs text-base-content/50">
                By creating an account, you agree to our
                <a href="#" class="underline hover:text-base-content/70">Terms of Service</a>
                and <a href="#" class="underline hover:text-base-content/70">Privacy Policy</a>.
              </p>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:ok, redirect(socket, to: ~p"/")}
    else
      changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

      {:ok,
       socket
       |> assign(form: to_form(changeset, as: "user"))
       |> assign(:role_options, @role_options)}
    end
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    user_params = clean_params(user_params)

    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{user.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    user_params = clean_params(user_params)

    changeset =
      Accounts.change_user_registration(%User{}, user_params, validate_unique: false)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end

  defp clean_params(params) do
    params
    |> Map.put_new("preferred_roles", [])
  end
end
