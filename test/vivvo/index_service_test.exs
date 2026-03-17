defmodule Vivvo.IndexServiceTest do
  use ExUnit.Case, async: true

  alias Vivvo.IndexService

  setup {Req.Test, :verify_on_exit!}

  describe "mocked IndexService tests" do
    test "handles API timeout" do
      Req.Test.stub(Vivvo.IndexService, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, _} = IndexService.latest(:ipc, plug: {Req.Test, Vivvo.IndexService})
    end

    test "handles API rate limiting (429 status)" do
      Req.Test.stub(Vivvo.IndexService, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{error: "Rate limit exceeded"})
      end)

      assert {:error, "HTTP 429"} =
               IndexService.latest(:ipc, plug: {Req.Test, Vivvo.IndexService})
    end

    test "handles empty history response" do
      Req.Test.stub(Vivvo.IndexService, fn conn ->
        if String.contains?(conn.request_path, "/range") do
          Req.Test.json(conn, %{data: []})
        else
          Req.Test.json(conn, %{data: %{anio: 2025, mes: 1, indice_ipc: 2.5}})
        end
      end)

      from = Date.new!(2025, 1, 1)
      to = Date.new!(2025, 3, 1)

      assert {:ok, []} =
               IndexService.history(:ipc, from, to, plug: {Req.Test, Vivvo.IndexService})
    end

    test "handles HTTP 500/502/503 errors" do
      for status <- [500, 502, 503] do
        Req.Test.stub(Vivvo.IndexService, fn conn ->
          conn
          |> Plug.Conn.put_status(status)
          |> Req.Test.json(%{error: "Server error"})
        end)

        expected_error = "HTTP #{status}"

        assert {:error, ^expected_error} =
                 IndexService.latest(:ipc, plug: {Req.Test, Vivvo.IndexService})
      end
    end

    test "handles partial data response with missing fields" do
      Req.Test.stub(Vivvo.IndexService, fn conn ->
        Req.Test.json(conn, %{data: [%{anio: 2025, mes: 1}]})
      end)

      from = Date.new!(2025, 1, 1)
      to = Date.new!(2025, 3, 1)

      assert {:error, _} =
               IndexService.history(:ipc, from, to, plug: {Req.Test, Vivvo.IndexService})
    end

    test "verifies correct IPC endpoint URL is called" do
      test_pid = self()

      Req.Test.stub(Vivvo.IndexService, fn conn ->
        send(test_pid, {:path, conn.request_path})

        Req.Test.json(conn, %{
          data: %{
            anio: 2025,
            mes: 1,
            indice_ipc: 2.5
          }
        })
      end)

      assert {:ok, %{date: _, value: _}} =
               IndexService.latest(:ipc, plug: {Req.Test, Vivvo.IndexService})

      assert_receive {:path, "/api/ipc"}
    end

    test "verifies correct ICL endpoint URL is called" do
      test_pid = self()

      Req.Test.stub(Vivvo.IndexService, fn conn ->
        send(test_pid, {:path, conn.request_path})

        Req.Test.json(conn, %{
          data: %{
            fecha: "01/01/2025",
            valor: 100.0
          }
        })
      end)

      assert {:ok, %{date: _, value: _}} =
               IndexService.latest(:icl, plug: {Req.Test, Vivvo.IndexService})

      assert_receive {:path, "/api/icl"}
    end

    test "handles network connection failure" do
      Req.Test.stub(Vivvo.IndexService, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, _} = IndexService.latest(:ipc, plug: {Req.Test, Vivvo.IndexService})
    end

    test "handles invalid JSON response" do
      Req.Test.stub(Vivvo.IndexService, fn conn ->
        Plug.Conn.send_resp(conn, 200, "not valid json {[")
      end)

      assert {:error, _} = IndexService.latest(:ipc, plug: {Req.Test, Vivvo.IndexService})
    end
  end

  describe "latest/1" do
    @tag :external
    test "fetches latest IPC data from API" do
      assert {:ok, %{date: date, value: value}} = IndexService.latest(:ipc)
      assert is_struct(date, Date)
      assert is_struct(value, Decimal)
    end

    @tag :external
    test "fetches latest ICL data from API" do
      assert {:ok, %{date: date, value: value}} = IndexService.latest(:icl)
      assert is_struct(date, Date)
      assert is_struct(value, Decimal)
    end

    test "returns error for unknown index type" do
      assert_raise ArgumentError, fn ->
        IndexService.latest(:unknown)
      end
    end
  end

  describe "history/3" do
    @tag :external
    test "fetches historical IPC data for specific date range" do
      from = Date.new!(2025, 1, 1)
      to = Date.new!(2025, 3, 1)

      assert {:ok, history} = IndexService.history(:ipc, from, to)
      assert is_list(history)

      for item <- history do
        assert %{date: date, value: value} = item
        assert is_struct(date, Date)
        assert is_struct(value, Decimal)
      end
    end

    @tag :external
    test "fetches historical ICL data for specific date range" do
      from = Date.new!(2025, 1, 1)
      to = Date.new!(2025, 3, 1)

      assert {:ok, history} = IndexService.history(:icl, from, to)
      assert is_list(history)

      for item <- history do
        assert %{date: date, value: value} = item
        assert is_struct(date, Date)
        assert is_struct(value, Decimal)
      end
    end

    test "returns error when from date is nil" do
      to = Date.new!(2025, 3, 1)
      assert {:error, "From and To dates cannot be nil"} = IndexService.history(:ipc, nil, to)
    end

    test "returns error when to date is nil" do
      from = Date.new!(2025, 1, 1)
      assert {:error, "From and To dates cannot be nil"} = IndexService.history(:ipc, from, nil)
    end

    test "returns error when both dates are nil" do
      assert {:error, "From and To dates cannot be nil"} = IndexService.history(:ipc, nil, nil)
    end
  end
end
