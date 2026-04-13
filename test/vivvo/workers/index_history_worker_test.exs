defmodule Vivvo.Workers.IndexHistoryWorkerTest do
  use Vivvo.DataCase, async: false

  alias Vivvo.Workers.IndexHistoryWorker

  setup {Req.Test, :verify_on_exit!}

  describe "perform/1" do
    test "fetches missing index histories for all index types" do
      today = Date.utc_today()
      previous_month = Date.shift(today, month: -1) |> Date.beginning_of_month()

      # Create initial IPC history
      Vivvo.Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: previous_month
      })

      # Stub external API for IPC
      Req.Test.stub(Vivvo.IndexService, fn conn ->
        if String.contains?(conn.request_path, "/ipc") do
          Req.Test.json(conn, %{
            data: [%{"anio" => today.year, "mes" => today.month, "valor" => 2.6}]
          })
        else
          Req.Test.json(conn, %{
            data: [%{"fecha" => "01/01/2025", "valor" => 100.0}]
          })
        end
      end)

      Application.put_env(:vivvo, Vivvo.IndexService,
        req_options: [plug: {Req.Test, Vivvo.IndexService}]
      )

      assert {:ok, :ok} = perform_job(IndexHistoryWorker, %{"today" => Date.to_iso8601(today)})

      # Should have created new index histories
      assert Repo.aggregate(Vivvo.Indexes.IndexHistory, :count) >= 1

      on_exit(fn ->
        Application.put_env(:vivvo, Vivvo.IndexService, req_options: [retry: false])
      end)
    end

    test "succeeds when all index types are up to date" do
      today = Date.utc_today()

      # Create index histories for today
      Vivvo.Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: today
      })

      Vivvo.Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.0"),
        date: today
      })

      assert {:ok, :ok} = perform_job(IndexHistoryWorker, %{"today" => Date.to_iso8601(today)})
    end

    test "backoff function returns exponential delays up to 12 hours" do
      job = %{attempt: 1}
      backoff_1 = IndexHistoryWorker.backoff(job)
      assert backoff_1 == 900

      job = %{attempt: 2}
      backoff_2 = IndexHistoryWorker.backoff(job)
      assert backoff_2 == 1800

      job = %{attempt: 3}
      backoff_3 = IndexHistoryWorker.backoff(job)
      assert backoff_3 == 3600

      job = %{attempt: 4}
      backoff_4 = IndexHistoryWorker.backoff(job)
      assert backoff_4 == 7200

      job = %{attempt: 5}
      backoff_5 = IndexHistoryWorker.backoff(job)
      assert backoff_5 == 14_400

      job = %{attempt: 6}
      backoff_6 = IndexHistoryWorker.backoff(job)
      assert backoff_6 == 28_800

      job = %{attempt: 7}
      backoff_7 = IndexHistoryWorker.backoff(job)
      assert backoff_7 == 43_200
    end

    test "returns error when external API fails" do
      today = Date.utc_today()

      Req.Test.stub(Vivvo.IndexService, fn conn ->
        conn
        |> Plug.Conn.put_status(503)
        |> Req.Test.json(%{error: "Service unavailable"})
      end)

      Application.put_env(:vivvo, Vivvo.IndexService,
        req_options: [plug: {Req.Test, Vivvo.IndexService}]
      )

      assert {:error, _} = perform_job(IndexHistoryWorker, %{"today" => Date.to_iso8601(today)})

      on_exit(fn ->
        Application.put_env(:vivvo, Vivvo.IndexService, req_options: [retry: false])
      end)
    end
  end
end
