# AWS CodeCommit integration

AWS CodeCommit does not provide webhooks like GitHub or GitLab. Pull
request state changes are published as `CodeCommit Pull Request State
Change` events on Amazon EventBridge.

This plugin supports two delivery methods:

1. **EventBridge API destination** — EventBridge invokes the plugin
   endpoint directly. No AWS code is required, but Redmine must be
   reachable from EventBridge over HTTPS.
2. **Lambda relay** — a Lambda function forwards the event to Redmine.
   This works when Redmine is inside a VPC or otherwise not publicly
   accessible.

## Why these two methods

- **API destination** is the simplest option: it requires only AWS
  console configuration and no code. The plugin already handles the
  event JSON, so no transformation is needed. The trade-off is that
  Redmine must be reachable by EventBridge, and the source IP cannot be
  restricted to a fixed range.
- **Lambda relay** is the fallback for VPC-hosted Redmine. A Lambda
  function inside your VPC can reach Redmine through a security group
  rule that allows inbound HTTPS only from the Lambda's security group.
  The trade-off is that you must maintain a Lambda function, IAM role,
  and deployment.

Both methods send the same `X-CodeCommit-Token` header, so the plugin
configuration is identical.

## EventBridge API destination

### Step 1: Create a connection

Create an EventBridge connection with **API key** authorization:

- **Authorization type**: API Key
- **API key name**: `X-CodeCommit-Token`
- **API key value**: the value of
  `REDMINE_MERGE_REQUEST_LINKS_CODECOMMIT_WEBHOOK_TOKEN`

EventBridge stores the secret in AWS Secrets Manager automatically.

### Step 2: Create an API destination

- **API destination endpoint**: `https://redmine.example.com/merge_requests/event`
- **HTTP method**: `POST`
- **Connection**: the connection created in step 1

For a Redmine inside a VPC, change the API type to **Private API** and
configure a VPC Lattice resource gateway for the endpoint. In that case
the endpoint still needs a publicly resolvable DNS name and a publicly
trusted certificate; the resource gateway handles the private routing.

### Step 3: Create an EventBridge rule

- **Event pattern**:

```json
{
  "source": ["aws.codecommit"],
  "detail-type": ["CodeCommit Pull Request State Change"]
}
```

- **Target**: the API destination created in step 2

### Notes

- The API destination must respond within **5 seconds**.
- EventBridge retries failed invocations for up to **24 hours**.
- Event delivery is best-effort and order is not guaranteed.
- Source IP restriction is not available for API destinations. If you
  need security group based filtering, use VPC Lattice (private API) or
  the Lambda relay below.

## Lambda relay

Use this when Redmine is not publicly reachable, or when you want to
restrict Redmine's security group to allow only the Lambda's security
group.

### Step 1: Create the Lambda function

Create a Python Lambda function with the code in
[`lambda_codecommit_relay.py`](lambda_codecommit_relay.py).

- **Runtime**: Python 3.12 or later
- **Environment variables**:
  - `REDMINE_URL`: `https://redmine.example.com/merge_requests/event`
  - `WEBHOOK_TOKEN`: the value of
    `REDMINE_MERGE_REQUEST_LINKS_CODECOMMIT_WEBHOOK_TOKEN`
- **VPC**: place the function in the same VPC/subnet as Redmine, and
  attach a security group that is allowed to reach Redmine on HTTPS.
- **Timeout**: 5 seconds (the Lambda calls `urlopen` with a 5 second
  timeout; increase if Redmine is slow to respond).

### Step 2: Create an EventBridge rule

- **Event pattern**: same as above
  (`CodeCommit Pull Request State Change`)
- **Target**: the Lambda function

The plugin receives the same event JSON from the Lambda as it would
from an API destination, so no additional plugin configuration is
needed.
