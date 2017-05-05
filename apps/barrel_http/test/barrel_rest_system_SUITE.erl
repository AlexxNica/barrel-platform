%% Copyright 2016, Bernard Notarianni
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

-module(barrel_rest_system_SUITE).

-export([all/0,
         end_per_suite/1,
         end_per_testcase/2,
         init_per_suite/1,
         init_per_testcase/2]).

-export([system_doc/1]).

all() -> [system_doc].

init_per_suite(Config) ->
  {ok, _} = application:ensure_all_started(barrel_http),
  {ok, _} = application:ensure_all_started(barrel),
  Config.

init_per_testcase(_, Config) ->
  _ = barrel_store:create_db(<<"testdb">>, #{}),
  Config.

end_per_testcase(_, Config) ->
  ok = barrel_local:delete_db(<<"testdb">>),
  Config.

end_per_suite(_Config) ->
  application:stop(barrel),
  ok.

%% ----------


system_doc(_Config) ->
  Doc = "{\"id\": \"cat\", \"name\" : \"tom\"}",
  {200, _} = test_lib:req(put, "/dbs/testdb/system/cat", Doc),
  {200, R} = test_lib:req(get, <<"/dbs/testdb/system/cat">>),
  J = jsx:decode(R, [return_maps]),
  #{<<"name">> := <<"tom">>} = J,
  {200, _} = test_lib:req(put, "/dbs/testdb/system/cat", "{}"),
  {200, _} = test_lib:req(delete, "/dbs/testdb/system/cat"),
  {404, _} = test_lib:req(get, <<"/dbs/testdb/system/cat">>),
  ok.

