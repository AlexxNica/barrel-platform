%% Copyright 2017, Benoit Chesneau
%%
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy of
%% the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations under
%% the License.


-module(barrel_peer_changes_SUITE).
-author("benoitc").


-define(DB_URL,<<"http://localhost:7080/dbs/testdb">>).
-define(DB_URL2,<<"http://localhost:7080/dbs/source">>).
-export([
  collect_change/1,
  collect_changes/1,
  changes_feed_callback/1,
  heartbeat_collect_change/1
]).

-export([
  all/0,
  init_per_suite/1,
  end_per_suite/1,
  init_per_testcase/2,
  end_per_testcase/2
]).

all() ->
  [
    collect_change,
    collect_changes,
    changes_feed_callback,
    heartbeat_collect_change
  ].

init_per_suite(Config) ->
  {ok, _} = application:ensure_all_started(barrel_http),
  {ok, _} = application:ensure_all_started(barrel),
  {ok, _} = application:ensure_all_started(barrel_peer),
  Config.

init_per_testcase(_, Config) ->
  ok = barrel_peer:create_database(?DB_URL),
  ok = barrel_peer:create_database(?DB_URL2),
  {ok, Conn} = barrel_peer:connect(?DB_URL),
  [{db, Conn} | Config].

end_per_testcase(_, _Config) ->
  _ = barrel_peer:delete_database(?DB_URL),
  _ = barrel_peer:delete_database(?DB_URL2),
  ok.

end_per_suite(Config) ->
  Config.


db(Config) -> proplists:get_value(db, Config).

collect_change(Config) ->
  {ok, Pid} = barrel_peer_changes:start_listener(db(Config), #{since => 0, mode => sse}),
  [] = barrel_peer_changes:fetch_changes(Pid),
  Doc = #{ <<"id">> => <<"aa">>, <<"v">> => 1},
  {ok, <<"aa">>, _RevId} = barrel_peer:post(db(Config), Doc, []),
  timer:sleep(100),
  [#{ <<"seq">> := 1, <<"id">> := <<"aa">>}] = barrel_peer_changes:fetch_changes(Pid),
  [] = barrel_peer_changes:fetch_changes(Pid),
  ok = barrel_peer_changes:stop_listener(Pid).

collect_changes(Config) ->
  {ok, Pid} = barrel_peer_changes:start_listener(db(Config), #{since => 0, mode => sse}),
  [] = barrel_peer_changes:fetch_changes(Pid),
  Doc = #{ <<"id">> => <<"aa">>, <<"v">> => 1},
  {ok, <<"aa">>, _} = barrel_peer:post(db(Config), Doc, []),
  timer:sleep(100),
  [#{ <<"seq">> := 1, <<"id">> := <<"aa">>}] = barrel_peer_changes:fetch_changes(Pid),
  [] = barrel_peer_changes:fetch_changes(Pid),
  Doc2 = #{ <<"id">> => <<"bb">>, <<"v">> => 1},
  {ok, <<"bb">>, _} = barrel_peer:post(db(Config), Doc2, []),
  {ok, _, _} = barrel_peer:get(db(Config), <<"bb">>, []),
  timer:sleep(100),
  [#{ <<"seq">> := 2, <<"id">> := <<"bb">>}] = barrel_peer_changes:fetch_changes(Pid),
  [] = barrel_peer_changes:fetch_changes(Pid),
  Doc3 = #{ <<"id">> => <<"cc">>, <<"v">> => 1},
  Doc4 = #{ <<"id">> => <<"dd">>, <<"v">> => 1},
  {ok, <<"cc">>, _} = barrel_peer:post(db(Config), Doc3, []),
  {ok, <<"dd">>, _} = barrel_peer:post(db(Config), Doc4, []),
  {ok, _, _} = barrel_peer:get(db(Config), <<"cc">>, []),
  {ok, _, _} = barrel_peer:get(db(Config), <<"dd">>, []),
  timer:sleep(100),
  [
    #{ <<"seq">> := 3, <<"id">> := <<"cc">>},
    #{ <<"seq">> := 4, <<"id">> := <<"dd">>}
  ] = barrel_peer_changes:fetch_changes(Pid),
  
  ok = barrel_peer_changes:stop_listener(Pid).

changes_feed_callback(Config) ->
  Self = self(),
  Callback =
  fun(Change) ->
    Self ! {change, Change}
  end,
  Options = #{since => 0, mode => sse, changes_cb => Callback },
  {ok, Pid} = barrel_peer_changes:start_listener(db(Config), Options),
  
  Doc1 = #{ <<"id">> => <<"aa">>, <<"v">> => 1},
  Doc2 = #{ <<"id">> => <<"bb">>, <<"v">> => 1},
  {ok, <<"aa">>, _} = barrel_peer:post(db(Config), Doc1, []),
  {ok, <<"bb">>, _} = barrel_peer:post(db(Config), Doc2, []),
  {ok, _, _} = barrel_peer:get(db(Config), <<"aa">>, []),
  {ok, _, _} = barrel_peer:get(db(Config), <<"bb">>, []),
  timer:sleep(100),
  [
    #{ <<"seq">> := 1, <<"id">> := <<"aa">>},
    #{ <<"seq">> := 2, <<"id">> := <<"bb">>}
  ] = collect_changes(2, queue:new()),
  ok = barrel_peer_changes:stop_listener(Pid).


heartbeat_collect_change(Config) ->
  Options = #{since => 0, heartbeat => 100, mode => sse },
  {ok, Pid} = barrel_peer_changes:start_listener(db(Config), Options),
  timer:sleep(500),
  [] = barrel_peer_changes:fetch_changes(Pid),
  Doc = #{ <<"id">> => <<"aa">>, <<"v">> => 1},
  {ok, <<"aa">>, _RevId} = barrel_peer:post(db(Config), Doc, []),
  timer:sleep(100),
  [#{ <<"seq">> := 1, <<"id">> := <<"aa">>}] = barrel_peer_changes:fetch_changes(Pid),
  [] = barrel_peer_changes:fetch_changes(Pid),
  ok = barrel_peer_changes:stop_listener(Pid).

collect_changes(0, Q) ->
  queue:to_list(Q);
collect_changes(I, Q) ->
  receive
    {change, Change} ->
      collect_changes(I-1, queue:in(Change, Q))
  end.