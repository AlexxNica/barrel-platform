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

-module(barrel_http_rest_revsdiff).
-author("Bernard Notarianni").

-export([init/2]).


init(Req, Opts) ->
  Method = cowboy_req:method(Req),
  Database = cowboy_req:binding(database, Req),
  route(Method, Database, Req, Opts).

route(<<"POST">>, Database, Req, State) ->
  {ok, Body, Req2} = cowboy_req:read_body(Req),
  RequestedDocs = jsx:decode(Body, [return_maps]),
  Result = maps:fold(fun(DocId, RevIds, Acc) ->
    {ok, Missing, Possible} = barrel:revsdiff(Database, DocId, RevIds),
                         Acc#{DocId => #{<<"missing">> => Missing,
                                         <<"possible_ancestors">> => Possible}}
                     end,#{}, RequestedDocs),
  barrel_http_reply:doc(Result, Req2, State);


route(_, _, Req, State) ->
  barrel_http_reply:code(405, Req, State).

