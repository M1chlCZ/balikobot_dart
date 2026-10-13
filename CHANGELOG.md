## [Unreleased]

- Added `downloadBatchLabels`: requests and downloads the labels of one to
  1000 packages in one call. A single package returns a PDF or ZPL body and
  several packages return a ZIP archive; the method returns the raw body with
  the validated media type.
- Added `parseTrackingNotifications` and the `TrackingNotification` model: parse
  the JSON body of a tracking webhook into typed notifications.

## 0.1.1

- Documentation and internal cleanup.

## 0.1.0

- Initial release: a parity port of balikobot-go v0.2.0.
- Six sentinel errors in `BalikobotError` with a `retryAfter` hint.
- Typed `Carrier`, `Currency`, and `Country` codes with `fromString` and
  `isValid`.
- Account mode with the `liveAccount` check and the five-minute cache.
- Hard response limits, refused redirects, and the label host allowlist.
- Built on `json_rest_client` and `http`.
