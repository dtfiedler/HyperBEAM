%%% @doc A module for interacting with local and global options inside
%%% HyperBEAM. Options are set globally, but can also be overridden using an
%%% an optional local `Opts' map argument. Many functions across the HyperBEAM 
%%% environment accept an `Opts' argument, which can be used to customize 
%%% behavior.
%%% 
%%% Options set in an `Opts' map must _never_ change the behavior of a function
%%% that should otherwise be deterministic. Doing so may lead to loss of funds
%%% by the HyperBEAM node operator, as the results of their executions will be
%%% different than those of other node operators. If they are economically 
%%% staked on the correctness of these results, they may experience punishments
%%% for non-verifiable behavior. Instead, if a local node setting makes 
%%% deterministic behavior impossible, the caller should fail the execution 
%%% with a refusal to execute.
-module(hb_opts).
-export([get/1, get/2, get/3, load/1, default_message/0]).
-include_lib("eunit/include/eunit.hrl").
-include("include/hb.hrl").

%% @doc The default configuration options of the hyperbeam node.
default_message() ->
    #{
        %%%%%%%% Functional options %%%%%%%%
        hb_config_location => <<"config.flat">>,
        initialized => true,
        %% What protocol should the node use for HTTP requests?
        %% Options: http1, http2, http3
        protocol => http2,
        %% What HTTP client should the node use?
        %% Options: gun, httpc
        http_client => gun,
        %% Scheduling mode: Determines when the SU should inform the recipient
        %% that an assignment has been scheduled for a message.
        %% Options: aggressive(!), local_confirmation, remote_confirmation
        scheduling_mode => local_confirmation,
        %% Compute mode: Determines whether the process device should attempt to 
        %% execute more messages on a process after it has returned a result.
        %% Options: aggressive, lazy
        compute_mode => lazy,
        %% Choice of remote nodes for tasks that are not local to hyperbeam.
        host => <<"localhost">>,
        gateway => <<"https://arweave.net">>,
        bundler_ans104 => <<"https://up.arweave.net:443">>,
        %% Location of the wallet keyfile on disk that this node will use.
        priv_key_location => <<"hyperbeam-key.json">>,
        %% The time-to-live that should be specified when we register
        %% ourselves as a scheduler on the network.
        %% Default: 7 days.
        scheduler_location_ttl => (60 * 60 * 24 * 7) * 1000,
        %% Preloaded devices for the node to use. These names override
        %% resolution of devices via ID to the default implementations.
        preloaded_devices =>
            #{
                <<"meta@1.0">> => dev_meta,
                <<"message@1.0">> => dev_message,
                <<"stack@1.0">> => dev_stack,
                <<"multipass@1.0">> => dev_multipass,
                <<"scheduler@1.0">> => dev_scheduler,
                <<"process@1.0">> => dev_process,
                <<"wasm-64@1.0">> => dev_wasm,
                <<"wasi@1.0">> => dev_wasi,
                <<"json-iface@1.0">> => dev_json_iface,
                <<"dedup@1.0">> => dev_dedup,
                <<"router@1.0">> => dev_router,
                <<"relay@1.0">> => dev_relay,
                <<"cron@1.0">> => dev_cron,
                <<"poda@1.0">> => dev_poda,
                <<"monitor@1.0">> => dev_monitor,
                <<"push@1.0">> => dev_push,
                <<"compute@1.0">> => dev_cu,
                <<"p4@1.0">> => dev_p4,
                <<"faff@1.0">> => dev_faff,
                <<"simple-pay@1.0">> => dev_simple_pay,
                <<"snp@1.0">> => dev_snp,
                <<"httpsig@1.0">> => dev_codec_httpsig,
                <<"ans104@1.0">> => dev_codec_ans104,
                <<"flat@1.0">> => dev_codec_flat,
                <<"structured@1.0">> => dev_codec_structured,
                <<"lookup@1.0">> => dev_lookup,
                <<"genesis-wasm@1.0">> => dev_genesis_wasm,
                <<"delegated-compute@1.0">> => dev_delegated_compute,
                <<"patch@1.0">> => dev_patch,
                <<"test-device@1.0">> => dev_test
            },
        %% Default execution cache control options
        cache_control => [<<"no-cache">>, <<"no-store">>],
        cache_lookup_hueristics => false,
        % Should we await in-progress executions, rather than re-running?
        % Has three settings: false, only `named` executions, or all executions.
        await_inprogress => named,
        %% Should the node attempt to access data from remote caches for
        %% client requests?
        access_remote_cache_for_client => false,
        %% Should the node attempt to load devices from remote signers?
        load_remote_devices => false,
        %% The list of device signers that the node should trust.
        trusted_device_signers => [],
        %% What should the node do if a client error occurs?
        client_error_strategy => throw,
        %% HTTP request options
        http_connect_timeout => 5000,
        http_keepalive => 120000,
        http_request_send_timeout => 60000,
        port => 8734,
        wasm_allow_aot => false,
        %% Options for the relay device
        relay_http_client => httpc,
        %% Dev options
        mode => debug,
        debug_stack_depth => 40,
        debug_print_map_line_threshold => 30,
        debug_print_binary_max => 60,
        debug_print_indent => 2,
        debug_print => false,
        stack_print_prefixes => ["hb", "dev", "ar"],
        debug_print_trace => short, % `short` | `false`. Has performance impact.
        short_trace_len => 5,
        debug_hide_metadata => true,
        debug_ids => false,
        debug_hide_priv => true,
		trusted => #{},
        routes => [
            #{
                % Routes for the genesis-wasm device to use a local CU, if requested.
                <<"template">> => <<"/result/.*">>,
                <<"node">> => #{ <<"prefix">> => <<"http://localhost:6363">> }
            },
            #{
                % Routes for GraphQL requests to use a remote GraphQL API.
                <<"template">> => <<"/graphql">>,
                <<"nodes">> =>
                    [
                        #{
                            <<"prefix">> => <<"https://arweave-search.goldsky.com">>,
                            <<"opts">> => #{ http_client => httpc }
                        },
                        #{
                            <<"prefix">> => <<"https://arweave.net">>,
                            <<"opts">> => #{ http_client => gun }
                        }
                    ]
            },
            #{
                % Routes for raw data requests to use a remote gateway.
                <<"template">> => <<"/raw">>,
                <<"node">> =>
                    #{
                        <<"prefix">> => <<"https://arweave.net">>,
                        <<"opts">> => #{ http_client => gun }
                    }
            }
        ],
        http_extra_opts =>
            #{
                force_message => true,
                store => [{hb_store_fs, #{ prefix => "mainnet-cache" }}, {hb_store_gateway, #{}}],
                cache_control => [<<"always">>]
            },
        % Should the node store all signed messages?
        store_all_signed => true,
        % Should the node use persistent processes?
        process_workers => true
    }.

%% @doc Get an option from the global options, optionally overriding with a
%% local `Opts' map if `prefer' or `only' is set to `local'. If the `only' 
%% option is provided in the `local' map, only keys found in the corresponding
%% (`local' or `global') map will be returned. This function also offers users
%% a way to specify a default value to return if the option is not set.
%% 
%% `prefer' defaults to `local'.
get(Key) -> ?MODULE:get(Key, undefined).
get(Key, Default) -> ?MODULE:get(Key, Default, #{}).
get(Key, Default, Opts) when is_binary(Key) ->
    try binary_to_existing_atom(Key, utf8) of
        AtomKey -> get(AtomKey, Default, Opts)
    catch
        error:badarg -> Default
    end;
get(Key, Default, Opts = #{ only := local }) ->
    case maps:find(Key, Opts) of
        {ok, Value} -> Value;
        error -> 
            Default
    end;
get(Key, Default, #{ only := global }) ->
    case global_get(Key, hb_opts_not_found) of
        hb_opts_not_found -> Default;
        Value -> Value
    end;
get(Key, Default, Opts = #{ prefer := global }) ->
    case ?MODULE:get(Key, hb_opts_not_found, #{ only => global }) of
        hb_opts_not_found -> ?MODULE:get(Key, Default, Opts#{ only => local });
        Value -> Value
    end;
get(Key, Default, Opts = #{ prefer := local }) ->
    case ?MODULE:get(Key, hb_opts_not_found, Opts#{ only => local }) of
        hb_opts_not_found ->
            ?MODULE:get(Key, Default, Opts#{ only => global });
        Value -> Value
    end;
get(Key, Default, Opts) ->
    % No preference was set in Opts, so we default to local.
    ?MODULE:get(Key, Default, Opts#{ prefer => local }).

-define(ENV_KEYS,
    #{
        priv_key_location => {"HB_KEY", "hyperbeam-key.json"},
        hb_config_location => {"HB_CONFIG", "config.flat"},
        port => {"HB_PORT", fun erlang:list_to_integer/1, "8734"},
        store =>
            {"HB_STORE",
                fun(Dir) ->
                    {
                        hb_store_fs,
                        #{ prefix => Dir }
                    }
                end,
                "TEST-cache"
            },
        mode => {"HB_MODE", fun list_to_existing_atom/1},
        debug_print =>
            {"HB_PRINT",
                fun
                    (Str) when Str == "1" -> true;
                    (Str) when Str == "true" -> true;
                    (Str) -> string:tokens(Str, ",")
                end
            }
    }
).

%% @doc Get an environment variable or configuration key.
global_get(Key, Default) ->
    case maps:get(Key, ?ENV_KEYS, Default) of
        Default -> config_lookup(Key, Default);
        {EnvKey, ValParser, DefaultValue} when is_function(ValParser) ->
            ValParser(os:getenv(EnvKey, DefaultValue));
        {EnvKey, ValParser} when is_function(ValParser) ->
            case os:getenv(EnvKey, not_found) of
                not_found -> config_lookup(Key, Default);
                Value -> ValParser(Value)
            end;
        {EnvKey, DefaultValue} ->
            os:getenv(EnvKey, DefaultValue)
    end.

%% @doc An abstraction for looking up configuration variables. In the future,
%% this is the function that we will want to change to support a more dynamic
%% configuration system.
config_lookup(Key, Default) -> maps:get(Key, default_message(), Default).

%% @doc Parse a `flat@1.0' encoded file into a map, matching the types of the 
%% keys to those in the default message.
load(Path) ->
    case file:read_file(Path) of
        {ok, Bin} ->
            try dev_codec_flat:deserialize(Bin) of
                Map -> {ok, mimic_default_types(Map, new_atoms)}
            catch
                error:B -> {error, B}
            end;
        _ -> {error, not_found}
    end.

%% @doc Mimic the types of the default message for a given map.
mimic_default_types(Map, Mode) ->
    Default = default_message(),
    maps:from_list(lists:map(
        fun({Key, Value}) ->
            NewKey = key_to_atom(Key, Mode),
            NewValue = 
                case maps:get(NewKey, Default, not_found) of
                    not_found -> Value;
                    DefaultValue when is_atom(DefaultValue) ->
                        binary_to_existing_atom(Value);
                    DefaultValue when is_integer(DefaultValue) ->
                        binary_to_integer(Value);
                    DefaultValue when is_float(DefaultValue) ->
                        binary_to_float(Value);
                    DefaultValue when is_binary(DefaultValue) ->
                        Value;
                    _ -> Value
                end,
            {NewKey, NewValue}
        end,
        maps:to_list(Map)
    )).

%% @doc Convert keys in a map to atoms, lowering `-' to `_'.
key_to_atom(Key, Mode) ->
    WithoutDashes = binary:replace(Key, <<"-">>, <<"_">>, [global]),
    case Mode of
        new_atoms -> binary_to_atom(WithoutDashes, utf8);
        _ ->
            try binary_to_existing_atom(WithoutDashes, utf8)
            catch
                error:badarg -> WithoutDashes
            end
    end.
    
%%% Tests

global_get_test() ->
    ?assertEqual(debug, ?MODULE:get(mode)),
    ?assertEqual(debug, ?MODULE:get(mode, production)),
    ?assertEqual(undefined, ?MODULE:get(unset_global_key)),
    ?assertEqual(1234, ?MODULE:get(unset_global_key, 1234)).

local_get_test() ->
    Local = #{ only => local },
    ?assertEqual(undefined, 
        ?MODULE:get(test_key, undefined, Local)),
    ?assertEqual(correct,
        ?MODULE:get(test_key, undefined, Local#{ test_key => correct })).

local_preference_test() ->
    Local = #{ prefer => local },
    ?assertEqual(correct,
        ?MODULE:get(test_key, undefined, Local#{ test_key => correct })),
    ?assertEqual(correct,
        ?MODULE:get(mode, undefined, Local#{ mode => correct })),
    ?assertNotEqual(undefined,
        ?MODULE:get(mode, undefined, Local)).

global_preference_test() ->
    Global = #{ prefer => global },
    ?assertEqual(undefined, ?MODULE:get(test_key, undefined, Global)),
    ?assertNotEqual(incorrect,
        ?MODULE:get(mode, undefined, Global#{ mode => incorrect })),
    ?assertNotEqual(undefined, ?MODULE:get(mode, undefined, Global)).

load_test() ->
    % File contents:
    % port: 1234
    % host: https://ao.computer
    % await-inprogress: false
    {ok, Conf} = load("test/config.flat"),
    ?event({loaded, {explicit, Conf}}),
    % Ensure we convert types as expected.
    ?assertEqual(1234, maps:get(port, Conf)),
    % A binary
    ?assertEqual(<<"https://ao.computer">>, maps:get(host, Conf)),
    % An atom, where the key contained a header-key `-' rather than a `_'.
    ?assertEqual(false, maps:get(await_inprogress, Conf)).
