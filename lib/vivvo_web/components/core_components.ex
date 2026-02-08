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
  use Phoenix.Component
  use Gettext, backend: VivvoWeb.Gettext

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

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

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
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

  @doc """
  Renders a status badge for contract status.

  ## Examples

      <.contract_status_badge status={:active} />
      <.contract_status_badge status={:upcoming} />
      <.contract_status_badge status={:expired} />
  """
  attr :status, :atom, required: true, values: [:upcoming, :active, :expired]

  def contract_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-x-1.5 rounded-md px-2 py-1 text-xs font-medium",
      @status == :upcoming && "bg-blue-50 text-blue-700 ring-1 ring-inset ring-blue-600/20",
      @status == :active && "bg-green-50 text-green-700 ring-1 ring-inset ring-green-600/20",
      @status == :expired && "bg-red-50 text-red-700 ring-1 ring-inset ring-red-600/20"
    ]}>
      <svg class="h-1.5 w-1.5 fill-current" viewBox="0 0 6 6" aria-hidden="true">
        <circle cx="3" cy="3" r="3" />
      </svg>
      {status_text(@status)}
    </span>
    """
  end

  defp status_text(:upcoming), do: "Upcoming"
  defp status_text(:active), do: "Active"
  defp status_text(:expired), do: "Expired"

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
        assigns.collection_rate >= 95 -> {"bg-success/10 text-success", "Excellent"}
        assigns.collection_rate >= 80 -> {"bg-info/10 text-info", "Good"}
        assigns.collection_rate >= 60 -> {"bg-warning/10 text-warning", "Fair"}
        true -> {"bg-error/10 text-error", "At Risk"}
      end

    assigns = assign(assigns, :color, color)
    assigns = assign(assigns, :label, label)

    ~H"""
    <span class={["px-2 py-1 rounded-full text-xs font-medium", @color]}>
      {@label}
    </span>
    """
  end

  @doc """
  Formats a monetary amount as USD currency.

  ## Examples

      iex> format_currency(Decimal.new("1234.56"))
      "$1,234.56"

      iex> format_currency(100)
      "$100.00"

      iex> format_currency(1234.56)
      "$1,234.56"
  """
  def format_currency(amount) when is_struct(amount, Decimal) do
    amount
    |> Decimal.to_float()
    |> format_currency()
  end

  def format_currency(amount) when is_float(amount) or is_integer(amount) do
    # Convert to float and format with 2 decimal places
    formatted = :erlang.float_to_binary(amount * 1.0, decimals: 2)

    # Add thousands separator
    [dollars, cents] = String.split(formatted, ".")

    dollars_with_commas =
      dollars
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join(&1, ""))
      |> String.reverse()

    "$#{dollars_with_commas}.#{cents}"
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
end
