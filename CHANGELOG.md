## 0.1.0

- Initial release: a parity port of balikobot-go v0.2.0.
- Six sentinel errors in `BalikobotError` with a `retryAfter` hint.
- Typed `Carrier`, `Currency`, and `Country` codes with `fromString` and
  `isValid`.
- Account mode with the `liveAccount` check and the five-minute cache.
- Hard response limits, refused redirects, and the label host allowlist.
- Built on `json_rest_client` and `http`.
