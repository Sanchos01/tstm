defmodule Tstm do
	use Application

	@ets_timers :__tstm__timers__
	@ets_states :__tstm__states__
	@ets_tab_specs [:public, :named_table, :ordered_set, {:write_concurrency, true}, {:read_concurrency, true}, :protected]

	@type t :: %Tstm{}
	defstruct 	curr: nil,
				prev: nil

	# See http://elixir-lang.org/docs/stable/elixir/Application.html
	# for more information on OTP Applications
	def start(_type, _args) do
		import Supervisor.Spec, warn: false
		@ets_timers = :ets.new(@ets_timers, @ets_tab_specs)
		@ets_states = :ets.new(@ets_states, @ets_tab_specs)

		children = [
		# Define workers and child supervisors to be supervised
		# worker(Tstm.Worker, [arg1, arg2, arg3]),
		]

		# See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
		# for other strategies and supported options
		opts = [strategy: :one_for_one, name: Tstm.Supervisor]
		Supervisor.start_link(children, opts)
	end

	#
	#	public
	#

	@spec put(any, (any -> any), (any -> boolean), any) :: any
	def put(raw_state, lambda, predicate, namespace) do
		this_state = lambda.(raw_state)
		# if state is valid
		if predicate.(this_state) do
			# if state changed
			case ets_get(namespace, @ets_states) do
				{^this_state, _} -> :ok
				{_, _} ->
					timers_key = {namespace, this_state}
					current_stamp = makestamp()
					# shift timer
					:ok = 	case ets_get(timers_key, @ets_timers) do
								nil -> %Tstm{prev: nil, curr: makestamp}
								%Tstm{curr: prev_stamp} -> %Tstm{prev: prev_stamp, curr: current_stamp}
							end
							|> ets_put(timers_key, @ets_timers)
					:ok = 	ets_put({this_state, current_stamp}, namespace, @ets_states)
			end
		end
		raw_state
	end

	@spec get(any, any, any) :: %{swithed: pos_integer, diff: non_neg_integer} | nil
	def get(state1, state2, namespace) do
		case Enum.map([state1, state2], &({namespace, &1} |> ets_get(@ets_timers))) do
			[%Tstm{prev: t1}, %Tstm{prev: t2}] when (is_integer(t1) and is_integer(t2) and (t1 > 0) and (t2 > 0)) ->
				{_, switched} = ets_get(namespace, @ets_states)
				%{swithed: switched, diff: abs(t1 - t2)}
			_ ->
				nil
		end
	end

	#
	#	priv
	#

	@typep local_ets_tab :: :__tstm__timers__ | :__tstm__states__

	@spec ets_get(any, local_ets_tab) :: any
	defp ets_get(key, tab) do
		case :ets.lookup(tab, key) do
			[{^key, data}] -> data
			[] -> nil
		end
	end
	@spec ets_put(Tstm.t | {any, pos_integer}, any, local_ets_tab) :: :ok
	defp ets_put(val, key, tab) do
		true = :ets.insert(tab, {key, val})
		:ok
	end

	@spec makestamp :: pos_integer
	defp makestamp do
		{a, b, c} = :os.timestamp
		a*1000000000 + b*1000 + div(c,1000)
	end

end
