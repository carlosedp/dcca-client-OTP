# Erlang Diameter Credit Control Client

This repository contains an example OTP DCCA application client built in Erlang. It's used as a companion to the [DCCA-server-OTP](https://github.com/carlosedp/dcca-server-OTP) application.

To run the commands, you need [rebar3](https://rebar3.org/docs/getting-started/) that can be either installed into the system (for example using Brew on Mac) or downloaded into the current application diretory (with execution permission).


To build the modules and diameter dictionaries, use rebar:

    rebar3 compile

or

    make

To start the module use (the DCCA server must be up already):

    make shell
    dccaclient:test().  # This will use a simulated event

on Windows, use `make wshell`.

## Testing

To test the client, use the server module from [dcca-server-OTP](https://github.com/carlosedp/dcca-server-OTP).

The accepted commands are:

### Test DCCA with a simulated event

    dccaclient:test().

### Simulate with your own values

    dccaclient:charge_event({gprs, {MSISDN, IMSI, ServiceId, RatingGroup, VolumeBytes, TimeToWait}}).

    ex:
    dccaclient:charge_event({gprs, {"5511985231234", "72412345678912", 1, 100, 1000000, 1}}).

To exit, type Ctrl+G to call the Erlang shell followed by the command "q".

**Where:**

Field|Type|Description
-----|----|-----------
MSISDN|String|User MSISDN
IMSI|String|User IMSI
ServiceId|Int|Session ServiceId
RatingGroup|Int|Session RatingGroup
VolumeBytes|Int|Session volume in bytes to be consumed
TimeToWait|Int|Time wo wait between each intermediate request
