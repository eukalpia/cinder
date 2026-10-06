# 1.0.0-rc.3

- `cinder logs` reads the authenticated endpoint file written by Cinder
  1.0.0-rc.3 and sends its access token. Port-only files from earlier releases
  are treated as stale.
- `cinder run` sets `CINDER_DEBUG_OVERLAY=1` and `CINDER_LOG_SERVER=1` for the
  app unless they are already set, because release defaults now leave both
  development tools off.

# 1.0.0-rc.1

- Align with the Cinder 1.0 release candidate, Dart 3.9 minimum, and Apache-2.0 distribution.
- Validate package analysis, installation metadata, and integration behavior.
