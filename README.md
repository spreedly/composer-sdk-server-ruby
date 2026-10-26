# Spreedly Composer Server SDK for Ruby

## Table of Contents

- [Purpose](#purpose)
- [Prerequisites](#prerequisites)
- [Related](#related)
- [Installation](#installation)
- [Usage](#usage)
- [API](#api)
- [Development](#development)
- [License](#license)
- [Support](#support)

## Purpose

[Spreedly Composer](https://developer.spreedly.com) enables developers to decouple security logic from their application code. This has several benefits including:

- The ability to toggle and compare security services like fraud engines, MFA, KYC, and bot prevention.
- Faster responses to new attacks. When threats evolve and new vulnerabilities are identified, your application's security logic can be updated without changing a single line of code.
- The ability to put in placeholders for future security improvements while focusing on product development.
- A way to visualize all application security logic in one place.

The Composer Server SDK for Ruby makes integration with the Composer API easy and is maintained by the Spreedly team.

## Prerequisites

- Ruby 3.2 or higher
- You will need to obtain an API key for your application from the Composer developer center.

## Related

Check out the [Client SDK](https://npmjs.com/package/@dodgeball/trust-sdk-client) for how to integrate Composer into your frontend applications.

[Composer examples](https://github.com/spreedly/composer-examples) has a runnable example server for this SDK in `server/ruby`, and a web client that calls it.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'spreedly-composer-sdk-server'
```

And then run:

```sh
bundle install
```

Or install it yourself:

```sh
gem install spreedly-composer-sdk-server
```

## Usage

This example protects an order endpoint end to end. Your API calls a checkpoint before placing the order. When the workflow needs more input from the user, such as MFA, your frontend gathers it with the Client SDK and calls your API again with the verification ID. See [Identifiers](#identifiers) for what each ID is and [useVerification](#useverification) for how the second call works.

```ruby
# In your API
require 'composer'
require 'ipaddr'
require 'json'
require 'sinatra'

enable :sessions

# composer = Composer::DodgeballClient.new(ENV['DODGEBALL_SECRET_KEY']) # The Dodgeball name is still supported.
composer = Composer::ComposerClient.new(ENV['SPREEDLY_SECRET_KEY'])

# Client IP for the risk engine. Callers must not choose this value.
# Default (TRUSTED_PROXY_COUNT=0): socket address, ignore X-Forwarded-For.
# Positive count: that many hops from the right of X-Forwarded-For; the hop must be an IP.
# Set TRUSTED_PROXY_COUNT only if your app runs behind trusted reverse proxies.
def get_ip(request)
  raw = ENV['TRUSTED_PROXY_COUNT']
  raw = '0' if raw.nil? || raw.empty?
  begin
    hops = Integer(raw)
  rescue ArgumentError
    hops = -1
  end
  raise 'Cannot derive client IP: TRUSTED_PROXY_COUNT is not a valid hop count' if hops < 0

  parts = (request.env['HTTP_X_FORWARDED_FOR'] || '').split(',').map(&:strip)
  candidate = if hops == 0
                request.env['REMOTE_ADDR']
              elsif hops <= parts.length
                parts[parts.length - hops]
              end

  raise IPAddr::Error if candidate.nil? || candidate.include?('/')
  IPAddr.new(candidate)
  candidate
rescue IPAddr::Error
  raise 'Cannot derive client IP: no valid IP for this TRUSTED_PROXY_COUNT'
end

# The Client SDK expects the verification's fields in camelCase
def verification_json(verification)
  { id: verification.id, status: verification.status, outcome: verification.outcome,
    nextSteps: verification.next_steps, stepData: verification.step_data }
end

post '/api/orders' do
  content_type :json
  order = JSON.parse(request.body.read)['order']

  checkpoint_response = composer.checkpoint(
    checkpoint_name: 'PLACE_ORDER',
    event: Composer::CheckpointEvent.new(ip: get_ip(request), data: { order: order }),
    source_token: request.env['HTTP_X_DODGEBALL_SOURCE_TOKEN'],
    session_id: session.id.to_s,
    user_id: session[:user_id],
    use_verification_id: request.env['HTTP_X_DODGEBALL_VERIFICATION_ID']
  )

  if composer.allowed?(checkpoint_response)
    placed_order = database.create_order(order)
    status 200
    { order: placed_order }.to_json
  elsif composer.denied?(checkpoint_response)
    # Return the verification so the frontend can show the reason
    status 403
    { verification: verification_json(checkpoint_response.verification) }.to_json
  elsif composer.running?(checkpoint_response)
    # The workflow needs more input from the user (such as MFA or KYC)
    status 202
    { verification: verification_json(checkpoint_response.verification) }.to_json
  else
    # No verdict: decide whether to return the error, proceed, retry, or reject. See Errors.
    status 500
    { message: checkpoint_response.errors.map(&:message) }.to_json
  end
end
```

```js
// In your frontend, with the Client SDK
const placeOrder = async (order, previousVerificationId = null) => {
  const sourceToken = await dodgeball.getSourceToken();

  const endpointResponse = await axios.post("/api/orders", { order }, {
    headers: {
      "x-dodgeball-source-token": sourceToken,
      "x-dodgeball-verification-id": previousVerificationId
    },
    // Let the 202 and 403 responses through instead of throwing
    validateStatus: (status) => [200, 202, 403].includes(status)
  });

  if (endpointResponse.status === 200) {
    setIsOrderPlaced(true);
    return;
  }

  dodgeball.handleVerification(endpointResponse.data.verification, {
    onVerified: async (verification) => {
      // The user completed the extra step: call your API again with the verification ID
      await placeOrder(order, verification.id);
    },
    onApproved: async () => {
      setIsOrderPlaced(true);
    },
    onDenied: async (verification) => {
      setIsOrderDenied(true);
    },
    onError: async (error) => {
      setError(error);
      setIsPlacingOrder(false);
    }
  });
}
```

## API

### Configuration

---

The SDK requires a secret API key as the first argument to the constructor.

```ruby
composer = Composer::ComposerClient.new('secret-api-key...')
```

Optionally, you can pass a hash of configuration options as the second argument. Keys must be symbols.

```ruby
composer = Composer::ComposerClient.new('secret-api-key...', {
  api_version: Composer::ApiVersion::V1,
  api_url: 'https://api.dodgeballhq.com',
  log_level: Composer::ComposerLogLevel::ERROR
})
```

| Option | Default | Description |
| --- | --- | --- |
| `api_version` | `v1` | The Composer API version to use. |
| `api_url` | `https://api.dodgeballhq.com` | The base URL of the Spreedly Composer API. Useful for sending requests to different environments such as `https://api.sandbox.dodgeballhq.com`. |
| `log_level` | `INFO` | `TRACE`, `INFO`, `ERROR` or `NONE`. The SDK logs errors, plus redacted request and response payloads at `TRACE`, so `INFO` and `ERROR` currently log the same thing. The level is shared by every client in the process. See [Safe logging](#safe-logging). |
| `request_timeout_ms` | `30000` | How long each stage of an HTTP request (connecting, or waiting for data) may take, in milliseconds. Applies to every call the SDK makes. A value that isn't a positive integer is logged and replaced with the default. See [Timeouts](#timeouts). |
| `enabled` | `true` | When `false`, the SDK makes no API calls: `checkpoint` returns an approved response and `event` returns without sending anything. |

### Safe logging

---

The SDK writes JSON log lines to standard output. At the default `INFO` level it writes no request or response payloads: a successful checkpoint logs nothing, and `ERROR` reports request failures. Payload logging is opt-in through `TRACE`, and even there the fields that describe your end users or carry provider credentials (`ip`, `data`, `stepData` and `nextSteps`) are replaced with `[REDACTED]`, so a verbose log shows the shape of a request or response without carrying PII. Turn `TRACE` on only in environments where you are comfortable with that extra detail.

### Identifiers

---

`checkpoint` and `event` both take these. Provide a `session_id`, a `source_token`, or both.

| Parameter | Required | Description |
| --- | --- | --- |
| `source_token` | Either this or `session_id` | A token representing the device making the request. Obtained from the [Client SDK](https://npmjs.com/package/@dodgeball/trust-sdk-client). |
| `session_id` | Either this or `source_token` | The current session ID of the request. |
| `user_id` | No | The ID of the user in your database, once you know it (for example, after registration). |
| `use_verification_id` | No | `checkpoint` only. The ID of a verification the user already completed. See [useVerification](#useverification). |

### Call a Checkpoint

---

Checkpoints represent key moments of risk in an application and are at the core of how Composer works. A checkpoint can represent any activity deemed to be a risk. Some common examples include: login, placing an order, redeeming a coupon, posting a review, changing bank account information, making a donation, transferring funds, creating a listing.

```ruby
checkpoint_response = composer.checkpoint(
  checkpoint_name: 'CHECKPOINT_NAME',
  event: Composer::CheckpointEvent.new(
    ip: '127.0.0.1',
    data: {
      transaction: { amount: 100, currency: 'USD' },
      payment_method: { token: 'ghi789' }
    }
  ),
  session_id: 'session_def456'
)
```

Along with the [identifiers](#identifiers), `checkpoint` takes:

| Parameter | Required | Description |
| --- | --- | --- |
| `checkpoint_name` | Yes | The name of the checkpoint to call. |
| `event` | Yes | A `Composer::CheckpointEvent`. |
| `event.ip` | No | The IP address of the device where the request originated. Recommended whenever an end user is present; leave it out for checkpoints with no user, such as renewals. |
| `event.data` | No | Data your checkpoint's workflow uses. Defaults to `{}`. |
| `options` | No | A hash with `sync` (defaults to `false`) and `timeout` (how long the SDK keeps polling an unresolved verification, in milliseconds; defaults to 10 minutes). See [Timeouts](#timeouts). |

### Timeouts

---

Two settings control timing and neither one caps the other. `request_timeout_ms` limits how long each stage of an HTTP request may take: connecting, or waiting for data. It applies to every call the SDK makes. It doesn't cap the request as a whole, so a response that keeps arriving slowly can take longer. The `timeout` in checkpoint options limits how long the SDK keeps polling for an unresolved verification, and defaults to 10 minutes. The SDK always polls at least once.

```ruby
composer = Composer::ComposerClient.new('secret-api-key...', {
  request_timeout_ms: 5000 # Give up if connecting, or waiting for data, takes longer than 5 seconds
})

checkpoint_response = composer.checkpoint(
  checkpoint_name: 'CHECKPOINT_NAME',
  event: Composer::CheckpointEvent.new(ip: '127.0.0.1'),
  session_id: 'session_def456',
  options: {
    timeout: 10_000 # Stop polling after 10 seconds and return whatever we have
  }
)
```

This example uses the default `sync: false`, which we recommend. The first request returns right away with a pending verification, and the SDK polls until it resolves, so each request is short and `request_timeout_ms` only guards against a hung connection. With `sync: true`, the first request waits on the server until the workflow finishes, so `request_timeout_ms` must be longer than your slowest workflow. Otherwise a slow but healthy checkpoint comes back as a failure.

When the polling budget runs out, the verification is simply still pending, which is not an error: `running?` returns `true`, and you can resume later by passing the verification ID to `use_verification_id`. The exception is when the last poll before the budget ran out failed: you get that failure instead, with `success` `false`, and `has_error?` returns `true`.

### Checkpoint Responses

---

Calling a checkpoint creates a verification in Composer. Its `status` and `outcome` determine how your application should proceed. Use the [utility methods](#utility-methods) rather than reading these fields directly.

```ruby
checkpoint_response.success                 # => true or false
checkpoint_response.errors                  # => array of Composer::ApiError (code, message)
checkpoint_response.version                 # => 'v1'
checkpoint_response.verification            # => Composer::Verification, or nil
checkpoint_response.verification.id         # => String
checkpoint_response.verification.status     # => String
checkpoint_response.verification.outcome    # => String
checkpoint_response.verification.step_data  # => Hash
checkpoint_response.verification.next_steps # => Array
checkpoint_response.is_timeout              # => true or false
```

#### Response fields

| Property | Description |
| --- | --- |
| `success` | `false` when no verification result could be produced. See [Errors](#errors). A verification that failed while running still has `success: true`. |
| `errors` | `Composer::ApiError` objects with a `message`, and a `code` when the API sends one. Usually empty when `success` is `true`. |
| `version` | The version of the Composer API that was used to make the request. |
| `verification` | The verification. Can be `nil` when `success` is `false`. |
| `verification.id` | The ID of the verification that was created. |
| `verification.status` | `COMPLETE`, `PENDING`, `BLOCKED` or `FAILED`. |
| `verification.outcome` | `APPROVED`, `DENIED`, `PENDING`, `ERROR`, `USAGE_LIMIT` or `API_LIMIT`. |
| `verification.step_data` | Data from the workflow's steps. |
| `verification.next_steps` | Steps the Client SDK runs next, such as MFA. Send them to your frontend as `nextSteps`, as the [Usage](#usage) example does, so the Client SDK can start them right away. |
| `is_timeout` | `true` when polling stopped after 3 failed polls in a row. See `timeout?` below. |

#### Statuses and outcomes

| `status` | `outcome` | Utility method | Meaning |
| --- | --- | --- | --- |
| `COMPLETE` | `APPROVED` | `allowed?` | Let the request proceed. |
| `COMPLETE` | `DENIED` | `denied?` | Deny the request. Return the verification to the frontend to show the reason. |
| `BLOCKED` | `PENDING` | `running?` | The workflow is waiting for input from the user, such as MFA or KYC. See [useVerification](#useverification). |
| `PENDING` | `PENDING` | `running?` | Still processing when the polling budget ran out. Resume later with `use_verification_id`. |
| `COMPLETE` | `PENDING` | `undecided?` | The workflow finished without reaching a verdict. Your application decides how to proceed. |
| `FAILED` | `ERROR` | `has_error?` | The workflow failed while running, for example a third-party service was unavailable. |
| `FAILED` | `USAGE_LIMIT` | `has_error?` | Your account reached its usage limit. |
| `FAILED` | `API_LIMIT` | `has_error?` | Your account is sending too many requests right now, or is deactivated. |

### Utility Methods

---

Each method takes a checkpoint response and returns a boolean. The same checks are available on the response itself (`checkpoint_response.allowed?` and so on).

| Method | Returns `true` when |
| --- | --- |
| `composer.allowed?(checkpoint_response)` | The request is allowed to proceed. |
| `composer.denied?(checkpoint_response)` | The request is denied. |
| `composer.running?(checkpoint_response)` | No verdict yet: the workflow is still processing or waiting on the user. |
| `composer.undecided?(checkpoint_response)` | The workflow finished without a verdict. |
| `composer.has_error?(checkpoint_response)` | `success` is `false`, or the workflow failed while running. `error?` is the same check. |
| `composer.timeout?(checkpoint_response)` | Polling stopped after 3 failed polls in a row. Running out of the polling `timeout` is not a timeout in this sense; see [Timeouts](#timeouts). |

### Errors

---

Only invalid input raises. Everything else comes back as a response, so a checkpoint never raises because of the network or the API. The errors in this table are all `Composer::ComposerError`.

| What happened | Raises? | What you get | Utility method |
| --- | --- | --- | --- |
| Missing secret key, or an invalid `api_version` or `log_level` | Yes, from the constructor: `Composer::MissingConfigError` or `Composer::InvalidConfigError` | | |
| Blank `checkpoint_name`, `nil` `event`, or neither `session_id` nor `source_token` | Yes, from `checkpoint`: `Composer::MissingParameterError` | | |
| The API rejected the request, for example there is no published workflow for the checkpoint name, or a usage or API limit was reached | No | `success: false`, the API's message in `errors` | `has_error?` |
| Network error, request timeout, or a response the SDK can't read | No | `success: false`, a `500` in `errors` | `has_error?` |
| 3 polls failed in a row | No | `success: false`, a `503` in `errors` | `has_error?`, `timeout?` |
| The workflow failed while running | No | `success: true`, status `FAILED`, outcome `ERROR` | `has_error?` |
| Invalid input to `event` | Never | Nothing; the SDK logs it (see [Track an Event](#track-an-event)) | |

When `success` is `false` there is no verdict at all. Don't treat it as a denial; decide whether to retry, proceed, or reject.

### useVerification

---

Sometimes the workflow needs more input from the user before it can reach a verdict. For example, if the user must complete MFA, the checkpoint response has `status` `BLOCKED` and `outcome` `PENDING`, and `running?` returns `true`. Return the verification to your frontend and pass it to the Client SDK's `handleVerification()` method, which gathers the input from the user. When the user is done, the frontend calls your API again with the verification ID, and your API passes it to `use_verification_id`. The checkpoint then uses that verification instead of creating a new one, so the user isn't asked twice. The [Usage](#usage) example shows the full flow.

**Important Note:** To prevent replay attacks, each verification ID can only be passed to `use_verification_id` once.

### Track an Event

---

You can track additional information about a user's journey by submitting tracking events from your server. This information will be added to the user's profile and is made available to checkpoints.

```ruby
composer.event(
  event: Composer::TrackEvent.new(
    type: 'ADD_TO_CART',
    data: { product: { id: 'sku_123', quantity: 1 } }
  ),
  session_id: 'session_def456'
)
```

Along with the [identifiers](#identifiers), `event` takes:

| Parameter | Required | Description |
| --- | --- | --- |
| `event` | Yes | A `Composer::TrackEvent`. |
| `event.type` | Yes | A name for where the user is in their journey. Can be any non-blank string you choose. |
| `event.data` | No | Data to track. Defaults to `{}`. |
| `event.event_time` | No | When the event happened, in milliseconds since the epoch. Defaults to now. |

`event` doesn't raise for invalid input and returns `nil`, so tracking can't break your request. `notify` and `track` are aliases. Problems are logged at `ERROR` instead:

- If `event` is `nil`, `event.type` is blank, or neither `session_id` nor `source_token` is provided, the event is not sent and the SDK logs `Composer event was not sent: <reason>`.
- If the API rejects the event, the SDK logs `Composer event was not accepted by the API (HTTP <status>).`
- If the request fails (network error or timeout), the SDK logs `There was an error making a request.`

## Development

### Versioning

The SDK version is declared in `lib/composer/version.rb` (`VERSION`). The gemspec and the `Composer-SDK-Version` header both read it.

### Testing

The project uses RSpec for testing.

To run tests:

```sh
bundle install
bundle exec rspec
```

Each run writes a coverage report to `coverage/index.html`.

### Code Style

This project uses RuboCop for code style enforcement:

```sh
bundle exec rubocop
```

### Testing with the examples

To try local SDK changes end to end, clone [Composer examples](https://github.com/spreedly/composer-examples) next to this repository, point the `server/ruby` example at your checkout in its `Gemfile`, and run it as the examples README describes:

```ruby
gem 'spreedly-composer-sdk-server', path: '../../../composer-sdk-server-ruby'
```

Restart the example after each change.

## License

This SDK is released under the Apache-2.0 License. See [LICENSE](LICENSE) for details, and [THIRD-PARTY-LICENSES](THIRD-PARTY-LICENSES) for the licenses of its dependencies.

## Support

For support, please contact:

- Email: support@spreedly.com
- Documentation: https://developer.spreedly.com
