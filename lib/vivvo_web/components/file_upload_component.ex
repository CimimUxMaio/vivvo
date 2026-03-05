defmodule VivvoWeb.FileUploadComponent do
  @moduledoc """
  Reusable file upload component for LiveView uploads.

  Usage:
      <.live_component
        module={VivvoWeb.FileUploadComponent}
        id="payment-files"
        upload={@uploads.files}
        field={@form[:files]}
        label="Supporting Documents"
      />
  """
  use Phoenix.LiveComponent

  import VivvoWeb.CoreComponents, only: [icon: 1, input_errors: 1]

  def render(assigns) do
    ~H"""
    <div class="space-y-4" id={@id}>
      <label :if={@label} class="label text-sm font-medium">{@label}</label>

      <%!-- Drop Zone --%>
      <div
        class="group relative border-2 border-dashed border-base-300 rounded-xl p-8 transition-all duration-200 hover:border-primary hover:bg-primary/5"
        phx-drop-target={@upload.ref}
      >
        <.live_file_input upload={@upload} class="hidden" />
        <label
          for={@upload.ref}
          class="cursor-pointer flex flex-col items-center gap-3"
        >
          <div class="w-14 h-14 rounded-full bg-base-200 flex items-center justify-center group-hover:bg-primary/10 group-hover:scale-110 transition-all duration-200">
            <.icon
              name="hero-cloud-arrow-up"
              class="w-7 h-7 text-base-content/50 group-hover:text-primary transition-colors"
            />
          </div>
          <div class="text-center space-y-1">
            <p class="text-sm font-medium text-base-content">
              <span class="text-primary">Click to upload</span> or drag and drop
            </p>
            <p class="text-xs text-base-content/50">
              PDF, JPG, PNG, GIF up to 10MB
            </p>
          </div>
        </label>
      </div>

      <%!-- Errors --%>
      <div :if={@upload.errors != []} class="space-y-2">
        <div :for={error <- @upload.errors} class="alert alert-error alert-sm">
          <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
          <span class="text-sm">{format_upload_error(error)}</span>
        </div>
      </div>

      <.input_errors field={@field} />

      <%!-- File List --%>
      <div :if={@upload.entries != []} class="space-y-2">
        <div
          :for={entry <- @upload.entries}
          class="flex items-center gap-3 p-3 bg-base-100 border border-base-200 rounded-lg hover:border-base-300 transition-colors"
        >
          <%!-- Preview or Icon --%>
          <div class="flex-shrink-0">
            <%= if entry.client_type =~ "image" do %>
              <.live_img_preview entry={entry} class="w-10 h-10 object-cover rounded-lg" />
            <% else %>
              <div class="w-10 h-10 bg-base-200 rounded-lg flex items-center justify-center">
                <.icon name="hero-document" class="w-5 h-5 text-base-content/40" />
              </div>
            <% end %>
          </div>

          <%!-- File Details --%>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-base-content truncate">
              {entry.client_name}
            </p>
            <p class="text-xs text-base-content/50">
              {format_file_size(entry.client_size)}
            </p>

            <%!-- Progress --%>
            <div class="mt-2 w-full bg-base-200 rounded-full h-1.5 overflow-hidden">
              <div
                class={[
                  "h-full rounded-full transition-all duration-300",
                  entry.progress == 100 && "bg-success",
                  entry.progress < 100 && "bg-primary"
                ]}
                style={"width: #{entry.progress}%"}
              />
            </div>
          </div>

          <%!-- Actions --%>
          <button
            type="button"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            class="flex-shrink-0 btn btn-ghost btn-xs btn-circle hover:bg-error/10 hover:text-error"
            aria-label="Remove file"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp format_upload_error({:too_large, _}), do: "File is too large (max 10MB)"
  defp format_upload_error({:too_many_files, _}), do: "Too many files (max 5 files)"
  defp format_upload_error({:invalid, _}), do: "Invalid file type"
  defp format_upload_error(_), do: "Upload error occurred"

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
end
