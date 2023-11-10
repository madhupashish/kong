#!/usr/bin/env bash

# This shell script schedules the test files that need to run.

set -e

if [ -z "$TESTS_TO_RUN_QUEUE_URL" ]
then
    echo "TESTS_TO_RUN_QUEUE_URL environment variable not set"
    exit 1
fi

(
    for test in $(find spec/01-unit \
                       spec/02-integration \
                       spec/03-plugins \
                       -name '*_spec.lua')
    do
        echo '{"TestFile":"'$test'","ExcludeTags":"flaky,ipv6,off","Environment":"KONG_TEST_DATABASE=postgres"}'
    done

    for test in $(find spec/02-integration/02-cmd \
                       spec/02-integration/05-proxy \
                       spec/02-integration/04-admin_api/02-kong_routes_spec.lua \
                       spec/02-integration/04-admin_api/15-off_spec.lua \
                       spec/02-integration/08-status_api/01-core_routes_spec.lua \
                       spec/02-integration/08-status_api/03-readiness_endpoint_spec.lua \
                       spec/02-integration/11-dbless \
                       spec/02-integration/20-wasm \
                       -name '*_spec.lua')
    do
        echo '{"TestFile":"'$test'","ExcludeTags":"flaky,ipv6,postgres,db","Environment":"KONG_TEST_DATABASE=postgres"}'
    done
) | .ci/send_to_sqs.py $TESTS_TO_RUN_QUEUE_URL
