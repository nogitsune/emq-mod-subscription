%%--------------------------------------------------------------------
%% Copyright (c) 2012-2016 Feng Lee <feng@emqtt.io>.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emq_mod_subscription).

-author("Feng Lee <feng@emqtt.io>").

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_protocol.hrl").

-export([load/1, on_client_connected/3, unload/0]).

-define(TAB, ?MODULE).

%%--------------------------------------------------------------------
%% Load/Unload Hook
%%--------------------------------------------------------------------

load(Topics) ->
    emqttd:hook('client.connected', fun ?MODULE:on_client_connected/3, [Topics]).

on_client_connected(?CONNACK_ACCEPT, Client = #mqtt_client{client_id  = ClientId,
                                                           client_pid = ClientPid,
                                                           username   = Username}, Topics) ->

    Replace = fun(Topic) -> rep(<<"%u">>, Username, rep(<<"%c">>, ClientId, Topic)) end,
    TopicTable = [{Replace(Topic), Qos} || {Topic, Qos} <- Topics],
    {ok, Redis} = eredis:start_link(),
    FinalList = case eredis:q(Redis, ["sMembers", "mqtt_sub:" ++ Username]) of
                {ok, OurTopics} ->
                  case listAppend(TopicTable, OurTopics) of
                    {ok, AppendedList} when is_list(AppendedList) ->
                      AppendedList;
                    {ok,_} ->
                      TopicTable;
                    {error} ->
                      TopicTable
                  end;
                {error,Reason} ->
                  TopicTable
                end,
    emqttd_client:subscribe(ClientPid, FinalList),
    {ok, Client};

on_client_connected(_ConnAck, _Client, _State) ->
    ok.

unload() ->
    emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3).

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------

listAppend(DefaultTopic,NewTopics) when length(NewTopics) > 0 ->
  ListLast = lists:last(NewTopics),
  LastDropped = lists:droplast(NewTopics),
  Result = case listAppend(DefaultTopic,LastDropped) of
             {ok,NewList} ->
               lists:append(NewList,[{ListLast,2}]);
             {error} ->
               lists:append(DefaultTopic,[{ListLast,2}])
           end,
  {ok,Result};
listAppend(_,_) ->
  {error}.

rep(<<"%c">>, ClientId, Topic) ->
    emqttd_topic:feed_var(<<"%c">>, ClientId, Topic);
rep(<<"%u">>, undefined, Topic) ->
    Topic;
rep(<<"%u">>, Username, Topic) ->
    emqttd_topic:feed_var(<<"%u">>, Username, Topic).

