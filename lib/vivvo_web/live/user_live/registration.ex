defmodule VivvoWeb.UserLive.Registration do
  use VivvoWeb, :live_view

  alias Vivvo.Accounts
  alias Vivvo.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:first_name]}
            type="text"
            label="First Name"
            required
            phx-mounted={JS.focus()}
          />

          <.input field={@form[:last_name]} type="text" label="Last Name" required />

          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            required
          />

          <.input field={@form[:phone_number]} type="text" label="Phone Number" required />

          <div class="space-y-2">
            <label class="block text-sm font-semibold leading-6 text-zinc-800">
              I'm interested in using Vivvo as a
            </label>
            <div class="space-y-2">
              <label class="flex items-center gap-2">
                <input
                  type="checkbox"
                  name="user[preferred_roles][]"
                  value="owner"
                  checked={:owner in (@form[:preferred_roles].value || [])}
                  class="rounded border-zinc-300 text-brand focus:ring-brand"
                />
                <span class="text-sm">Property Owner</span>
              </label>
              <label class="flex items-center gap-2">
                <input
                  type="checkbox"
                  name="user[preferred_roles][]"
                  value="tenant"
                  checked={:tenant in (@form[:preferred_roles].value || [])}
                  class="rounded border-zinc-300 text-brand focus:ring-brand"
                />
                <span class="text-sm">Tenant</span>
              </label>
            </div>
            <.input_errors field={@form[:preferred_roles]} />
          </div>

          <.button phx-disable-with="Creating account..." class="btn btn-primary w-full">
            Create an account
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: VivvoWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    # Auto-calculate current_role based on preferred_roles
    user_params =
      case user_params["preferred_roles"] do
        [first_role | _] -> Map.put(user_params, "current_role", first_role)
        _ -> Map.put(user_params, "current_role", nil)
      end

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
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    # Auto-calculate current_role based on preferred_roles
    user_params =
      case user_params["preferred_roles"] do
        [first_role | _] -> Map.put(user_params, "current_role", first_role)
        _ -> Map.put(user_params, "current_role", nil)
      end

    changeset = Accounts.change_user_registration(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
