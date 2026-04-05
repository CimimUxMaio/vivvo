defmodule VivvoWeb.Components.MultiSelect do
  @moduledoc """
  A LiveComponent for multi-select input with pill-based selection.

  Works like a standard form input: accepts a `field` assign from a form
  and renders hidden inputs with the field name. When selections change,
  an input event is dispatched on the hidden inputs, triggering the parent
  form's `phx-change` event automatically.

  ## Examples

      <.live_component
        module={MultiSelect}
        id="role-selector"
        field={@form[:preferred_roles]}
        label="Select Roles"
        placeholder="Select role(s)..."
        options={[
          %{value: :owner, label: "Property Owner", icon: "hero-home", variant: :primary},
          %{value: :tenant, label: "Tenant", icon: "hero-user", variant: :info}
        ]}
      />

  The component works automatically with form validation - when selections
  change, the parent form's `phx-change` handler will receive the updated
  values just like any other input field.

  ## Options

  Each option is a map with the following keys:
    * `:value` - The option value (required, can be atom or string)
    * `:label` - The display label (required)
    * `:icon` - The hero icon name (required)
    * `:variant` - The DaisyUI color variant atom for styling (optional, defaults to :base-200).
      Valid variants include: `:primary`, `:secondary`, `:accent`, `:neutral`, `:info`, `:success`,
      `:warning`, `:error`. Only atom values are supported.
  """
  use VivvoWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    field = socket.assigns[:field]

    selected =
      if field do
        field.value |> List.wrap() |> Enum.map(&to_string/1)
      else
        []
      end

    name = if field, do: field.name <> "[]", else: ""

    {:ok,
     socket
     |> assign(:selected, selected)
     |> assign(:name, name)
     |> assign_new(:dropdown_open, fn -> false end)
     |> assign_new(:placeholder, fn -> "Select options..." end)
     |> assign_new(:label, fn -> nil end)
     |> assign_new(:required, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    selected_set = MapSet.new(assigns.selected)

    options =
      Enum.map(assigns.options, fn opt ->
        Map.update!(opt, :value, &to_string/1)
      end)

    {selected_options, available_options} =
      Enum.split_with(options, fn opt -> opt.value in selected_set end)

    assigns =
      assigns
      |> assign(:selected_options, selected_options)
      |> assign(:available_options, available_options)

    ~H"""
    <div class="fieldset mb-2" id={@id} phx-hook="MultiSelect">
      <label :if={@label} class="label mb-1">
        {@label}
      </label>

      <div
        id={"#{@id}-container"}
        class={[
          "w-full h-auto input py-2",
          "flex items-center justify-between gap-2",
          if(field_has_errors?(@field),
            do: "border-error input-error"
          )
        ]}
      >
        <%!-- Pills and placeholder container (takes remaining space) --%>
        <div class="flex-1 flex flex-wrap gap-2 items-center">
          <%!-- Selected options --%>
          <.selected_option
            :for={option <- @selected_options}
            option={option}
            myself={@myself}
          />

          <%!-- Placeholder when nothing selected --%>
          <span :if={@selected_options == []} class="text-sm text-base-content/50 select-none">
            {@placeholder}
          </span>

          <%!-- Hidden input used only to dispatch form change events --%>
          <input class="multi-input" type="hidden" name={"#{@id}_trigger"} value="" />

          <%!-- Real form inputs are only rendered for actual selections --%>
          <input
            :for={value <- @selected}
            class="multi-input-real"
            type="hidden"
            name={@name}
            value={value}
          />
        </div>

        <%!-- Add button + dropdown using daisyUI dropdown classes --%>
        <div
          :if={@available_options != []}
          class={[
            "dropdown dropdown-end",
            @dropdown_open && "dropdown-open"
          ]}
        >
          <.button
            type="button"
            tabindex="0"
            role="button"
            phx-click="toggle-dropdown"
            phx-target={@myself}
          >
            <.icon name="hero-plus" class="w-4 h-4" />
            <span class="hidden sm:inline">Add</span>
          </.button>

          <div
            id={"#{@id}-dropdown"}
            tabindex="-1"
            class="dropdown-content menu bg-base-100 rounded-box z-50 w-64 p-2 shadow-sm"
            phx-click-away="close-dropdown"
            phx-target={@myself}
          >
            <.dropdown_option
              :for={option <- @available_options}
              option={option}
              myself={@myself}
            />
          </div>
        </div>
      </div>

      <.input_errors field={@field} />
    </div>
    """
  end

  @impl true
  def handle_event("toggle-dropdown", _params, socket) do
    {:noreply, assign(socket, :dropdown_open, !socket.assigns.dropdown_open)}
  end

  @impl true
  def handle_event("close-dropdown", _params, socket) do
    {:noreply, assign(socket, :dropdown_open, false)}
  end

  @impl true
  def handle_event("add-option", %{"selected" => value}, socket) do
    new_selected = socket.assigns.selected ++ [to_string(value)]

    {:noreply,
     socket
     |> assign(:selected, new_selected)
     |> assign(:dropdown_open, false)
     |> push_event("multi_select_changed", %{id: socket.assigns.id})}
  end

  @impl true
  def handle_event("remove-option", %{"selected" => value}, socket) do
    # Normalize the incoming value to string for comparison
    value_str = to_string(value)
    new_selected = List.delete(socket.assigns.selected, value_str)

    {:noreply,
     socket
     |> assign(:selected, new_selected)
     |> push_event("multi_select_changed", %{id: socket.assigns.id})}
  end

  defp field_has_errors?(%Phoenix.HTML.FormField{errors: errors}), do: errors != []
  defp field_has_errors?(_), do: false

  # Private component abstractions

  attr :option, :map,
    required: true,
    doc: "The option map with value, label, icon, and variant"

  attr :myself, :any, required: true, doc: "The LiveComponent target"

  defp selected_option(assigns) do
    assigns = assign(assigns, :class, variant_class(assigns.option.variant))

    ~H"""
    <button
      type="button"
      class={[
        "inline-flex items-center gap-2 px-3 py-1.5 rounded-box text-sm font-medium cursor-pointer",
        @class
      ]}
      phx-click="remove-option"
      phx-value-selected={@option.value}
      phx-target={@myself}
    >
      <.icon name={@option.icon} class="w-4 h-4 shrink-0" />
      <span class="truncate max-w-[150px] sm:max-w-[200px]">{@option.label}</span>
      <.icon name="hero-x-mark" class="w-3.5 h-3.5 shrink-0" />
    </button>
    """
  end

  attr :option, :map, required: true, doc: "The option map with value, label, icon, and variant"
  attr :myself, :any, required: true, doc: "The LiveComponent target"

  defp dropdown_option(assigns) do
    assigns = assign(assigns, :class, variant_class(assigns.option.variant) <> "")

    ~H"""
    <li>
      <button
        type="button"
        class="group cursor-pointer"
        phx-click="add-option"
        phx-value-selected={@option.value}
        phx-target={@myself}
      >
        <div class={[
          "w-9 h-9 rounded-lg flex items-center justify-center shrink-0",
          @class
        ]}>
          <.icon
            name={@option.icon}
            class="w-5 h-5"
          />
        </div>

        <span>{@option.label}</span>

        <div class={[
          "w-6 h-6 rounded-full flex items-center justify-center",
          @class,
          "transition-all duration-150 group-hover:scale-115"
        ]}>
          <.icon
            name="hero-plus"
            class="w-3.5 h-3.5"
          />
        </div>
      </button>
    </li>
    """
  end

  defp variant_class(nil),
    do: "bg-base-200/10 text-base-200 border border-base-200/20"

  defp variant_class(:primary),
    do: "bg-primary/10 text-primary border border-primary/20"

  defp variant_class(:secondary),
    do: "bg-secondary/10 text-secondary border border-secondary/20"

  defp variant_class(:accent),
    do: "bg-accent/10 text-accent border border-accent/20"

  defp variant_class(:neutral),
    do: "bg-neutral/10 text-neutral border border-neutral/20"

  defp variant_class(:info),
    do: "bg-info/10 text-info border border-info/20"

  defp variant_class(:success),
    do: "bg-success/10 text-success border border-success/20"

  defp variant_class(:warning),
    do: "bg-warning/10 text-warning border border-warning/20"

  defp variant_class(:error),
    do: "bg-error/10 text-error border border-error/20"

  defp variant_class(_variant), do: variant_class(nil)
end
