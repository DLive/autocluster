%%%-------------------------------------------------------------------
%%% @author dlive
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 01. Dec 2018 10:56 AM
%%%-------------------------------------------------------------------
-module(autocluster_app_tests).
-author("dlive").

-include_lib("eunit/include/eunit.hrl").

gen_node_info_test()->
    NodeInfo = autocluster_zookeeper:encode_node_info(<<"default">>),
    io:format(user,"nodeinfo ~p",[edoc_lib:escape_uri(NodeInfo)]).

