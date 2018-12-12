%%%-------------------------------------------------------------------
%% @doc autocluster public API
%% @end
%%%-------------------------------------------------------------------

-module(autocluster_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    autocluster_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================