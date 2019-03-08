defmodule Fluminus.APITest do
  use ExUnit.Case, async: true

  @port Application.get_env(:fluminus, :port)
  @fixtures_path Application.get_env(:fluminus, :fixtures_path) |> Path.join("api")
  @cassettes @fixtures_path
             |> File.ls!()
             |> Enum.filter(&String.ends_with?(&1, ".json"))
             |> Enum.map(&Path.join(@fixtures_path, &1))
             |> Enum.map(&File.read!/1)
             |> Enum.map(&Jason.decode!/1)

  alias Fluminus.API
  alias Plug.Conn

  require Logger

  setup do
    bypass = Bypass.open(port: @port)
    Bypass.expect(bypass, &handle_conn/1)
    :ok
  end

  defp handle_conn(conn) do
    conn = conn |> Conn.fetch_cookies() |> Conn.fetch_query_params()

    {:ok, body, conn} = Conn.read_body(conn)
    body = if body != "", do: URI.decode_query(body), else: %{}

    cassette =
      Enum.find(@cassettes, fn %{"request" => request} ->
        request["request_path"] == conn.request_path and
          request["method"] == conn.method and
          (request["cookies"] || %{}) == conn.cookies and
          (request["body"] || %{}) == body and
          Enum.all?(request["query"] || %{}, fn {key, value} -> Map.get(conn.query_params, key) == value end)
      end)

    if cassette do
      response = cassette["response"]

      response["headers"]
      |> Enum.reduce(conn, fn [key, value], acc ->
        Conn.put_resp_header(acc, key, value)
      end)
      |> Conn.resp(response["status_code"], response["body"])
    else
      Logger.error("Please create cassette for this request: #{conn.method} #{conn.request_path}")
      Logger.error("conn:")
      Logger.error(inspect(conn))
      Logger.error("body:")
      Logger.error(inspect(body))
      conn
    end
  end
end
