%% @author Carlos Eduardo de Paula <carlosedp@gmail.com>
%% @copyright 2015 Carlos Eduardo de Paula
%% @doc gen_server callback module implementation:
%%
%% @end
-module(dccaclient).

-author('Carlos Eduardo de Paula <carlosedp@gmail.com>').

-behaviour(gen_server).

-include_lib("rfc4006_cc_Gy.hrl").
-include_lib("diameter_settings.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([start_link/0]).
-export([start/0, stop/0, terminate/2]).
-export([test/0, charge_event/1, looptest/1]).
%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([code_change/3]).

%%%.
%%%'   Diameter Application Definitions
%%%.
-define(SERVER, ?MODULE).
-define(SVC_NAME, ?MODULE).
-define(APP_ALIAS, ?MODULE).
-define(CALLBACK_MOD, client_cb).
-define(DIAMETER_DICT_CCRA, rfc4006_cc_Gy).
%% The service configuration. As in the server example, a client
%% supporting multiple Diameter applications may or may not want to
%% configure a common callback module on all applications.
-define(SERVICE(Name), [
    {'Origin-Host', application:get_env(?SERVER, origin_host, "default.com")},
    {'Origin-Realm', application:get_env(?SERVER, origin_realm, "realm.default.com")},
    {'Vendor-Id', application:get_env(?SERVER, vendor_id, 0)},
    {'Product-Name', "Client"},
    {'Auth-Application-Id', [?DCCA_APPLICATION_ID]},
    {application, [{alias, ?APP_ALIAS}, {dictionary, ?DIAMETER_DICT_CCRA}, {module, ?CALLBACK_MOD}]}
]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

%% @doc starts gen_server implementation and caller links to the process too.
-spec start_link() -> {ok, Pid} | ignore | {error, Error} when
    Pid :: pid(),
    Error :: {already_started, Pid} | term().
start_link() ->
    % TODO: decide whether to name gen_server callback implementation or not.
    % gen_server:start_link(?MODULE, [], []). % for unnamed gen_server
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc starts gen_server implementation process
-spec start() -> ok | {error, term()}.
start() ->
    application:ensure_all_started(?MODULE),
    start_link().

%% @doc stops gen_server implementation process
-spec stop() -> ok.
stop() ->
    gen_server:cast(?SERVER, stop).

%% @doc Generate a test event
looptest(0) ->
    ok;
looptest(Count) ->
    test(),
    looptest(Count - 1).

test() ->
    Res = gen_server:call(
        ?SERVER,
        {gprs, {"5511985231234", "72412345678912", 1, 100, 1000000, 1}}
    ),
    lager:info("Response is ~p~n", [Res]).

%% @doc Charges event
charge_event(data) ->
    % Data format: {gprs, {MSISDN, IMSI, ServiceId, RatingGroup, VolumeBytes, TimeToConsumeBytes}}
    Res = gen_server:call(?SERVER, data),
    lager:info("Response is ~p~n", [Res]).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(State) ->
    Proto = application:get_env(?SERVER, diameter_proto, tcp),
    Server =
        case os:getenv("DCCASERVER") of
            false -> application:get_env(?SERVER, diameter_server_ip, "127.0.0.1");
            Name -> Name
        end,
    {ok, Ip} = inet:getaddr(Server, inet),
    Port = application:get_env(?SERVER, diameter_port, 3868),
    diameter:start_service(?MODULE, ?SERVICE(Name)),
    connect({address, Proto, Ip, Port}),
    {ok, State}.

%% @callback gen_server
handle_call(
    {gprs, {MSISDN, IMSI, ServiceId, RatingGroup, VolumeBytes, TimeToConsumeBytes}},
    _From,
    State
) ->
    SessionId = diameter:session_id(atom_to_list(?SVC_NAME)),
    ReqN = 0,
    % Generate initial CCR without MSCC
    Ret = create_session(gprs, {initial, MSISDN, IMSI, SessionId, ReqN}),
    case Ret of
        {ok, _} ->
            lager:info("CCR-INITIAL Success..."),
            rate_service(
                gprs,
                {update, MSISDN, IMSI, SessionId, ReqN, {ServiceId, RatingGroup, 0, VolumeBytes},
                    TimeToConsumeBytes}
            ),
            lager:info("Event charged successfully.");
        {error, Err} ->
            lager:error("Error: ~w~n", [Err])
    end,
    {reply, ok, State}.

%% @callback gen_server
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_Req, State) ->
    {noreply, State}.

%% @callback gen_server
handle_info(_Info, State) ->
    {noreply, State}.

%% @callback gen_server
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% @callback gen_server
terminate(normal, _State) ->
    diameter:stop_service(?SVC_NAME),
    ok;
terminate(shutdown, _State) ->
    ok;
terminate({shutdown, _Reason}, _State) ->
    ok;
terminate(_Reason, _State) ->
    ok.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% connect/2
connect(Name, {address, Protocol, IPAddr, Port}) ->
    % {ok, IP} = inet_parse:address(IPAddr),
    TransportOpts =
        [
            {transport_module, tmod(Protocol)},
            {transport_config, [
                {reuseaddr, true},
                {raddr, IPAddr},
                %{ip, {IP}},
                {rport, Port}
            ]}
        ],
    diameter:add_transport(Name, {connect, [{reconnect_timer, 1000} | TransportOpts]}).

connect(Address) ->
    connect(?SVC_NAME, Address).

%% Convert connection type
tmod(tcp) ->
    diameter_tcp;
tmod(sctp) ->
    diameter_sctp.

%% Convert IP address to binary
ip2bin({A, B, C, D}) ->
    <<A, B, C, D>>;
ip2bin(Bin) when is_binary(Bin) ->
    Bin;
ip2bin(Ip) when is_list(Ip) ->
    {ok, IP} = inet_parse:address(Ip),
    ip2bin(IP).

%% Create the PDP context. First CCR does not contain MSCC
create_session(gprs, {initial, MSISDN, IMSI, SessionId, ReqN}) ->
    CCR = #'CCR'{
        'Session-Id' = SessionId,
        'Auth-Application-Id' = 4,
        'Service-Context-Id' = application:get_env(?SERVER, context_id, "context@dcca"),
        'CC-Request-Type' = ?CCR_INITIAL,
        'Framed-IP-Address' = [ip2bin("1.2.3.4")],
        'CC-Request-Number' = ReqN,
        'Event-Timestamp' =
            [
                calendar:now_to_local_time(
                    erlang:timestamp()
                )
            ],
        'Subscription-Id' =
            [
                #'Subscription-Id'{
                    'Subscription-Id-Type' = ?'MSISDN',
                    'Subscription-Id-Data' = MSISDN
                },
                #'Subscription-Id'{
                    'Subscription-Id-Type' = ?'IMSI',
                    'Subscription-Id-Data' = IMSI
                }
            ],
        'Multiple-Services-Indicator' = [1]
    },
    diameter:call(?SVC_NAME, ?APP_ALIAS, CCR, []).

%% Rate service
rate_service(
    gprs,
    {update, MSISDN, IMSI, SessionId, ReqN, {ServiceId, RatingGroup, ConsumedBytes, RemainingBytes},
        TimeToConsumeBytes}
) ->
    ReqN2 = ReqN + 1,
    CCR1 = generate_MSCC(ServiceId, RatingGroup, ConsumedBytes, RemainingBytes),
    CCR2 =
        CCR1#'CCR'{
            'Session-Id' = SessionId,
            'Auth-Application-Id' = ?DCCA_APPLICATION_ID,
            'Service-Context-Id' = application:get_env(?SERVER, context_id, "context@dcca"),
            'CC-Request-Type' = ?CCR_UPDATE,
            'Framed-IP-Address' = [ip2bin("1.2.3.4")],
            'CC-Request-Number' = ReqN2,
            'Event-Timestamp' =
                [
                    calendar:now_to_local_time(
                        erlang:timestamp()
                    )
                ],
            'Subscription-Id' =
                [
                    #'Subscription-Id'{
                        'Subscription-Id-Type' = ?'MSISDN',
                        'Subscription-Id-Data' = MSISDN
                    },
                    #'Subscription-Id'{
                        'Subscription-Id-Type' = ?'IMSI',
                        'Subscription-Id-Data' = IMSI
                    }
                ],
            'Called-Station-Id' = ["apn.com"],
            'Multiple-Services-Indicator' = [1]
        },
    Ret = diameter:call(?SVC_NAME, ?APP_ALIAS, CCR2, []),
    case Ret of
        {ok, CCA} ->
            lager:info("CCR-UPDATE Success..."),
            %% Extract GSU from CCA
            #'CCA'{'Multiple-Services-Credit-Control' = MSCC} = CCA,
            [#'Multiple-Services-Credit-Control'{'Granted-Service-Unit' = GSU} | _] = MSCC,
            [#'Granted-Service-Unit'{'CC-Total-Octets' = [UsedUnits]}] = GSU,
            % Simulate time to consume granted quota
            timer:sleep(TimeToConsumeBytes),
            %% Subtract GSU from total
            case RemainingBytes - UsedUnits of
                NewRemainingBytes when NewRemainingBytes > 0 ->
                    rate_service(
                        gprs,
                        {update, MSISDN, IMSI, SessionId, ReqN2,
                            {ServiceId, RatingGroup, UsedUnits, NewRemainingBytes},
                            TimeToConsumeBytes}
                    );
                NewRemainingBytes when NewRemainingBytes =< 0 ->
                    lager:info(
                        "Last request: ~w | ~w | ~w ~n",
                        [UsedUnits, RemainingBytes, NewRemainingBytes]
                    ),
                    rate_service(
                        gprs,
                        {terminate, MSISDN, IMSI, SessionId, ReqN2,
                            {ServiceId, RatingGroup, RemainingBytes, 0}, TimeToConsumeBytes}
                    )
            end;
        {error, Err} ->
            lager:error("Error: ~w~n", [Err])
    end,
    ok;
rate_service(
    gprs,
    {terminate, MSISDN, IMSI, SessionId, ReqN,
        {ServiceId, RatingGroup, ConsumedBytes, RemainingBytes}, _TimeToConsumeBytes}
) ->
    CCR1 = generate_MSCC(ServiceId, RatingGroup, ConsumedBytes, RemainingBytes),
    CCR2 =
        CCR1#'CCR'{
            'Session-Id' = SessionId,
            'Auth-Application-Id' = ?DCCA_APPLICATION_ID,
            'Service-Context-Id' = application:get_env(?SERVER, context_id, "context@dcca"),
            'CC-Request-Type' = ?CCR_TERMINATE,
            'Framed-IP-Address' = [ip2bin("1.2.3.4")],
            'CC-Request-Number' = ReqN + 1,
            'Event-Timestamp' =
                [
                    calendar:now_to_local_time(
                        erlang:timestamp()
                    )
                ],
            'Subscription-Id' =
                [
                    #'Subscription-Id'{
                        'Subscription-Id-Type' = ?'MSISDN',
                        'Subscription-Id-Data' = MSISDN
                    },
                    #'Subscription-Id'{
                        'Subscription-Id-Type' = ?'IMSI',
                        'Subscription-Id-Data' = IMSI
                    }
                ],
            'Called-Station-Id' = ["apn.com"]
        },
    Ret = diameter:call(?SVC_NAME, ?APP_ALIAS, CCR2, []),
    case Ret of
        {ok, _} ->
            lager:info("CCR-TERMINATE Success...");
        {error, Err} ->
            lager:error("Error: ~w~n", [Err])
    end,
    ok.

%% Generate MSCC AVP for requests based on remaining quota
generate_MSCC(ServiceId, RatingGroup, ConsumedBytes, RemainingBytes) ->
    if
        (ConsumedBytes == 0) and (RemainingBytes > 0) ->
            %% First request. Must send RSU and no USU.
            MSCC =
                #'CCR'{
                    'Multiple-Services-Credit-Control' =
                        [
                            #'Multiple-Services-Credit-Control'{
                                'Requested-Service-Unit' =
                                    [
                                        #'Requested-Service-Unit'{
                                            'CC-Total-Octets' =
                                                []
                                        }
                                    ],
                                'Service-Identifier' = [ServiceId],
                                'Rating-Group' = [RatingGroup]
                            }
                        ]
                };
        (ConsumedBytes /= 0) and (RemainingBytes > 0) ->
            %% Update request. Must send RSU and USU.
            MSCC =
                #'CCR'{
                    'Multiple-Services-Credit-Control' =
                        [
                            #'Multiple-Services-Credit-Control'{
                                'Requested-Service-Unit' =
                                    [
                                        #'Requested-Service-Unit'{
                                            'CC-Total-Octets' =
                                                []
                                        }
                                    ],
                                'Used-Service-Unit' =
                                    [
                                        #'Used-Service-Unit'{
                                            'CC-Total-Octets' =
                                                [ConsumedBytes]
                                        }
                                    ],
                                'Service-Identifier' = [ServiceId],
                                'Rating-Group' = [RatingGroup],
                                'Reporting-Reason' =
                                    [?'REPORTING-REASON_QUOTA_EXAUSTED']
                            }
                        ]
                };
        (ConsumedBytes /= 0) and (RemainingBytes =< 0) ->
            %% Last update request. Must send USU to report last used bytes. No RSU.
            MSCC =
                #'CCR'{
                    'Multiple-Services-Credit-Control' =
                        [
                            #'Multiple-Services-Credit-Control'{
                                'Used-Service-Unit' =
                                    [
                                        #'Used-Service-Unit'{
                                            'CC-Total-Octets' =
                                                [ConsumedBytes]
                                        }
                                    ],
                                'Service-Identifier' = [ServiceId],
                                'Rating-Group' = [RatingGroup],
                                'Reporting-Reason' =
                                    [?'REPORTING-REASON_FINAL']
                            }
                        ]
                };
        true ->
            MSCC = err
    end,
    MSCC.

%%%.
%%% vim: set filetype=erlang tabstop=2 foldmarker=%%%',%%%. foldmethod=marker:
