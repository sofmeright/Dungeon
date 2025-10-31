# Zitadel Helm Chart vs Kustomize Implementation Audit

**Date**: 2025-10-31
**Purpose**: Comprehensive comparison of official Zitadel Helm chart patterns vs our Kustomize implementation
**Source**: `/tmp/zitadel-charts/` (official Zitadel CloudNativePG example)

---

## EXECUTIVE SUMMARY

### 🔴 CRITICAL FINDING: FIRSTINSTANCE Workflow Fundamentally Wrong

The official Helm chart handles FIRSTINSTANCE creation in the **setup job with sidecar containers**, NOT in the StatefulSet/Deployment.

Our implementation attempted to handle FIRSTINSTANCE in the StatefulSet with a sidecar, which is **architecturally incorrect**.

### Correct Helm Chart Workflow:
1. **Init Job** → Creates database structure (`zitadel init [zitadel]`)
2. **Setup Job Main Container** → Runs migrations AND processes FIRSTINSTANCE config, writing credentials to `/machinekey/` emptyDir
3. **Setup Job Sidecar Containers** → Wait for setup container to terminate, then extract credentials from emptyDir and create Kubernetes secrets
4. **Deployment** → Runs `zitadel start` with NO FIRSTINSTANCE env vars (credentials already created by setup job)

### Our Current (Incorrect) Implementation:
1. **Init Job** → Creates database structure (`zitadel init` WITHOUT optional subcommand)
2. **Setup Job** → Runs migrations only (MISSING FIRSTINSTANCE configuration entirely)
3. **StatefulSet** → Runs `zitadel start` WITH FIRSTINSTANCE env vars + sidecar trying to extract PAT
4. **Result** → FIRSTINSTANCE never processes correctly because setup job should handle it, not StatefulSet

---

## KEY FINDINGS SUMMARY

| Component | Helm Chart | Our Implementation | Status |
|-----------|-----------|-------------------|---------|
| Init Job Command | `args: [init, zitadel]` for CNPG | `command: [/app/zitadel, init]` | ❌ Missing `zitadel` subcommand |
| Setup Job FIRSTINSTANCE | ✅ Configured with env vars + sidecars | ❌ MISSING entirely | ❌ FATAL |
| Setup Job Sidecars | ✅ 3 sidecars extract credentials | ❌ No sidecars | ❌ FATAL |
| Deployment FIRSTINSTANCE | ✅ NOT present (handled by setup) | ❌ Incorrectly in StatefulSet | ❌ FATAL |
| Resource Type | Deployment (stateless) | StatefulSet | ⚠️ Suboptimal |
| CNPG Bootstrap | ✅ Creates DB and user | ✅ Creates DB and user | ✅ CORRECT |

---

## DETAILED COMPARISON

## 1. INIT JOB

### Official Helm Chart Template
**File**: `/tmp/zitadel-charts/charts/zitadel/templates/job_init.yaml`

**Command Structure** (lines 57-67):
```yaml
args:
  - init
  {{- with .Values.initJob.command }}
  {{- if not (has . (list "database" "grant" "user" "zitadel")) }}
  {{- fail "You can only set one of the following command: database, grant, user, zitadel" }}
  {{- end -}}
  - {{ . }}
  {{- end }}
  - --config
  - /config/zitadel-config-yaml
```

**Init Command Options** (from values.yaml):
- `""` (empty) = Full initialization (create database, create user, create schemas)
- `"database"` = Only create database
- `"grant"` = Only set grants  
- `"user"` = Only create user
- `"zitadel"` = **Skip database/user creation, only create Zitadel internals**

**CloudNativePG Example** (`/tmp/zitadel-charts/examples/cloudnativepg/zitadel-values.yaml`):
```yaml
initJob:
  command: "zitadel"  # Uses "zitadel init zitadel" to skip DB/user creation
```

**Why**: When using CloudNativePG, the database and user are already created via `bootstrap.initdb`, so init job should skip those steps.

### Our Implementation
**File**: `/srv/dungeon/fluxcd/infrastructure/controllers/base/zitadel/zitadel-initjob.yaml`

```yaml
command:
- /app/zitadel
- init
- --config
- /config/zitadel-config.yaml
```

### Problems:

1. ❌ **MISSING `zitadel` subcommand**
   - Helm (with CNPG): `zitadel init zitadel` (skip DB/user creation)
   - Ours: `zitadel init` (tries to create DB/user, sees they exist, only runs verify)
   - **Impact**: Init job only verifies instead of creating schemas because CNPG already created DB/user

2. ⚠️ **Minor**: Using `command:` instead of container entrypoint + `args:`
   - Helm: Uses implicit entrypoint with args
   - Ours: Overrides entire command
   - **Impact**: Functionally equivalent for Kustomize, just different style

---

## 2. SETUP JOB

### Official Helm Chart Template
**File**: `/tmp/zitadel-charts/charts/zitadel/templates/job_setup.yaml`

**🔴 THIS IS WHERE THE CRITICAL DIFFERENCE EXISTS 🔴**

**Setup Job Main Container** (lines 72-93):
```yaml
args:
  - setup
  - --masterkeyFromEnv
  - --config
  - /config/zitadel-config-yaml
  - --steps
  - /config/zitadel-config-yaml
  {{- if .Values.setupJob.additionalArgs }}
  {{- toYaml .Values.setupJob.additionalArgs | nindent 12 }}
  {{- end }}
```

**FIRSTINSTANCE Environment Variables** (lines 105-112):
```yaml
env:
  - name: ZITADEL_MASTERKEY
    valueFrom:
      secretKeyRef:
        name: zitadel-masterkey
        key: masterkey
  - name: ZITADEL_FIRSTINSTANCE_MACHINEKEYPATH
    value: "/machinekey/sa.json"
  {{- if $hasMachinePat }}
  - name: ZITADEL_FIRSTINSTANCE_PATPATH
    value: "/machinekey/pat"
  {{- end }}
  - name: ZITADEL_FIRSTINSTANCE_LOGINCLIENTPATPATH
    value: "/login-client/pat"
```

**EmptyDir Volumes** (lines 327-334):
```yaml
volumes:
  - name: machinekey
    emptyDir: {}
  - name: login-client
    emptyDir: {}
```

**Sidecar Container 1: machinekey-writer** (lines 169-209):
Waits for setup container to terminate, then extracts `/machinekey/sa.json` and creates secret `iam-admin`.

**Sidecar Container 2: machine-pat-writer** (lines 210-250):
Waits for setup container to terminate, then extracts `/machinekey/pat` and creates secret `iam-admin-pat`.

**Sidecar Container 3: login-client-pat-writer** (lines 251-291):
Waits for setup container to terminate, then extracts `/login-client/pat` and creates secret `login-client`.

### Our Implementation
**File**: `/srv/dungeon/fluxcd/infrastructure/controllers/base/zitadel/zitadel-setupjob.yaml`

Our setup job is **COMPLETELY MISSING**:
- ❌ FIRSTINSTANCE path environment variables
- ❌ emptyDir volumes for credential extraction
- ❌ Sidecar containers to extract and create secrets
- ❌ The entire FIRSTINSTANCE workflow

**Our current setup job likely only runs migrations, NOT FIRSTINSTANCE processing.**

### Problems:

1. ❌ **FATAL: Setup job doesn't handle FIRSTINSTANCE**
   - Helm: Setup job processes FIRSTINSTANCE config and writes credentials to emptyDir
   - Ours: Setup job only runs migrations
   - **Impact**: FIRSTINSTANCE never processes, credentials never generated

2. ❌ **FATAL: No sidecar containers to extract credentials**
   - Helm: THREE sidecar containers wait for setup completion, then extract credentials and create K8s secrets
   - Ours: No sidecars in setup job at all
   - **Impact**: Even if credentials were generated, nothing would extract them

3. ❌ **FATAL: Missing emptyDir volumes**
   - Helm: Uses emptyDir volumes to share credentials between setup container and sidecars
   - Ours: No shared volumes
   - **Impact**: No way to pass credentials from setup to sidecars

---

## 3. DEPLOYMENT/STATEFULSET

### Official Helm Chart Template
**File**: `/tmp/zitadel-charts/charts/zitadel/templates/deployment_zitadel.yaml`

**Resource Type**:
```yaml
apiVersion: apps/v1
kind: Deployment  # NOT StatefulSet
```

**Command** (lines 61-72):
```yaml
args:
  - start
  - --config
  - /config/zitadel-config-yaml
  - --masterkeyFromEnv
```

**Environment Variables** (lines 74-110):
```yaml
env:
  - name: POD_IP
    valueFrom:
      fieldRef:
        apiVersion: v1
        fieldPath: status.podIP
  - name: ZITADEL_MASTERKEY
    valueFrom:
      secretKeyRef:
        name: zitadel-masterkey
        key: masterkey
  # NO FIRSTINSTANCE ENV VARS HERE
```

**Key Facts**:
- Uses Deployment (stateless workload)
- NO FIRSTINSTANCE environment variables
- FIRSTINSTANCE was already processed by setup job
- Just runs `zitadel start` with masterkey

### Our Implementation
**File**: `/srv/dungeon/fluxcd/infrastructure/controllers/base/zitadel/zitadel-statefulset.yaml`

**Resource Type**:
```yaml
apiVersion: apps/v1
kind: StatefulSet  # Wrong for stateless app
```

**FIRSTINSTANCE Environment Variables** (from overlay patch):
```yaml
env:
- name: ZITADEL_FIRSTINSTANCE_ORG_NAME
  value: "PrecisionPlanIT"
- name: ZITADEL_FIRSTINSTANCE_ORG_MACHINE_MACHINE_USERNAME
  value: "zitadel-admin-sa"
- name: ZITADEL_FIRSTINSTANCE_ORG_MACHINE_MACHINEKEY_PATH
  value: "/machinekey/machinekey"
- name: ZITADEL_FIRSTINSTANCE_ORG_MACHINE_PAT_PATH
  value: "/machinekey/pat"
```

**Sidecar Container: pat-extractor** (from overlay patch):
```yaml
- name: pat-extractor
  image: docker.io/alpine/k8s:1.34.0
  command:
    - sh
    - -c
    - |
      # Waits for /machinekey/pat file
      kubectl create secret generic zitadel-k8s-admin-sa --from-literal=pat="$PAT"
      sleep infinity  # Keeps running forever
```

### Problems:

1. ❌ **FATAL: FIRSTINSTANCE in wrong place**
   - Helm: FIRSTINSTANCE handled in setup JOB, NOT in deployment
   - Ours: FIRSTINSTANCE env vars in StatefulSet
   - **Impact**: FIRSTINSTANCE runs on EVERY pod start, not just once during initial setup. This is wrong.

2. ❌ **WRONG: StatefulSet vs Deployment**
   - Helm: Uses Deployment (Zitadel is stateless with external Postgres)
   - Ours: Uses StatefulSet
   - **Impact**: StatefulSet adds unnecessary complexity for a stateless application

3. ❌ **WRONG: Sidecar in wrong resource + wrong lifecycle**
   - Helm: Sidecars in setup job (run once, terminate after extracting credentials)
   - Ours: Sidecar in StatefulSet (runs forever with `sleep infinity`)
   - **Impact**: Wasteful resource usage, wrong lifecycle semantics

---

## 4. CLOUDNATIVEPG POSTGRES

### Official Helm Chart Example
**File**: `/tmp/zitadel-charts/examples/cloudnativepg/postgres-cluster/templates/cluster.yaml`

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: zitadel-pg
spec:
  instances: 1
  bootstrap:
    initdb:
      database: zitadel
      owner: zitadel
      secret:
        name: zitadel-pg-user
  superuserSecret:
    name: zitadel-pg-superuser
```

### Our Implementation
**File**: `/srv/dungeon/fluxcd/infrastructure/controllers/base/zitadel/postgres-cluster.yaml`

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: zitadel-postgres
spec:
  instances: 3
  bootstrap:
    initdb:
      database: zitadel
      owner: zitadel
      secret:
        name: zitadel-secrets
  superuserSecret:
    name: zitadel-postgres-superuser
```

✅ **Our CNPG implementation matches the Helm chart pattern correctly**.

CNPG creates the database and user BEFORE the init job runs. This is expected and correct.

The issue we encountered (init job only showing "verify" instead of "create") is because:
1. Database and user already exist (created by CNPG)
2. `zitadel init` (without `zitadel` subcommand) sees they exist and only verifies
3. Solution: Use `zitadel init zitadel` to skip DB/user creation and only create Zitadel schemas

---

## RECOMMENDATIONS

### 🔴 CRITICAL FIXES (MUST DO):

#### 1. Fix Init Job
Add `zitadel` subcommand to skip database/user creation (already done by CNPG):

```yaml
command:
- /app/zitadel
- init
- zitadel  # <-- ADD THIS
- --config
- /config/zitadel-config.yaml
```

#### 2. Fix Setup Job - Add FIRSTINSTANCE Configuration
Add these environment variables to setup job:

```yaml
env:
  - name: ZITADEL_FIRSTINSTANCE_MACHINEKEYPATH
    value: "/machinekey/sa.json"
  - name: ZITADEL_FIRSTINSTANCE_PATPATH
    value: "/machinekey/pat"
  - name: ZITADEL_FIRSTINSTANCE_LOGINCLIENTPATPATH
    value: "/login-client/pat"
```

Add emptyDir volumes:

```yaml
volumes:
  - name: machinekey
    emptyDir: {}
  - name: login-client
    emptyDir: {}
```

Add volume mounts to main container:

```yaml
volumeMounts:
  - name: machinekey
    mountPath: /machinekey
  - name: login-client
    mountPath: /login-client
```

#### 3. Add Sidecar Containers to Setup Job
Add THREE sidecar containers (based on Helm chart patterns):

**machinekey-writer sidecar**:
```yaml
- name: machinekey-writer
  image: docker.io/alpine/k8s:1.34.0
  command:
    - sh
    - -c
    - |
      # Wait for setup container to terminate
      until [ ! -z $(kubectl get pod ${POD_NAME} -o jsonpath="{.status.containerStatuses[?(@.name=='zitadel-setup')].state.terminated}") ]; do
        sleep 5
      done
      # Extract sa.json and create secret
      kubectl create secret generic zitadel-admin-sa \
        --from-file=zitadel-admin-sa.json=/machinekey/sa.json \
        --dry-run=client -o yaml | kubectl apply -f -
  volumeMounts:
    - name: machinekey
      mountPath: /machinekey
      readOnly: true
```

**machine-pat-writer sidecar**:
```yaml
- name: machine-pat-writer
  image: docker.io/alpine/k8s:1.34.0
  command:
    - sh
    - -c
    - |
      # Wait for setup container to terminate
      until [ ! -z $(kubectl get pod ${POD_NAME} -o jsonpath="{.status.containerStatuses[?(@.name=='zitadel-setup')].state.terminated}") ]; do
        sleep 5
      done
      # Extract PAT and create secret
      kubectl create secret generic zitadel-admin-sa-pat \
        --from-file=pat=/machinekey/pat \
        --dry-run=client -o yaml | kubectl apply -f -
  volumeMounts:
    - name: machinekey
      mountPath: /machinekey
      readOnly: true
```

**login-client-pat-writer sidecar**:
```yaml
- name: login-client-pat-writer
  image: docker.io/alpine/k8s:1.34.0
  command:
    - sh
    - -c
    - |
      # Wait for setup container to terminate
      until [ ! -z $(kubectl get pod ${POD_NAME} -o jsonpath="{.status.containerStatuses[?(@.name=='zitadel-setup')].state.terminated}") ]; do
        sleep 5
      done
      # Extract login client PAT and create secret
      kubectl create secret generic zitadel-login-client \
        --from-file=pat=/login-client/pat \
        --dry-run=client -o yaml | kubectl apply -f -
  volumeMounts:
    - name: login-client
      mountPath: /login-client
      readOnly: true
```

#### 4. Remove FIRSTINSTANCE from StatefulSet
Delete the entire `statefulset-firstinstance-patch.yaml` file. FIRSTINSTANCE should ONLY be in the setup job, NEVER in the StatefulSet.

### ⚠️ RECOMMENDED IMPROVEMENTS:

1. **Consider switching from StatefulSet to Deployment**
   - Zitadel is stateless when using external Postgres
   - Deployment is the correct resource type for stateless apps
   - StatefulSet adds unnecessary complexity

2. **Add POD_IP environment variable** to init and setup jobs for consistency

3. **Use args instead of command** for better consistency with upstream Helm chart

---

## CONCLUSION

Our implementation has fundamental architectural differences from the official Helm chart. The most critical issue is that we attempted to handle FIRSTINSTANCE in the StatefulSet, when it should be handled in the setup job with sidecar containers.

**The root cause of all our problems**:
- Init job completes but only runs "verify" → Missing `zitadel` subcommand
- Setup job completes but doesn't create credentials → FIRSTINSTANCE not configured in setup job
- StatefulSet tries to process FIRSTINSTANCE but fails → FIRSTINSTANCE in wrong place

**The fix requires**:
1. Adding `zitadel` subcommand to init job
2. Moving FIRSTINSTANCE processing from StatefulSet to setup job
3. Adding credential extraction sidecars to setup job
4. Removing all FIRSTINSTANCE configuration from StatefulSet

This will align our implementation with the official Helm chart architecture.
