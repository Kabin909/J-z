# J&Z deployment modes

J&Z supports three explicit deployment target classes:

- **VPS** — real J&Z Wings + Docker node. Recommended for production.
- **CodeSandbox** — application/control-plane development target. It cannot safely provide privileged Docker/Wings control.
- **Playit** — public tunnel provider used with a real node or development service.

The Admin → Deployment module can reserve ports and store a provider public-address template. Port reservation is transactional and uses PostgreSQL uniqueness constraints.

## Playit setup

1. Install/run the Playit agent on the machine that owns the service.
2. Create the required tunnel in the Playit dashboard/agent.
3. Configure the J&Z Playit deployment target with the resulting public address/template.
4. Keep the Playit credential/agent token outside the browser and out of logs.
5. Let J&Z reserve internal service ports and display the resulting public endpoint to authorized administrators/users.

J&Z does not fabricate a public IP or domain and does not claim a tunnel is online until provider/node telemetry confirms it.
