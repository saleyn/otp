%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1998-2013. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%
-module(erl_epmd).

-behaviour(gen_server).

-ifdef(DEBUG).
-define(port_please_failure(), io:format("Net Kernel 2: EPMD port please failed at ~p:~p~n", [?MODULE,?LINE])).
-define(port_please_failure2(Term), io:format("Net Kernel 2: EPMD port please failed at ~p:~p [~p]~n", [?MODULE,?LINE,Term])).
-else.
-define(port_please_failure(), noop).
-define(port_please_failure2(Term), noop).
-endif.

%% External exports
-export([start/0, start_link/0, stop/0,
     port_please/2, port_please/3, port_please/4,
     names/0, names/1, names/2,
	 register_node/3, register_node/4,
     open/0, open/1, open/2, open/3]).

%% Deprecated External exports
-export([register_node/2]).
-deprecated([register_node/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, 
	 terminate/2, code_change/3]).

-import(lists, [reverse/1]).

-record(state, {socket, name = "", portprotos = []}).
-type state() :: #state{}.

-include("inet_int.hrl").
-include("erl_epmd.hrl").


%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start() ->
    gen_server:start({local, erl_epmd}, ?MODULE, [], []).


start_link() ->
    gen_server:start_link({local, erl_epmd}, ?MODULE, [], []).


stop() ->
    gen_server:call(?MODULE, stop, infinity).

-type port_please_reply() ::
        {ports, [{Port :: integer(), Proto :: atom()}],
                Version :: integer(),
                Opts :: [{epmd, {Addr :: tuple(), Port :: non_neg_integer()}} |
                         {extra, Extra :: binary()}]} |
        noport.
%% Lookup a node "Node" at Host given a list of supported protocols.
%%
-spec port_please(Node :: atom() | string(), Host :: atom() | list() | tuple()) ->
        port_please_reply().
port_please(Node, Host) ->
  port_please(Node, Host, infinity).

-spec port_please(Node :: atom() | string(), Host :: atom() | list() | tuple(),
                  infinity | non_neg_integer() | [string()]) ->
        port_please_reply().
port_please(Node, HostName, Timeout) when is_integer(Timeout); Timeout =:= infinity ->
  port_please1(Node, HostName, net_kernel:dist_protos(), Timeout, system);
port_please(Node, HostName, Protos) when is_list(Protos) ->
  port_please(Node, HostName, Protos, infinity).

-spec port_please(Node :: atom() | string(), Host :: atom() | list() | tuple(),
                   Protos :: [string()], Timeout :: infinity | non_neg_integer()) ->
        port_please_reply().
port_please(Node,HostName, Protos, Timeout) when is_atom(HostName), is_list(Protos) ->
  port_please1(Node, atom_to_list(HostName), Protos, Timeout, user);
port_please(Node, HostName, Protos, Timeout) when is_list(HostName), is_list(Protos) ->
  port_please1(Node,HostName, Protos, Timeout, user);
port_please(Node, EpmdAddr, Protos, Timeout) ->
  get_ports(Node, EpmdAddr, Protos, Timeout, user).



port_please1(Node, HostName, Protos, Timeout, DistSource) ->
  case inet:gethostbyname(HostName, inet, Timeout) of
    {ok,{hostent, _Name, _ , _Af, _Size, [EpmdAddr | _]}} ->
      get_ports(Node, EpmdAddr, Protos, Timeout, DistSource);
    Else ->
      Else
  end.

names() -> 
  {ok, H} = inet:gethostname(),
  names(H).

names(Port) when is_integer(Port) ->
  {ok, H} = inet:gethostname(),
  names(H, Port);
names(Host) when is_atom(Host); is_list(Host); is_tuple(Host) ->
  names(Host, get_epmd_port()).

names(Host, EpmdPort) ->
  names1(Host, EpmdPort, ?EPMD_NAMES3).

names1(HostName, EpmdPort, Opcode) when is_atom(HostName) ->
  names2(atom_to_list(HostName), EpmdPort, Opcode);
names1(HostName, EpmdPort, Opcode) when is_list(HostName) ->
  names2(HostName, EpmdPort, Opcode);
names1(EpmdAddr, EpmdPort, Opcode) ->
  get_names(EpmdAddr, EpmdPort, Opcode).

names2(HostName, EpmdPort, Opcode) when is_integer(Opcode) ->
  case inet:gethostbyname(HostName) of
    {ok,{hostent, _Name, _ , _Af, _Size, [EpmdAddr | _]}} ->
      get_names(EpmdAddr, EpmdPort, Opcode);
    Else ->
      Else
  end.


-spec register_node(Name :: atom() | string(), PortNo :: non_neg_integer()) ->
            {alive, Socket :: inet:socket(), Creation :: integer()} |
            {error, any()}.
register_node(Name, PortNo) ->
    register_node(Name, PortNo, "inet_tcp").

-spec register_node(Name :: atom() | string(), PortNo :: non_neg_integer(),
        Proto :: string()) ->
            {alive, Socket :: inet:socket(), Creation :: integer()} |
            {error, any()}.
register_node(Name, PortNo, Proto) when is_list(Proto) ->
    register_node(Name, PortNo, Proto, <<>>).

-spec register_node(Name :: atom() | string(), PortNo :: non_neg_integer(),
        Proto :: string(), Extra :: binary()) ->
            {alive, Socket :: inet:socket(), Creation :: integer()} |
            {error, any()}.
register_node(Name, PortNo, Proto, Extra) when is_list(Proto), is_binary(Extra) ->
    gen_server:call(erl_epmd, {register, Name, PortNo, Proto, Extra}, infinity).

%%%----------------------------------------------------------------------
%%% Callback functions from gen_server
%%%----------------------------------------------------------------------

-spec init(_) -> {'ok', state()}.

init(_) ->
    {ok, #state{socket = -1}}.
	    
%%----------------------------------------------------------------------

-type calls() :: 'client_info_req' | 'stop' |
                 {'register', string(), integer(), string(), binary()}.

-spec handle_call(calls(), term(), state()) ->
        {'reply', term(), state()} | {'stop', 'shutdown', 'ok', state()}.

handle_call({register, Name, PortNo, Proto, Extra}, _From, State) ->
    case do_register_node(State#state.socket, Name, PortNo, Proto, Extra) of
    {alive, Socket, Creation} ->
        P = [{Proto, PortNo} | proplists:delete(Proto, State#state.portprotos)],
        S = State#state{socket = Socket, portprotos = P, name = Name},
        {reply, {ok, Creation}, S};
    Error ->
        {reply, Error, State#state{socket = -1}}
    end;

handle_call(client_info_req, _From, State) ->
    Reply = {ok,{r5,State#state.name,State#state.portprotos}},
    {reply, Reply, State};
  
handle_call(stop, _From, State) ->
    {stop, shutdown, ok, State}.

%%----------------------------------------------------------------------

-spec handle_cast(term(), state()) -> {'noreply', state()}.

handle_cast(_, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------

-spec handle_info(term(), state()) -> {'noreply', state()}.

handle_info({tcp_closed, Socket}, State) when State#state.socket =:= Socket ->
    {noreply, State#state{socket = -1}};
handle_info(_, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------

-spec terminate(term(), state()) -> 'ok'.

terminate(_, #state{socket = Socket}) when Socket > 0 ->
    close(Socket),
    ok;
terminate(_, _) ->
    ok.

%%----------------------------------------------------------------------

-spec code_change(term(), state(), term()) -> {'ok', state()}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

get_epmd_port() ->
    case init:get_argument(epmd_port) of
	{ok, [[PortStr|_]|_]} when is_list(PortStr) ->
	    list_to_integer(PortStr);
	error ->
	    ?erlang_daemon_port
    end.

%%
%% Epmd socket
%%
open() ->
    open({127,0,0,1}).  % The localhost IP address.
open(Addr) ->
    open(Addr, infinity).  % The localhost IP address.
open(Addr, Timeout) ->
    open(Addr, get_epmd_port(), Timeout).

open({A,B,C,D}=EpmdAddr, Port, Timeout) when ?ip(A,B,C,D) ->
    open2(EpmdAddr, Port, [inet], Timeout);
open({A,B,C,D,E,F,G,H}=EpmdAddr, Port, Timeout) when ?ip6(A,B,C,D,E,F,G,H) ->
    open2(EpmdAddr, Port, [inet6], Timeout).

open2(EpmdAddr, EpmdPort, Opts, Timeout) when is_integer(EpmdPort) ->
    gen_tcp:connect(EpmdAddr, EpmdPort, [{packet,2},binary | Opts], Timeout).

close(Socket) ->
    gen_tcp:close(Socket).

do_register_node(Socket, NodeName, Port, Proto, Extra)
        when is_integer(Socket), Socket < 0, is_binary(Extra) ->
    case open() of
    {ok, S} ->
        do_register_node(S, NodeName, Port, Proto, Extra);
    Error ->
        Error
    end;
do_register_node(Socket, NodeName, Port, SProto, Extra)
        when is_list(SProto), is_binary(Extra) ->
    SName = to_string(NodeName),
    Name  = unicode:characters_to_binary(SName),
    Proto = unicode:characters_to_binary(SProto),
    Packet = <<?EPMD_ALIVE3_REQ, Port:16/integer, $M,
               (byte_size(Proto)), Proto/binary,
               (epmd_dist_high()):16/integer,
               (epmd_dist_low()):16/integer,
               (byte_size(Name)):16/integer, Name/binary,
               (byte_size(Extra)):16/integer, Extra/binary>>,
    case gen_tcp:send(Socket, Packet) of
        ok ->
            wait_for_reg_reply(Socket);
        Error ->
            close(Socket),
            Error
    end.

epmd_dist_high() ->
    case os:getenv("ERL_EPMD_DIST_HIGH") of
	false ->
	   ?epmd_dist_high; 
	Version ->
	    case (catch list_to_integer(Version)) of
		N when is_integer(N), N < ?epmd_dist_high ->
		    N;
		_ ->
		   ?epmd_dist_high
	    end
    end.

epmd_dist_low() ->
    case os:getenv("ERL_EPMD_DIST_LOW") of
	false ->
	   ?epmd_dist_low; 
	Version ->
	    case (catch list_to_integer(Version)) of
		N when is_integer(N), N > ?epmd_dist_low ->
		    N;
		_ ->
		   ?epmd_dist_low
	    end
    end.
		    


%%% (When we reply 'duplicate_name', it's because it's the most likely
%%% reason; there is no interpretation of the error result code.)
wait_for_reg_reply(Socket) ->
    receive
	{tcp, Socket, <<?EPMD_ALIVE2_RESP, 0, Creation:16/integer>>} ->
        {alive, Socket, Creation};
	{tcp, Socket, <<?EPMD_ALIVE2_RESP, _>>} ->
        {error, duplicate_name};
	{tcp, Socket, Garbage} ->
        {error, {garbage_from_epmd, Garbage}};
	{tcp_closed, Socket} ->
	    {error, epmd_close}
    after 10000 ->
	    gen_tcp:close(Socket),
	    {error, no_reg_reply_from_epmd}
    end.
    
%%
%% Lookup a node "Name" at Host
%%

get_ports(_Node, _EpmdAddress, [], _Timeout, system) ->
    noport;
get_ports(Node, EpmdAddress, [], Timeout, user) ->
    get_ports(Node, EpmdAddress, net_kernel:dist_protos(), Timeout, system);
get_ports(Node, EpmdAddress, Protos, Timeout, _DistSource) when is_list(Protos) ->
    case open(EpmdAddress, Timeout) of
	{ok, Socket} ->
        Msg = encode_port_please(Node, Protos),
	    case gen_tcp:send(Socket, Msg) of
		ok ->
		    wait_for_port_reply(Socket);
		_Error ->
		    ?port_please_failure2(_Error),
		    noport
	    end;
	_Error -> 
	    ?port_please_failure2(_Error),
	    noport
    end.

encode_proto(Proto) ->
    Bin = unicode:characters_to_binary(Proto),
    [byte_size(Bin), Bin].

encode_port_please(Node, Protos) ->
    % R17 packet format
    SNode = to_string(Node),
    Name  = unicode:characters_to_binary(SNode),
    BProt = list_to_binary([encode_proto(N) || N <- Protos]),
    <<?EPMD_PORT3_REQ, 0, (length(Protos)),
        (byte_size(BProt)):16/integer, BProt/binary,
        (byte_size(Name)), Name/binary>>.

wait_for_port_reply(Socket) ->
    {ok, AddrPort} = inet:peername(Socket),
    receive
	{tcp, Socket, % R17 packet format
        <<?EPMD_PORT2_RESP,
            0,              % Result
            0:16/integer,   % Filler
            _ProtoCount,
            Len:16/integer,  Protos:Len/binary,
            _NodeType,
            High:16/integer, Low:16/integer,
            NLen:16/integer,_Name:NLen/binary,
            ELen:16/integer, Extra:ELen/binary>>} ->
        Version    = best_version(Low, High),
        PortProtos = split_port_protos(Protos),
        {ports, PortProtos, Version, reply_opts(AddrPort, Extra)};
	%{tcp, Socket, % R16 packet format
    %    <<?EPMD_PORT2_RESP, 0, Port:16/integer, _Tp, Proto,
    %        High:16/integer, Low:16/integer,
    %        NLen:16/integer,_Name:NLen/binary,
    %       ELen:16/integer, Extra:ELen/binary>>} ->
    %   Version = best_version(Low, High),
    %   {ports, [{Port, proto_mod(Proto)}], Version, reply_opts(AddrPort,Extra)};
	{tcp, Socket, <<?EPMD_PORT2_RESP, _, _/binary>>} ->
        ?port_please_failure(),
        wait_for_close(Socket, noport);
	{tcp, Socket, <<?EPMD_PORT2_RESP, Garbage/binary>>} ->
        ?port_please_failure(),
        {error, {garbage_from_epmd, Garbage}};
	{tcp_closed, Socket} ->
	    ?port_please_failure(),
	    closed
    after 10000 ->
	    ?port_please_failure(),
	    gen_tcp:close(Socket),
	    noport
    end.

%proto_mod(0) -> "inet_tcp";
%proto_mod(_) -> "".

reply_opts(AddrPort, <<>>)  -> [{epmd, AddrPort}];
reply_opts(AddrPort, Extra) -> [{epmd, AddrPort}, {extra, Extra}].

split_port_protos(<<>>) ->
    [];
split_port_protos(<<I:16/integer, Len, Proto:Len/binary, Rest/binary>>) ->
    [{I, binary_to_list(Proto)} | split_port_protos(Rest)].

best_version(Low, High) ->
    OurLow =  epmd_dist_low(),
    OurHigh =  epmd_dist_high(),
    select_best_version(OurLow, OurHigh, Low, High).

%%% We silently assume that the low's are not greater than the high's.
%%% We should report if the intervals don't overlap.
select_best_version(L1, _H1, _L2, H2) when L1 > H2 ->
    0;
select_best_version(_L1, H1, L2, _H2) when L2 > H1 ->
    0;
select_best_version(_L1, H1, L2, _H2) when L2 > H1 ->
    0;
select_best_version(_L1, H1, _L2, H2) ->
    erlang:min(H1, H2).

wait_for_close(Socket, Reply) ->
    receive
	{tcp_closed, Socket} -> 
	    Reply
    after 10000 ->
	    gen_tcp:close(Socket),
	    Reply
    end.


%%
%% Creates a (flat) null terminated string from atom or list.
%%

to_string(S) when is_atom(S) -> atom_to_list(S);
to_string(S) when is_list(S) -> S.

get_data(Socket, Timeout) ->
    receive
    {tcp, Socket, Data} ->
        {ok, Data};
    {tcp_closed, Socket} ->
        {error, endofdata}
    after Timeout ->
        {error, timeout}
    end.

%%
%% Find names on epmd
%%
%%
get_names(EpmdAddress, EpmdPort, Opt) ->
    case open(EpmdAddress, EpmdPort, infinity) of
	{ok, Socket} ->
        ok = gen_tcp:send(Socket, <<Opt>>),
        case get_data(Socket, 10000) of
        {ok, <<MoreData, Port:32/integer, Data/binary>>} when Port =:= EpmdPort ->
            do_get_names(Socket, MoreData, [Data]);
        {ok, <<_MoreData, Port:32/integer, _/binary>>} when Port =/= EpmdPort ->
            close(Socket),
            {error, address};
        Other ->
            close(Socket),
            Other
        end;
	Error ->
	    Error
    end.

do_get_names(Socket, 1, Acc) ->
    case get_data(Socket, 10000) of
	{ok, <<MoreData, Data/binary>>} ->
        do_get_names(Socket, MoreData, [Data | Acc]);
    {error, Reason} ->
        {error, Reason}
    end;
do_get_names(Socket, 0, Acc) ->
    close(Socket),
    Data = lists:foldl(fun(Bin, A) ->
        L = [parse_name(binary:split(B, <<" ">>, [global,trim]))
             || <<"name ", B/binary>> <- binary:split(Bin, <<"\n">>,
                                                  [global,trim])],
        L ++ A
    end, [], Acc),
    {ok, Data}.

parse_name([Name | Data]) ->
    parse_name(binary_to_list(Name), Data).
parse_name(Name, [<<"at">>, <<"port">> | PortProtos]) ->
    {Name, [begin
               [I, S] = binary:split(B, <<"#">>),
               {binary_to_integer(I), binary_to_list(S)}
            end || B <- PortProtos]}.
%parse_name(Name, [<<"at">>, <<"port">>, Port], ?EPMD_NAMES2) ->
%    {Name, binary_to_integer(Port)}.% Legacy R16 format
