-define(DCCA_APPLICATION_ID, 4).
-define(DIAMETER_IP, "127.0.0.1").
-define(DIAMETER_PORT, 3868).
-define(DIAMETER_PROTO, tcp).
-define(VENDOR_ID, 0).
-define(ORIGIN_HOST, "example.com").
-define(ORIGIN_REALM, "realm.example.com").
-define(CONTEXT_ID, "gprs@diameter.com").

-define(CCR_INITIAL, ?'CC-REQUEST-TYPE_INITIAL_REQUEST').
-define(CCR_UPDATE, ?'CC-REQUEST-TYPE_UPDATE_REQUEST').
-define(CCR_TERMINATE, ?'CC-REQUEST-TYPE_TERMINATION_REQUEST').

-define(MSISDN, ?'SUBSCRIPTION-ID-TYPE_END_USER_E164').
-define(IMSI, ?'SUBSCRIPTION-ID-TYPE_END_USER_IMSI').