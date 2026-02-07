defmodule Vivvo.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Vivvo.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Vivvo.Accounts.User

  defstruct user: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Checks if the scope's user has the given role.

  Returns true if the user's current_role matches the given role.
  Returns false if the scope has no user or the role doesn't match.
  """
  def has_role?(%__MODULE__{user: %User{current_role: user_role}}, role) do
    user_role == role
  end

  def has_role?(%__MODULE__{}, _role), do: false
  def has_role?(nil, _role), do: false

  @doc """
  Checks if the scope's user has the :owner role.

  This is a convenience function that calls `has_role?(scope, :owner)`.
  """
  def owner?(scope), do: has_role?(scope, :owner)

  @doc """
  Checks if the scope's user has the :tenant role.

  This is a convenience function that calls `has_role?(scope, :tenant)`.
  """
  def tenant?(scope), do: has_role?(scope, :tenant)
end
