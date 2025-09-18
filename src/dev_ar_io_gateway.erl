%%% @doc A device that manages an ar-io-gateway environment, loading and 
%%% running a node service from GitHub. This device spawns a gateway service
%%% and exposes it internally to the Erlang VM.
-module(dev_ar_io_gateway).
-export([info/1, info/3, start/3, stop/3, status/3, logs/3, resolver/3, resolver/0, resolver/1]).
-include_lib("eunit/include/eunit.hrl").
-include_lib("include/hb.hrl").

%%% Timeout for gateway status check.
-define(STATUS_TIMEOUT, 100).

%% @doc Exported function for getting device info, controls which functions 
%% are exposed via the device API.
info(_) -> 
    ?event(debug_ar_io_gateway, {info, entry, device_info_requested}),
    #{ exports => [info, start, stop, status, logs, resolver, proxy] }.

%% @doc HTTP info response providing information about this device
info(_Msg1, _Msg2, _Opts) ->
    ?event(debug_ar_io_gateway, {info, http_request, starting}),
    InfoBody = #{
        <<"description">> => 
            <<"AR.IO Gateway Management for HyperBEAM Nodes">>,
        <<"version">> => <<"1.0">>,
        <<"api">> => #{
            <<"info">> => #{
                <<"description">> => <<"Get device info">>
            },
            <<"start">> => #{
                <<"description">> => <<"Start the AR.IO gateway service">>
            },
            <<"stop">> => #{
                <<"description">> => <<"Stop the AR.IO gateway service">>
            },
            <<"status">> => #{
                <<"description">> => <<"Check AR.IO gateway service status">>
            },
            <<"logs">> => #{
                <<"description">> => <<"Get recent logs from AR.IO gateway service">>
            },
            <<"resolver">> => #{
                <<"description">> => <<"Resolve ARNS names to transaction IDs using local AR.IO gateway">>,
                <<"parameters">> => #{
                    <<"name">> => <<"The ARNS name to resolve (e.g., 'ardrive')">>
                }
            }
        }
    },
    ?event(debug_ar_io_gateway, {info, http_response, success}),
    {ok, #{<<"status">> => 200, <<"body">> => InfoBody}}.

%% @doc Start the AR.IO gateway service
start(_Msg1, _Msg2, Opts) ->
    ?event(debug_ar_io_gateway, {start, entry, starting_gateway}),
    
    % Check if already running
    case hb_name:lookup(<<"ar-io-gateway@1.0">>) of
        Pid when is_pid(Pid) ->
            case is_process_alive(Pid) of
                true ->
                    {ok, #{<<"status">> => 200, <<"body">> => <<"AR.IO gateway is already running">>}};
                false ->
                    start_gateway_async(Opts)
            end;
        undefined ->
            start_gateway_async(Opts)
    end.

%% @doc Start the gateway asynchronously and return immediately
start_gateway_async(Opts) ->
    spawn(fun() -> ensure_started(Opts) end),
    {ok, #{<<"status">> => 202, <<"body">> => <<"AR.IO gateway startup initiated. Use /status to check progress.">>}}.

%% @doc Stop the AR.IO gateway service
stop(_Msg1, _Msg2, _Opts) ->
    ?event(debug_ar_io_gateway, {stop, entry, stopping_gateway}),
    % Unregister the process if it exists
    case hb_name:lookup(<<"ar-io-gateway@1.0">>) of
        undefined ->
            {ok, #{<<"status">> => 200, <<"body">> => <<"AR.IO gateway processes cleaned up">>}};
        Pid when is_pid(Pid) ->
            % Send stop message to the Erlang process
            Pid ! stop,
            hb_name:unregister(<<"ar-io-gateway@1.0">>),
            {ok, #{<<"status">> => 200, <<"body">> => <<"AR.IO gateway stopped successfully">>}}
    end.

%% @doc Check the status of the AR.IO gateway service
status(_Msg1, _Msg2, Opts) ->
    ?event(debug_ar_io_gateway, {status, entry, checking_status}),
    % Check if the process is registered first
    ProcessRunning = case hb_name:lookup(<<"ar-io-gateway@1.0">>) of
        undefined -> false;
        Pid when is_pid(Pid) -> is_process_alive(Pid)
    end,
    % If process is running, check HTTP endpoint
    case ProcessRunning of
        true ->
            HttpRunning = is_gateway_server_running(Opts),
            Port = hb_opts:get(ar_io_gateway_port, 4000, Opts),
            case HttpRunning of
                true ->
                    {ok, #{<<"status">> => 200, <<"body">> => iolist_to_binary(["AR.IO gateway is running and responding on port ", integer_to_list(Port)])}};
                false ->
                    {ok, #{<<"status">> => 200, <<"body">> => iolist_to_binary(["AR.IO gateway process is running but not responding to HTTP on port ", integer_to_list(Port), ". Check logs for Node.js startup issues."])}}
            end;
        false ->
            {ok, #{<<"status">> => 200, <<"body">> => <<"AR.IO gateway is not running">>}}
    end.

%% @doc Get recent logs from the AR.IO gateway service  
logs(_Msg1, _Msg2, _Opts) ->
    ?event(debug_ar_io_gateway, {logs, entry, getting_logs}),
    
    % Try to get logs from the gateway process itself
    case hb_name:lookup(<<"ar-io-gateway@1.0">>) of
        undefined ->
            {ok, #{<<"status">> => 200, <<"body">> => <<"Gateway process not found - service not started">>}};
        Pid when is_pid(Pid) ->
            case is_process_alive(Pid) of
                false ->
                    {ok, #{<<"status">> => 200, <<"body">> => <<"Gateway process died - check startup errors">>}};
                true ->
                    % Process is alive, try to get logs from it
                    % Use a shorter timeout and non-blocking approach to prevent hanging
                    try
                        % Send a message to get logs from the process
                        Pid ! {get_logs, self()},
                        receive
                            {logs, LogLines} when is_list(LogLines) ->
                                RecentLogs = lists:sublist(lists:reverse(LogLines), 50),
                                LogText = iolist_to_binary(lists:join(<<"\n">>, RecentLogs)),
                                {ok, #{<<"status">> => 200, <<"body">> => LogText}};
                            {logs, undefined} ->
                                {ok, #{<<"status">> => 200, <<"body">> => <<"No logs captured yet - Node.js may be starting">>}}
                        after 500 ->
                            % Shorter timeout to prevent blocking
                            {ok, #{<<"status">> => 200, <<"body">> => <<"Gateway process busy - logs not immediately available">>}}
                        end
                    catch
                        _:Error ->
                            ErrorMsg = iolist_to_binary(io_lib:format("Error getting logs: ~p", [Error])),
                            {ok, #{<<"status">> => 500, <<"body">> => ErrorMsg}}
                    end
            end
    end.

%% @doc Resolve ARNS names using the local AR.IO gateway
resolver(_Msg1, Msg2, Opts) ->
    ?event(debug_ar_io_gateway, {resolver, entry, resolving_name}),
    
    % Get the name parameter from the request
    Name = case hb_ao:get(<<"name">>, Msg2, Opts) of
        undefined -> 
            hb_ao:get(<<"key">>, Msg2, Opts); % Fallback to 'key' parameter
        N -> N
    end,
    
    case Name of
        undefined ->
            {ok, #{<<"status">> => 400, <<"body">> => <<"Missing 'name' parameter">>}};
        NameBin when is_binary(NameBin) ->
            resolve_arns_name(NameBin, Opts);
        _ ->
            {ok, #{<<"status">> => 400, <<"body">> => <<"Invalid 'name' parameter format">>}}
    end.

%% @doc Internal function to resolve ARNS name via local gateway
resolve_arns_name(Name, Opts) ->
    Port = integer_to_binary(hb_opts:get(ar_io_gateway_port, 4000, Opts)),
    RelayPath = <<"/ar-io/resolver/", Name/binary>>,
    
    ?event(debug_ar_io_gateway, {resolver, request, {name, Name}, {relay_path, RelayPath}}),
    
    try hb_ao:resolve(
        #{
            <<"device">> => <<"relay@1.0">>,
            <<"content-type">> => <<"application/json">>
        },
        #{
            <<"path">> => <<"call">>,
            <<"relay-method">> => <<"GET">>,
            <<"relay-path">> => RelayPath,
            <<"peer">> => <<"http://localhost:", Port/binary>>,
            <<"content-type">> => <<"application/json">>
        },
        Opts#{
            hashpath => ignore,
            cache_control => [<<"no-store">>, <<"no-cache">>]
        }
    ) of
        {ok, Res} ->
            ?event(debug_ar_io_gateway, {resolver, success, {name, Name}, {response, Res}}),
            {ok, Res};
        {error, Reason} ->
            ?event(debug_ar_io_gateway, {resolver, request_failed, {reason, Reason}}),
            {ok, #{<<"status">> => 503, <<"body">> => <<"AR.IO gateway is not accessible">>}}
    catch
        Error:Reason ->
            ?event(debug_ar_io_gateway, {resolver, http_exception, {error, Error}, {reason, Reason}}),
            {ok, #{<<"status">> => 503, <<"body">> => <<"AR.IO gateway connection failed">>}}
    end.

%% @doc Return a resolver configuration for use with the name@1.0 device
resolver() ->
    resolver(#{}).

resolver(_Opts) ->
    ?event(debug_ar_io_gateway_resolver, {resolver_config_created}),
    #{
        <<"device">> => #{
            <<"lookup">> => fun(_, Req, ResolverOpts) ->
                ?event(debug_ar_io_gateway_resolver, {lookup_called, {req, Req}}),
                Name = hb_ao:get(<<"key">>, Req, ResolverOpts),
                ?event(debug_ar_io_gateway_resolver, {extracted_name, {name, Name}}),
                case Name of
                    not_found -> 
                        ?event(debug_ar_io_gateway_resolver, {lookup_failed, name_not_found}),
                        {error, invalid_request};
                    NameBin when is_binary(NameBin) ->
                        ?event(debug_ar_io_gateway_resolver, {resolving_name, {name, NameBin}}),
                        % Ensure the AR.IO gateway is started before resolving
                        case ensure_started(ResolverOpts) of
                            true ->
                                case hb_ao:resolve(
                                    #{<<"device">> => <<"ar-io-gateway@1.0">>},
                                    #{<<"path">> => <<"resolver">>, <<"name">> => NameBin},
                                    ResolverOpts
                                ) of
                            {ok, #{<<"status">> := 200, <<"body">> := Body}} when is_binary(Body) ->
                                ?event(debug_ar_io_gateway_resolver, {got_response_body, {body, Body}}),
                                try
                                    case jsx:decode(Body, [return_maps]) of
                                        #{<<"txId">> := TxId} when is_binary(TxId) ->
                                            ?event(debug_ar_io_gateway_resolver, {extracted_txid, {txid, TxId}}),
                                            {ok, TxId};
                                        DecodedBody ->
                                            ?event(debug_ar_io_gateway_resolver, {invalid_json_structure, {decoded, DecodedBody}}),
                                            {error, invalid_response}
                                    end
                                catch
                                    _:JsonError -> 
                                        ?event(debug_ar_io_gateway_resolver, {json_decode_error, {error, JsonError}, {body, Body}}),
                                        {error, json_decode_failed}
                                end;
                            {ok, #{<<"status">> := Status, <<"body">> := Body}} ->
                                ?event(debug_ar_io_gateway_resolver, {non_200_response, {status, Status}, {body, Body}}),
                                {error, {http_error, Status}};
                            {ok, Response} -> 
                                ?event(debug_ar_io_gateway_resolver, {invalid_response_format, {response, Response}}),
                                {error, invalid_response_format};
                                    Error -> 
                                        ?event(debug_ar_io_gateway_resolver, {resolve_error, {error, Error}}),
                                        Error
                                end;
                            false ->
                                ?event(debug_ar_io_gateway_resolver, {gateway_not_started}),
                                {error, gateway_not_available}
                        end
                end
            end
        }
    }.

%% @doc Ensure the local `ar-io-gateway@1.0' is live. If it not, start it.
ensure_started(Opts) ->
    % Check if the `ar-io-gateway@1.0' device is already running. The presence
    % of the registered name implies its availability.
    {ok, Cwd} = file:get_cwd(),
    ?event({ensure_started, cwd, Cwd}),
    % Determine path based on whether we're in a release or development
    GatewayServerDir =
        case init:get_argument(mode) of
            {ok, [["embedded"]]} ->
                % We're in release mode - ar-io-gateway is in the release root
                filename:join([Cwd, "ar-io-gateway"]);
            _ ->
                % We're in development mode - look in the build directory
                DevPath =
                    filename:join(
                        [
                            Cwd,
                            "_build",
                            "gateway",
                            "ar-io-gateway"
                        ]
                    ),
                case filelib:is_dir(DevPath) of
                    true -> DevPath;
                    false -> filename:join([Cwd, "_build/ar-io-gateway"]) % Fallback
                end
        end,
    ?event({ensure_started, ar_io_gateway_server_dir, GatewayServerDir}),
    ?event({ensure_started, ar_io_gateway, self()}),
    IsRunning = is_gateway_server_running(Opts),
    IsCompiled = hb_features:ar_io_gateway(),
    GatewayProc = is_pid(hb_name:lookup(<<"ar-io-gateway@1.0">>)),
    case IsRunning orelse (IsCompiled andalso GatewayProc) of
        true ->
            % If it is, do nothing.
            true;
        false ->
			% The device is not running, so we need to start it.
            PID =
                spawn(
                    fun() ->
                        io:format("AR.IO Gateway: Starting process ~p in directory ~s~n", [self(), GatewayServerDir]),
                        ?event({ar_io_gateway_booting, {pid, self()}, {server_dir, GatewayServerDir}}),
                        
                        % Check if the server directory exists
                        case filelib:is_dir(GatewayServerDir) of
                            false ->
                                ?event({ar_io_gateway_error, {server_dir_not_found, GatewayServerDir}}),
                                exit({error, server_dir_not_found});
                            true ->
                                ?event({ar_io_gateway_server_dir_ok, GatewayServerDir})
                        end,
                        
                        % Check if package.json exists
                        PackageJsonPath = filename:join([GatewayServerDir, "package.json"]),
                        case filelib:is_file(PackageJsonPath) of
                            false ->
                                ?event({ar_io_gateway_error, {package_json_not_found, PackageJsonPath}}),
                                exit({error, package_json_not_found});
                            true ->
                                ?event({ar_io_gateway_package_json_ok, PackageJsonPath})
                        end,
                        
                        % Create ar_io_gateway data dir, if it does not exist.
                        RelativeDataDir =
                            hb_util:list(
                                hb_opts:get(
                                    ar_io_gateway_data_dir,
                                    "data",
                                    Opts
                                )
                            ),
                        DataDir = filename:absname(RelativeDataDir),
                        ?event({ar_io_gateway_creating_data_dir, DataDir}),
                        filelib:ensure_path(DataDir),
                        DelegatedComputeURL =
                            case hb_features:genesis_wasm() of
                                true  -> "http://localhost:6363";
                                false -> "https://cu.ardrive.io"
                            end,
                        io:format("AR.IO Gateway: About to start npm in ~s~n", [GatewayServerDir]),
                        ?event({ar_io_gateway_starting_npm, {cwd, GatewayServerDir}}),
                        Port =
                            open_port(
                                {spawn_executable,
                                    filename:join(
                                        [
                                            GatewayServerDir,
                                            "launch-monitored.sh"
                                        ]
                                    )
                                },
                                [
                                    binary, use_stdio, stderr_to_stdout,
                                    {cd, GatewayServerDir},
                                    {args, Args = [
                                        "sh",
                                        "-c",
                                        "npm run db:migrate up && npm run start:prod"
                                    ]},
                                    {env,
                                        Env = [
                                            {"NODE_ENV", "production"},
                                            {"PORT",
                                                integer_to_list(
                                                    hb_opts:get(
                                                        ar_io_gateway_port,
                                                        4000,
                                                        Opts
                                                    )
                                                )
                                            },
                                            {"START_HEIGHT", "0"},
                                            {"START_WRITERS", "false"},
                                            {"ANT_AO_CU_URL", DelegatedComputeURL},
                                            {"NETWORK_AO_CU_URL", DelegatedComputeURL},
                                            {"LOG_LEVEL", "debug"},
                                            {"DATA_DIR", DataDir},
                                            {"ARNS_RESOLVER_PRIORITY_ORDER", "on-demand"},
                                            {"ENABLE_BACKGROUND_DATA_VERIFICATION", "false"},
                                            {"ARWEAVE_GATEWAY",
                                                hb_util:list(
                                                    hb_opts:get(
                                                        gateway,
                                                        "https://arweave.net",
                                                        Opts
                                                    )
                                                )
                                            },
                                            {"WALLET_FILE",
                                                filename:absname(
                                                    hb_util:list(
                                                        hb_opts:get(
                                                            priv_key_location,
                                                            no_key,
                                                            Opts
                                                        )
                                                    )
                                                )
                                            }
                                        ]
                                    }
                                ]
                            ),
                        io:format("AR.IO Gateway: Port opened successfully ~p~n", [Port]),
                        ?event({ar_io_gateway_port_opened, {port, Port}}),
                        ?event(
                            debug_ar_io_gateway,
                            {started_ar_io_gateway,
                                {args, Args},
                                {env, maps:from_list(Env)}
                            }
                        ),
                        collect_events(Port)
                    end
                ),
            hb_name:register(<<"ar-io-gateway@1.0">>, PID),
            ?event({ar_io_gateway_starting, {pid, PID}}),
            % Wait for the device to start with a timeout
            StartTime = erlang:system_time(millisecond),
            MaxWaitTime = 60000, % 60 seconds timeout
            WaitResult = hb_util:until(
                fun() ->
                    CurrentTime = erlang:system_time(millisecond),
                    ElapsedTime = CurrentTime - StartTime,
                    if ElapsedTime > MaxWaitTime ->
                        ?event({ar_io_gateway_startup_timeout, {elapsed_ms, ElapsedTime}}),
                        timeout;
                    true ->
                        receive after 2000 -> ok end,
                        io:format("AR.IO Gateway: Checking if server is running (elapsed: ~pms)~n", [ElapsedTime]),
                        Status = is_gateway_server_running(Opts),
                        io:format("AR.IO Gateway: Health check result: ~p~n", [Status]),
                        ?event({ar_io_gateway_boot_wait, {received_status, Status}, {elapsed_ms, ElapsedTime}}),
                        Status
                    end
                end
            ),
            case WaitResult of
                timeout ->
                    ?event({ar_io_gateway_startup_failed, timeout}),
                    false;
                _ ->
                    ?event({ar_io_gateway_started, {pid, PID}}),
                    true
            end
    end.

%% @doc Check if the ar-io-gateway server is running, using the cached process ID
%% if available.
is_gateway_server_running(Opts) ->
    case get(ar_io_gateway_pid) of
        undefined ->
            ?event(ar_io_gateway_pinging_server),
            Parent = self(),
            PID = spawn(
                fun() ->
                    ?event({ar_io_gateway_get_info_endpoint, {worker, self()}}),
                    Parent ! {ok, self(), gateway_status_check(Opts)}
                end
            ),
            receive
                {ok, PID, Status} ->
                    put(ar_io_gateway_pid, Status),
                    ?event({ar_io_gateway_received_status, Status}),
                    Status
            after ?STATUS_TIMEOUT ->
                ?event({ar_io_gateway_status_check, timeout}),
                erlang:exit(PID, kill),
                false
            end;
        _ -> true
    end.

%% @doc Check if the ar-io-gateway server is running by requesting its status
%% endpoint.
gateway_status_check(Opts) ->
    ServerPort =
        integer_to_binary(
            hb_opts:get(
                ar_io_gateway_port,
                4000,
                Opts
            )
        ),
    % Try multiple possible health check endpoints
    Endpoints = [
        <<"/ar-io/info">>
    ],
    try_endpoints(<<"http://localhost:", ServerPort/binary>>, Endpoints, Opts).

try_endpoints(_BaseUrl, [], _Opts) ->
    false;
try_endpoints(BaseUrl, [Endpoint|Rest], Opts) ->
    Url = <<BaseUrl/binary, Endpoint/binary>>,
    io:format("AR.IO Gateway: Trying health check URL: ~s~n", [Url]),
    ?event({ar_io_gateway_trying_endpoint, {url, Url}}),
    try hb_http:get(Url, Opts) of
        {ok, Res} ->
            ?event({ar_io_gateway_status_check, {success, Endpoint}, {res, Res}}),
            true;
        Err ->
            io:format("AR.IO Gateway: Health check failed for ~s: ~p~n", [Url, Err]),
            ?event({ar_io_gateway_status_check, {failed, Endpoint}, {err, Err}}),
            try_endpoints(BaseUrl, Rest, Opts)
    catch
        _:Err ->
            io:format("AR.IO Gateway: Health check error for ~s: ~p~n", [Url, Err]),
            ?event({ar_io_gateway_status_check, {error, Endpoint}, {err, Err}}),
            try_endpoints(BaseUrl, Rest, Opts)
    end.

%% @doc Collect events from the port and log them.
collect_events(Port) ->
    collect_events(Port, <<>>).
collect_events(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_events(Port,
                log_server_events(<<Acc/binary, Data/binary>>)
            );
        {get_logs, From} ->
            % Send current logs to requesting process
            CurrentLogs = case get(ar_io_gateway_logs) of
                undefined -> undefined;
                Logs -> Logs
            end,
            From ! {logs, CurrentLogs},
            collect_events(Port, Acc);
        stop ->
            port_close(Port),
            ?event(ar_io_gateway_stopped, {pid, self()}),
            ok
    end.

%% @doc Log lines of output from the ar-io-gateway server.
log_server_events(Bin) when is_binary(Bin) ->
    log_server_events(binary:split(Bin, <<"\n">>, [global]));
log_server_events([Remaining]) -> Remaining;
log_server_events([Line | Rest]) ->
    % Print directly to console
    io:format("AR.IO Gateway Node.js: ~s~n", [Line]),
    ?event(ar_io_gateway_server, {server_logged, {string, Line}}),
    % Store logs in process dictionary for debugging
    CurrentLogs = case get(ar_io_gateway_logs) of
        undefined -> [];
        Logs -> Logs
    end,
    % Keep only last 100 lines to prevent memory issues
    UpdatedLogs = lists:sublist([Line | CurrentLogs], 100),
    put(ar_io_gateway_logs, UpdatedLogs),
    log_server_events(Rest).
