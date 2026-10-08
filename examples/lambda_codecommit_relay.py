"""AWS Lambda function to relay CodeCommit pull request events to Redmine.

Configure an EventBridge rule matching `CodeCommit Pull Request State Change`
events with this function as target. The plugin receives the same event JSON
it would get from an EventBridge API destination, so no plugin changes are
needed beyond the `codecommit` provider.

Required environment variables:
  REDMINE_URL   - e.g. https://redmine.example.com/merge_requests/event
  WEBHOOK_TOKEN - value of REDMINE_MERGE_REQUEST_LINKS_CODECOMMIT_WEBHOOK_TOKEN

Place the Lambda inside the VPC if Redmine is not publicly reachable, and
restrict Redmine's security group to allow inbound HTTPS only from the
Lambda's security group.
"""

import json
import os
import urllib.request

REDMINE_URL = os.environ['REDMINE_URL']
WEBHOOK_TOKEN = os.environ['WEBHOOK_TOKEN']
TIMEOUT = 5


def handler(event, _context):
    request = urllib.request.Request(
        REDMINE_URL,
        data=json.dumps(event).encode(),
        headers={
            'Content-Type': 'application/json',
            'X-CodeCommit-Token': WEBHOOK_TOKEN,
        },
        method='POST',
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return {'statusCode': response.status}
