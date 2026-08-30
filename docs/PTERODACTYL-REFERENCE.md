# J&Z reference notes

J&Z may study publicly observable control-plane patterns from Pterodactyl, including the separation between a web panel and a node daemon, Docker isolation, server lifecycle operations, node heartbeats, server templates/eggs, queues, and installation workflows.

The upstream Pterodactyl panel is publicly available and states that its code is released under the MIT License. urlPterodactyl Panel repositoryhttps://github.com/pterodactyl/panel

J&Z does **not** copy Pterodactyl/Wings source files, branding, exact UI, assets, or proprietary material. J&Z implementation remains independently structured and branded.

Useful design lessons to validate against upstream documentation/source:

- Panel/node service boundary.
- Docker-backed workload isolation.
- Node configuration and daemon authentication.
- Template/egg driven server creation.
- Asynchronous server installation and lifecycle jobs.
- Admin/user separation and application API concepts.

When a feature is implemented in J&Z, write J&Z-native code and tests rather than transplanting upstream implementation.
