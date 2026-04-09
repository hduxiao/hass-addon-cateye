# Cateye Client Add-on Documentation

## Web UI

- This add-on exposes the Cateye admin page through Home Assistant Ingress.
- After the add-on starts, use `Open Web UI` from the add-on page or the `Cateye` sidebar entry.

## Configuration File

- The add-on reads `/config/client.toml` for all Cateye client settings.
- On first start, the bundled template (`cateye/client.toml`) is copied to `/config/client.toml` if the file does not already exist.
- Edit `/config/client.toml` to match your Cateye server details, including `token`, `server_public_key`, `server_addr`, `port`, and tunnel definitions.
- The default template forwards Home Assistant from `127.0.0.1:8123` through a TCP tunnel named `homeassistant`.
- Keep the `[admin]` section enabled. For the embedded Web UI to work correctly, keep `bind_addr = "127.0.0.1"`.

## Log Files

- Logs are written to `/config/log/` by default.
- The Home Assistant add-on log view follows the current Cateye log file from this directory.
- Keep `log.dir = "/config/log"` in the TOML file unless you intentionally want a different location.

## Notes

- This add-on runs `cateye client`.
- The add-on uses host networking so Cateye can access services bound on the Home Assistant host, including `127.0.0.1`.
- The add-on configuration tab does not expose form fields. Edit `/config/client.toml` directly or use the embedded Web UI.

After saving changes to `/config/client.toml`, restart the add-on to apply the new configuration.
