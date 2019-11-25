defmodule Ecto.Adapters.Neo4j.Behaviour.Schema do
  @moduledoc false

  alias Ecto.Adapters.Neo4j.Cql.Node, as: NodeCql

  def autogenerate(:id), do: :erlang.system_time(:microsecond)
  def autogenerate(:binary_id), do: Ecto.UUID.generate()
  def autogenerate(:embed_id), do: Ecto.UUID.generate()

  def insert_all(
        adapter,
        schema_meta,
        _header,
        entries,
        on_conflict,
        returning,
        options
      ) do
    inserts =
      entries
      |> Enum.map(fn data ->
        insert(adapter, schema_meta, data, on_conflict, returning, options)
      end)

    case returning do
      [] -> {length(inserts), nil}
      _ -> {length(inserts), Enum.map(inserts, fn {_, v} -> v end)}
    end
  end

  def insert(
        adapter_meta,
        %{source: source, schema: schema},
        fields,
        _on_conflict,
        returning,
        opts \\ []
      ) do
    returning_field =
      returning
      |> Enum.map(fn
        :id -> :nodeId
        field -> field
      end)
      |> Enum.reject(fn k ->
        case Atom.to_string(k) do
          "rel" <> _rel_type -> true
          _ -> false
        end
      end)

    # Relationships and foreign keyw should not be saved as node properties
    foreign_keys = get_foreign_keys(schema)

    insert_data =
      fields
      |> Keyword.drop(foreign_keys)
      |> Enum.reject(fn {k, _} ->
        case Atom.to_string(k) do
          "rel" <> _rel_type -> true
          _ -> false
        end
      end)

    execute(adapter_meta, NodeCql.insert(source, format_data(insert_data), returning_field), opts)
  end

  def update(adapter_meta, %{source: source}, fields, filters, _returning, opts) do
    execute(adapter_meta, NodeCql.update(source, format_data(fields), format_data(filters)), opts)
  end

  def delete(adapter_meta, %{source: source}, filters, opts) do
    execute(adapter_meta, NodeCql.delete(source, format_data(filters)), opts)
  end

  defp execute(%{pid: pool}, {cql, params}, opts) do
    default_role =
      Application.get_env(:ecto_neo4j, Ecto.Adapters.Neo4j, bolt_role: :direct)
      |> Keyword.get(:bolt_role)

    bolt_role = Keyword.get(opts, :bolt_role, default_role)
    conn = Ecto.Adapters.Neo4j.Behaviour.Queryable.get_conn(pool, bolt_role)

    case Bolt.Sips.query(conn, cql, params) do
      {:ok, %Bolt.Sips.Response{results: [%{"n" => _record}]}} ->
        {:ok, []}

      {:ok, %Bolt.Sips.Response{records: [record]}} ->
        {:ok, record}

      {:error,
       %Bolt.Sips.Error{
         code: "Neo.ClientError.Schema.ConstraintValidationFailed",
         message: message
       }} ->
        [_, label, property] =
          Regex.run(~r/.*`(?<label>[a-zA-Z_]+)`.*`(?<property>[a-zA-Z_]+)`/, message)

        {:invalid, [{:unique, "#{label}_#{property}_index"}]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_data(data) do
    data
    |> Map.new()
    |> Ecto.Adapters.Neo4j.Helper.manage_id(:to_db)
  end

  @doc """
  Retrieve foreign keys related to the parent for the given schema.

  ## Example

      iex> Ecto.Adapters.Neo4j.Behaviour.Schema.get_foreign_keys(MyApp.Post)
      [:author]
  """
  @spec get_foreign_keys(module()) :: [atom()]
  def get_foreign_keys(schema) do
    Enum.map(schema.__schema__(:associations), fn assoc ->
      schema.__schema__(:association, assoc)
    end)
    |> Enum.filter(fn
      %Ecto.Association.BelongsTo{} -> true
      _ -> false
    end)
    |> Enum.map(fn data -> Map.get(data, :owner_key) end)
  end

  @doc """
  Removes all foreign key data that can be found in the schema and its associations.
  This is because foreign keyw are useless in Neo4j database
  """
  @spec remove_foreign_keys({:ok, Ecto.Schema.t()}) :: {:ok, Ecto.Schema.t()}
  def remove_foreign_keys({:ok, %{} = data}) do
    {:ok, do_remove_foreign_keys(data)}
  end

  defp do_remove_foreign_keys(%{__struct__: schema} = data) do
    fks = get_foreign_keys(schema)

    assocs =
      Enum.reduce(schema.__schema__(:associations), %{}, fn assoc_key, acc ->
        data_assoc =
          case Map.get(data, assoc_key) do
            %Ecto.Association.NotLoaded{} = data_assoc ->
              data_assoc

            assoc_list ->
              Enum.map(assoc_list, fn data_assoc ->
                do_remove_foreign_keys(data_assoc)
              end)
          end

        Map.put(acc, assoc_key, data_assoc)
      end)

    Map.merge(Map.drop(data, fks), assocs)
  end
end
