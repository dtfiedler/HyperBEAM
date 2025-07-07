%%% @doc Redis-based store implementation for HyperBEAM.
%%% Keys are stored as binary values using Redis string commands.
%%% Groups and links are not explicitly supported; they are stored as simple values.

-module(hb_store_redis).
-behaviour(hb_store).

-export([start/1, stop/1, reset/1, scope/1]).
-export([read/2, write/3, list/2, type/2, make_group/2, make_link/3, resolve/2]).

%% Record to hold connection pid
-record(state, {pid}).

%% @doc Start a Redis connection based on the given options.
start(#{ <<"url">> := Url }) ->
    {Host, Port} = parse_url(hb_util:bin(Url)),
    {ok, Pid} = eredis:start_link(Host, Port),
    {ok, #{ <<"pid">> => Pid }};
start(_) ->
    {error, badarg}.

%% @doc Stop the Redis connection.
stop(#{ <<"pid">> := Pid }) ->
    exit(Pid, shutdown),
    ok;
stop(_) -> ok.

%% @doc Scope is local for Redis connections.
scope(_) -> local.

%% @doc Reset simply flushes the database.
reset(State = #{ <<"pid">> := Pid }) ->
    ok = eredis:q(Pid, [<<"FLUSHDB">>]),
    {ok, State}.

%% @doc Resolve returns the key unchanged.
resolve(_, Key) -> Key.

%% @doc Write a value to Redis.
write(#{ <<"pid">> := Pid }, Key, Value) ->
    Path = hb_store:join(Key),
    ok = eredis:q(Pid, [<<"SET">>, Path, Value]),
    ok.

%% @doc Read a value from Redis.
read(#{ <<"pid">> := Pid }, Key) ->
    Path = hb_store:join(Key),
    case eredis:q(Pid, [<<"GET">>, Path]) of
        {ok, undefined} -> not_found;
        {ok, Bin} -> {ok, Bin};
        _ -> not_found
    end.

%% @doc Return simple type if key exists.
type(Opts, Key) ->
    case read(Opts, Key) of
        {ok, _} -> simple;
        not_found -> not_found
    end.

%% @doc Listing keys by prefix using KEYS.
list(#{ <<"pid">> := Pid }, Prefix) ->
    Path = hb_store:join(Prefix) ++ "/*",
    case eredis:q(Pid, [<<"KEYS">>, hb_util:bin(Path)]) of
        {ok, Keys} when is_list(Keys) -> {ok, [hb_util:bin(K) || K <- Keys]};
        _ -> not_found
    end.

make_group(_Opts, _Path) -> ok.
make_link(_Opts, _Existing, _New) -> ok.

%% Internal helper to parse redis URL
parse_url(Url) ->
    Parsed = uri_string:parse(Url),
    Host = maps:get(host, Parsed, "localhost"),
    Port = maps:get(port, Parsed, 6379),
    {hb_util:list(Host), Port}.
