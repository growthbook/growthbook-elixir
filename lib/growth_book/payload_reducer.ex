defmodule GrowthBook.PayloadReducer do
  @moduledoc false
  # Implements `GrowthBook.reduce_payload/2`. Works on the decoded (and decrypted) payload map,
  # the way the GrowthBook API returns it, so the result can be serialized for a client SDK.

  alias GrowthBook.Condition

  @spec reduce(map(), keyword()) :: map()
  def reduce(payload, opts \\ []) do
    attributes = Keyword.get(opts, :attributes, %{})
    include = Map.new(Keyword.get(opts, :include, []))
    exclude = Map.new(Keyword.get(opts, :exclude, []))
    prerequisites = Keyword.get(opts, :prerequisites, :keep)

    saved_groups = payload["savedGroups"] || %{}
    all_features = payload["features"] || %{}
    all_experiments = payload["experiments"] || []

    state = %{
      attributes: attributes,
      saved_groups: saved_groups,
      all_features: all_features,
      include: include,
      exclude: exclude,
      prerequisites: prerequisites
    }

    features =
      all_features
      |> Enum.filter(fn {_id, feature} -> matches?(state, metadata(feature)) end)
      |> Enum.reduce(%{}, fn {id, _feature}, added -> add_feature(state, id, added) end)

    experiments =
      all_experiments
      |> Enum.filter(&matches?(state, metadata(&1)))
      |> Enum.map(&prune_item(state, &1, false))

    features = Enum.reduce(experiments, features, &add_parents(state, &1, &2))

    contextual_bandits =
      reduce_bandits(state, payload["contextualBandits"] || %{}, features, experiments)

    kept = [features, experiments, contextual_bandits]
    {as_written, _seen} = mark(state, kept, true, {MapSet.new(), MapSet.new()})
    state = Map.merge(state, %{as_written: as_written, cyclic: cyclic_groups(saved_groups)})
    groups = keep_groups(state, kept, %{})

    reduced = %{
      "features" => features,
      "experiments" => experiments,
      "savedGroups" => groups
    }

    # Only when there were any, as with the payload's other optional keys
    reduced =
      if truthy?(payload["contextualBandits"]),
        do: Map.put(reduced, "contextualBandits", contextual_bandits),
        else: reduced

    Map.merge(payload, reduced)
  end

  defp metadata(%{} = item), do: item["metadata"] || %{}
  defp metadata(_item), do: %{}

  # Only a list counts, as with `$in`, and any one of its values is enough
  defp has?(actual, want) when is_list(want), do: in?(actual, want)
  defp has?(_actual, _want), do: false

  defp in?(actual, want) when is_list(actual), do: Enum.any?(actual, &includes?(want, &1))
  defp in?(actual, want), do: includes?(want, actual)

  # Like JavaScript's `Array.prototype.includes`: arrays and objects are never equal
  defp includes?(list, value), do: Enum.any?(list, &same_value?(&1, value))

  defp same_value?(left, right) when is_number(left) and is_number(right), do: left == right

  defp same_value?(left, right)
       when is_map(left) or is_list(left) or is_map(right) or is_list(right),
       do: false

  defp same_value?(left, right), do: left === right

  # A rule without projects applies wherever its feature is delivered
  defp rule_in_projects?(state, meta) do
    is_nil(state.include[:projects]) or is_nil(meta) or is_nil(meta["projects"]) or
      has?(meta["projects"], state.include[:projects])
  end

  # A feature or experiment has to list one of the projects, or be in all of them. One without
  # projects is in none, like one without tags.
  defp in_projects?(state, meta) do
    is_nil(state.include[:projects]) or truthy?(meta["allProjects"]) or
      has?(meta["projects"], state.include[:projects])
  end

  # Kept when it matches every `include` filter and no `exclude` filter. Only listed projects are
  # excluded, so one in all projects stays.
  defp matches?(state, meta) do
    fields = meta["customFields"] || %{}
    in_fields = state.include[:custom_fields] || %{}
    out_fields = state.exclude[:custom_fields] || %{}

    in_projects?(state, meta) and
      (is_nil(state.include[:tags]) or has?(meta["tags"], state.include[:tags])) and
      Enum.all?(in_fields, fn {key, want} -> has?(fields[key], want) end) and
      not has?(meta["projects"], state.exclude[:projects]) and
      not has?(meta["tags"], state.exclude[:tags]) and
      not Enum.any?(out_fields, fn {key, want} -> has?(fields[key], want) end)
  end

  # Reduces a rule or an auto experiment
  defp prune_item(state, %{"condition" => condition} = item, rule?) when not is_nil(condition) do
    case Condition.prune_condition(state.attributes, condition, state.saved_groups) do
      true ->
        Map.delete(item, "condition")

      # Kept, since sticky buckets and forced variations skip an experiment's condition, and a
      # rule's prerequisites are checked before it
      false ->
        item = Map.put(item, "condition", %{"$not" => %{}})
        # A force rule that never passes never returns its value. An auto experiment's forced
        # variation still applies to a sticky bucketed user.
        if rule? and Map.has_key?(item, "force"), do: Map.put(item, "force", nil), else: item

      pruned ->
        Map.put(item, "condition", pruned)
    end
  end

  defp prune_item(_state, item, _rule?), do: item

  # Adds a feature, then the prerequisites the client evaluates for it, even when the filters
  # drop them. With :filter, only the filters decide, except for holdouts, which aren't app
  # features and are always kept.
  defp add_feature(state, id, added) do
    feature = Map.get(state.all_features, id)

    if not truthy?(feature) or Map.has_key?(added, id) do
      added
    else
      # Rules scoped to other projects aren't served. A prerequisite from another project keeps
      # its own, as on the server.
      scoped = in_projects?(state, metadata(feature))

      rules =
        case feature["rules"] do
          rules when is_list(rules) ->
            rules
            |> Enum.filter(&(not scoped or rule_in_projects?(state, rule_metadata(&1))))
            |> Enum.map(&prune_item(state, &1, true))

          _none ->
            nil
        end

      # Stored before its parents are added, so a prerequisite cycle ends
      added = Map.put(added, id, if(rules, do: Map.put(feature, "rules", rules), else: feature))
      Enum.reduce(rules || [], added, &add_parents(state, &1, &2))
    end
  end

  defp rule_metadata(%{} = rule), do: rule["metadata"]
  defp rule_metadata(_rule), do: nil

  defp add_parents(state, %{} = item, added) do
    (item["parentConditions"] || [])
    |> Enum.reduce(added, fn parent, added ->
      id = parent["id"]

      if state.prerequisites != :filter or
           (is_binary(id) and String.starts_with?(id, "$holdout:")),
         do: add_feature(state, id, added),
         else: added
    end)
  end

  defp add_parents(_state, _item, added), do: added

  # The contextual bandits that kept rules and experiments use. A context whose condition never
  # passes can't be the first that does, so it goes.
  defp reduce_bandits(state, all_bandits, features, experiments) do
    items = Enum.flat_map(Map.values(features), &(&1["rules"] || [])) ++ experiments

    Enum.reduce(items, %{}, fn item, bandits ->
      ref = is_map(item) && item["contextualBanditRef"]

      if not truthy?(ref) or Map.has_key?(bandits, ref) or not Map.has_key?(all_bandits, ref) do
        bandits
      else
        bandit = all_bandits[ref]
        reduce_bandit(state, bandits, ref, bandit)
      end
    end)
  end

  # Evaluation tolerates a definition that isn't an object, so it stays
  defp reduce_bandit(_state, bandits, ref, bandit) when not is_map(bandit),
    do: Map.put(bandits, ref, bandit)

  defp reduce_bandit(state, bandits, ref, bandit) do
    contexts =
      Enum.flat_map(bandit["contexts"] || [], fn context ->
        condition = context["condition"] || %{}

        case Condition.prune_condition(state.attributes, condition, state.saved_groups) do
          false -> []
          true -> [Map.put(context, "condition", %{})]
          pruned -> [Map.put(context, "condition", pruned)]
        end
      end)

    Map.put(bandits, ref, Map.put(bandit, "contexts", contexts))
  end

  # Keeps each saved group whose id appears as a string anywhere, with condition groups reduced.
  # This needs no list of the operators that reference groups.
  defp keep_groups(state, value, groups) when is_binary(value) do
    if not Map.has_key?(state.saved_groups, value) or Map.has_key?(groups, value) do
      groups
    else
      group = state.saved_groups[value]

      group =
        if MapSet.member?(state.as_written, value) or MapSet.member?(state.cyclic, value) do
          group
        else
          case Condition.prune_saved_group(state.attributes, %{"id" => value}, state.saved_groups) do
            %{} = condition -> Map.put(group, "condition", condition)
            _decided -> group
          end
        end

      keep_groups(state, group, Map.put(groups, value, group))
    end
  end

  defp keep_groups(state, value, groups) when is_map(value),
    do: Enum.reduce(Map.values(value), groups, &keep_groups(state, &1, &2))

  defp keep_groups(state, value, groups) when is_list(value),
    do: Enum.reduce(value, groups, &keep_groups(state, &1, &2))

  defp keep_groups(_state, _value, groups), do: groups

  # Groups that keep their condition as written: those evaluated against something other than the
  # user (each item in $elemMatch, or the parent's value in a prerequisite), and the groups those
  # reference. `user` is whether the value is evaluated against the user.
  defp mark(state, value, user, {as_written, seen} = acc) when is_binary(value) do
    cond do
      not Map.has_key?(state.saved_groups, value) or MapSet.member?(as_written, value) -> acc
      user and MapSet.member?(seen, value) -> acc
      user -> mark(state, state.saved_groups[value], true, {as_written, MapSet.put(seen, value)})
      true -> mark(state, state.saved_groups[value], false, {MapSet.put(as_written, value), seen})
    end
  end

  defp mark(state, value, user, acc) when is_map(value) do
    Enum.reduce(value, acc, fn {key, child}, acc ->
      mark(state, child, user and key not in ["$elemMatch", "parentConditions"], acc)
    end)
  end

  defp mark(state, value, user, acc) when is_list(value),
    do: Enum.reduce(value, acc, &mark(state, &1, user, &2))

  defp mark(_state, _value, _user, acc), do: acc

  # A group on a cycle can't be reduced on its own: its result depends on which group the
  # evaluation entered the cycle from. Each group's references are collected once, then the
  # groups on a cycle (a strongly connected component of more than one group, or a group that
  # references itself) are found in one pass (Tarjan's algorithm).
  defp cyclic_groups(saved_groups) do
    graph =
      Map.new(saved_groups, fn {id, group} ->
        {id, group |> group_ids(saved_groups) |> Enum.uniq()}
      end)

    acc = %{
      index: 0,
      indices: %{},
      low: %{},
      stack: [],
      on_stack: MapSet.new(),
      cyclic: MapSet.new()
    }

    graph
    |> Map.keys()
    |> Enum.reduce(acc, fn id, acc ->
      if Map.has_key?(acc.indices, id), do: acc, else: strong_connect(id, graph, acc)
    end)
    |> Map.fetch!(:cyclic)
  end

  defp strong_connect(id, graph, acc) do
    acc = %{
      acc
      | index: acc.index + 1,
        indices: Map.put(acc.indices, id, acc.index),
        low: Map.put(acc.low, id, acc.index),
        stack: [id | acc.stack],
        on_stack: MapSet.put(acc.on_stack, id)
    }

    acc =
      Enum.reduce(graph[id], acc, fn ref, acc ->
        cond do
          not Map.has_key?(acc.indices, ref) ->
            acc = strong_connect(ref, graph, acc)
            %{acc | low: Map.put(acc.low, id, min(acc.low[id], acc.low[ref]))}

          MapSet.member?(acc.on_stack, ref) ->
            %{acc | low: Map.put(acc.low, id, min(acc.low[id], acc.indices[ref]))}

          true ->
            acc
        end
      end)

    if acc.low[id] == acc.indices[id] do
      {above, [^id | rest]} = Enum.split_while(acc.stack, &(&1 != id))
      component = [id | above]

      cyclic =
        if length(component) > 1 or id in graph[id],
          do: MapSet.union(acc.cyclic, MapSet.new(component)),
          else: acc.cyclic

      %{
        acc
        | stack: rest,
          on_stack: MapSet.difference(acc.on_stack, MapSet.new(component)),
          cyclic: cyclic
      }
    else
      acc
    end
  end

  # Every saved group id that appears as a string anywhere in the value
  defp group_ids(value, saved_groups) when is_binary(value),
    do: if(Map.has_key?(saved_groups, value), do: [value], else: [])

  defp group_ids(value, saved_groups) when is_map(value),
    do: Enum.flat_map(Map.values(value), &group_ids(&1, saved_groups))

  defp group_ids(value, saved_groups) when is_list(value),
    do: Enum.flat_map(value, &group_ids(&1, saved_groups))

  defp group_ids(_value, _saved_groups), do: []

  defp truthy?(value), do: value not in [nil, false, 0, ""]
end
