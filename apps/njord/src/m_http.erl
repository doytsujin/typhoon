%%
%%   Copyright 2016 Zalando SE
%%
%%   Licensed under the Apache License, Version 2.0 (the "License");
%%   you may not use this file except in compliance with the License.
%%   You may obtain a copy of the License at
%%
%%       http://www.apache.org/licenses/LICENSE-2.0
%%
%%   Unless required by applicable law or agreed to in writing, software
%%   distributed under the License is distributed on an "AS IS" BASIS,
%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%   See the License for the specific language governing permissions and
%%   limitations under the License.
%%
%% @doc
%%   http IO monad
-module(m_http).

-export([return/1, fail/1, '>>='/2]).
-export([new/0, new/1, url/1, header/2]).
-export([thinktime/1, get/0, put/1, post/1, delete/0, request/1, request/2]).

%%%----------------------------------------------------------------------------   
%%%
%%% state monad
%%%
%%%----------------------------------------------------------------------------   

return(X) ->
   fun(State) -> [X|maps:remove(fd, State)] end.

fail(X) ->
   m_state:fail(X).

'>>='(X, Fun) ->
   m_state:'>>='(X, Fun).

%%%----------------------------------------------------------------------------   
%%%
%%% http monad
%%%
%%%----------------------------------------------------------------------------   

%%
%% http request specification
id()      -> lens:c([lens:map(fd, #{}), lens:map(id,  none)]).
url()     -> lens:c([lens:map(fd, #{}), lens:map(url, none)]).
header()  -> lens:c([lens:map(fd, #{}), lens:map(header, [])]).
header(X) -> lens:c([lens:map(fd, #{}), lens:map(header, []), lens:pair(X, none)]).

%% @todo: use pipe stream concept to return stream of element from socket

new() ->
   m_state:put(id(), undefined).

new(Id) -> 
   m_state:put(id(), uri:new(scalar:s(Id))).

url(Url) ->
   m_state:put(url(), uri:new(Url)).

header(Head, Value) ->
   % @todo: fix htstream to accept various headers
   m_state:put(header(scalar:atom(Head)), scalar:s(Value)).

%%
%% http actions
thinktime(T) ->
   fun(State) ->
      [timer:sleep(T)|State]
   end.


get() ->
   request('GET').

put(Payload) ->
   request('PUT', Payload).

post(Payload) ->
   request('POST', Payload).

delete() ->
   request('DELETE').


% @todo: validate and normalize method
request(Mthd) ->
   fun(State0) ->
      {Sock, State1} = socket(State0),
      Url  = lens:get(url(), State1),
      Head = lens:get(header(), State1),
      knet:send(Sock, {trace, lens:get(id(), State1)}),
      knet:send(Sock, {Mthd, Url, Head}),
      %% @todo: remove authority if connection is not keep/alive
      [recv(Sock)|State1]
   end.

request(Mthd, Payload) ->
   fun(State0) ->
      {Sock, State1} = socket(State0),
      Url  = lens:get(url(), State1),
      Head = [{'Transfer-Encoding', <<"chunked">>} | lens:get(header(), State1)],
      knet:send(Sock, {trace, lens:get(id(), State1)}),
      knet:send(Sock, {Mthd, Url, Head}),
      knet:send(Sock, Payload),
      knet:send(Sock, eof),
      %% @todo: remove authority if connection is not keep/alive
      [recv(Sock)|State1]
   end.

%%%----------------------------------------------------------------------------   
%%%
%%% private
%%%
%%%----------------------------------------------------------------------------   

%%
%%
authority(State) ->
   uri:authority(lens:get(url(), State)).

%%
%%
socket(State) ->
   case 
      maps:get(authority(State), State, undefined)  
   of
      undefined ->
         Sock = connect(State),
         {Sock, State#{authority(State) => Sock}};
      Sock ->
         {Sock, State}
   end.

connect(State) ->
   %% @todo: configurable io timeout
   Uri = lens:get(url(), State),
   {ok, Sock} = supervisor:start_child(njord_sup, [Uri]),
   pipe:bind(a, Sock),
   Sock.

%%
%%
recv(Sock) ->
   %% @todo: customizable timeout by client
   case knet:recv(Sock, 30000) of
      {http, Sock,  eof} ->
         [];
      {http, Sock, Pckt} ->
         [Pckt | recv(Sock)]
   end.

