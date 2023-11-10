#!/bin/bash

# This shell script runs test files that have been scheduled to run.
# One test run job is pulled from the TESTS_TO_RUN_QUEUE and executed.
# When it finishes, the entry is deleted from the TESTS_TO_RUN_QUEUE.
# If it failed, it the same job is put to the TESTS_FAILED_QUEUE.

# When starting, all jobs are moved from the TESTS_FAILED_QUEUE to the
# TESTS_TO_RUN_QUEUE so that when re-running the worker(s), those
# tests that failed are retried.

# A theoretical race condition exists when multiple workers are
# started and one worker executes a failing test before another of the
# workers came to start.  This will cause the failing test to be
# immediately re-queued, causing it to be re-run multiple times.
# Given the long startup times for the workers, this scenario is very
# unlikely and won't cause any serious harm, though.

set -e

if [ -z "$TESTS_TO_RUN_QUEUE_URL" ]
then
    echo "TESTS_TO_RUN_QUEUE_URL environment variable not set"
    exit 1
fi

if [ -z "$TESTS_FAILED_QUEUE_URL" ]
then
    echo "TESTS_FAILED_QUEUE_URL environment variable not set"
    exit 1
fi

# Function to run a test
run_test() {
    local TestFile=$(echo "$1" | jq -r '.TestFile')
    local Environment=$(echo "$1" | jq -r '.Environment')
    local ExcludeTags=$(echo "$1" | jq -r '.ExcludeTags')
    echo env $Environment bin/busted -o gtest --exclude-tags=$ExcludeTags $TestFile
    env $Environment bin/busted -o gtest --exclude-tags=$ExcludeTags $TestFile
    return $?
}

# Re-queue tests that failed in a previous run
while true
do
    message=$(aws sqs receive-message --queue-url "$TESTS_FAILED_QUEUE_URL" --max-number-of-messages 1)

    if [ -z "$message" ]
    then
        break
    fi

    ReceiptHandle=$(echo "$message" | jq -r '.Messages[0].ReceiptHandle')
    MessageBody=$(echo "$message" | jq -r '.Messages[0].Body')
    aws sqs send-message --queue-url "$TESTS_TO_RUN_QUEUE_URL" --message-body "$MessageBody"
    aws sqs delete-message --queue-url "$TESTS_FAILED_QUEUE_URL" --receipt-handle "$ReceiptHandle"
done

failures=0
count=0
# Process tests off the queue
while true
do
    message=$(aws sqs receive-message --queue-url "$TESTS_TO_RUN_QUEUE_URL" --max-number-of-messages 1)

    if [ -z "$message" ]
    then
        break
    fi

    ReceiptHandle=$(echo "$message" | jq -r '.Messages[0].ReceiptHandle')
    MessageBody=$(echo "$message" | jq -r '.Messages[0].Body')

    count=$(expr $count + 1)
    echo "Running #$count $MessageBody"
    output_file=/tmp/test-out.$$.txt
    if ! run_test "$MessageBody" >& $output_file
    then
        aws sqs send-message --queue-url "$TESTS_FAILED_QUEUE_URL" --message-body "$MessageBody"
        echo "FAILED"
        cat $output_file
        failures=$(expr $failures + 1)
    fi
    rm -f $output_file
    aws sqs delete-message --queue-url "$TESTS_TO_RUN_QUEUE_URL" --receipt-handle "$ReceiptHandle"
done

if [ $failures != 0 ]
then
    echo "$failures test files failed"
    exit 1
fi

exit 0
