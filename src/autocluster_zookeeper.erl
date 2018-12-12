%%%-------------------------------------------------------------------
%%% @author dlive
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 30. Nov 2018 11:32 PM
%%%-------------------------------------------------------------------
-module(autocluster_zookeeper).
-author("dlive").

-behaviour(gen_server).

%% API
-export([start_link/0,register_node/3,query_registed_list/2]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-include("autocluster.hrl").

-record(state, {zk_pid,prefix,env}).

-ifdef(TEST).
-compile(export_all).
-endif.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([]) ->
    {ok,Pid} = connection(),
    {ok, #state{zk_pid=Pid}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call({query_registed_list,Prefix,Env},_,State)->
    Path = << <<"/">>/binary,Prefix/binary,<<"/">>/binary,Env/binary,<<"/nodes">>/binary >>,
    {ok,List } = get_node_list(State#state.zk_pid,Path),
    {reply,{ok,List},State};
handle_call({register_node,Prefix,Env,NodeType},_From,State)->
    write_node_info(State#state.zk_pid,Prefix,Env,NodeType),
    {reply,{ok},State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

connection()->
    {ok,List} = application:get_env(autocluster,zookeeper_list),
    {ok, Pid} = erlzk:connect(List, 30000, [
        {chroot, "/"},
        {monitor, self()}]),
    {ok,Pid}.


create_path(Pid,Path,CreateType)->
    case erlzk:create(Pid,Path,CreateType) of
        {ok,ActualPath}->
            lager:debug("create zk path  success ~p",[ActualPath]),
            ok;
        {error,R1}->
            lager:debug("create zk path error ~p ~p",[Path,R1])
    end,
    ok.

check_and_create_path(ZkPid,PathList)->
    check_and_create_path(ZkPid,<<"">>,PathList).
check_and_create_path(_,_,[]) ->
    ok;
check_and_create_path(ZkPid,RootPath,[{Item,CreateType}|Rst])->
    CheckPath= << RootPath/binary,<<"/">>/binary,Item/binary>>,
    case erlzk:exists(ZkPid,CheckPath) of
        {ok,_Stat} ->
            check_and_create_path(ZkPid,CheckPath,Rst);
        {error,no_node}->
            lager:info("check_and_create_path unexist no_node ~p",[CheckPath]),
            create_path(ZkPid,CheckPath,CreateType),
            check_and_create_path(ZkPid,CheckPath,Rst);
        {error,R1} ->
            lager:info("check_and_create_path unexist ~p ~p",[R1,CheckPath]),
            check_and_create_path(ZkPid,CheckPath,Rst)
    end.

encode_node_info(NodeType)->
    Value=io_lib:format(<<"node=~s&node_type=~s&timestamp=~p&ip=~s">>,
        [
            atom_to_binary(node(),utf8),
            NodeType,
            time_util:timestamp(),
            local_ip_v4_str()
        ]),
    lists:flatten(Value).

decode_node_info(NodeStr)->
    NodeStr2 =http_uri:decode(NodeStr),
    KVList = string:split(NodeStr2,"&"),
    NodeInfo = decode_node_info(KVList,#node_info{}),
    {ok,NodeInfo}.
decode_node_info([],NodeInfo)->
    NodeInfo;
decode_node_info([InfoItem|Rst],NodeInfo)->
    case string:split(InfoItem,"=") of
        [Key,Value] ->
            NodeInfo2= decode_node_info(Key,Value,NodeInfo),
            decode_node_info(Rst,NodeInfo2);
        _KeyValue->
            error,
            decode_node_info(Rst,NodeInfo)
    end.
decode_node_info("timestamp",Value,NodeInfo)->
    NodeInfo#node_info{created_time = list_to_integer(Value)};
decode_node_info("ip",Value,NodeInfo)->
    NodeInfo#node_info{ip = Value};
decode_node_info("node_type",Value,NodeInfo)->
    NodeInfo#node_info{node_type = list_to_atom(Value)};
decode_node_info("node",Value,NodeInfo)->
    NodeInfo#node_info{node = list_to_atom(Value)};
decode_node_info(_,Value,NodeInfo)->
    NodeInfo.


register_node(Prefix,Env,NodeType)->
    try gen_server:call(?SERVER,{register_node,Prefix,Env,NodeType},5000) of
        {ok}->
            ok
    catch
        T:R->
            lager:debug("autocluster register node fail ~p ~p",[T,R]),
            fail
    end.
query_registed_list(Prefix,Env)->
    try gen_server:call(?SERVER,{query_registed_list,Prefix,Env},5000) of
        {ok,List}->
            List
    catch
        T:R->
            lager:debug("autocluster query registed list fail ~p ~p",[T,R]),
            []
    end.

write_node_info(Pid,Prefix,Env,NodeType)->
    NodeInfo = encode_node_info(NodeType),

    NodeInfo2= list_to_binary(edoc_lib:escape_uri(NodeInfo)),
    check_and_create_path(Pid,[{Prefix,p},{Env,p},{<<"nodes">>,p},{NodeInfo2,e}]),
    ok.


get_node_list(Pid,Path)->
    case erlzk:get_children(Pid,Path,spawn(autocluster_zookeeper,node_watcher,[Path])) of
        {ok,ChildList} ->
            lager:debug("get provider list ~p",[ChildList]),
            NodeList2 =
                lists:map(fun(Item)->
                    {ok,Nodeinfo}=decode_node_info(Item),
                    Nodeinfo
                          end,ChildList),
            {ok,NodeList2};
        {error,R1} ->
            lager:debug("get_provider_list error ~p ~p",[R1,Path]),
            {ok,[]}
    end.

node_watcher(Interface)->
    receive
        {node_children_changed,Path} ->
            gen_server:cast(?SERVER,{provider_node_change,Interface,Path}),
            lager:debug("provider_watcher get event ~p ~p",[node_children_changed,Path]);
        {Event, Path} ->
%%            Path = "/a",
%%            Event = node_created
            lager:debug("provider_watcher get event ~p ~p",[Event,Path])
    end,
    ok.



local_ip_v4() ->
    {ok, Addrs} = inet:getifaddrs(),
    hd([
        Addr || {_, Opts} <- Addrs, {addr, Addr} <- Opts,
        size(Addr) == 4, Addr =/= {127,0,0,1}
    ]).
local_ip_v4_str()->
    {V1,V2,V3,V4} =local_ip_v4(),
    list_to_binary(io_lib:format("~p.~p.~p.~p",[V1,V2,V3,V4])).
