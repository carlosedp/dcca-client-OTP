-module(dccaclient_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    DiaClient =
        {dccaclient, {dccaclient, start_link, []}, permanent, 5000, worker, [client_cb]},
    {ok, {{one_for_one, 5, 10}, [DiaClient]}}.
