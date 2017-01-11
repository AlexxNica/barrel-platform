%% Copyright 2016, Benoit Chesneau
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

%% Created by benoitc on 03/09/16.

-module(barrel_rocksdb_SUITE).
-author("Benoit Chesneau").

%% API
-export([
  all/0,
  init_per_suite/1,
  end_per_suite/1,
  init_per_testcase/2,
  end_per_testcase/2
]).

-export([
  store_exists/1,
  basic_op/1,
  update_doc/1,
  update_doc_lwww/1,
  bad_doc/1,
  create_doc/1,
  fold_by_id/1,
  change_since/1,
  change_since_many/1,
  change_since_include_doc/1,
  revdiff/1,
  get_revisions/1,
  put_rev/1,
  find_by_key/1
]).

all() ->
  [
    store_exists,
    basic_op,
    update_doc,
    update_doc_lwww,
    bad_doc,
    create_doc,
    get_revisions,
    fold_by_id,
    change_since,
    change_since_many,
    change_since_include_doc,
    revdiff,
    put_rev,
    find_by_key
  ].

init_per_suite(_Config) ->
  {ok, _} = application:ensure_all_started(barrel),
  _Config.


init_per_testcase(_, _Config) ->
  ok = barrel:open_store(testdb, #{ dir => "data/testdb"}),
  [{conn, testdb} | _Config].

end_per_testcase(_, _Config) ->
  ok = barrel:delete_store(testdb),
  ok.

end_per_suite(_Config) ->
  %%ok = barrel:delete_store(testdb),
  _Config.

store_exists(_Config) ->
  true = filelib:is_dir(<<"data/testdb">>),
  ok.


basic_op(_Config) ->
  {error, not_found} = barrel:get(testdb, <<"a">>, []),
  Doc = #{ <<"id">> => <<"a">>, <<"v">> => 1},
  {ok, <<"a">>, RevId} = barrel:put(testdb, Doc, []),
  Doc2 = Doc#{<<"_rev">> => RevId},
  {ok, Doc2} = barrel:get(testdb, <<"a">>, []),
  {ok, <<"a">>, _RevId2} = barrel:delete(testdb, <<"a">>, RevId, []),
  {error, not_found} = barrel:get(testdb, <<"a">>, []).

update_doc(_Config) ->
  Doc = #{ <<"id">> => <<"a">>, <<"v">> => 1},
  {ok, <<"a">>, RevId} = barrel:put(testdb, Doc, []),
  Doc2 = Doc#{<<"_rev">> => RevId},
  {ok, Doc2} = barrel:get(testdb, <<"a">>, []),
  Doc3 = Doc2#{ v => 2},
  {ok, <<"a">>, RevId2} = barrel:put(testdb, Doc3, []),
  true = (RevId =/= RevId2),
  Doc4 = Doc3#{<<"_rev">> => RevId2},
  {ok, Doc4} = barrel:get(testdb, <<"a">>, []),
  {ok, <<"a">>, _RevId2} = barrel:delete(testdb, <<"a">>, RevId2, []),
  {error, not_found} = barrel:get(testdb, <<"a">>, []),
  {ok, <<"a">>, _RevId3} = barrel:put(testdb, Doc, []).

update_doc_lwww(_Config) ->
  Doc = #{ <<"id">> => <<"a">>, <<"v">> => 1},
  {ok, <<"a">>, _RevId} = barrel:put(testdb, Doc, []),
  {ok, Doc2} = barrel:get(testdb, <<"a">>, []),
  #{ <<"v">> := 1 } = Doc2,

  Doc3 = #{ <<"id">> => <<"a">>, <<"v">> => 2},
  {error, {conflict, doc_exists}} = barrel:put(testdb, Doc3, []),

  {ok, <<"a">>, _RevId2} = barrel:put(testdb, Doc3, [{lww, true}]),
  {ok, Doc4} = barrel:get(testdb, <<"a">>, []),
  #{ <<"v">> := 2 } = Doc4.

bad_doc(_Config) ->
  Doc = #{ <<"v">> => 1},
  try barrel:put(testdb, Doc, [])
  catch
    error:{bad_doc, invalid_docid} -> ok
  end.

create_doc(_Config) ->
  Doc = #{<<"v">> => 1},
  {ok, DocId, RevId} =  barrel:post(testdb, Doc, []),
  CreatedDoc = Doc#{ <<"id">> => DocId, <<"_rev">> => RevId},
  {ok, CreatedDoc} = barrel:get(testdb, DocId, []),
  {error, not_found} =  barrel:post(testdb, CreatedDoc, []),
  Doc2 = #{<<"id">> => <<"b">>, <<"v">> => 1},
  {ok, <<"b">>, _RevId2} =  barrel:post(testdb, Doc2, []).

get_revisions(_Config) ->
  Doc = #{<<"v">> => 1},
  {ok, DocId, RevId} =  barrel:post(testdb, Doc, []),
  {ok, Doc2} = barrel:get(testdb, DocId, []),
  Doc3 = Doc2#{ v => 2},
  {ok, DocId, RevId2} = barrel:put(testdb, Doc3, []),
  {ok, Doc4} = barrel:get(testdb, DocId, [{history, true}]),
  Revisions = barrel_doc:parse_revisions(Doc4),
  Revisions == [RevId2, RevId].

put_rev(_Config) ->
  Doc = #{<<"v">> => 1},
  {ok, DocId, RevId} =  barrel:post(testdb, Doc, []),
  {ok, Doc2} = barrel:get(testdb, DocId, []),
  Doc3 = Doc2#{ v => 2},
  {ok, DocId, RevId2} = barrel:put(testdb, Doc3, []),
  Doc4_0 = Doc2#{ v => 3 },
  {Pos, _} = barrel_doc:parse_revision(RevId),
  NewRev = barrel_doc:revid(Pos +1, RevId, Doc4_0),
  Doc4 = Doc4_0#{<<"_rev">> => NewRev},
  History = [NewRev, RevId],
  {ok, DocId, _RevId3} = barrel:put_rev(testdb, Doc4, History, []),
  {ok, Doc5} = barrel:get(testdb, DocId, [{history, true}]),
  Revisions = barrel_doc:parse_revisions(Doc5),
  Revisions == [RevId2, RevId].


fold_by_id(_Config) ->
  Doc = #{ <<"id">> => <<"a">>, <<"v">> => 1},
  {ok, <<"a">>, _RevId} = barrel:put(testdb, Doc, []),
  Doc2 = #{ <<"id">> => <<"b">>, <<"v">> => 1},
  {ok, <<"b">>, _RevId2} = barrel:put(testdb, Doc2, []),
  Doc3 = #{ <<"id">> => <<"c">>, <<"v">> => 1},
  {ok, <<"c">>, _RevId3} = barrel:put(testdb, Doc3, []),
  Fun = fun(DocId, _DocInfo, {ok, FoldDoc}, Acc1) ->
      DocId = barrel_doc:id(FoldDoc),
      {ok, [DocId | Acc1]}
    end,
  Acc = barrel:fold_by_id(testdb, Fun, [], [{include_doc, true}]),
  [<<"c">>, <<"b">>, <<"a">>] = Acc,
  Acc2 = barrel:fold_by_id(testdb, Fun, [],
                              [{include_doc, true}, {lt, <<"b">>}]),
  [<<"a">>] = Acc2,
  Acc3 = barrel:fold_by_id(testdb, Fun, [],
                              [{include_doc, true}, {lte, <<"b">>}]),
  [<<"b">>, <<"a">>] = Acc3,
  Acc4 = barrel:fold_by_id(testdb, Fun, [],
                              [{include_doc, true}, {gte, <<"b">>}]),
  [<<"c">>, <<"b">>] = Acc4,
  Acc5 = barrel:fold_by_id(testdb, Fun, [],
                              [{include_doc, true}, {gt, <<"b">>}]),
  [<<"c">>] = Acc5,
  ok.

change_since(_Config) ->
  Fun = fun(_Seq, Change, Acc) ->
                  Id = maps:get(id, Change),
                  {ok, [Id|Acc]}
        end,
  [] = barrel:changes_since(testdb, 0, Fun, []),
  Doc = #{ <<"id">> => <<"aa">>, <<"v">> => 1},
  {ok, <<"aa">>, _RevId} = barrel:put(testdb, Doc, []),
  Doc2 = #{ <<"id">> => <<"bb">>, <<"v">> => 1},
  {ok, <<"bb">>, _RevId2} = barrel:put(testdb, Doc2, []),
  {ok, _} = barrel:get(testdb, <<"bb">>, []),
  [<<"bb">>, <<"aa">>] = barrel:changes_since(testdb, 0, Fun, []),
  [<<"bb">>] = barrel:changes_since(testdb, 1, Fun, []),
  [] = barrel:changes_since(testdb, 2, Fun, []),
  Doc3 = #{ <<"id">> => <<"cc">>, <<"v">> => 1},
  {ok, <<"cc">>, _RevId3} = barrel:put(testdb, Doc3, []),
  [<<"cc">>] = barrel:changes_since(testdb, 2, Fun, []),
  ok.

change_since_include_doc(_Config) ->
  Fun =
    fun(Seq, Change, Acc) ->
      {ok, [{Seq, maps:get(doc, Change)} |Acc]}
    end,
  Doc = #{ <<"id">> => <<"aa">>, <<"v">> => 1},
  {ok, <<"aa">>, _RevId} = barrel:put(testdb, Doc, []),
  {ok, Doc1} = barrel:get(testdb, <<"aa">>, []),
  [Change] = barrel:changes_since(testdb, 0, Fun, [], [{include_doc, true}]),
  {1, Doc1} = Change,
  ok.

change_since_many(_Config) ->
  Fun = fun(Seq, Change, Acc) ->
            {ok, [{Seq, Change}|Acc]}
        end,

  %% No changes. Database is empty.
  [] = barrel:changes_since(testdb, 0, Fun, []),

  %% Add 20 docs (doc1 to doc20).
  AddDoc = fun(N) ->
               K = integer_to_binary(N),
               Key = <<"doc", K/binary>>,
               Doc = #{ <<"id">> => Key, <<"v">> => 1},
               {ok, Key, _RevId} = barrel:put(testdb, Doc, [])
           end,
  [AddDoc(N) || N <- lists:seq(1,20)],

  %% Delete doc1
  {ok, Doc1} = barrel:get(testdb, <<"doc1">>, []),
  #{<<"_rev">> := RevId} = Doc1,
  {ok, <<"doc1">>, _} = barrel:delete(testdb, <<"doc1">>, RevId, []),

  %% 20 changes (for doc1 to doc20)
  All = barrel:changes_since(testdb, 0, Fun, [], [{history, all}]),
  20 = length(All),
  %% History for doc1 includes creation and deletion
  {21, #{changes := HistoryDoc1}} = hd(All),
  2 = length(HistoryDoc1),

  [{21, #{id := <<"doc1">>}},
   {20, #{id := <<"doc20">>}},
   {19, #{id := <<"doc19">>}}] = barrel:changes_since(testdb, 18, Fun, []),
  [{21, #{id := <<"doc1">>}},
   {20, #{id := <<"doc20">>}}] = barrel:changes_since(testdb, 19, Fun, []),
  [] = barrel:changes_since(testdb, 21, Fun, []),
  ok.

revdiff(_Config) ->
  Doc = #{ <<"id">> => <<"revdiff">>, <<"v">> => 1},
  {ok, <<"revdiff">>, RevId} = barrel:put(testdb, Doc, []),
  Doc2 = Doc#{<<"_rev">> => RevId, <<"v">> => 2},
  {ok, <<"revdiff">>, _RevId3} = barrel:put(testdb, Doc2, []),
  {ok, [<<"1-missing">>], []} = barrel:revsdiff(testdb, <<"revdiff">>, [<<"1-missing">>]),
  ok.


find_by_key(_Config) ->
  Doc = #{
    <<"id">> => <<"AndersenFamily">>,
    <<"lastName">> => <<"Andersen">>,
    <<"parents">> => [
      #{ <<"firstName">> => <<"Thomas">> },
      #{ <<"firstName">> => <<"Mary Kay">>}
    ],
    <<"children">> => [
      #{
        <<"firstName">> => <<"Henriette Thaulow">>, <<"gender">> => <<"female">>, <<"grade">> =>  5,
        <<"pets">> => [#{ <<"givenName">> => <<"Fluffy">> }]
      }
    ],
    <<"address">> => #{ <<"state">> => <<"WA">>, <<"county">> => <<"King">>, <<"city">> => <<"seattle">> },
    <<"creationDate">> => 1431620472,
    <<"isRegistered">> => true
  },
  {ok, <<"AndersenFamily">>, _Rev} = barrel:put(testdb, Doc, []),
  timer:sleep(400),
  {ok, Doc1} = barrel:get(testdb, <<"AndersenFamily">>, []),
  
  lager:info("ici", []),
  Fun = fun(Id, D, Acc) -> {ok, [{Id, D} | Acc]} end,
  [{<<"AndersenFamily">>, <<"AndersenFamily">>}] = barrel:find_by_key(testdb, <<"id">>, Fun, [], []),
  [{<<"AndersenFamily">>, Doc1}] = barrel:find_by_key(
                                     testdb, <<"id/AndersenFamily">>, Fun, [], []
                                    ),
  ok.

