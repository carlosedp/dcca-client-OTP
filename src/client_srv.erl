%% @author Carlos Eduardo de Paula <carlosedp@gmail.com>
%% @copyright 2015 Carlos Eduardo de Paula
%% @doc gen_server callback module implementation:
%%
%% @end
-module(client_srv).
-author('Carlos Eduardo de Paula <carlosedp@gmail.com>').

-behaviour(gen_server).

-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include_lib("include/rfc4006_cc_Gy.hrl").
-include_lib("diameter_settings.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([start_link/0]).
-export([stop/0, terminate/2]).
-export([test/0, charge_event/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([code_change/3]).

% TODO: If unnamed server, remove definition below.
-define(SERVER, ?MODULE).

%%%.
%%%'   Diameter Application Definitions

-define(SVC_NAME, ?MODULE).
-define(APP_ALIAS, ?MODULE).
-define(CALLBACK_MOD, client_cb).
-define(DIAMETER_DICT_CCRA, rfc4006_cc_Gy).

-define(L, atom_to_list).

%% The service configuration. As in the server example, a client
%% supporting multiple Diameter applications may or may not want to
%% configure a common callback module on all applications.
-define(SERVICE(Name), [{'Origin-Host', ?ORIGIN_HOST},
                        {'Origin-Realm', ?ORIGIN_REALM},
                        {'Vendor-Id', ?VENDOR_ID},
                        {'Product-Name', "Client"},
                        {'Auth-Application-Id', [?DCCA_APPLICATION_ID]},
                        {application, [{alias, ?APP_ALIAS},
                                       {dictionary, ?DIAMETER_DICT_CCRA},
                                       {module, ?CALLBACK_MOD}]}]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

%% @doc starts gen_server implementation and caller links to the process too.
-spec start_link() -> {ok, Pid} | ignore | {error, Error}
  when
      Pid :: pid(),
      Error :: {already_started, Pid} | term().
start_link() ->
  % TODO: decide whether to name gen_server callback implementation or not.
  % gen_server:start_link(?MODULE, [], []). % for unnamed gen_server
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc stops gen_server implementation process
-spec stop() -> ok.
stop() ->
  gen_server:cast(?SERVER, stop).

test() ->
    gen_server:call(?SERVER, {gprs, {"5511985231234", "72412345678912", 1, 100, 1000000, 1}}).

charge_event(data) ->
  % Data format: {gprs, {MSISDN, IMSI, ServiceId, RatingGroup, VolumeBytes, TimeToConsumeBytes}}
  gen_server:call(?SERVER, data).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(State) ->
  diameter:start_service(?MODULE, ?SERVICE(Name)),
  connect({address, ?DIAMETER_PROTO, ?DIAMETER_IP, ?DIAMETER_PORT}),
  {ok, State}.

%% @callback gen_server
handle_call({gprs, {MSISDN, IMSI, ServiceId, RatingGroup, VolumeBytes, TimeToConsumeBytes}}, _From, State) ->
    SessionId = diameter:session_id(?L(?SVC_NAME)),
    ReqN = 0,
    % Generate initial CCR without MSCC
    Ret = create_session(gprs, {initial, MSISDN, IMSI, SessionId, ReqN}),
    case Ret of
        {ok, _} ->
            io:format("CCR-INITIAL Success...~n"),
            rate_service(gprs, {update, MSISDN, IMSI, SessionId, ReqN, {ServiceId, RatingGroup, 0, VolumeBytes}, TimeToConsumeBytes}),
            io:format("Event charged successfully.~n");
        {error, Err} ->
            io:format("Error: ~w~n", [Err])
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
    {ok, IP} = inet_parse:address(IPAddr),
    TransportOpts =  [{transport_module, tmod(Protocol)},
                      {transport_config, [
                        {reuseaddr, true},
                        {raddr, IP},
                        %{ip, {IP}},
                        {rport, Port}]}
                    ],
    diameter:add_transport(Name, {connect, [{reconnect_timer, 1000} | TransportOpts]}).


connect(Address) ->
    connect(?SVC_NAME, Address).

%% Convert connection type
tmod(tcp)  -> diameter_tcp;
tmod(sctp) -> diameter_sctp.

%% Create the PDP context. First CCR does not contain MSCC
create_session(gprs, {initial, MSISDN, IMSI, SessionId, ReqN}) ->
    CCR = #'CCR'{
        'Session-Id' = SessionId,
        'Auth-Application-Id' = 4,
        'Service-Context-Id' = "gprs@diameter.com",
        'CC-Request-Type' = ?CCR_INITIAL,
        'CC-Request-Number' = ReqN,
        'Event-Timestamp' = [calendar:now_to_local_time(now())],
        'Subscription-Id' = [#'Subscription-Id' {
                                'Subscription-Id-Type' = ?'MSISDN',
                                'Subscription-Id-Data' = MSISDN
                            },
                            #'Subscription-Id' {
                                'Subscription-Id-Type' = ?'IMSI',
                                'Subscription-Id-Data' = IMSI
                            }],
        'Multiple-Services-Indicator' = [1]
    },
    diameter:call(?SVC_NAME, ?APP_ALIAS, CCR, []).

%% Rate service
rate_service(gprs, {update, MSISDN, IMSI, SessionId, ReqN, {ServiceId, RatingGroup, ConsumedBytes, RemainingBytes}, TimeToConsumeBytes}) ->
    ReqN2 = ReqN + 1,
    CCR1 = generate_MSCC(ServiceId, RatingGroup, ConsumedBytes, RemainingBytes),
    CCR2 = CCR1#'CCR'{
            'Session-Id' = SessionId,
            'Auth-Application-Id' = ?DCCA_APPLICATION_ID,
            'Service-Context-Id' = ?CONTEXT_ID,
            'CC-Request-Type' = ?CCR_UPDATE,
            'CC-Request-Number' = ReqN2,
            'Event-Timestamp' = [calendar:now_to_local_time(now())],
            'Subscription-Id' = [#'Subscription-Id' {
                                'Subscription-Id-Type' = ?'MSISDN',
                                'Subscription-Id-Data' = MSISDN
                            },
                            #'Subscription-Id' {
                                'Subscription-Id-Type' = ?'IMSI',
                                'Subscription-Id-Data' = IMSI
                            }],
            'Called-Station-Id' = ["apn.com"],
            'Multiple-Services-Indicator' = [1]
            },
    Ret = diameter:call(?SVC_NAME, ?APP_ALIAS, CCR2, []),
    case Ret of
        {ok, CCA} ->
            io:format("CCR-UPDATE Success...~n"),
            %% Extract GSU from CCA
            #'CCA'{
                  'Multiple-Services-Credit-Control' = MSCC
                } = CCA,
            [#'Multiple-Services-Credit-Control' {
                    'Granted-Service-Unit' = GSU
                }|_] = MSCC,
            [#'Granted-Service-Unit' {
                         'CC-Total-Octets' = [UsedUnits]
            }] = GSU,
            % Simulate time to consume granted quota
            timer:sleep(TimeToConsumeBytes),
            %% Subtract GSU from total
            case RemainingBytes - UsedUnits of
                NewRemainingBytes when NewRemainingBytes > 0 ->
                    rate_service(gprs, {update, MSISDN, IMSI, SessionId, ReqN2, {ServiceId, RatingGroup, UsedUnits, NewRemainingBytes}, TimeToConsumeBytes});
                NewRemainingBytes when NewRemainingBytes =< 0 ->
                    io:format("Last request: ~w | ~w | ~w ~n", [UsedUnits, RemainingBytes, NewRemainingBytes]),
                    rate_service(gprs, {terminate, MSISDN, IMSI, SessionId, ReqN2, {ServiceId, RatingGroup, RemainingBytes, 0}, TimeToConsumeBytes})
            end;
        {error, Err} ->
            io:format("Error: ~w~n", [Err])
    end,
    ok;

rate_service(gprs, {terminate, MSISDN, IMSI, SessionId, ReqN, {ServiceId, RatingGroup, ConsumedBytes, RemainingBytes}, _TimeToConsumeBytes}) ->
    CCR1 = generate_MSCC(ServiceId, RatingGroup, ConsumedBytes, RemainingBytes),
    CCR2 = CCR1#'CCR'{
            'Session-Id' = SessionId,
            'Auth-Application-Id' = ?DCCA_APPLICATION_ID,
            'Service-Context-Id' = ?CONTEXT_ID,
            'CC-Request-Type' = ?CCR_TERMINATE,
            'CC-Request-Number' = ReqN + 1,
            'Event-Timestamp' = [calendar:now_to_local_time(now())],
            'Subscription-Id' = [#'Subscription-Id' {
                                'Subscription-Id-Type' = ?'MSISDN',
                                'Subscription-Id-Data' = MSISDN
                            },
                            #'Subscription-Id' {
                                'Subscription-Id-Type' = ?'IMSI',
                                'Subscription-Id-Data' = IMSI
                            }],
            'Called-Station-Id' = ["apn.com"]
            },
    Ret = diameter:call(?SVC_NAME, ?APP_ALIAS, CCR2, []),
    case Ret of
        {ok, _} ->
            io:format("CCR-TERMINATE Success...~n");
        {error, Err} ->
            io:format("Error: ~w~n", [Err])
    end,
    ok.

%% Generate MSCC AVP for requests based on remaining quota
generate_MSCC(ServiceId, RatingGroup, ConsumedBytes, RemainingBytes) ->
    if
        ((ConsumedBytes == 0 ) and (RemainingBytes > 0)) ->
            %% First request. Must send RSU and no USU.
            MSCC = #'CCR' {
                'Multiple-Services-Credit-Control' = [#'Multiple-Services-Credit-Control' {
                    'Requested-Service-Unit' = [#'Requested-Service-Unit' {
                         'CC-Total-Octets' = []
                     }],
                     'Service-Identifier' = [ServiceId],
                     'Rating-Group' = [RatingGroup]
                }]
            };
        ((ConsumedBytes /= 0 ) and (RemainingBytes > 0)) ->
            %% Update request. Must send RSU and USU.
            MSCC = #'CCR' {
            'Multiple-Services-Credit-Control' = [#'Multiple-Services-Credit-Control' {
                'Requested-Service-Unit' = [#'Requested-Service-Unit' {
                     'CC-Total-Octets' = []
                 }],
                'Used-Service-Unit' = [#'Used-Service-Unit' {
                   'CC-Total-Octets' = [ConsumedBytes]
                }],
                 'Service-Identifier' = [ServiceId],
                 'Rating-Group' = [RatingGroup],
                 'Reporting-Reason' = [?'REPORTING-REASON_QUOTA_EXAUSTED']
            }]
            };
        ((ConsumedBytes /= 0 ) and (RemainingBytes =< 0) ) ->
            %% Last update request. Must send USU to report last used bytes. No RSU.
            MSCC = #'CCR' {
                'Multiple-Services-Credit-Control' = [#'Multiple-Services-Credit-Control' {
                    'Used-Service-Unit' = [#'Used-Service-Unit' {
                        'CC-Total-Octets' = [ConsumedBytes]
                    }],
                    'Service-Identifier' = [ServiceId],
                    'Rating-Group' = [RatingGroup],
                    'Reporting-Reason' = [?'REPORTING-REASON_FINAL']
                }]
            };
        true ->
            MSCC = err
    end,
    MSCC.

%%%.
%%% vim: set filetype=erlang tabstop=2 foldmarker=%%%',%%%. foldmethod=marker:
