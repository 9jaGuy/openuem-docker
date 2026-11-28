# OpenUEM LAN onboarding

Use this runbook after the OpenUEM deployment has completed on `svc1`. Start with one disposable or low-risk Windows endpoint. Do not deploy broadly until that endpoint reports inventory and survives a reboot.

## 1. Confirm the service is ready

From `svc1`, in `/opt/openuem/repo`:

```bash
sudo docker compose --env-file /etc/openuem/openuem.env \
  -f compose.yml -f ops/compose.lan.yml ps
sudo systemctl status openuem-firewall.service openuem-backup.timer --no-pager
sudo ops/backup.sh
```

All seven long-running containers must be running. Keep the first backup path and verify its manifest with `sha256sum -c SHA256SUMS` from inside that directory.

## 2. Prepare administrator access

1. Copy `certificates/ca/ca.cer` and the administrator `.pfx` from `certificates/users/` to the administrator workstation through an approved internal file-transfer channel.
2. Import `ca.cer` into the workstation's trusted root certificate store.
3. Import the `.pfx` into the administrator's personal certificate store. Use its configured password. Do not assume or publish a default password.
4. Open `https://openuem.epoh.casa` from the LAN and select the imported client certificate when prompted.
5. Store the `.pfx` in the approved secrets location, then delete the transfer copy.

If certificate login is unavailable, OpenUEM also creates an `openuem` account with a temporary password. Locate the initial-password entry without copying it into tickets or chat:

```bash
sudo docker compose --env-file /etc/openuem/openuem.env \
  -f compose.yml -f ops/compose.lan.yml logs console | grep -i 'initial password'
```

Change that password immediately, enable MFA, and retain certificate authentication as the recovery path.

## 3. Prepare one Windows endpoint

Traffic from the endpoint must arrive at `svc1` with a source address in `192.168.1.0/24`. Before onboarding a routed subnet without source NAT, update and review the firewall policy to allow that subnet explicitly.

Run these checks in PowerShell:

```powershell
Resolve-DnsName openuem.epoh.casa
Resolve-DnsName openuem-nats.epoh.casa
Resolve-DnsName openuem-ocsp.epoh.casa
Test-NetConnection openuem.epoh.casa -Port 443
Test-NetConnection openuem-nats.epoh.casa -Port 4433
Test-NetConnection openuem-ocsp.epoh.casa -Port 8000
```

Each name must resolve to `192.168.1.106`, and each TCP test must succeed.

Download the Windows agent installer from OpenUEM's Downloads page. Compare its SHA-256 checksum with the published checksum:

```powershell
Get-FileHash .\openuem-agent-setup.exe -Algorithm SHA256
```

Create a temporary staging folder containing exactly:

- `openuem-agent-setup.exe`
- `ca.cer` from `certificates/ca/ca.cer`
- `agent.cer` from `certificates/agents/agent.cer`
- `agent.key` from `certificates/agents/agent.key`
- `sftp.cer` from `certificates/console/sftp.cer`

The private key must stay inside the approved LAN distribution path. Do not send the bundle through email or chat.

## 4. Install the agent

Open an elevated PowerShell window in the staging folder:

```powershell
$arguments = @(
  '/server=openuem-nats.epoh.casa:4433'
  '/sftp=2022'
  '/vnc=1443'
  '/VERYSILENT'
)
Start-Process -FilePath '.\openuem-agent-setup.exe' -ArgumentList $arguments -Verb RunAs -Wait
```

For a non-default organization or site, add both `/tenantid=<ID>` and `/siteid=<ID>`. Never specify only one.

After installation, securely delete the staging folder. The installer creates Windows Firewall rules. If another endpoint firewall is active, allow outbound TCP 4433 to `192.168.1.106`. Allow inbound TCP 2022 and 1443 from `192.168.1.106` only if file browsing or remote assistance will be used.

## 5. Admit and verify the endpoint

1. Open the OpenUEM console and select **Agents**.
2. Confirm the new endpoint is pending admission, then admit it.
3. Verify hostname, operating system, IP address, last contact, and inventory are populated.
4. Reboot the endpoint.
5. Confirm the OpenUEM Agent service starts automatically and the endpoint reports again.
6. If enabled for the pilot, test file browsing and remote assistance from the console.

Do not expand beyond the pilot until all six checks pass.

## 6. Troubleshoot or remove

On Windows, inspect:

- `C:\Program Files\OpenUEM Agent\logs\openuem-log.txt`
- `C:\Program Files\OpenUEM Agent\config\openuem.ini`
- the OpenUEM Agent service in `services.msc`

Common causes are LAN DNS failure, blocked TCP 4433, an incorrect NATS hostname, missing certificates, or a stopped NATS or agents-worker container.

To roll back the pilot, uninstall **OpenUEM Agent** from Windows and remove the endpoint from the console. The staged `agent.cer` and `agent.key` are shared deployment credentials, so revoking that certificate can disconnect every enrolled endpoint. Revoke a certificate only after verifying that OpenUEM issued it uniquely to the endpoint being removed.

## 7. Later public-internet phase

Do not reuse the LAN firewall policy for public enrollment. Before enabling off-LAN agents, review public DNS, NAT, NATS exposure, certificate lifecycle, rate limiting, endpoint update delivery, monitoring, and incident response. Keep the console and OCSP exposure separate from the agent transport decision.

## References

- [Windows agent installation](https://openuem.eu/docs/Installation/Agent/windows/)
- [Docker installation and console certificates](https://openuem.eu/docs/Installation/Server/docker/)
- [Console authentication](https://openuem.eu/docs/Console/intro/)
- [Browser certificate import](https://openuem.eu/docs/Advanced%20Topics/user-certificate/)
