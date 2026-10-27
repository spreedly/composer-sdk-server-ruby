# Changelog

## 1.0.0 (2026-10-27)

First release as `spreedly-composer-sdk-server`. If you're upgrading from `dodgeball-trust-sdk-ruby`, read **Changed** and **Removed**.

### Added
- `checkpoint` and `event`. `checkpoint` polls a pending verification for up to 10 minutes by default; set `options: { timeout: <ms> }` to change it. `notify` and `track` are aliases of `event`.
- `Composer::CheckpointResponse` with `success`, `errors`, `version`, `verification` (`id`, `status`, `outcome`, `step_data` and `next_steps`) and `is_timeout`, plus the `allowed?`, `denied?`, `running?`, `undecided?`, `has_error?` and `timeout?` helpers.
- `log_level` config option (`TRACE`, `INFO`, `ERROR`, `NONE`; default `INFO`). The SDK writes JSON log lines to stdout, and the level is shared by every client in the process. At `TRACE`, `ip`, `data`, `stepData` and `nextSteps` are redacted.
- `request_timeout_ms` config option, default 30000 ms for connecting and for waiting on data. A value that isn't a positive integer is logged and replaced with the default.
- `enabled: false` makes no API calls: `checkpoint` returns an approved response with verification ID `COMPOSER_IS_DISABLED`, and `event` sends nothing.

### Changed
- The gem is now `spreedly-composer-sdk-server`, required with `require 'composer'`. `Dodgeball::Client` is now `Composer::ComposerClient`. `Composer::DodgeballClient` and `Composer::DodgeballLogLevel` still work.
- Requires Ruby 3.2 or later and `faraday` 2.14.3 or later, below 3.0.
- The constructor takes the secret key as its first argument and a hash of symbol-keyed options: `Composer::ComposerClient.new(secret_key, api_version:, api_url:, log_level:, enabled:, request_timeout_ms:)`. `write_key` is now the positional `secret_key`, and `dodgeball_api_url` is now `api_url`, which defaults to `https://api.dodgeballhq.com/`.
- The constructor raises `Composer::MissingConfigError` for a missing key and `Composer::InvalidConfigError` for an unsupported `api_version` or `log_level`. `checkpoint` raises `Composer::MissingParameterError` for a blank `checkpoint_name`, a `nil` `event`, or when both `session_id` and `source_token` are blank. All three are `Composer::ComposerError`, not `ArgumentError`, so update any `rescue ArgumentError`.
- A network failure or timeout returns `success: false` with a `500` in `errors` instead of raising or returning a status of `-1`.
- Each request is made once, with no retries. Polling gives up after 3 failed polls in a row and returns a `503` with `is_timeout: true`. Add your own retry if you need one.
- Logs go to stdout as JSON lines, filtered by `log_level`. The logger can no longer be replaced.

### Removed
- `verify(workflow, dodgeball_id, verification_id, options)`. Use `checkpoint(checkpoint_name:, event:, session_id:, user_id:, source_token:, use_verification_id:, options:)` with a `Composer::CheckpointEvent.new(ip:, data:)`, where `ip` is optional. `verification_id` is now `use_verification_id`, and `dodgeball_id` is replaced by `source_token` and `session_id`.
- `Dodgeball::Client::Response`. `checkpoint` returns a `Composer::CheckpointResponse`.
- The `on_error`, `ssl` and `stub` constructor options. Use the response's `errors`, put the scheme in `api_url`, and use `enabled: false` in tests.
- The `dodgeball` and `trust-sdk-ruby` require paths.
