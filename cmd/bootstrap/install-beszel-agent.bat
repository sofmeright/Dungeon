# create the service
nssm install beszelagent "C:\_Staging\_Toolchest\beszel-agent\beszel-agent_windows_amd64.exe"

# set your public key as an env var for the service
nssm set beszelagent AppEnvironmentExtra "KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL5kuNx1mU7U/sDpNuJwzQHKsv6nZ0DC7BXw2TWQ5t6T"

# start the service
nssm start beszelagent

# view services logs
nssm dump beszelagent

echo Successfully Installed the beszelagent?

pause