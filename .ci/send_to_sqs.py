#!/usr/bin/env python

import sys
import boto3

def read_lines_from_stdin():
    lines = []
    for line in sys.stdin:
        lines.append(line.strip())
    return lines

def send_messages_to_sqs(queue_url, lines):
    sqs = boto3.client('sqs')
    
    # Split input lines into batches of 10
    batches = [lines[i:i+10] for i in range(0, len(lines), 10)]

    any_failures = False  # Flag to track failures

    for batch in batches:
        entries = []
        for line in batch:
            entries.append({'Id': str(len(entries) + 1), 'MessageBody': line})
        
        response = sqs.send_message_batch(
            QueueUrl=queue_url,
            Entries=entries
        )

        for failed in response.get('Failed', []):
            print(f"Failed to send message with ID {failed['Id']}: {failed['Message']}")
            any_failures = True  # Set the flag to True if there are failures

    if any_failures:
        sys.exit(1)  # Exit with a non-zero status code if there are failures

    print(f"Scheduled {len(lines)} test files to be run.")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python send_to_sqs_batch.py <queue_url>")
        sys.exit(1)

    queue_url = sys.argv[1]

    send_messages_to_sqs(queue_url, read_lines_from_stdin())
