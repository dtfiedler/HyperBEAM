#!/usr/bin/env escript

main(_) ->
    io:format("Starting HyperBEAM with AR.IO Gateway...~n"),
    hb:init(),
    Port = case os:getenv("HB_PORT") of
        false -> 8734;
        PortStr -> list_to_integer(PortStr)
    end,
    hb:start_mainnet(#{port => Port}),
    io:format("HyperBEAM started with AR.IO Gateway on port ~p~n", [Port]).