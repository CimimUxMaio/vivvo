defmodule Vivvo.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Vivvo.Accounts` context.
  """

  import Ecto.Query

  alias Vivvo.Accounts
  alias Vivvo.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    # Convert keyword list to map if needed
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

    # Extract preferred_roles to determine default current_role
    preferred_roles = Map.get(attrs, :preferred_roles, [:owner, :tenant])

    # Determine default current_role based on preferred_roles
    default_current_role =
      cond do
        :owner in preferred_roles -> :owner
        :tenant in preferred_roles -> :tenant
        true -> :owner
      end

    Enum.into(attrs, %{
      first_name: "Test",
      last_name: "User",
      email: unique_user_email(),
      phone_number: "+1234567890",
      preferred_roles: preferred_roles,
      current_role: Map.get(attrs, :current_role, default_current_role)
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Vivvo.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Vivvo.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Vivvo.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
