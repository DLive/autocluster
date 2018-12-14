%%%-------------------------------------------------------------------
%%% @author dlive
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 01. Dec 2018 11:14 AM
%%%-------------------------------------------------------------------
-module(autocluster_monitor).
-author("dlive").

-behaviour(gen_server).
-define(SERVER, ?MODULE).
%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([query_node_typelists/1]).
%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
-record(state, {precheck_time = 0, self_type}).
-record(node_typelist, {node_type, type}).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) ->
    (catch ets:new(node_typelists, [public, named_table, {read_concurrency, true}])),
    ok = net_kernel:monitor_nodes(true),
    {ok, #state{self_type = autocluster:node_type()}}.

insert_node_typelists(TypeNodelist) ->
    lists:foreach(
        fun(X) ->
            (catch ets:insert(node_typelists, {X, field_ignore})),
            ok
        end, TypeNodelist),
    ok.
delete_node_typelists(Node) ->
    ets:match_delete(node_typelists, {{Node, '_'}, '_'}).

%% 获取集群节点分类列表  解决call这个服务造成的性能问题
query_node_typelists(Type) ->
    try ets:match(node_typelists, {{'$1', Type}, '_'}) of
        [] ->
            gen_server:cast(?SERVER, {nodeinfo_recheck}),
            [];
        RetNodeList ->
            lists:flatten(RetNodeList)
    catch
        _ET:_ER ->
            (catch ets:new(node_typelists, [public, named_table, {read_concurrency, true}])),
            []
    end.
%% @doc 获取集群节点分类列表
handle_call({typenode_list, Type}, _From, State) ->
    RetNodeList = query_node_typelists(Type),
    {reply, {ok, RetNodeList}, State};

%% @doc 获取集群当前节点的类型
handle_call({sync_node_info}, _From, State) ->
    logger:info("reciver one sync_node_info from:~p", [_From]),
    Self_typelist = get_self_typelist(State),
    {reply, {ok, Self_typelist}, State};

handle_call({sync_nodeid, Nodeid}, _From, State) ->
    logger:info("reciver one sync_nodeid from:~p", [_From]),
    {reply, {ok}, State};


handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%收到一个通知，一个新的节点类型已启动
handle_cast({notificaion_node_type, Node_TypeList}, State) ->
    logger:info("notificaion_node_type:~p", [Node_TypeList]),
    insert_node_typelists(Node_TypeList),
    {noreply, State};



handle_cast({nodeinfo_recheck}, State) ->
    PreCheckTime = State#state.precheck_time,
    Now = time_util:timestamp(),
    if
        (Now - PreCheckTime) > 30 ->
            {ok, Type_nodelist} = sync_other_nodeinfo(),
            insert_node_typelists(Type_nodelist), %%同时存储到内存表
            {noreply, State#state{precheck_time = Now}};
        true ->
            {noreply, State}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({nodeup, Node}, State) ->
    logger:info("[nodeup] get event nodeup node name:~p", [Node]),
    {noreply, State};

handle_info({timeout, _TimerRef, {check_cluster_node}}, State) ->
    check_cluster_node(State),
    {noreply, State};

handle_info({timeout, _TimerRef, {re_sync_nodeinfo, NodeList}}, State) ->
    {ok, Type_nodelist} = sync_other_nodeinfo(NodeList),
    insert_node_typelists(Type_nodelist),
    {noreply, State};

handle_info({nodedown, Node}, State) ->
    delete_node_typelists(Node),
    check_cluster_node(State), %%进行节点检查。
    logger:info("node ~w was down", [Node]),
    notice_down(Node),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
sync_other_nodeinfo() ->
    sync_other_nodeinfo(nodes()).
sync_other_nodeinfo(NodeList) ->
    Type_nodelist = lists:foldl(
        fun(X, TypeList) ->
            logger:info("sync_node_info will  sync from ~p", [X]),
            try gen_server:call({push_node_monitor, X}, {sync_node_info}, 3000) of
                {ok, NodeInfo} ->
                    logger:info("sync_node_info success from ~p, ~w", [X, NodeInfo]),
                    TypeList ++ NodeInfo
            catch
                ET:ER ->
                    logger:info("sync_node_info fail from ~p, et:~p er:~p", [X, ET, ER]),
                    Timout = case random:uniform(60) of
                                 0 ->
                                     20000;
                                 Other ->
                                     Other * 1000
                             end,
                    logger:info("re_sync_nodeinfo  timeout:~p", [Timout]),
                    erlang:start_timer(Timout, self(), {re_sync_nodeinfo, [X]}),
                    TypeList
            end
%%            {ok, NodeInfo} = gen_server:call({push_node_monitor, X}, {sync_node_info}),
        end, [], NodeList),
    {ok, Type_nodelist}.


%% @doc 检查是否已加入集群
check_cluster_node(State) ->
    case nodes() of
        [] ->
            case autocluster:join_cluster() of
                pong ->
                    SelfTypelist = get_self_typelist(State),
                    app_util:notification_nodeup(SelfTypelist);
                pang ->
                    erlang:start_timer(4000, self(), {check_cluster_node})
            end;
        _ ->
            ok
    end.
get_self_typelist(State) ->
    [{node(), State#state.self_type}].

notice_down(Node) ->
    ThisNode = node(),
    case get_max_hash_node() of
        {_, ThisNode} ->
            mod_paf_monitor:node_down(Node);
        _Unknow ->
            ok
    end,
    ok.

get_max_hash_node() ->
    NodeList = nodes() ++ [node()],
    {NodeList2, MaxValue} = lists:mapfoldl(fun(X, Acc) ->
        Value = erlang:phash2(X, 10240),
        Max = if
                  Value > Acc; Acc == 0 ->
                      Value;
                  true ->
                      Acc
              end,
        {{Value, X}, Max}
                                           end, 0, NodeList),
    lists:keyfind(MaxValue, 1, NodeList2).