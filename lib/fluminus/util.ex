defmodule Fluminus.Util do
  @moduledoc """
  A collection of common methods in Fluminus.
  """

  alias Fluminus.HTTPClient

  import FFmpex
  use FFmpex.Options

  @doc """
  Sanitises filename according to Unix standard.
  """
  @spec sanitise_filename(String.t(), String.t()) :: String.t()
  def sanitise_filename(name, replacement \\ "-") when is_binary(name) and is_binary(replacement) do
    # According to http://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html:
    # The bytes composing the name shall not contain the <NUL> or <slash> characters
    String.replace(name, ~r|[/\0]|, replacement)
  end

  @doc """
  Downloads the given url to a destination path generated by the provided function.

  This function will return `{:error, :exists}` if the file already exists.
  """
  @spec download((() -> {:ok, String.t()} | {:error, any()}), Path.t(), bool()) :: :ok | {:error, :exists | any()}
  def download(f, destination, verbose) when is_function(f) do
    download_fn = fn url ->
      HTTPClient.download(%HTTPClient{}, url, destination, false, [], verbose)
    end

    download_wrapper(f, download_fn, destination)
  end

  @spec download_multimedia((() -> {:ok, String.t()} | {:error, :noffmpeg | any()}), Path.t(), bool()) ::
          :ok | {:error, :exists | any()}
  def download_multimedia(f, destination, verbose) when is_function(f) do
    if not String.ends_with?(destination, ".mp4") do
      destination = destination <> ".mp4"
    end

    download_fn = fn url ->
      # FFMpex has a wrong spec: https://github.com/talklittle/ffmpex/pull/22
      {_, cmd_args} =
        FFmpex.new_command()
        |> add_input_file(url)
        |> add_output_file(destination)
        |> add_file_option(option_c("copy"))
        |> prepare()

      output = if verbose, do: IO.stream(:stdio, :line), else: ""

      with executable when not is_nil(executable) <- System.find_executable("ffmpeg"),
           {_, 0} <- System.cmd(executable, cmd_args, into: output, stderr_to_stdout: true) do
        :ok
      else
        nil -> {:error, :noffmpeg}
        other -> {:error, other}
      end
    end

    download_wrapper(f, download_fn, destination)
  end

  @spec download_wrapper(
          (() -> {:ok, String.t()} | {:error, any()}),
          (url :: String.t() -> :ok | {:error, any()}),
          Path.t()
        ) ::
          :ok | {:error, :exists | any()}
  defp download_wrapper(url_gen, download_fn, destination) when is_function(url_gen) and is_function(download_fn) do
    with {:exists?, false} <- {:exists?, File.exists?(destination)},
         {:ok, url} <- url_gen.(),
         :ok <- download_fn.(url) do
      :ok
    else
      {:exists?, true} -> {:error, :exists}
      {:error, reason} -> {:error, reason}
    end
  end
end
