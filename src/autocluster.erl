%%%-------------------------------------------------------------------
%%% @author dlive
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 30. Nov 2018 11:38 PM
%%%-------------------------------------------------------------------
-module(autocluster).
-author("dlive").

-include("autocluster.hrl").
%% API
-export([register/0,join/0,node_type/0,notification_nodeup/0,join_cluster/0]).


register()->
    register(get_config(prefix),get_config(env),get_config(node_type)).
register(Prefix,Env,NodeType)->
    autocluster_zookeeper:register_node(Prefix,Env,NodeType),
    ok.

join()->
    join_cluster(),
    ok.

node_type()->
    case application:get_env(autocluster,node_type) of
        {ok,Value}->
            Value;
        undefined->
            unknow_node_type
    end.


get_cluster_list()->
    List = autocluster_zookeeper:query_registed_list(get_config(prefix),get_config(env)),
    lists:map(fun(Item)->
              Item#node_info.node
              end,List).

join_cluster()->
    PingList=get_cluster_list() -- [node()],
    logger:debug("find cluster list ~p",[PingList]),
    case ping_list(PingList)  of
        pong ->
            pong;
        pang when PingList =/= []->
            logger:warning("can not join to cluster nodes:~p",[PingList]),
            pang;
        pang ->
            logger:warning("node is not config cluster list",[]),
            pang
    end.


ping_list([])->
    pang;
ping_list([Node | NodeList])->
    case net_adm:ping(Node) of
        pang ->
            ping_list(NodeList);
        pong ->
            ping_list(NodeList),
            pong
    end.


%% @doc 广播一个节点已经启动
notification_nodeup()->
    TypeList=[{node(),node_type()}],
    notification_nodeup(TypeList).

notification_nodeup(TypeList)->
    gen_server:abcast(nodes(),autocluster_monitor, {notificaion_node_type,TypeList}),
    ok.


get_config(prefix)->
    Prefix = application:get_env(autocluster,prefix,"erlang_cluster"),
    list_to_binary(Prefix);
get_config(env)->
    Env = application:get_env(autocluster,env,prod),
    atom_to_binary(Env,utf8);
get_config(node_type)->
    NodeType = application:get_env(autocluster,node_type,default),
    atom_to_binary(NodeType,utf8).