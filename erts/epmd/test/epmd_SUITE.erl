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
-module(epmd_SUITE).
-include_lib("test_server/include/test_server.hrl").
-include_lib("kernel/include/file.hrl").


% Timeout for test cases (rather long to work on slow machines)
-define(SHORT_TEST_TIMEOUT, ?t:seconds(30)).	% Default
-define(MEDIUM_TEST_TIMEOUT, ?t:minutes(3)).
-define(LONG_TEST_TIMEOUT, ?t:minutes(10)).

% Delay inserted into code
-define(SHORT_PAUSE, 100).
-define(MEDIUM_PAUSE, ?t:seconds(1)).
-define(LONG_PAUSE, ?t:seconds(5)).

% Information about nodes
-record(node_info, {port, node_type, prot, lvsn, hvsn, node_name, extra}).

% Test server specific exports
-export([all/0, suite/0,groups/0,init_per_suite/1, end_per_suite/1, 
	 init_per_group/2,end_per_group/2, 
	 init_per_testcase/2, end_per_testcase/2]).

-export(
   [
    register_name/1,
    register_name_v3/1,
    register_names_1/1,
    register_names_2/1,
    register_duplicate_name/1,
    unicode_name/1,
    long_unicode_name/1,
    get_port_nr/1,
    slow_get_port_nr/1,
    unregister_others_name_1/1,
    unregister_others_name_2/1,
    register_overflow/1,
    name_with_null_inside/1,
    name_null_terminated/1,
    stupid_names_req/1,
    names3_req/1,

    no_data/1,
    one_byte/1,
    two_bytes/1,
    partial_packet/1,
    zero_length/1,
    too_large/1,
    alive_req_too_small_1/1,
    alive_req_too_small_2/1,
    alive_req_too_large/1,

    returns_valid_empty_extra/1,
    returns_valid_populated_extra_with_nulls/1,

    buffer_overrun_1/1,
    buffer_overrun_2/1,
    no_nonlocal_register/1,
    no_nonlocal_kill/1,
    no_live_killing/1
   ]).


% Port we use for testing
-define(PORT,2243).
-define(EPMDARGS,"-packet_timeout 1").

-define(DUMMY_PORT, 1000).			% Port number to register
						% not in real use.

% Timeouts etc inside test cases. Time is in milliseconds.
-define(CONN_RETRY, 4).				% Times to retry connecting
-define(CONN_SLEEP, 500).
-define(CONN_TIMEOUT, 100).
-define(RECV_TIMEOUT, 2000).
-define(REG_REPEAT_LIM,1000).

% Message codes in epmd protocol
-define(EPMD_ALIVE2_REQ, $x).
-define(EPMD_ALIVE3_REQ, $X).
-define(EPMD_PORT2_REQ,  $z).
-define(EPMD_PORT3_REQ,  $Z).
-define(EPMD_ALIVE2_RESP,$y).
-define(EPMD_PORT2_RESP, $w).
-define(EPMD_NAMES2,     $n).
-define(EPMD_NAMES3,     $N).

%% Commands used only by interactive client
-define(EPMD_DUMP, $d).
-define(EPMD_DUMP3,$D).
-define(EPMD_KILL, $k).
-define(EPMD_KILL3,$K).
-define(EPMD_STOP, $s).
-define(EPMD_STOP3,$S).

%%
%% all/1
%%

suite() -> [{ct_hooks,[ts_install_cth]}].

all() -> 
    [register_name, register_names_1, register_names_2,
     register_name_v3, names3_req,
     register_duplicate_name, unicode_name, long_unicode_name,
     get_port_nr, slow_get_port_nr,
     unregister_others_name_1, unregister_others_name_2,
     register_overflow, name_with_null_inside,
     name_null_terminated, stupid_names_req, no_data,
     one_byte, two_bytes, partial_packet, zero_length,
     too_large, alive_req_too_small_1, alive_req_too_small_2,
     alive_req_too_large, returns_valid_empty_extra,
     returns_valid_populated_extra_with_nulls,
     {group, buffer_overrun}, no_nonlocal_register,
     no_nonlocal_kill, no_live_killing].

groups() -> 
    [{buffer_overrun, [],
      [buffer_overrun_1, buffer_overrun_2]}].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.


%%
%% Run before and after each test case
%%

init_per_testcase(_Func, Config) ->
    Dog = test_server:timetrap(?MEDIUM_TEST_TIMEOUT),
    cleanup(),
    [{watchdog, Dog} | Config].

end_per_testcase(_Func, Config) ->
    cleanup(),
    Dog = ?config(watchdog, Config),
    catch test_server:timetrap_cancel(Dog),	% We may have canceled already
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

register_name(doc) ->
    ["Register a name"];
register_name(suite) ->
    [];
register_name(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = register_node("foobar"),
    ?line ok = close(Sock),			% Unregister
    ok.

register_name_v3(doc) ->
    ["Register a name epmd v3"];
register_name_v3(suite) ->
    [];
register_name_v3(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = register_node_v3("foobar", 12345, <<"abc">>),
    ?line ok = close(Sock),			% Unregister
    ok.

register_names_1(doc) ->
    ["Register and unregister two nodes"];
register_names_1(suite) ->
    [];
register_names_1(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock1} = register_node("foobar"),
    ?line {ok,Sock2} = register_node("foozap"),
    ?line ok = close(Sock1),			% Unregister
    ?line ok = close(Sock2),			% Unregister
    ok.

register_names_2(doc) ->
    ["Register and unregister two nodes"];
register_names_2(suite) ->
    [];
register_names_2(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock1} = register_node("foobar"),
    ?line {ok,Sock2} = register_node("foozap"),
    ?line ok = close(Sock2),			% Unregister
    ?line ok = close(Sock1),			% Unregister
    ok.

register_duplicate_name(doc) ->
    ["Two nodes with the same name"];
register_duplicate_name(suite) ->
    [];
register_duplicate_name(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = register_node("foobar"),
    ?line error = register_node("foobar"),
    ?line ok = close(Sock),			% Unregister
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

unicode_name(doc) ->
    ["Check that we can register and lookup a unicode name"];
unicode_name(suite) ->
    [];
unicode_name(Config) when is_list(Config) ->
    ok = epmdrun(),
    NodeName = [16#1f608],
    {ok,Sock} = register_node_v2(4711, 72, 0, 5, 5, NodeName, []),
    {ok,NodeInfo} = port_please_v2(NodeName),
    NodeName = NodeInfo#node_info.node_name,
    ok = close(Sock),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

long_unicode_name(doc) ->
    ["Check that we can register and lookup a long unicode name"];
long_unicode_name(suite) ->
    [];
long_unicode_name(Config) when is_list(Config) ->
    ok = epmdrun(),
    BaseChar = 16#1f600,
    NodeName = lists:seq(BaseChar, BaseChar+200), % will be 800 bytes long
    {ok,Sock} = register_node_v2(4711, 72, 0, 5, 5, NodeName, []),
    {ok,NodeInfo} = port_please_v2(NodeName),
    NodeName = NodeInfo#node_info.node_name,
    ok = close(Sock),
    ok.

% Internal function to register a node name, no close, i.e. unregister

register_node(Name) ->
    register_node_v2(?DUMMY_PORT,$M,0,5,5,Name,"").
register_node(Name,Port) ->
    register_node_v2(Port,$M,0,5,5,Name,"").

register_node_v2(Port, NodeType, Prot, HVsn, LVsn, Name, Extra) ->
    Utf8Name = unicode:characters_to_binary(Name),
    Req = [?EPMD_ALIVE2_REQ, put16(Port), NodeType, Prot,
	   put16(HVsn), put16(LVsn),
	   put16(size(Utf8Name)), binary_to_list(Utf8Name),
	   size16(Extra), Extra],
    case send_req(Req) of
	{ok,Sock} ->
	    case recv(Sock,4) of
		{ok, [?EPMD_ALIVE2_RESP,_Res=0,_C0,_C1]} ->
		    {ok,Sock};
		Other ->
		    test_server:format("recv on sock ~w: ~p~n",
				       [Sock,Other]),
		    error
	    end;
	error ->
	    error
    end.

register_node_v3(Name, Port, Extra) ->
    register_node_v3(Port, $M, "inet_tcp", 5, 5, Name, Extra).
register_node_v3(Port, NodeType, Proto, HVsn, LVsn, Name, Extra) ->
    Utf8Name = unicode:characters_to_binary(Name),
    Packet = <<?EPMD_ALIVE3_REQ, Port:16/integer, NodeType,
               (length(Proto)), (list_to_binary(Proto))/binary,
               (HVsn):16/integer,
               (LVsn):16/integer,
               (byte_size(Utf8Name)):16/integer, Utf8Name/binary,
               (byte_size(Extra)):16/integer, Extra/binary>>,
    case connect_opt([{packet, 2}, binary]) of
    {ok, S} ->
        ?line ok = send_direct(S, Packet),
        receive
        {tcp, S, <<?EPMD_ALIVE2_RESP, 0, _Creation:16/integer>>} ->
            {ok, S};
        Err ->
            {error, Err}
        after 10000 ->
            {error, no_req_reply_from_epmd}
        end;
    Error ->
        Error
    end.

% Internal function to fetch information about a node

port_please_v2(Name) ->
    case send_req([?EPMD_PORT2_REQ,
		   binary_to_list(unicode:characters_to_binary(Name))]) of
	{ok,Sock} ->
	    case recv_until_sock_closes(Sock) of
		{ok, Resp} ->
		    parse_port2_resp(Resp);
		Other ->
		    test_server:format("recv on sock ~w: ~p~n",
				       [Sock,Other]),
		    error
	    end;
	error ->
	    error
    end.

parse_port2_resp(Resp) ->
    case list_to_binary(Resp) of
	<<?EPMD_PORT2_RESP,Res,Port:16,NodeType,Prot,HVsn:16,LVsn:16,
	  NLen:16,NodeName:NLen/binary,
	  ELen:16,Extra:ELen/binary>> when Res =:= 0 ->
	    {ok, #node_info{port=Port,node_type=NodeType,prot=Prot,
			    hvsn=HVsn,lvsn=LVsn,
			    node_name=unicode:characters_to_list(NodeName),
			    extra=binary_to_list(Extra)}};
	_Other ->
	    test_server:format("invalid port2 resp: ~p~n",
			       [Resp]),
	    error
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

name_with_null_inside(doc) ->
    ["Register a name with a null char in it"];
name_with_null_inside(suite) ->
    [];
name_with_null_inside(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line error = register_node("foo\000bar"),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

name_null_terminated(doc) ->
    ["Register a name with terminating null byte"];
name_null_terminated(suite) ->
    [];
name_null_terminated(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line error = register_node("foobar\000"),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

stupid_names_req(doc) ->
    ["Read names from epmd in a stupid way"];
stupid_names_req(suite) ->
    [];
stupid_names_req(Config) when is_list(Config) ->
    Dog = ?config(watchdog, Config),
    test_server:timetrap_cancel(Dog),
    LongDog = test_server:timetrap(?MEDIUM_TEST_TIMEOUT),
    ?line ok = epmdrun(),
    ?line [FirstConn | Conn] = register_many(1, ?REG_REPEAT_LIM, "foo"),
    ?line unregister_many([FirstConn]),
    sleep(?MEDIUM_PAUSE),
    ?line ok = check_names(Conn, ?EPMD_NAMES2),
    ?line ok = unregister_many(Conn),
    test_server:timetrap_cancel(LongDog),
    ok.

check_names(Conn, ?EPMD_NAMES2 = Opcode) ->
    ?line {ok,Sock} = connect_active(),
    ?line {ok,Reply} = do_get_names(Sock, Opcode),
    ?line SortConn  = lists:sort(Conn),
    ?line SortReply = lists:sort(Reply),
    ?line ok = check_names_cmp(SortConn, SortReply),
    ok;
check_names(Conn, ?EPMD_NAMES3) ->
    ?line {ok, Reply} = erl_epmd:names(?PORT),
    ?line SortConn  = lists:sort(Conn),
    ?line SortReply = lists:sort(Reply),
    ?line ok = check_names_cmp(SortConn, SortReply),
    ok.


names3_req(doc) ->
    ["Read names from epmd using epmd v3 protocol"];
names3_req(suite) ->
    [];
names3_req(Config) when is_list(Config) ->
    Dog = ?config(watchdog, Config),
    test_server:timetrap_cancel(Dog),
    LongDog = test_server:timetrap(?MEDIUM_TEST_TIMEOUT),
    ?line ok = epmdrun(),
    ?line Conn = register_many(1, ?REG_REPEAT_LIM, "foo", v3),
    ?line ok = check_names(Conn, ?EPMD_NAMES3),
    ?line ok = unregister_many(Conn),
    test_server:timetrap_cancel(LongDog),
    ok.
    

% Compare if the result was the same as was registered

check_names_cmp([], []) ->
    ok;
check_names_cmp([{Name,Port,_Sock} | Conn], [{Name,Port} | Reply]) ->
    check_names_cmp(Conn, Reply);
check_names_cmp([{Name,Port,_Sock} | Conn], [{Name,[{Port,"inet_tcp"}]} | Reply]) ->
    check_names_cmp(Conn, Reply).

% This code is taken directly from "erl_epmd.erl" in R3A01

-define(int16(X), [(X bsr 8) band 16#ff, X band 16#ff]).
-define(u32(X1,X2,X3,X4), 
	(((X1) bsl 24) bor ((X2) bsl 16) bor ((X3) bsl 8) bor X4)).

do_get_names(Socket, ?EPMD_NAMES2) ->
    ok = gen_tcp:send(Socket, [?int16(1),?EPMD_NAMES2]),
    receive
	{tcp, Socket, [P0,P1,P2,P3 | T]} ->
	    EpmdPort = ?u32(P0,P1,P2,P3),
	    if EpmdPort == ?PORT ->
		    names_loop(Socket, T, []);
	       true ->
		    close(Socket),
		    {error, address}
	    end;
	{tcp_closed, Socket} ->
	    {ok, []}
    end;
do_get_names(Socket, ?EPMD_NAMES3) ->
    ok = gen_tcp:send(Socket, [?int16(1),?EPMD_NAMES3]),
    receive
	{tcp, Socket, [P0,P1,P2,P3 | T]} ->
	    EpmdPort = ?u32(P0,P1,P2,P3),
	    if EpmdPort == ?PORT ->
		    names_loop(Socket, T, []);
	       true ->
		    close(Socket),
		    {error, address}
	    end;
	{tcp_closed, Socket} ->
	    {ok, []}
    end.

names_loop(Socket, Acc, Ps) ->
    receive
	{tcp, Socket, Bytes} ->
	    {NAcc, NPs} = scan_names(Acc ++ Bytes, Ps),
	    names_loop(Socket, NAcc, NPs);
	{tcp_closed, Socket} ->
	    {_, NPs} = scan_names(Acc, Ps),	% Really needed?
	    {ok, NPs}
    end.

scan_names(Buf, Ps) ->
    case scan_line(Buf, []) of
	{Line, NBuf} ->
	    case parse_line(Line) of
		{ok, Entry} -> 
		    scan_names(NBuf, [Entry | Ps]);
		error ->
		    scan_names(NBuf, Ps)
	    end;
	[] -> {Buf, Ps}
    end.

scan_line([$\n | Buf], Line) -> {lists:reverse(Line), Buf};
scan_line([C | Buf], Line) -> scan_line(Buf, [C|Line]);
scan_line([], _) -> [].

parse_line([$n,$a,$m,$e,$ | Buf0]) ->
    case parse_name(Buf0, []) of
	{Name, Buf1}  ->
	    case Buf1 of
		[$a,$t,$ ,$p,$o,$r,$t,$ | Buf2] ->
		    case catch list_to_integer(Buf2) of
			{'EXIT', _} -> error;
			Port -> {ok, {Name, Port}}
		    end;
		_ -> error
	    end;
	error -> error
    end;
parse_line(_) -> error.


parse_name([$  | Buf], Name) -> {lists:reverse(Name), Buf};
parse_name([C | Buf], Name) -> parse_name(Buf, [C|Name]);
parse_name([], _Name) -> error.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

get_port_nr(doc) ->
    ["Register a name on a port and ask about port nr"];
get_port_nr(suite) ->
    [];
get_port_nr(Config) when is_list(Config) ->
    port_request([?EPMD_PORT2_REQ,"foo"]).

slow_get_port_nr(doc) ->
    ["Register with slow write and ask about port nr"];
slow_get_port_nr(suite) ->
    [];
slow_get_port_nr(Config) when is_list(Config) ->
    port_request([?EPMD_PORT2_REQ,d,$f,d,$o,d,$o]).


% Internal function used above

port_request(M) ->
    ?line ok = epmdrun(),
    Port = 1042,
    ?line {ok,RSock} = register_node("foo", Port),
    ?line {ok,Sock} = connect(),
    ?line ok = send(Sock,[size16(M),M]),
    ?line case recv_until_sock_closes(Sock) of
	      {ok, Resp} ->
		  ?line close(RSock),
		  ?line {ok,Rec} = parse_port2_resp(Resp),
		  ?line Port = Rec#node_info.port,
		  ok;
	      Other ->
		  ?line close(RSock),
		  ?line test_server:format("recv on sock ~w: ~p~n",
					   [Sock,Other]),
		  ?line throw({error,Other})
	  end,
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

unregister_others_name_1(doc) ->
    ["Unregister name of other node"];
unregister_others_name_1(suite) ->
    [];
unregister_others_name_1(Config) when is_list(Config) ->
    ?line ok = epmdrun("-relaxed_command_check"),
    ?line {ok,RSock} = register_node("foo"),
    ?line {ok,Sock} = connect(),
    M = [?EPMD_STOP,"foo"],
    ?line ok = send(Sock,[size16(M),M]),
    R = "STOPPED",
    ?line {ok,R} = recv(Sock,length(R)),
    ?line ok = close(RSock),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

unregister_others_name_2(doc) ->
    ["Unregister name of other node"];
unregister_others_name_2(suite) ->
    [];
unregister_others_name_2(Config) when is_list(Config) ->
    ?line ok = epmdrun("-relaxed_command_check"),
    ?line {ok,Sock} = connect(),
    M = [?EPMD_STOP,"xxx42"],
    ?line ok = send(Sock,[size16(M),M]),
    R = "NOEXIST",
    ?line {ok,R} = recv(Sock,length(R)),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

register_overflow(doc) ->
    ["Register too many, clean and redo 10 times"];
register_overflow(suite) ->
    [];
register_overflow(Config) when is_list(Config) ->
    Dog = ?config(watchdog, Config),
    test_server:timetrap_cancel(Dog),
    LongDog = test_server:timetrap(?LONG_TEST_TIMEOUT),
    ?line ok = epmdrun(),
    ?line Conn = register_many(1, ?REG_REPEAT_LIM, "foo"),
    Count = length(Conn),
    ?line ok = unregister_many(Conn),
    sleep(?MEDIUM_PAUSE),
    test_server:format("Limit was ~w names, now reg/unreg all 10 times~n",
		       [Count]),
    ?line ok = register_repeat(Count),
    sleep(?MEDIUM_PAUSE),
    ?line ok = rregister_repeat(Count),
    sleep(?MEDIUM_PAUSE),
    ?line ok = register_repeat(Count),
    sleep(?MEDIUM_PAUSE),
    ?line ok = rregister_repeat(Count),
    sleep(?MEDIUM_PAUSE),
    ?line ok = register_repeat(Count),
    sleep(?MEDIUM_PAUSE),
    ?line ok = rregister_repeat(Count),
    sleep(?MEDIUM_PAUSE),
    ?line ok = register_repeat(Count),
    sleep(?MEDIUM_PAUSE),
    ?line ok = rregister_repeat(Count),
    sleep(?MEDIUM_PAUSE),
    ?line ok = register_repeat(Count),
    sleep(?MEDIUM_PAUSE),
    ?line ok = rregister_repeat(Count),
    test_server:timetrap_cancel(LongDog),
    ok.

register_repeat(Count) ->
    Conn = register_many(1, ?REG_REPEAT_LIM, "foo"),
    ok = unregister_many(Conn),
    if
	length(Conn) == Count ->
	    ok;
	true ->
	    error
    end.

rregister_repeat(Count) ->
    Conn = register_many(1, ?REG_REPEAT_LIM, "foo"),
    ok = unregister_many(lists:reverse(Conn)),
    if
	length(Conn) == Count ->
	    ok;
	true ->
	    error
    end.

% Return count of successful registrations

register_many(I, N, Prefix) ->
    register_many(I, N, Prefix, v2).

register_many(I, N, _Prefix, _Ver) when I > N ->
    test_server:format("Done with all ~n", []),
    [];
register_many(I, N, Prefix, Ver) ->
    Name = gen_name(Prefix, I),
    Port = ?DUMMY_PORT + I,				% Just make it up
    Res  = case Ver of
           v2 -> register_node(Name, Port);
           v3 -> register_node_v3(Name, Port, <<>>)
           end,
    case Res of
	{ok,Sock} ->
	    [{Name,Port,Sock} | register_many(I + 1, N, Prefix, Ver)];
	Any ->
	    test_server:format("Can't register: ~w of 1..~w ~w~n", 
			       [Name,N,Any]),
	    []
    end.

unregister_many([]) ->
    ok;
unregister_many([{Name,_Port,Sock} | Socks]) ->
    case close(Sock) of
	ok ->
	    unregister_many(Socks);
	Any ->
	    test_server:format("Can't unregister: ~w reason ~w~n", [Name,Any]),
	    error
    end.

gen_name(Str,Int) ->
    Str ++ integer_to_list(Int).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

no_data(doc) ->
    ["Open but send no data"];
no_data(suite) ->
    [];
no_data(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = connect(),
    sleep(?LONG_PAUSE),
    ?line closed = recv(Sock,1),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

one_byte(doc) ->
    ["Send one byte only"];
one_byte(suite) ->
    [];
one_byte(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = connect(),
    ?line ok = send(Sock,[0]),
    sleep(?LONG_PAUSE),
    ?line closed = recv(Sock,1),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

two_bytes(doc) ->
    ["Send packet size only"];
two_bytes(suite) ->
    [];
two_bytes(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = connect(),
    ?line ok = send(Sock,[put16(3)]),
    sleep(?LONG_PAUSE),
    ?line closed = recv(Sock,1),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

partial_packet(doc) ->
    ["Got only part of a packet"];
partial_packet(suite) ->
    [];
partial_packet(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = connect(),
    ?line ok = send(Sock,[put16(100),"only a few bytes"]),
    sleep(?LONG_PAUSE),
    ?line closed = recv(Sock,1),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

zero_length(doc) ->
    ["Invalid zero packet size"];
zero_length(suite) ->
    [];
zero_length(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = connect(),
    ?line ok = send(Sock,[0,0,0,0,0,0,0,0,0,0]),
    sleep(?MEDIUM_PAUSE),
    ?line closed = recv(Sock,1),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

too_large(doc) ->
    ["Invalid large packet"];
too_large(suite) ->
    [];
too_large(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = connect(),
    Size = 63000,
    M = lists:duplicate(Size, $z),
    ?line ok = send(Sock,[put16(Size),M]),
    sleep(?MEDIUM_PAUSE),
    % With such a large packet, even the writes can fail as the
    % daemon closes before everything is delivered -> econnaborted
    case recv(Sock,1) of
	closed -> ok;
	{error,econnaborted} -> ok;
	Other -> exit({unexpected,Other})
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

alive_req_too_small_1(doc) ->
    ["Try to register but not enough data"];
alive_req_too_small_1(suite) ->
    [];
alive_req_too_small_1(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = connect(),
    M = [?EPMD_ALIVE2_REQ, put16(?DUMMY_PORT),$M,0, put16(5),
	 put16(5),put16(0)],
    ?line ok = send(Sock, [size16(M), M]),
    sleep(?MEDIUM_PAUSE),
    ?line closed = recv(Sock,1),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

alive_req_too_small_2(doc) ->
    ["Try to register but not enough data"];
alive_req_too_small_2(suite) ->
    [];
alive_req_too_small_2(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = connect(),
    M =  [?EPMD_ALIVE2_REQ, put16(?DUMMY_PORT),$M,0, put16(5),
	  put16(5)],
    ?line ok = send(Sock, [size16(M), M]),
    sleep(?MEDIUM_PAUSE),
    ?line closed = recv(Sock,1),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

alive_req_too_large(doc) ->
    ["Try to register but node name too large"];
alive_req_too_large(suite) ->
    [];
alive_req_too_large(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = connect(),
    L = [
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	 ],
    S = length(lists:flatten(L)),
    M = [?EPMD_ALIVE2_REQ, put16(?DUMMY_PORT),$M,0, put16(5),
	 put16(5), put16(S),L,put16(0)],
    ?line ok = send(Sock, [size16(M), M]),
    sleep(?MEDIUM_PAUSE),
    ?line {ok,[?EPMD_ALIVE2_RESP,1]} = recv(Sock,2),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

returns_valid_empty_extra(doc) ->
    ["Check that an empty extra is prefixed by a two byte length"];
returns_valid_empty_extra(suite) ->
    [];
returns_valid_empty_extra(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = register_node_v2(4711, 72, 0, 5, 5, "foo", []),
    ?line {ok,#node_info{extra=[]}} = port_please_v2("foo"),
    ?line ok = close(Sock),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

returns_valid_populated_extra_with_nulls(doc) ->
    ["Check a populated extra with embedded null characters"];
returns_valid_populated_extra_with_nulls(suite) ->
    [];
returns_valid_populated_extra_with_nulls(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,Sock} = register_node_v2(4711, 72, 0, 5, 5, "foo", "ABC\000\000"),
    ?line {ok,#node_info{extra="ABC\000\000"}} = port_please_v2("foo"),
    ?line ok = close(Sock),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

buffer_overrun_1(suite) ->
    [];
buffer_overrun_1(doc) ->
    ["Test security vulnerability in fake extra lengths in alive2_req"];
buffer_overrun_1(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line true = alltrue([hostile(N) || N <- lists:seq(1,10000)]),
    ok.
buffer_overrun_2(suite) ->
    [];
buffer_overrun_2(doc) ->
    ["Test security vulnerability in fake extra lengths in alive2_req"];
buffer_overrun_2(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line [false | Rest] = [hostile2(N) || N <- lists:seq(255*4,10000)],
    ?line true = alltrue(Rest),
    ok.
hostile(N) ->
    try
	Bin= <<$x:8,4747:16,$M:8,0:8,5:16,5:16,5:16,"gurka",N:16>>,
	S = size(Bin),
	{ok,E}=connect_sturdy(),
	gen_tcp:send(E,[<<S:16>>,Bin]),
	closed = recv(E,1),
	gen_tcp:close(E),
	true
    catch
	_:_ ->
	    false
    end.
hostile2(N) ->
    try
	B2 = list_to_binary(lists:duplicate(N,255)),
	Bin= <<$x:8,4747:16,$M:8,0:8,5:16,5:16,5:16,"gurka",N:16,B2/binary>>,
	S = size(Bin),
	{ok,E}=connect_sturdy(),
	gen_tcp:send(E,[<<S:16>>,Bin]),
	Z = recv(E,2),
	gen_tcp:close(E),
	(Z =:= closed) or (Z =:= {ok, [$y,1]})
    catch
	_A:_B ->
	    false
    end.

alltrue([]) ->
    true;
alltrue([true|T]) ->
    alltrue(T);
alltrue([_|_]) ->
    false.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
no_nonlocal_register(suite) ->
    [];
no_nonlocal_register(doc) ->
    ["Ensure that we cannot register throug a nonlocal connection"];
no_nonlocal_register(Config) when is_list(Config) ->
    ?line case {os:find_executable("ssh"),ct:get_config(ssh_proxy_host)} of
	      {SSH,Name} when is_list(Name), is_list(SSH) ->
		  do_no_nonlocal_register(Config,Name);
	      {false,_} ->
		  {skip, "No ssh command found to create proxy"};
	      _ ->
		  {skip, "No ssh_proxy_host configured in ts.config"}
	  end.
do_no_nonlocal_register(Config,SSHHost) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line ProxyPort = proxy_port(),
    ?line ok = ssh_proxy(SSHHost,ProxyPort),
    Res = try
	      ?line Name = "gurka_"
	      %++
	      %integer_to_list(A1)++"_"++
	      %integer_to_list(A2)++"_"++
	      %integer_to_list(A3)++"_"++
	      %integer_to_list(A4)
	      ,
	      ?line Bname = list_to_binary(Name),
	      ?line NameS = byte_size(Bname),
	      ?line Bin= <<$x:8,4747:16,$M:8,0:8,5:16,
			  5:16,NameS:16,Bname/binary,
			  0:16>>,
	      ?line S = size(Bin),
	      ?line {ok, E} = connect("localhost",ProxyPort,passive),
	      ?line gen_tcp:send(E,[<<S:16>>,Bin]),
	      ?line closed = recv(E,1),
	      ?line gen_tcp:close(E),
	      true
	  catch
	      _:_ ->
		  false
	  end,
    %erlang:display(Res),
    true = Res,
    ok.

no_nonlocal_kill(suite) ->
    [];
no_nonlocal_kill(doc) ->
    ["Ensure that we cannot kill through nonlocal connection"];
no_nonlocal_kill(Config) when is_list(Config) ->
    ?line case {os:find_executable("ssh"),ct:get_config(ssh_proxy_host)} of
	      {SSH,Name} when is_list(Name), is_list(SSH) ->
		  do_no_nonlocal_kill(Config,Name);
	      {false,_} ->
		  {skip, "No ssh command found to create proxy"};
	      _ ->
		  {skip, "No ssh_proxy_host configured in ts.config"}
	  end.
do_no_nonlocal_kill(Config,SSHHost) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line ProxyPort = proxy_port(),
    ?line ok = ssh_proxy(SSHHost,ProxyPort),
    Res = try
	      {ok, E} = connect("localhost",ProxyPort,passive),
	      M = [?EPMD_KILL],
	      send(E, [size16(M), M]),
	      closed = recv(E,2),
	      gen_tcp:close(E),
	      sleep(?MEDIUM_PAUSE),
	      {ok, E2} = connect("localhost",ProxyPort,passive),
	      gen_tcp:close(E2),
	      true
	  catch
	      _:_ ->
		  false
	  end,
    %erlang:display(Res),
    true = Res,
    ok.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
no_live_killing(doc) ->
    ["Dont allow killing with live nodes or any unregistering w/o -relaxed_command_check"];
no_live_killing(suite) ->
    [];
no_live_killing(Config) when is_list(Config) ->
    ?line ok = epmdrun(),
    ?line {ok,RSock} = register_node("foo"),
    ?line {ok,Sock} = connect(),
    ?line M = [?EPMD_KILL],
    ?line ok = send(Sock,[size16(M),M]),
    ?line {ok,"NO"} = recv(Sock,2),
    ?line close(Sock),
    ?line {ok,Sock2} = connect(),
    ?line M2 = [?EPMD_STOP,"foo"],
    ?line ok = send(Sock2,[size16(M2),M2]),
    ?line closed = recv(Sock2,1),
    ?line close(Sock2),
    ?line close(RSock),
    ?line sleep(?MEDIUM_PAUSE),
    ?line {ok,Sock3} = connect(),
    ?line M3 = [?EPMD_KILL],
    ?line ok = send(Sock3,[size16(M3),M3]),
    ?line {ok,"OK"} = recv(Sock3,2),
    ?line close(Sock3),
    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Terminate all tests with killing epmd.

cleanup() ->
    sleep(?MEDIUM_PAUSE),
    case connect() of
	{ok,Sock} ->
	    M = [?EPMD_KILL],
	    send(Sock, [size16(M), M]),
	    recv(Sock,length("OK")),
	    close(Sock),
	    sleep(?MEDIUM_PAUSE);
	_ ->
	    true
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Start an ssh channel to simulate remote access

proxy_port() ->
    ?PORT+1.

ssh_proxy(SSHHost,ProxyPort) ->
    ?line Host = lists:nth(2,string:tokens(atom_to_list(node()),"@")),
    % Requires proxy to be a unix host with the command 'read' accessible
    ?line osrun("ssh -L "++integer_to_list(ProxyPort)++":"++Host++":"
		++integer_to_list(?PORT)++" "++SSHHost++" read").
    


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Normal debug start of epmd

epmdrun() ->
    epmdrun([]).
epmdrun(Args) ->
    case os:find_executable(epmd) of
	false ->
	    {error, {could_not_find_epmd_in_path}};
	Path ->
	    epmdrun(Path,Args)
    end.

epmdrun(Epmd,Args0) ->
  %% test_server:format("epmdrun() => Epmd = ~p",[Epmd]),
    Args = case Args0 of
	       [] ->
		   [];
	       O ->
		   " "++O
	   end,
  osrun("\"" ++ Epmd ++ "\"" ++ Args ++ " " ?EPMDARGS " -port " ++ integer_to_list(?PORT)).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Start an external process

osrun(Cmd) ->
    _ = open_port({spawn, Cmd}, []),
    ok.
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Wrappers of TCP functions

% These functions is the interface for connect.
% Passive mode is the default

connect() ->
    connect("localhost",?PORT, passive).

connect_active() ->
    connect_active([]).
connect_active(Opts) ->
    connect("localhost", ?PORT, active, Opts).

%% Retry after 15 seconds, to avoid TIME_WAIT socket exhaust.
connect_sturdy() ->
    connect("localhost",?PORT, passive, 15000, 3).

connect_opt(Opts) ->
    connect_opt("localhost", Opts).
connect_opt(Addr, Opts) ->
    connect(Addr, ?PORT, active, Opts).

% Try a few times before giving up
connect(Addr, Port, Mode) ->
    connect(Addr, Port, Mode, ?CONN_SLEEP, ?CONN_RETRY).
connect(Addr, Port, Mode, Opts) ->
    connect(Addr, Port, Mode, ?CONN_SLEEP, ?CONN_RETRY, Opts).

connect(Addr, Port, Mode, Sleep, Retry) ->
    connect(Addr, Port, Mode, Sleep, Retry, [{packet, 0}]).

connect(Addr, Port, Mode, Sleep, Retry, Opts) ->
    case connect_repeat(Addr, Retry, Port, Mode, Sleep, Opts) of
	{ok,Sock} ->
	    {ok,Sock};
	{error,timeout} ->
	    timeout;
	{error,Reason} ->
	    test_server:format("connect: error: ~w~n",[Reason]),
	    error;
	Any ->
	    test_server:format("connect: unknown message: ~w~n",[Any]),
	    exit(1)
    end.


% Try a few times before giving up. Pause a small time between
% each try.

connect_repeat(Addr, 1, Port, Mode, _Sleep, Opts) ->
    connect_mode(Addr,Port, Mode, Opts);
connect_repeat(Addr,Retry, Port, Mode, Sleep, Opts) ->
    case connect_mode(Addr,Port, Mode, Opts) of
	{ok,Sock} ->
	    {ok,Sock};
	{error,Reason} ->
	    test_server:format("connect: error: ~w~n",[Reason]),
	    timer:sleep(Sleep),
	    connect_repeat(Addr, Retry - 1, Port, Mode, Sleep, Opts);
	Any ->
	    test_server:format("connect: unknown message: ~w~n",[Any]),
	    exit(1)
    end.

connect_mode(Addr,Port, active, Opts) ->
    gen_tcp:connect(Addr, Port, Opts, ?CONN_TIMEOUT);
connect_mode(Addr, Port, passive, Opts) ->
    gen_tcp:connect(Addr, Port, [{active, false} | Opts], ?CONN_TIMEOUT).


close(Sock) ->
    case gen_tcp:close(Sock) of
	{error,_} ->
	    error;
	ok ->
	    ok;
	Any ->
	    test_server:format("unknown message: ~w~n",[Any]),
	    exit(1)
    end.

recv(Sock, Len) ->
    recv(Sock, Len, ?RECV_TIMEOUT).

recv(Sock, Len, Timeout) ->
    case gen_tcp:recv(Sock, Len, Timeout) of
	{ok,[]} ->				% Should not be the case
	    recv(Sock, 1, 1);			% any longer
	{ok,Data} ->
	    {ok,Data};
	{error,timeout} ->
	    timeout;
	{error,closed} ->
	    closed;
	{error,_}=Error ->
	    Error;
	Any ->
	    test_server:format("unknown message: ~w~n",[Any]),
	    exit(1)
    end.

%% Send data to socket. The list can be non flat and contain
%% the atom 'd' or tuple {d,Seconds} where this is delay
%% put in between the sent characters.

send(Sock, SendSpec) ->
    case send(SendSpec, [], Sock) of
	{ok,[]} ->
	    ok;
	{ok,RevBytes} ->
	    send_direct(Sock, lists:reverse(RevBytes));
	Any ->
	    Any
    end.


% If an error, return immediately
% Collect real characters in the first argument to form
% a string to send. Only perform "actions", like a delay,
% when this argument is empty.

send([], RevBytes, _Sock) ->
    {ok,RevBytes};
send([Byte | Spec], RevBytes, Sock) when is_integer(Byte) ->
    send(Spec, [Byte | RevBytes], Sock);
send([List | Spec], RevBytes, Sock) when is_list(List) ->
    case send(List, RevBytes, Sock) of
	{ok,Left} ->
	    send(Spec, Left, Sock);
	Other ->
	    Other
    end;
send([d | Spec], RevBytes, Sock) ->
    send([{d,1000} | Spec], RevBytes, Sock);
send([{d,S} | Spec], RevBytes, Sock) ->
    case send_direct(Sock, lists:reverse(RevBytes)) of
	ok ->
	    timer:sleep(S),
	    send(Spec, [], Sock);
	Any ->
	    Any
    end.

%%%%

send_direct(Sock, Bytes) ->
    case gen_tcp:send(Sock, Bytes) of
	ok ->
	    ok;
	{error, closed} ->
	    closed;
	{error, _Reason} ->
	    error;
	Any ->
	    test_server:format("unknown message: ~w~n",[Any]),
	    Any
    end.

send_req(Req) ->
    case connect() of
	{ok,Sock} ->
	    case send(Sock, [size16(Req), Req]) of
		ok ->
		    {ok,Sock};
		Other ->
		    test_server:format("Failed to send ~w on sock ~w: ~w~n",
				       [Req,Sock,Other]),
		    error
	    end;
	Other ->
	    test_server:format("Connect failed when sending ~w: ~p~n",
			       [Req, Other]),
	    error
    end.

recv_until_sock_closes(Sock) ->
    recv_until_sock_closes_2(Sock,[]).

recv_until_sock_closes_2(Sock,AccData) ->
    case recv(Sock,0) of
	{ok,Data} ->
	    recv_until_sock_closes_2(Sock,AccData++Data);
	closed ->
	    {ok,AccData};
	Other ->
	    Other
    end.

sleep(MilliSeconds) ->
    timer:sleep(MilliSeconds).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

put16(N) ->
    [N bsr 8, N band 16#ff].

size16(List) ->
    N = flat_count(List, 0),
    [N bsr 8, N  band 16#ff].

flat_count([H|T], N) when is_integer(H) ->
    flat_count(T, N+1);
flat_count([H|T], N) when is_list(H) ->
    flat_count(T, flat_count(H, N));
flat_count([_|T], N) ->
    flat_count(T, N);
flat_count([], N) -> N.
    
