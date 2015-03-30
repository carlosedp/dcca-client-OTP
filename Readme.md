# Erlang Diameter Credit Control Client

This repository contains an example OTP DCCA application client built in Erlang.

To build the modules and diameter dictionaries, use rebar:

    ./rebar get-deps compile

or

    make all

To start the module use:

    erl -pa deps/ebin ebin
    
    application:start(diameter).
    application:start(dccaclient).

Or use the provided Makefile:

    make compile
    make shell

on Windows, use `make wshell`.

## Testing

To test the client, use the server module from [dcca-server-OTP](https://github.com/carlosedp/dcca-server-OTP).

The accepted commands are:

### Test DCCA with a simulated event

    client_srv:test().

### Simulate with your own values

    client_srv:charge_event({gprs, {MSISDN, IMSI, ServiceId, RatingGroup, VolumeBytes, TimeToWait}}).
    
    ex:
    client_srv:charge_event({gprs, {"5511985231234", "72412345678912", 1, 100, 1000000, 1}}).

**Where:**

Field|Type|Description
-----|----|-----------
MSISDN|String|User MSISDN
IMSI|String|User IMSI
ServiceId|Int|Session ServiceId
RatingGroup|Int|Session RatingGroup
VolumeBytes|Int|Session volume in bytes to be consumed
TimeToWait|Int|Time wo wait between each intermediate request
