defmodule VivvoWeb.UserLive.Settings do
  @moduledoc """
  LiveView for user account settings.

  Allows users to manage their email address, password, and preferred roles.
  Requires sudo mode (recent authentication) for security.
  """
  use VivvoWeb, :live_view

  on_mount {VivvoWeb.UserAuth, :require_sudo_mode}

  alias Vivvo.Accounts

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
      <div class="max-w-3xl mx-auto space-y-6">
        <%!-- Page Header --%>
        <.page_header
          title="Account Settings"
          back_navigate={~p"/"}
        >
          <:subtitle>Manage your email, password, and role preferences</:subtitle>
        </.page_header>

        <%!-- Email Settings Card --%>
        <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden">
          <div class="h-1 bg-gradient-to-r from-info via-info/80 to-info/60"></div>

          <div class="p-6">
            <div class="flex items-center gap-3 mb-6">
              <div class="p-2 bg-info/10 rounded-xl">
                <.icon name="hero-envelope" class="w-6 h-6 text-info" />
              </div>
              <div>
                <h2 class="text-lg font-semibold text-base-content">Email Address</h2>
                <p class="text-sm text-base-content/60">Update your account email</p>
              </div>
            </div>

            <div class="mb-4 p-3 bg-base-200/50 rounded-lg">
              <p class="text-sm text-base-content/60">Current email</p>
              <p class="font-medium text-base-content">{@current_email}</p>
            </div>

            <.form
              for={@email_form}
              id="email_form"
              phx-submit="update_email"
              phx-change="validate_email"
              class="space-y-4"
            >
              <.input
                field={@email_form[:email]}
                type="email"
                label="New Email Address"
                placeholder="you@example.com"
                autocomplete="email"
                required
              />

              <div class="flex justify-end">
                <.button
                  variant="primary"
                  phx-disable-with="Sending..."
                >
                  <span class="flex items-center gap-2">
                    <.icon name="hero-paper-airplane" class="w-4 h-4" /> Change Email
                  </span>
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Password Settings Card --%>
        <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden">
          <div class="h-1 bg-gradient-to-r from-warning via-warning/80 to-warning/60"></div>

          <div class="p-6">
            <div class="flex items-center gap-3 mb-6">
              <div class="p-2 bg-warning/10 rounded-xl">
                <.icon name="hero-lock-closed" class="w-6 h-6 text-warning" />
              </div>
              <div>
                <h2 class="text-lg font-semibold text-base-content">Password</h2>
                <p class="text-sm text-base-content/60">Update your account password</p>
              </div>
            </div>

            <.form
              for={@password_form}
              id="password_form"
              action={~p"/users/update-password"}
              method="post"
              phx-change="validate_password"
              phx-submit="update_password"
              phx-trigger-action={@trigger_submit}
              class="space-y-4"
            >
              <input
                name={@password_form[:email].name}
                type="hidden"
                id="hidden_user_email"
                autocomplete="username"
                value={@current_email}
              />

              <.input
                field={@password_form[:password]}
                type="password"
                label="New Password"
                placeholder="Enter a strong password"
                autocomplete="new-password"
                required
              />

              <.input
                field={@password_form[:password_confirmation]}
                type="password"
                label="Confirm New Password"
                placeholder="Re-enter your password"
                autocomplete="new-password"
              />

              <div class="flex justify-end">
                <.button
                  variant="primary"
                  phx-disable-with="Saving..."
                >
                  <span class="flex items-center gap-2">
                    <.icon name="hero-key" class="w-4 h-4" /> Save Password
                  </span>
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Role Settings Card --%>
        <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden">
          <div class="h-1 bg-gradient-to-r from-primary via-primary/80 to-primary/60"></div>

          <div class="p-6">
            <div class="flex items-center gap-3 mb-6">
              <div class="p-2 bg-primary/10 rounded-xl">
                <.icon name="hero-user-group" class="w-6 h-6 text-primary" />
              </div>
              <div>
                <h2 class="text-lg font-semibold text-base-content">Role Preferences</h2>
                <p class="text-sm text-base-content/60">
                  Manage your account roles.
                </p>
              </div>
            </div>

            <.form
              for={@settings_form}
              id="settings_form"
              phx-submit="update_settings"
              phx-change="validate_settings"
              class="space-y-6"
            >
              <%!-- Preferred Roles MultiSelect --%>
              <div>
                <label class="label mb-2">
                  <span class="label-text font-medium">I'm interested in using Vivvo as:</span>
                </label>
                <.live_component
                  module={VivvoWeb.Components.MultiSelect}
                  id="preferred-roles-selector"
                  field={@settings_form[:preferred_roles]}
                  placeholder="Select your role(s)..."
                  options={@role_options}
                  required
                />
              </div>

              <div class="flex justify-end">
                <.button
                  variant="primary"
                  phx-disable-with="Saving..."
                >
                  <span class="flex items-center gap-2">
                    <.icon name="hero-check" class="w-4 h-4" /> Save Role Settings
                  </span>
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Payment Information Card --%>
        <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden">
          <div class="h-1 bg-gradient-to-r from-success via-success/80 to-success/60"></div>

          <div class="p-6">
            <div class="flex items-center gap-3 mb-6">
              <div class="p-2 bg-success/10 rounded-xl">
                <.icon name="hero-banknotes" class="w-6 h-6 text-success" />
              </div>
              <div>
                <h2 class="text-lg font-semibold text-base-content">Payment Information</h2>
                <p class="text-sm text-base-content/60">
                  Manage your bank account details for payments
                </p>
              </div>
            </div>

            <.form
              for={@payment_info_form}
              id="payment_info_form"
              phx-submit="update_payment_info"
              phx-change="validate_payment_info"
              class="space-y-4"
            >
              <.input
                field={@payment_info_form[:cbu]}
                type="text"
                label="CBU"
                placeholder="22-digit CBU number"
                maxlength="22"
              />

              <.input
                field={@payment_info_form[:alias]}
                type="text"
                label="Alias"
                placeholder="your.alias.name"
              />

              <.input
                field={@payment_info_form[:account_name]}
                type="text"
                label="Account Holder Name"
                placeholder="Full name of the account owner"
              />

              <div class="flex justify-end">
                <.button
                  variant="primary"
                  phx-disable-with="Saving..."
                >
                  <span class="flex items-center gap-2">
                    <.icon name="hero-check" class="w-4 h-4" /> Save Payment Info
                  </span>
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)
    settings_changeset = Accounts.change_user_settings(user)
    payment_info_changeset = Accounts.change_user_payment_info(user)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:settings_form, to_form(settings_changeset))
      |> assign(:payment_info_form, to_form(payment_info_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:role_options, @role_options)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", %{"user" => user_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", %{"user" => user_params}, socket) do
    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_settings", params, socket) do
    user_params = params["user"] || %{}
    user = socket.assigns.current_scope.user

    # Normalize params to handle multi-select properly
    user_params = normalize_settings_params(user_params)

    settings_form =
      user
      |> Accounts.change_user_settings(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, settings_form: settings_form)}
  end

  def handle_event("update_settings", params, socket) do
    user_params = params["user"] || %{}
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    # Normalize params to handle multi-select properly
    user_params = normalize_settings_params(user_params)

    case Accounts.update_user_settings(user, user_params) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Role settings updated successfully.")
         |> push_navigate(to: ~p"/users/settings")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, settings_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_payment_info", %{"user" => user_params}, socket) do
    payment_info_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_payment_info(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, payment_info_form: payment_info_form)}
  end

  def handle_event("update_payment_info", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.update_user_payment_info(user, user_params) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Payment information updated successfully.")
         |> push_navigate(to: ~p"/users/settings")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, payment_info_form: to_form(changeset, action: :insert))}
    end
  end

  # Helper functions

  defp normalize_settings_params(params) do
    params
    |> Map.put_new("preferred_roles", [])
  end
end
