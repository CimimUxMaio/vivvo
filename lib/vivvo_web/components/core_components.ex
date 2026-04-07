defmodule VivvoWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use VivvoWeb, :verified_routes
  use Phoenix.Component
  use Gettext, backend: VivvoWeb.Gettext

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  import VivvoWeb.FormatHelpers, only: [format_date: 1]

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    base_class = ["btn", Map.fetch!(variants, assigns[:variant])]

    assigns =
      assigns
      |> Map.update(:class, base_class, fn class ->
        [base_class, class]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders the Vivvo app icon with automatic theme switching.

  The icon automatically switches between light and dark theme versions
  based on the `data-theme` attribute on the document root.

  ## Examples

      <.app_icon class="w-12 h-12" />
  """
  attr :class, :string, default: "w-12 h-12", doc: "CSS classes for sizing"

  def app_icon(assigns) do
    ~H"""
    <img
      src={~p"/images/vivvo_icon_light.svg"}
      class={[
        @class,
        "[[data-theme=dark]_&]:hidden [@media(prefers-color-scheme:dark)]:[[data-theme=system]_&]:hidden"
      ]}
      alt="Vivvo"
    />
    <img
      src={~p"/images/vivvo_icon_dark.svg"}
      class={[
        @class,
        "hidden [[data-theme=dark]_&]:block [@media(prefers-color-scheme:dark)]:[[data-theme=system]_&]:block"
      ]}
      alt="Vivvo"
    />
    """
  end

  @doc """
  Renders the Vivvo full logo (icon + wordmark) with automatic theme switching.

  The logo automatically switches between light and dark theme versions
  based on the `data-theme` attribute on the document root.

  ## Examples

      <.app_logo class="h-8" />
  """
  attr :class, :string, default: "h-8", doc: "CSS classes for sizing (typically height)"

  def app_logo(assigns) do
    ~H"""
    <img
      src={~p"/images/vivvo_logo_light.svg"}
      class={[
        @class,
        "[[data-theme=dark]_&]:hidden [@media(prefers-color-scheme:dark)]:[[data-theme=system]_&]:hidden"
      ]}
      alt="Vivvo"
    />
    <img
      src={~p"/images/vivvo_logo_dark.svg"}
      class={[
        @class,
        "hidden [[data-theme=dark]_&]:block [@media(prefers-color-scheme:dark)]:[[data-theme=system]_&]:block"
      ]}
      alt="Vivvo"
    />
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  # When no field is provided, ensure value has a default and mark field as processed
  def input(assigns) when not is_map_key(assigns, :field) do
    assigns
    |> assign(:field, nil)
    |> assign_new(:value, fn -> nil end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.input_errors errors={@errors} />
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.input_errors errors={@errors} />
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.input_errors errors={@errors} />
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.input_errors errors={@errors} />
    </div>
    """
  end

  @doc """
  Renders form error messages with consistent styling.

  ## Examples

      <.input_errors errors={@errors} />
      <.input_errors field={@form[:email]} />
  """
  attr :field, Phoenix.HTML.FormField, required: false, doc: "a form field struct"
  attr :errors, :list, default: [], doc: "list of error message strings"
  attr :class, :string, default: nil, doc: "additional CSS classes"

  def input_errors(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign(:field, nil)
    |> input_errors()
  end

  def input_errors(%{errors: errors} = assigns) when is_list(errors) do
    ~H"""
    <p :for={msg <- @errors} class={["mt-1.5 flex gap-2 items-center text-sm text-error", @class]}>
      <.icon name="hero-exclamation-circle" class="size-5" />
      {msg}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a page header with title, optional back button, subtitle, and action buttons.

  ## Examples

      <.page_header title="Properties" back_navigate={~p"/properties"}>
        <:subtitle>Manage your rental properties</:subtitle>
        <:action>
          <.button variant="primary" navigate={~p"/properties/new"}>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Property
          </.button>
        </:action>
      </.page_header>

      <.page_header title="Edit Property" back_navigate={~p"/properties"}>
        <:subtitle>Update your property details</:subtitle>
      </.page_header>
  """
  attr :title, :string, required: true, doc: "the page title"
  attr :back_navigate, :any, default: nil, doc: "navigate path for back button (optional)"
  slot :subtitle, doc: "optional subtitle or description"
  slot :action, doc: "action buttons displayed on the right side"

  def page_header(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
      <div class="flex items-center gap-4">
        <%= if @back_navigate do %>
          <.link
            navigate={@back_navigate}
            class="flex items-center justify-center w-10 h-10 rounded-xl bg-base-100 border border-base-200 text-base-content/60 hover:text-primary hover:border-primary/30 transition-all"
            aria-label="Back"
          >
            <.icon name="hero-arrow-left" class="w-5 h-5" />
          </.link>
        <% end %>
        <div>
          <h1 class="text-2xl sm:text-3xl font-bold text-base-content">{@title}</h1>
          <%= if @subtitle != [] do %>
            <p class="text-sm text-base-content/60 mt-1">
              {render_slot(@subtitle)}
            </p>
          <% end %>
        </div>
      </div>
      <%= if @action != [] do %>
        <div class="flex items-center gap-3">
          <%= for action <- @action do %>
            {render_slot(action)}
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @contract_status_config %{
    upcoming: {"hero-clock", "bg-info/10 text-info border-info/20", "Upcoming"},
    active: {"hero-check-circle", "bg-success/10 text-success border-success/20", "Active"},
    expired: {"hero-x-circle", "bg-error/10 text-error border-error/20", "Expired"}
  }

  @size_config %{
    sm: %{classes: "px-2 py-0.5 text-xs gap-1", icon: "w-3 h-3"},
    md: %{classes: "px-2.5 py-1 text-xs sm:text-sm gap-1.5", icon: "w-3.5 h-3.5 sm:w-4 sm:h-4"},
    lg: %{classes: "px-3 py-1.5 text-sm gap-2", icon: "w-4 h-4 sm:w-5 sm:h-5"}
  }

  @doc """
  Renders a badge for contract status.

  ## Examples

      <.contract_status_badge status={:active} />
      <.contract_status_badge status={:upcoming} />
      <.contract_status_badge status={:expired} />
  """
  attr :status, :atom, required: true, values: [:upcoming, :active, :expired]
  attr :size, :atom, default: :md, values: [:sm, :md, :lg]

  def contract_status_badge(assigns) do
    {icon_name, color_class, label} = Map.get(@contract_status_config, assigns.status)
    size_config = Map.get(@size_config, assigns.size)

    assigns =
      assign(assigns,
        icon_name: icon_name,
        color_class: color_class,
        label: label,
        size_classes: size_config.classes,
        icon_size: size_config.icon
      )

    ~H"""
    <span class={[
      "inline-flex items-center rounded-full font-medium border transition-all duration-200",
      "hover:shadow-sm hover:scale-[1.02]",
      @color_class,
      @size_classes
    ]}>
      <.icon name={@icon_name} class={[@icon_size, "flex-shrink-0"]} />
      <span class="whitespace-nowrap cursor-default">{@label}</span>
    </span>
    """
  end

  @doc """
  Renders a badge for payment status in tenant dashboard context.

  ## Examples

      <.payment_status_badge status={:paid} />
      <.payment_status_badge status={:on_time} />
      <.payment_status_badge status={:overdue} />
      <.payment_status_badge status={:upcoming} />
      <.payment_status_badge status={nil} />
  """
  attr :status, :atom, required: false, values: [:paid, :on_time, :overdue, :upcoming, nil]

  def payment_status_badge(%{status: nil} = assigns) do
    ~H"""
    <span class="px-2 py-1 bg-base-200 rounded-full text-xs font-medium">No Contract</span>
    """
  end

  def payment_status_badge(assigns) do
    colors = %{
      paid: "bg-success/10 text-success",
      on_time: "bg-info/10 text-info",
      overdue: "bg-error/10 text-error",
      upcoming: "bg-base-200 text-base-content"
    }

    labels = %{
      paid: "Paid Up",
      on_time: "On Time",
      overdue: "Overdue",
      upcoming: "Upcoming"
    }

    assigns =
      assign(assigns,
        color: Map.get(colors, assigns.status, "bg-base-200"),
        label: Map.get(labels, assigns.status, "Unknown")
      )

    ~H"""
    <span class={["px-3 py-1 rounded-full text-xs font-medium", @color]}>
      {@label}
    </span>
    """
  end

  @doc """
  Renders a badge for month payment status.

  ## Examples

      <.month_status_badge status={:paid} />
      <.month_status_badge status={:partial} />
      <.month_status_badge status={:unpaid} />
  """
  attr :status, :atom, required: true, values: [:paid, :partial, :unpaid]

  def month_status_badge(assigns) do
    colors = %{
      paid: "bg-success/10 text-success",
      partial: "bg-warning/10 text-warning",
      unpaid: "bg-base-200 text-base-content"
    }

    labels = %{
      paid: "Paid",
      partial: "Partial",
      unpaid: "Unpaid"
    }

    assigns =
      assign(assigns,
        color: Map.get(colors, assigns.status, "bg-base-200"),
        label: Map.get(labels, assigns.status, "Unknown")
      )

    ~H"""
    <span class={["px-2 py-0.5 rounded text-xs font-medium", @color]}>
      {@label}
    </span>
    """
  end

  @doc """
  Renders a badge for payment submission status.

  ## Examples

      <.payment_badge status={:pending} />
      <.payment_badge status={:accepted} />
      <.payment_badge status={:rejected} />
  """
  attr :status, :atom, required: true, values: [:pending, :accepted, :rejected]
  attr :size, :atom, default: :md, values: [:sm, :md]

  def payment_badge(assigns) do
    colors = %{
      pending: "bg-warning/10 text-warning",
      accepted: "bg-success/10 text-success",
      rejected: "bg-error/10 text-error"
    }

    labels = %{
      pending: "Pending",
      accepted: "Accepted",
      rejected: "Rejected"
    }

    size_classes = %{
      sm: "px-2 py-0.5 text-xs",
      md: "px-3 py-1 text-xs"
    }

    assigns =
      assign(assigns,
        color: Map.get(colors, assigns.status, "bg-base-200"),
        label: Map.get(labels, assigns.status, "Unknown"),
        size_class: Map.get(size_classes, assigns.size, "px-2 py-0.5 text-xs")
      )

    ~H"""
    <span class={["rounded font-medium", @color, @size_class]}>
      {@label}
    </span>
    """
  end

  @doc """
  Renders a badge for property collection performance status.

  ## Examples

      <.property_status_badge collection_rate={95.0} />
      <.property_status_badge collection_rate={75.0} />
      <.property_status_badge collection_rate={45.0} />
  """
  attr :collection_rate, :float, required: true

  def property_status_badge(assigns) do
    {color, label} =
      cond do
        assigns.collection_rate >= 100 -> {"bg-success/10 text-success", "Excellent"}
        assigns.collection_rate >= 90 -> {"bg-info/10 text-info", "Good"}
        assigns.collection_rate >= 80 -> {"bg-warning/10 text-warning", "Fair"}
        true -> {"bg-error/10 text-error", "At Risk"}
      end

    assigns = assign(assigns, :color, color)
    assigns = assign(assigns, :label, label)

    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-1 rounded-full text-xs font-medium whitespace-nowrap",
      @color
    ]}>
      {@label}
    </span>
    """
  end

  @doc """
  Renders a modal for rejecting an item with a reason.

  ## Examples

      <.reject_modal
        id="reject-payment-modal"
        title="Reject Payment"
        description="Please provide a reason for rejecting this payment."
        submit_event="reject_payment"
        close_event="close_reject_modal"
        reason_label="Rejection Reason"
        reason_placeholder="Enter rejection reason..."
        submit_text="Reject Payment"
      />
  """
  attr :id, :string, required: true, doc: "the DOM id for the modal"
  attr :title, :string, required: true, doc: "the modal title"
  attr :description, :string, required: true, doc: "description text explaining the action"
  attr :submit_event, :string, required: true, doc: "the phx-submit event name"
  attr :close_event, :string, required: true, doc: "the phx-click event name to close modal"
  attr :reason_label, :string, default: "Reason", doc: "label for the reason textarea"

  attr :reason_placeholder, :string,
    default: "Enter reason...",
    doc: "placeholder for the textarea"

  attr :submit_text, :string, default: "Reject", doc: "text for the submit button"
  attr :cancel_text, :string, default: "Cancel", doc: "text for the cancel button"

  def reject_modal(assigns) do
    ~H"""
    <div id={@id} class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div class="card bg-base-100 w-full max-w-md shadow-2xl">
        <div class="card-body">
          <h3 class="card-title text-lg">{@title}</h3>
          <p class="text-base-content/70 mb-4">
            {@description}
          </p>

          <form phx-submit={@submit_event} id={"#{@id}-form"}>
            <.input
              type="textarea"
              name="rejection-reason"
              rows="3"
              placeholder={@reason_placeholder}
              required
              label={@reason_label}
            />

            <div class="card-actions justify-end gap-3 mt-4">
              <button
                type="button"
                phx-click={@close_event}
                class="btn btn-ghost"
              >
                {@cancel_text}
              </button>
              <button
                type="submit"
                class="btn btn-error"
                phx-disable-with="Rejecting..."
              >
                {@submit_text}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a sliding selector control with animated background indicator.

  The indicator position and active styling are computed server-side from
  the `value` attr.

  ## Examples

      <.sliding_selector value={@active_method} on_select="switch_method">
        <:option value="magic">Magic Link</:option>
        <:option value="password">Password</:option>
      </.sliding_selector>
  """
  attr :id, :string, default: nil, doc: "the optional id of the selector container"
  attr :value, :string, required: true, doc: "the currently selected option value"
  attr :on_select, :any, required: true, doc: "phx-click event name or JS command for selection"
  attr :class, :string, default: "bg-base-200 rounded-xl", doc: "container CSS classes"

  slot :option, required: true do
    attr :value, :string, required: true, doc: "the option value"
  end

  def sliding_selector(assigns) do
    count = length(assigns.option)
    active_index = Enum.find_index(assigns.option, &(&1.value == assigns.value)) || 0

    option_width = 100.0 / count
    indicator_left = option_width * active_index

    assigns =
      assign(assigns,
        option_width: option_width,
        indicator_left: indicator_left
      )

    ~H"""
    <div id={@id} class={["flex p-1 relative", @class]} data-selected={@value}>
      <%!-- Sliding background indicator --%>
      <div
        class="absolute h-[calc(100%-0.5rem)] bg-base-100 rounded-lg shadow-sm transition-all duration-300 ease-out top-1"
        style={"width: calc(#{@option_width}% - 0.5rem); left: calc(#{@indicator_left}% + 0.25rem);"}
      />

      <%= for option <- @option do %>
        <button
          type="button"
          phx-click={@on_select}
          phx-value-selected={option.value}
          class={[
            "flex-1 relative z-10 py-2.5 px-4 text-sm font-medium rounded-lg transition-colors duration-200 cursor-pointer",
            "flex items-center justify-center gap-2",
            @value == option.value && "text-primary",
            @value != option.value && "text-base-content/60 hover:text-base-content"
          ]}
        >
          {render_slot(option)}
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a vertical timeline container with connected timeline items.

  Each `timeline_item` slot displays a status node connected by a vertical line,
  with customizable content rendered inside the slot body. Timeline items can only
  be used within this container, enforcing consistent structure.

  ## Status Values

    - `:success` - Completed or active items (green styling)
    - `:info` - Upcoming or in-progress items (blue styling)
    - `:warning` - Items requiring attention (yellow/amber styling)
    - `:error` - Failed or rejected items (red styling)
    - `:base` - Neutral or inactive items (gray styling)

  ## Examples

      <.timeline_container>
        <:timeline_item :for={contract <- @contracts} status={:success} icon="hero-check" label="Active">
          <div>Contract card content here</div>
        </:timeline_item>
      </.timeline_container>

      <.timeline_container>
        <:timeline_item status={:info} icon="hero-clock" label="Pending">
          <div>Payment details here</div>
        </:timeline_item>
      </.timeline_container>
  """
  attr :id, :string, default: nil, doc: "optional DOM id for the container"

  attr :class, :string, default: nil, doc: "additional CSS classes for the container"

  attr :gap, :atom,
    default: :md,
    values: [:sm, :md, :lg],
    doc: "spacing between timeline items (sm: space-y-4, md: space-y-6, lg: space-y-8)"

  slot :timeline_item, required: true, doc: "a timeline item with status node and content" do
    attr :status, :atom, required: true, values: [:success, :info, :warning, :error, :base]
    attr :icon, :string, required: true
    attr :label, :string
  end

  def timeline_container(assigns) do
    gap_classes = %{
      sm: "space-y-4",
      md: "space-y-6",
      lg: "space-y-8"
    }

    assigns = assign(assigns, :gap_class, Map.fetch!(gap_classes, assigns.gap))

    ~H"""
    <div id={@id} class={["relative rounded-xl p-4", @class]}>
      <%!-- Vertical Timeline Line --%>
      <div class="absolute left-9 top-4 bottom-2 w-0.5 bg-base-300"></div>

      <div class={@gap_class}>
        <div :for={item <- @timeline_item} class="relative flex gap-4">
          <%!-- Timeline Node --%>
          <div class="relative flex-shrink-0">
            <div
              class={[
                "w-10 h-10 rounded-full flex items-center justify-center border-2",
                "bg-base-100 z-10 relative",
                item.status == :success && "border-success text-success",
                item.status == :info && "border-info text-info",
                item.status == :warning && "border-warning text-warning",
                item.status == :error && "border-error text-error",
                item.status == :base && "border-base-400 text-base-content/50"
              ]}
              aria-label={item[:label]}
            >
              <.icon name={item.icon} class="w-5 h-5" />
            </div>
          </div>

          <%!-- Content with Card Styling --%>
          <div class="flex-1 min-w-0">
            <div class="bg-base-100 rounded-xl p-4 shadow-sm border border-base-200 hover:shadow-md transition-shadow">
              {render_slot(item)}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(VivvoWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(VivvoWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  # ============================================================================
  # Contract Components
  # ============================================================================

  alias Vivvo.Contracts
  alias VivvoWeb.Helpers.ContractHelpers

  @doc """
  Renders a contract progress bar showing progress through the contract period.

  ## Examples

      <.contract_progress_bar contract={@contract} />
      <.contract_progress_bar contract={@contract} compact />
      <.contract_progress_bar contract={@contract} show_title={false} />
  """
  attr :contract, :any, required: true
  attr :compact, :boolean, default: false, doc: "Whether to render in compact mode (smaller)"
  attr :show_title, :boolean, default: true, doc: "Whether to show the 'Contract Journey' title"
  attr :show_status_badge, :boolean, default: true, doc: "Whether to show the status badge"
  attr :class, :string, default: nil, doc: "Additional CSS classes"

  def contract_progress_bar(assigns) do
    contract = assigns.contract
    today = Date.utc_today()

    progress = ContractHelpers.calculate_contract_progress(contract, today)
    today_marker = ContractHelpers.calculate_today_marker(contract, today)
    timeline_data = ContractHelpers.calculate_timeline_data(contract, today)

    assigns =
      assign(assigns,
        progress: progress,
        today_marker: today_marker,
        days_until_start: timeline_data.days_until_start,
        current_month: timeline_data.current_month,
        total_months: timeline_data.total_months,
        today: today
      )

    ~H"""
    <div class={["space-y-4", @class]}>
      <%= if @show_title do %>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <div class="p-1.5 bg-primary/10 rounded-lg flex items-center justify-center">
              <.icon
                name="hero-map"
                class={[@compact && "w-4 h-4", not @compact && "w-5 h-5", "text-primary"]}
              />
            </div>
            <span class={[
              @compact && "text-sm",
              not @compact && "text-lg font-semibold",
              "text-base-content"
            ]}>
              Contract Journey
            </span>
          </div>
          <div class="flex items-center gap-2">
            <%= if @show_status_badge do %>
              <.contract_status_badge
                status={Contracts.contract_status(@contract)}
                size={if @compact, do: :sm, else: :md}
              />
            <% end %>
            <span class="text-sm font-medium px-3 py-1 rounded-full bg-info/10 text-info">
              {@progress}%
            </span>
          </div>
        </div>
      <% end %>

      <.progress_track progress={@progress} today_marker={@today_marker} />

      <.progress_labels
        contract={@contract}
        days_until_start={@days_until_start}
        current_month={@current_month}
        total_months={@total_months}
      />
    </div>
    """
  end

  @doc """
  Renders a progress track with optional today marker.

  ## Examples

      <.progress_track progress={75} color="bg-primary" today_marker={80} />
  """
  attr :progress, :integer, required: true
  attr :color, :string, required: false, default: "bg-primary"
  attr :today_marker, :integer, required: false, default: nil

  def progress_track(assigns) do
    ~H"""
    <div class="relative h-3">
      <%!-- Background Track --%>
      <div class="h-3 bg-base-200 rounded-full overflow-hidden">
        <%!-- Progress Fill --%>
        <div
          class={["h-full rounded-full transition-all duration-1000 ease-out", @color]}
          style={"width: #{@progress}%"}
        >
        </div>
      </div>

      <%!-- Today Marker --%>
      <%= if @today_marker do %>
        <div
          class="absolute top-0 w-5 h-5 bg-white rounded-full shadow-lg border-2 border-primary flex items-center justify-center -mt-1"
          style={"left: calc(#{@today_marker}% - 10px)"}
          title="Today"
        >
          <div class="w-2 h-2 bg-primary rounded-full"></div>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders progress labels showing start date, current position, and end date.

  ## Examples

      <.progress_labels contract={@contract} days_until_start={0} current_month={5} total_months={12} />
  """
  attr :contract, :any, required: true
  attr :days_until_start, :integer, required: true
  attr :current_month, :integer, required: true
  attr :total_months, :integer, required: true

  def progress_labels(assigns) do
    ~H"""
    <div class="flex items-center justify-between text-xs text-base-content/50">
      <span>{format_date(@contract.start_date)}</span>

      <span>
        <%= if @days_until_start > 0 do %>
          Starts in {@days_until_start} days
        <% else %>
          <%= if @current_month == 0 do %>
            Not started
          <% else %>
            Month {@current_month} of {@total_months}
          <% end %>
        <% end %>
      </span>

      <span>{format_date(@contract.end_date)}</span>
    </div>
    """
  end

  @doc """
  Renders the "Next Rent Update" field showing when the next rent update is scheduled.

  ## Examples

      <.next_rent_update_field contract={@contract} />
  """
  attr :contract, :any, required: true

  def next_rent_update_field(assigns) do
    next_update = Contracts.next_rent_update_date(assigns.contract)
    days_until = Contracts.days_until_next_update(assigns.contract)

    assigns =
      assigns
      |> assign(:next_update, next_update)
      |> assign(:days_until, days_until)

    ~H"""
    <div class="space-y-2">
      <label class="text-sm font-medium text-base-content/60">Next Rent Update</label>
      <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
        <.icon name="hero-calendar" class="w-5 h-5 text-base-content/50" />
        <div>
          <%= if @next_update do %>
            <p class="font-medium text-base-content">{format_date(@next_update)}</p>
            <p class="text-xs mt-0.5">
              <%= cond do %>
                <% @days_until == 0 -> %>
                  <span class="text-warning font-medium">Today</span>
                <% @days_until < 0 -> %>
                  <span class="text-error">Update overdue</span>
                <% @days_until <= 30 -> %>
                  <span class="text-warning">In {@days_until} days</span>
                <% true -> %>
                  <span class="text-base-content/50">In {@days_until} days</span>
              <% end %>
            </p>
          <% else %>
            <span class="font-medium text-base-content/50">-</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
