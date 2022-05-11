%-*- mode: erlang -*-
%% @author Carlos Eduardo de Paula <carlosedp@gmail.com>
%% @copyright 2015 Carlos Eduardo de Paula
%% @doc gen_server callback module implementation:
%%
%% @end

-module(dccaclient_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    dccaclient_sup:start_link().

stop(_State) ->
    ok.
