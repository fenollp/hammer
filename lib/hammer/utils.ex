defmodule Hammer.Utils do
  @moduledoc false

  def pool_name do
    pool_name(:single)
  end

  def pool_name(name) do
    :"hammer_backend_#{name}_pool"
  end

  # Returns Erlang Time as milliseconds since 00:00 GMT, January 1, 1970
  def timestamp do
    DateTime.utc_now() |> DateTime.to_unix(:millisecond)
  end

  # Returns tuple of {timestamp, key}, where key is {bucket_number, id}
  def stamp_key(id, scale_ms) do
    stamp = timestamp()
    # with scale_ms = 1 bucket changes every millisecond
    bucket_number = trunc(stamp / scale_ms)
    key = {bucket_number, id}
    {stamp, key}
  end

  def get_backend_module(:single) do
    case Application.get_env(:hammer, :backend) do
      {backend_module, _config} ->
        backend_module

      _ ->
          case {get_env(:hammer, :backend_module), get_env(:hammer, :backend_config)} do
            config = {bm, c} when not is_nil(bm) and not is_nil(c) -> config
            _ ->
              raise RuntimeError, "trying to get single backend, but multiple backends configured"
          end
    end
  end

  def get_backend_module(which) do
    case Application.get_env(:hammer, :backend)[which] do
      {backend_module, _config} ->
        backend_module

      _ ->
        raise KeyError, "backend #{which} is not configured"
    end
  end

  def get_env(app, key, default \\ nil) do
    case Application.get_env(app, key, default) do
      nil -> get_env_resolve(default)
      value -> get_env_resolve(value)
    end
  end

  defp get_env_resolve({:system, env_key, nil}), do: System.get_env(env_key)
  defp get_env_resolve({:system, env_key, default}) when is_binary(default) do
    System.get_env(env_key) || default
  end
  defp get_env_resolve({:system, env_key, default}) do
    case System.get_env(env_key) do
      nil -> default
      str ->
        case str |> Code.string_to_quoted do
          {:ok, terms} -> do_parse(terms)
          {:error, _}  -> throw({:badcode, str})
        end
    end
  end

  # https://stackoverflow.com/a/29241725/1418165
  defp do_parse(term) when is_atom(term), do: term
  defp do_parse(term) when is_number(term), do: term
  defp do_parse(term) when is_binary(term), do: term

  defp do_parse([]), do: []
  defp do_parse([h|t]), do: [do_parse(h) | do_parse(t)]

  defp do_parse({a, b}), do: {do_parse(a), do_parse(b)}
  defp do_parse({:"{}", _anno, terms}) do
    terms |> Enum.map(&do_parse/1) |> List.to_tuple
  end

  defp do_parse({:"%{}", _anno, terms}) do
    for {k, v} <- terms, into: %{}, do: {do_parse(k), do_parse(v)}
  end
end
