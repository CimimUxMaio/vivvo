defmodule VivvoWeb.PropertyLive.Form do
  @moduledoc """
  LiveView for creating and editing properties.

  Handles both new property creation and existing property updates
  with form validation and navigation.
  """
  use VivvoWeb, :live_view

  alias Vivvo.Properties
  alias Vivvo.Properties.Property

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6 sm:space-y-8">
        <%!-- Page Header --%>
        <.page_header
          title={@page_title}
          back_navigate={return_path(@current_scope, @return_to, @property)}
        >
          <:subtitle>
            <%= if @live_action == :new do %>
              Create a new property listing
            <% else %>
              Update your property details
            <% end %>
          </:subtitle>
        </.page_header>

        <%!-- Main Content: Two Column Layout --%>
        <div class="grid grid-cols-1 lg:grid-cols-5 gap-6">
          <%!-- Left Side: Property Preview Card (40%) --%>
          <div class="lg:col-span-2">
            <.property_preview_card form={@form} />
          </div>

          <%!-- Right Side: Form Container (60%) --%>
          <div class="lg:col-span-3">
            <.form_container
              form={@form}
              current_scope={@current_scope}
              return_to={@return_to}
              property={@property}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Property Preview Card Component - Live updating preview
  defp property_preview_card(assigns) do
    # Extract form values for live preview
    page_title = assigns[:page_title] || "Property"
    name = get_form_value(assigns.form, :name, page_title)
    address = get_form_value(assigns.form, :address, "Address will appear here...")
    area = get_form_value(assigns.form, :area, nil)
    rooms = get_form_value(assigns.form, :rooms, nil)
    notes = get_form_value(assigns.form, :notes, nil)

    assigns =
      assigns
      |> assign(:preview_name, name)
      |> assign(:preview_address, address)
      |> assign(:preview_area, area)
      |> assign(:preview_rooms, rooms)
      |> assign(:preview_notes, notes)

    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-6 lg:sticky lg:top-6">
      <%!-- Hero Icon --%>
      <div class="flex justify-center mb-6">
        <div class="w-24 h-24 rounded-full bg-primary/10 flex items-center justify-center">
          <.icon name="hero-building-office" class="w-12 h-12 text-primary" />
        </div>
      </div>

      <%!-- Property Name --%>
      <div class="text-center mb-4">
        <h2 class="text-xl sm:text-2xl font-bold text-base-content break-words">
          {@preview_name}
        </h2>
      </div>

      <%!-- Property Address --%>
      <div class="text-center mb-6">
        <p class="text-sm text-base-content/70 flex items-center justify-center gap-2">
          <.icon name="hero-map-pin" class="w-4 h-4 flex-shrink-0" />
          <span class="break-words">{@preview_address}</span>
        </p>
      </div>

      <%!-- Specification Badges --%>
      <div class="flex flex-wrap items-center justify-center gap-3 mb-6">
        <%= if @preview_area do %>
          <div class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-base-200 rounded-full text-sm">
            <.icon name="hero-square-3-stack-3d" class="w-4 h-4 text-base-content/60" />
            <span class="font-medium">{@preview_area} m²</span>
          </div>
        <% end %>

        <%= if @preview_rooms do %>
          <div class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-base-200 rounded-full text-sm">
            <.icon name="hero-home" class="w-4 h-4 text-base-content/60" />
            <span class="font-medium">{@preview_rooms} rooms</span>
          </div>
        <% end %>
      </div>

      <%!-- Notes Preview --%>
      <%= if @preview_notes && @preview_notes != "" do %>
        <div class="pt-4 border-t border-base-200">
          <div class="flex items-start gap-2">
            <.icon
              name="hero-document-text"
              class="w-4 h-4 text-base-content/50 flex-shrink-0 mt-0.5"
            />
            <p class="text-sm text-base-content/70 line-clamp-4">
              {@preview_notes}
            </p>
          </div>
        </div>
      <% end %>

      <%!-- Empty State Hint --%>
      <%= if !@preview_area && !@preview_rooms && (!@preview_notes || @preview_notes == "") do %>
        <div class="pt-4 border-t border-base-200">
          <p class="text-xs text-base-content/50 text-center">
            Fill in the form to see property details appear here
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  # Form Container Component with grouped sections
  defp form_container(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-6">
      <.form for={@form} id="property-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <%!-- Basic Information Section --%>
        <div class="space-y-4">
          <div class="flex items-center gap-2 pb-2 border-b border-base-200">
            <div class="p-1.5 bg-primary/10 rounded-lg flex items-center justify-center">
              <.icon name="hero-information-circle" class="w-4 h-4 text-primary" />
            </div>
            <h3 class="font-semibold text-base-content">Basic Information</h3>
          </div>

          <div class="space-y-4">
            <.input
              field={@form[:name]}
              type="text"
              label="Property Name"
              placeholder="e.g., Sunset Apartments"
            />
            <.input
              field={@form[:address]}
              type="text"
              label="Address"
              placeholder="e.g., 123 Main Street, City"
            />
          </div>
        </div>

        <%!-- Property Specifications Section --%>
        <div class="space-y-4">
          <div class="flex items-center gap-2 pb-2 border-b border-base-200">
            <div class="p-1.5 bg-success/10 rounded-lg flex items-center justify-center">
              <.icon name="hero-square-3-stack-3d" class="w-4 h-4 text-success" />
            </div>
            <h3 class="font-semibold text-base-content">Property Specifications</h3>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input field={@form[:area]} type="number" label="Area (m²)" placeholder="e.g., 120" />
            <.input field={@form[:rooms]} type="number" label="Number of Rooms" placeholder="e.g., 3" />
          </div>
        </div>

        <%!-- Additional Details Section --%>
        <div class="space-y-4">
          <div class="flex items-center gap-2 pb-2 border-b border-base-200">
            <div class="p-1.5 bg-info/10 rounded-lg flex items-center justify-center">
              <.icon name="hero-document-text" class="w-4 h-4 text-info" />
            </div>
            <h3 class="font-semibold text-base-content">Additional Details</h3>
          </div>

          <.input
            field={@form[:notes]}
            type="textarea"
            label="Notes"
            placeholder="Add any additional notes about this property..."
            rows="4"
          />
        </div>

        <%!-- Action Buttons --%>
        <div class="flex flex-col sm:flex-row items-stretch sm:items-center gap-3 pt-4 border-t border-base-200">
          <.button phx-disable-with="Saving..." variant="primary" class="sm:flex-1 btn btn-primary">
            Save Property
          </.button>
          <.link
            navigate={return_path(@current_scope, @return_to, @property)}
            class="btn flex-1 inline-flex items-center justify-center"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  # Helper function to get form value for live preview
  defp get_form_value(form, field, default) do
    case form[field].value do
      nil -> default
      "" -> default
      value -> value
    end
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    property = Properties.get_property!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Property")
    |> assign(:property, property)
    |> assign(:form, to_form(Properties.change_property(socket.assigns.current_scope, property)))
  end

  defp apply_action(socket, :new, _params) do
    property = %Property{}

    socket
    |> assign(:page_title, "New Property")
    |> assign(:property, property)
    |> assign(:form, to_form(Properties.change_property(socket.assigns.current_scope, property)))
  end

  @impl true
  def handle_event("validate", %{"property" => property_params}, socket) do
    changeset =
      Properties.change_property(
        socket.assigns.current_scope,
        socket.assigns.property,
        property_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"property" => property_params}, socket) do
    save_property(socket, socket.assigns.live_action, property_params)
  end

  defp save_property(socket, :edit, property_params) do
    case Properties.update_property(
           socket.assigns.current_scope,
           socket.assigns.property,
           property_params
         ) do
      {:ok, property} ->
        {:noreply,
         socket
         |> put_flash(:info, "Property updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, property)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_property(socket, :new, property_params) do
    case Properties.create_property(socket.assigns.current_scope, property_params) do
      {:ok, property} ->
        {:noreply,
         socket
         |> put_flash(:info, "Property created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, property)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _property), do: ~p"/properties"
  defp return_path(_scope, "show", property), do: ~p"/properties/#{property}"
end
