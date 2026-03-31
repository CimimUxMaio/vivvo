defmodule VivvoWeb.ContractLive.Show do
  @moduledoc """
  LiveView for displaying contract details with a visual timeline/journey design.

  Presents the contract as a visual journey through its lifecycle, featuring:
  - A horizontal progress bar showing the contract period from start to end
  - Visual milestone indicators for key contract events
  - Timeline cards for Property, Parties, Terms, and Financial information
  - Visual indicators for rent periods and indexing updates
  """
  use VivvoWeb, :live_view

  import VivvoWeb.Helpers.ContractHelpers

  alias Vivvo.Contracts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6 sm:space-y-8">
        <%!-- Page Header with Back Navigation --%>
        <.page_header title="Contract Details" back_navigate={@back_path}>
          <:subtitle>
            {@property.name} — {format_contract_period(@contract)}
          </:subtitle>
        </.page_header>

        <%!-- Main Two-Column Layout --%>
        <div class="grid grid-cols-1 lg:grid-cols-5 gap-6">
          <%!-- LEFT: Contract Journey/Timeline (60-70% on desktop) --%>
          <div class="lg:col-span-3 space-y-6">
            <%!-- Contract Progress Bar --%>
            <.contract_progress_bar contract={@contract} progress={@progress} today={@today} />

            <%!-- Timeline Container with Journey Sections --%>
            <.contract_timeline
              contract={@contract}
              property={@property}
              current_rent={@current_rent}
              next_update={@next_update}
              days_until={@days_until}
              today={@today}
            />
          </div>

          <%!-- RIGHT: Graph Container (30-40% on desktop) --%>
          <div class="lg:col-span-2">
            <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-6 lg:sticky lg:top-24">
              <div class="flex items-center gap-2 mb-4">
                <div class="p-1.5 bg-primary/10 rounded-lg flex items-center justify-center">
                  <.icon name="hero-chart-bar" class="w-5 h-5 text-primary" />
                </div>
                <h3 class="text-lg font-semibold text-base-content">Rent Value Over Time</h3>
              </div>
              <div class="aspect-video">
                <canvas
                  id="rent-chart"
                  phx-hook="SteppedLineChart"
                  data-chart-labels={@chart_labels_json}
                  data-chart-values={@chart_values_json}
                  data-chart-min={@chart_min_value}
                  data-chart-max={@chart_max_value}
                  class="w-full h-full"
                >
                </canvas>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Contract Timeline Component
  # ============================================================================

  defp contract_timeline(assigns) do
    ~H"""
    <.timeline_container class="bg-base-200 shadow-md">
      <:timeline_item status={:success} icon="hero-building-office" label="Property">
        <.property_timeline_card property={@property} />
      </:timeline_item>

      <:timeline_item status={:info} icon="hero-users" label="Parties">
        <.parties_timeline_card contract={@contract} />
      </:timeline_item>

      <:timeline_item status={:info} icon="hero-document-text" label="Terms">
        <.terms_timeline_card contract={@contract} />
      </:timeline_item>

      <:timeline_item status={:success} icon="hero-banknotes" label="Financials">
        <.financials_timeline_card contract={@contract} current_rent={@current_rent} />
      </:timeline_item>

      <:timeline_item
        :if={@contract.index_type}
        status={:warning}
        icon="hero-arrow-path"
        label="Rent Updates"
      >
        <.rent_periods_timeline_card
          contract={@contract}
          rent_periods={@contract.rent_periods}
          next_update={@next_update}
          days_until={@days_until}
        />
      </:timeline_item>

      <:timeline_item
        :if={@contract.notes && @contract.notes != ""}
        status={:info}
        icon="hero-document-text"
        label="Notes"
      >
        <.notes_timeline_card notes={@contract.notes} />
      </:timeline_item>
    </.timeline_container>
    """
  end

  # ============================================================================
  # Timeline Card Components
  # ============================================================================

  # Property card showing property details in the timeline
  defp property_timeline_card(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex items-start justify-between gap-3">
        <div>
          <h4 class="font-semibold text-base-content">{@property.name}</h4>
          <p class="text-sm text-base-content/60">{@property.address}</p>
        </div>
        <.link
          navigate={~p"/properties/#{@property.id}"}
          class="btn btn-ghost btn-xs text-primary"
        >
          <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
        </.link>
      </div>

      <div class="flex flex-wrap gap-2">
        <%= if @property.area do %>
          <span class="inline-flex items-center gap-1 px-2 py-1 bg-base-200 rounded-full text-xs">
            <.icon name="hero-square-3-stack-3d" class="w-3.5 h-3.5" />
            {@property.area} m²
          </span>
        <% end %>
        <%= if @property.rooms do %>
          <span class="inline-flex items-center gap-1 px-2 py-1 bg-base-200 rounded-full text-xs">
            <.icon name="hero-home" class="w-3.5 h-3.5" />
            {@property.rooms} rooms
          </span>
        <% end %>
      </div>
    </div>
    """
  end

  # Parties card showing tenant and owner information
  defp parties_timeline_card(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <%!-- Tenant --%>
      <div class="space-y-2">
        <p class="text-xs font-medium text-base-content/50 uppercase tracking-wide">Tenant</p>
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-full bg-info/10 flex items-center justify-center flex-shrink-0">
            <span class="text-sm font-bold text-info">
              {String.first(@contract.tenant.first_name)}{String.first(@contract.tenant.last_name)}
            </span>
          </div>
          <div class="min-w-0">
            <p class="font-medium text-sm truncate">
              {@contract.tenant.first_name} {@contract.tenant.last_name}
            </p>
            <p class="text-xs text-base-content/60 truncate">
              {@contract.tenant.email}
            </p>
          </div>
        </div>
      </div>

      <%!-- Owner --%>
      <div class="space-y-2">
        <p class="text-xs font-medium text-base-content/50 uppercase tracking-wide">Owner</p>
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
            <span class="text-sm font-bold text-primary">
              {String.first(@contract.user.first_name)}{String.first(@contract.user.last_name)}
            </span>
          </div>
          <div class="min-w-0">
            <p class="font-medium text-sm truncate">
              {@contract.user.first_name} {@contract.user.last_name}
            </p>
            <p class="text-xs text-base-content/60 truncate">
              {@contract.user.email}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Terms card showing contract dates and payment terms
  defp terms_timeline_card(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-1">
        <p class="text-xs text-base-content/50">Start Date</p>
        <div class="flex items-center gap-2">
          <.icon name="hero-calendar" class="w-4 h-4 text-success" />
          <span class="font-medium text-sm">{format_date(@contract.start_date)}</span>
        </div>
      </div>

      <div class="space-y-1">
        <p class="text-xs text-base-content/50">End Date</p>
        <div class="flex items-center gap-2">
          <.icon name="hero-calendar" class="w-4 h-4 text-error" />
          <span class="font-medium text-sm">{format_date(@contract.end_date)}</span>
        </div>
      </div>

      <div class="space-y-1">
        <p class="text-xs text-base-content/50">Duration</p>
        <div class="flex items-center gap-2">
          <.icon name="hero-clock" class="w-4 h-4 text-base-content/50" />
          <span class="font-medium text-sm">
            {format_duration(@contract.start_date, @contract.end_date)}
          </span>
        </div>
      </div>

      <div class="space-y-1">
        <p class="text-xs text-base-content/50">Payment Due</p>
        <div class="flex items-center gap-2">
          <.icon name="hero-calendar-days" class="w-4 h-4 text-base-content/50" />
          <span class="font-medium text-sm">Day {@contract.expiration_day} of month</span>
        </div>
      </div>
    </div>
    """
  end

  # Financials card showing rent and indexing information
  defp financials_timeline_card(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Current Rent --%>
      <div class="flex items-center justify-between p-3 bg-success/5 rounded-xl border border-success/10">
        <div class="flex items-center gap-3">
          <div class="p-2 bg-success/10 rounded-lg flex items-center justify-center">
            <.icon name="hero-banknotes" class="w-5 h-5 text-success" />
          </div>
          <div>
            <p class="text-xs text-base-content/50">Current Monthly Rent</p>
            <p class="text-xl font-bold text-success">{format_currency(@current_rent)}</p>
          </div>
        </div>
        <%= if @contract.index_type do %>
          <span class="inline-flex items-center gap-1 px-2 py-1 bg-info/10 text-info rounded-full text-xs font-medium">
            <.icon name="hero-arrow-trending-up" class="w-3 h-3" /> Indexed
          </span>
        <% end %>
      </div>

      <%!-- Indexing Information (if applicable) --%>
      <%= if @contract.index_type do %>
        <div class="grid grid-cols-2 gap-3">
          <div class="space-y-1">
            <p class="text-xs text-base-content/50">Index Type</p>
            <div class="flex items-center gap-2">
              <.icon name="hero-arrow-trending-up" class="w-4 h-4 text-info" />
              <span class="font-medium text-sm">{index_type_label(@contract.index_type)}</span>
            </div>
          </div>

          <div class="space-y-1">
            <p class="text-xs text-base-content/50">Update Frequency</p>
            <div class="flex items-center gap-2">
              <.icon name="hero-arrow-path" class="w-4 h-4 text-base-content/50" />
              <span class="font-medium text-sm">
                {rent_period_duration_label(@contract.rent_period_duration)}
              </span>
            </div>
          </div>
        </div>
      <% else %>
        <div class="p-3 bg-base-200/50 rounded-xl">
          <div class="flex items-center gap-2">
            <.icon name="hero-information-circle" class="w-4 h-4 text-base-content/50" />
            <p class="text-sm text-base-content/60">Fixed rent (no indexing)</p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Rent periods card showing milestone updates
  defp rent_periods_timeline_card(assigns) do
    sorted_periods = Enum.sort_by(assigns.rent_periods, & &1.start_date)
    assigns = assign(assigns, :sorted_periods, sorted_periods)

    ~H"""
    <div class="space-y-4">
      <%!-- Next Update Info --%>
      <%= if @next_update do %>
        <div class="flex items-center justify-between p-3 bg-warning/5 rounded-xl border border-warning/10">
          <div class="flex items-center gap-3">
            <div class="p-2 bg-warning/10 rounded-lg flex items-center justify-center">
              <.icon name="hero-bell" class="w-5 h-5 text-warning" />
            </div>
            <div>
              <p class="text-xs text-base-content/50">Next Rent Update</p>
              <p class="font-semibold text-sm">{format_date(@next_update)}</p>
            </div>
          </div>
          <div class="text-right">
            <%= cond do %>
              <% @days_until == 0 -> %>
                <span class="text-warning font-bold text-sm">Today</span>
              <% @days_until < 0 -> %>
                <span class="text-error text-sm">Overdue</span>
              <% @days_until <= 30 -> %>
                <span class="text-warning text-sm">In {@days_until} days</span>
              <% true -> %>
                <span class="text-base-content/50 text-sm">In {@days_until} days</span>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Rent Period Milestones --%>
      <%= if @sorted_periods != [] do %>
        <div class="space-y-2">
          <p class="text-xs font-medium text-base-content/50 uppercase tracking-wide">Rent History</p>
          <div class="space-y-2 max-h-[280px] overflow-y-auto pr-1">
            <%= for {period, index} <- Enum.with_index(@sorted_periods) do %>
              <div class="flex items-center gap-3 p-2 rounded-lg hover:bg-base-200/50 transition-colors">
                <div class={[
                  "w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0",
                  index == 0 && "bg-success/10 text-success",
                  index > 0 && "bg-base-200 text-base-content/60"
                ]}>
                  {index + 1}
                </div>
                <div class="flex-1 min-w-0">
                  <div class="flex items-center justify-between">
                    <span class="font-medium text-sm truncate">
                      {format_currency(period.value)}
                    </span>
                    <span class="text-xs text-base-content/50">
                      {format_date(period.start_date)}
                    </span>
                  </div>
                  <div class="text-xs text-base-content/40">
                    Until {format_date(period.end_date)}
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Notes card showing contract notes in the timeline
  defp notes_timeline_card(assigns) do
    ~H"""
    <div class="space-y-2">
      <p class="text-sm text-base-content/80 whitespace-pre-wrap">
        {@notes}
      </p>
    </div>
    """
  end

  # ============================================================================
  # Progress Bar Component
  # ============================================================================

  defp contract_progress_bar(assigns) do
    today_marker = calculate_today_marker(assigns.contract, assigns.today)

    assigns =
      assigns
      |> assign(:today_marker, today_marker)

    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-6">
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-2">
          <div class="p-1.5 bg-primary/10 rounded-lg flex items-center justify-center">
            <.icon name="hero-map" class="w-5 h-5 text-primary" />
          </div>
          <h3 class="text-lg font-semibold text-base-content">Contract Journey</h3>
        </div>
        <div class="flex items-center gap-2">
          <.contract_status_badge status={Contracts.contract_status(@contract)} />
          <span class="text-sm font-medium px-3 py-1 rounded-full bg-info/10 text-info">
            {@progress}%
          </span>
        </div>
      </div>

      <%!-- Progress Track with Today Marker --%>
      <div class="relative h-3">
        <%!-- Background Track --%>
        <div class="h-3 bg-base-200 rounded-full overflow-hidden">
          <%!-- Progress Fill --%>
          <div
            class="h-full rounded-full transition-all duration-1000 ease-out bg-primary"
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

      <%!-- Start and End Labels --%>
      <div class="flex justify-between mt-3 text-xs text-base-content/50">
        <div class="flex items-center gap-1">
          <span>{format_date(@contract.start_date)}</span>
        </div>
        <div class="flex items-center gap-1">
          <span>{format_date(@contract.end_date)}</span>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Format contract period for subtitle
  defp format_contract_period(contract) do
    "#{format_date(contract.start_date)} — #{format_date(contract.end_date)}"
  end

  # Calculate contract progress percentage
  defp calculate_contract_progress(contract, today) do
    total_days = Date.diff(contract.end_date, contract.start_date)
    elapsed_days = Date.diff(today, contract.start_date)

    cond do
      Date.compare(today, contract.start_date) == :lt -> 0
      Date.compare(today, contract.end_date) == :gt -> 100
      total_days == 0 -> 100
      true -> round(elapsed_days / total_days * 100)
    end
  end

  # Calculate today's position on the progress bar
  defp calculate_today_marker(contract, today) do
    total_days = Date.diff(contract.end_date, contract.start_date)
    elapsed_days = Date.diff(today, contract.start_date)

    cond do
      Date.compare(today, contract.start_date) == :lt -> nil
      Date.compare(today, contract.end_date) == :gt -> nil
      total_days == 0 -> nil
      true -> round(elapsed_days / total_days * 100)
    end
  end

  # ============================================================================
  # Lifecycle Callbacks
  # ============================================================================

  @impl true
  def mount(
        %{"property_id" => property_id, "contract_id" => contract_id} = params,
        _session,
        socket
      ) do
    scope = socket.assigns.current_scope
    today = Date.utc_today()

    contract =
      Contracts.get_contract!(scope, contract_id)
      |> Vivvo.Repo.preload([:tenant, :property, :user, :rent_periods])

    # Verify the contract belongs to this property
    if contract.property_id != String.to_integer(property_id) do
      {:ok,
       socket
       |> put_flash(:error, "Contract not found for this property")
       |> push_navigate(to: ~p"/properties/#{property_id}")}
    else
      progress = calculate_contract_progress(contract, today)
      next_update = Contracts.next_rent_update_date(contract)
      days_until = Contracts.days_until_next_update(contract)
      current_rent = Contracts.current_rent_value(contract)

      chart_data = Contracts.generate_rent_chart_data(contract, today)
      chart_labels_json = Jason.encode!(chart_data.labels)
      chart_values_json = Jason.encode!(chart_data.values)

      return_to = Map.get(params, "return_to", "contract")
      back_path = ~p"/properties/#{contract.property.id}?tab=#{return_to}"

      {:ok,
       socket
       |> assign(:page_title, "Contract Details")
       |> assign(:contract, contract)
       |> assign(:property, contract.property)
       |> assign(:today, today)
       |> assign(:progress, progress)
       |> assign(:next_update, next_update)
       |> assign(:days_until, days_until)
       |> assign(:current_rent, current_rent)
       |> assign(:chart_labels_json, chart_labels_json)
       |> assign(:chart_values_json, chart_values_json)
       |> assign(:chart_min_value, chart_data.min_value)
       |> assign(:chart_max_value, chart_data.max_value)
       |> assign(:back_path, back_path)}
    end
  end
end
