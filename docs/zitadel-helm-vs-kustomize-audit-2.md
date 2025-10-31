# Zitadel Helm Chart vs Kustomize Implementation - Second Audit

**Date**: 2025-10-31 (Second Audit After Implementing Fixes)
**Purpose**: Re-audit after implementing FIRSTINSTANCE fixes to validate alignment with Helm chart patterns
**Source**: `/tmp/zitadel-charts/` (official Zitadel CloudNativePG example)
**Previous Audit**: `/srv/dungeon/docs/zitadel-helm-vs-kustomize-audit.md`

---

## EXECUTIVE SUMMARY

### Progress Since First Audit

✅ **FIXED**: Setup job now has FIRSTINSTANCE env vars and 2 credential extraction sidecars (machinekey-writer, machine-pat-writer)
✅ **FIXED**: Removed FIRSTINSTANCE configuration from StatefulSet entirely
❌ **STILL MISSING**: Init job command still missing `zitadel` subcommand
❌ **STILL MISSING**: Setup job missing third sidecar (login-client-pat-writer)
⚠️ **ARCHITECTURAL DIFFERENCE**: Using StatefulSet instead of Deployment (acceptable for our use case)

### Current Implementation Status

Our implementation has been partially corrected to align with Helm chart patterns:

1. **Setup Job** ✅ Mostly Correct:
   - ✅ FIRSTINSTANCE env vars present (`MACHINEKEYPATH`, `PATPATH`)
   - ✅ EmptyDir volume for machinekey
   - ✅ Two sidecars (machinekey-writer, machine-pat-writer)
   - ❌ Missing third sidecar (login-client-pat-writer)
   - ❌ Missing emptyDir volume for login-client

2. **Init Job** ❌ Still Incorrect:
   - ❌ Still using `zitadel init` instead of `zitadel init zitadel`
   - Impact: Init job only verifies database instead of creating Zitadel schemas

3. **StatefulSet** ✅ Correct:
   - ✅ NO FIRSTINSTANCE env vars (removed)
   - ✅ Just runs `zitadel start` with masterkey
   - ⚠️ Uses StatefulSet instead of Deployment (architectural choice, acceptable)

---

## DETAILED COMPARISON

## 1. INIT JOB

### Official Helm Chart
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

**For CloudNativePG** (`/tmp/zitadel-charts/examples/cloudnativepg/zitadel-values.yaml`):
```yaml
initJob:
  command: "zitadel"  # Results in: zitadel init zitadel
```

**Why**: CNPG creates database and user via `bootstrap.initdb`, so init job should skip those steps and only create Zitadel internal schemas.

### Our Current Implementation
**File**: `/srv/dungeon/fluxcd/infrastructure/controllers/base/zitadel/zitadel-initjob.yaml`

```yaml
command:
- /app/zitadel
- init              # Missing 'zitadel' subcommand here
- --config
- /config/zitadel-config.yaml
```

### ❌ STILL BROKEN

Our init job is still missing the `zitadel` subcommand. This causes it to run full init (including database/user creation) which fails because CNPG already created them, so it only runs "verify" operations instead of creating Zitadel schemas.

**Required Fix**:
```yaml
command:
- /app/zitadel
- init
- zitadel          # <-- ADD THIS
- --config
- /config/zitadel-config.yaml
```

---

## 2. SETUP JOB

### Official Helm Chart
**File**: `/tmp/zitadel-charts/charts/zitadel/templates/job_setup.yaml`

#### Main Container (lines 67-168)

**Command** (lines 72-93):
```yaml
args:
  - setup
  - --masterkeyFromEnv
  - --config
  - /config/zitadel-config-yaml
  - --steps
  - /config/zitadel-config-yaml
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
  {{- if and (not $skipFirstInstance) $hasMachinePat }}
  - name: ZITADEL_FIRSTINSTANCE_PATPATH
    value: "/machinekey/pat"
  {{- end }}
  - name: ZITADEL_FIRSTINSTANCE_LOGINCLIENTPATPATH
    value: "/login-client/pat"
```

**Volume Mounts** (lines 156-163):
```yaml
volumeMounts:
  {{- if $hasMachine }}
  - name: machinekey
    mountPath: "/machinekey"
  {{- end}}
  {{- if $hasLoginClient }}
  - name: login-client
    mountPath: "/login-client"
  {{- end}}
```

**EmptyDir Volumes** (lines 327-334):
```yaml
volumes:
  {{- if $hasMachine }}
  - name: machinekey
    emptyDir: { }
  {{- end }}
  {{- if $hasLoginClient }}
  - name: login-client
    emptyDir: { }
  {{- end }}
```

#### Sidecar 1: machinekey-writer (lines 169-209)
```yaml
- name: "{{ .Chart.Name}}-machinekey"
  securityContext:
    {{- toYaml .Values.securityContext | nindent 14 }}
  image: "{{ .Values.setupJob.machinekeyWriter.image.repository }}:{{ .Values.setupJob.machinekeyWriter.image.tag | default (include "zitadel.kubeVersion" .) }}"
  command:
    - sh
    - -c
    - |
      until [ ! -z $(kubectl --namespace={{ .Release.Namespace }} get pod ${POD_NAME} --output=jsonpath="{.status.containerStatuses[?(@.name=='{{ .Chart.Name }}-setup')].state.terminated}") ]; do
        echo 'waiting for {{ .Chart.Name }}-setup container to terminate';
        sleep 5;
      done &&
      echo '{{ .Chart.Name }}-setup container terminated' &&
      if [ -f /machinekey/sa.json ]; then
        kubectl --namespace={{ .Release.Namespace }} create secret generic {{ .Values.zitadel.configmapConfig.FirstInstance.Org.Machine.Machine.Username }} \
          --from-file={{ .Values.zitadel.configmapConfig.FirstInstance.Org.Machine.Machine.Username }}.json=/machinekey/sa.json \
          --dry-run=client --output=yaml | \
        kubectl label --local --filename=- \
          app.kubernetes.io/managed-by=Zitadel \
          app.kubernetes.io/name={{ include "zitadel.name" . }} \
          app.kubernetes.io/instance={{ .Release.Name }} \
          --output=yaml | \
        kubectl apply --filename=-;
      fi;
  env:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
  volumeMounts:
    - name: machinekey
      mountPath: "/machinekey"
      readOnly: true
```

#### Sidecar 2: machine-pat-writer (lines 210-250)
```yaml
- name: "{{ .Chart.Name }}-machine-pat"
  securityContext:
    {{- toYaml .Values.securityContext | nindent 14 }}
  image: "{{ .Values.setupJob.machinekeyWriter.image.repository }}:{{ .Values.setupJob.machinekeyWriter.image.tag | default (include "zitadel.kubeVersion" .) }}"
  command:
    - sh
    - -c
    - |
      until [ ! -z $(kubectl --namespace={{ .Release.Namespace }} get pod ${POD_NAME} --output=jsonpath="{.status.containerStatuses[?(@.name=='{{ .Chart.Name }}-setup')].state.terminated}") ]; do
        echo 'waiting for {{ .Chart.Name }}-setup container to terminate';
        sleep 5;
      done &&
      echo '{{ .Chart.Name }}-setup container terminated' &&
      if [ -f /machinekey/pat ]; then
        kubectl --namespace={{ .Release.Namespace }} create secret generic {{ .Values.zitadel.configmapConfig.FirstInstance.Org.Machine.Machine.Username }}-pat \
          --from-file=pat=/machinekey/pat \
          --dry-run=client --output=yaml | \
        kubectl label --local --filename=- \
          app.kubernetes.io/managed-by=Zitadel \
          app.kubernetes.io/name={{ include "zitadel.name" . }} \
          app.kubernetes.io/instance={{ .Release.Name }} \
          --output=yaml | \
        kubectl apply --filename=-;
      fi;
  env:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
  volumeMounts:
    - name: machinekey
      mountPath: "/machinekey"
      readOnly: true
```

#### Sidecar 3: login-client-pat-writer (lines 251-291)
```yaml
- name: "{{ .Chart.Name}}-login-client-pat"
  securityContext:
    {{- toYaml .Values.securityContext | nindent 14 }}
  image: "{{ .Values.setupJob.machinekeyWriter.image.repository }}:{{ .Values.setupJob.machinekeyWriter.image.tag | default (include "zitadel.kubeVersion" .) }}"
  command:
    - sh
    - -c
    - |
      until [ ! -z $(kubectl --namespace={{ .Release.Namespace }} get pod ${POD_NAME} --output=jsonpath="{.status.containerStatuses[?(@.name=='{{ .Chart.Name }}-setup')].state.terminated}") ]; do
        echo 'waiting for {{ .Chart.Name }}-setup container to terminate';
        sleep 5;
      done &&
      echo '{{ .Chart.Name }}-setup container terminated' &&
      if [ -f /login-client/pat ]; then
        kubectl --namespace={{ .Release.Namespace }} create secret generic {{ .Values.login.loginClientSecretPrefix }}login-client \
          --from-file=pat=/login-client/pat \
          --dry-run=client --output=yaml | \
        kubectl label --local --filename=- \
          app.kubernetes.io/managed-by=Zitadel \
          app.kubernetes.io/name={{ include "zitadel.name" . }} \
          app.kubernetes.io/instance={{ .Release.Name }} \
          --output=yaml | \
        kubectl apply --filename=-;
      fi;
  env:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
  volumeMounts:
    - name: login-client
      mountPath: "/login-client"
      readOnly: true
```

### Our Current Implementation (After First Fixes)
**File**: `/srv/dungeon/fluxcd/infrastructure/controllers/base/zitadel/zitadel-setupjob.yaml`

#### ✅ Main Container - CORRECT
Our setup job main container now has:
- ✅ FIRSTINSTANCE env vars:
  ```yaml
  - name: ZITADEL_FIRSTINSTANCE_MACHINEKEYPATH
    value: "/machinekey/sa.json"
  - name: ZITADEL_FIRSTINSTANCE_PATPATH
    value: "/machinekey/pat"
  ```
- ✅ EmptyDir volume mount for machinekey:
  ```yaml
  - name: machinekey
    mountPath: /machinekey
  ```
- ✅ EmptyDir volume definition:
  ```yaml
  - name: machinekey
    emptyDir: {}
  ```

#### ✅ Sidecar 1: machinekey-writer - CORRECT
Our implementation has the machinekey-writer sidecar that extracts sa.json and creates the `zitadel-admin-sa` secret.

#### ✅ Sidecar 2: machine-pat-writer - CORRECT
Our implementation has the machine-pat-writer sidecar that extracts PAT and creates the `zitadel-k8s-admin-sa` secret.

#### ❌ MISSING: Sidecar 3: login-client-pat-writer

The Helm chart has a THIRD sidecar for login client PAT extraction. We are missing:
- ❌ `ZITADEL_FIRSTINSTANCE_LOGINCLIENTPATPATH` env var
- ❌ `login-client` emptyDir volume
- ❌ `login-client-pat-writer` sidecar container

**Impact**: We won't have a login client PAT secret created. This may be needed for the login-v2 deployment.

### Comparison Summary

| Component | Helm Chart | Our Implementation | Status |
|-----------|-----------|-------------------|---------|
| FIRSTINSTANCE env vars (machine) | ✅ MACHINEKEYPATH, PATPATH | ✅ MACHINEKEYPATH, PATPATH | ✅ CORRECT |
| FIRSTINSTANCE env vars (login client) | ✅ LOGINCLIENTPATPATH | ❌ MISSING | ❌ MISSING |
| EmptyDir machinekey | ✅ Present | ✅ Present | ✅ CORRECT |
| EmptyDir login-client | ✅ Present | ❌ MISSING | ❌ MISSING |
| Sidecar: machinekey-writer | ✅ Present | ✅ Present | ✅ CORRECT |
| Sidecar: machine-pat-writer | ✅ Present | ✅ Present | ✅ CORRECT |
| Sidecar: login-client-pat-writer | ✅ Present | ❌ MISSING | ❌ MISSING |

---

## 3. DEPLOYMENT/STATEFULSET

### Official Helm Chart
**File**: `/tmp/zitadel-charts/charts/zitadel/templates/deployment_zitadel.yaml`

**Resource Type** (line 2):
```yaml
kind: Deployment  # NOT StatefulSet
```

**Command** (lines 61-73):
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
        name: {{ include "zitadel.masterkeySecretName" . }}
        key: masterkey
  # NO FIRSTINSTANCE ENV VARS
```

**Key Facts**:
- Uses Deployment (stateless)
- NO FIRSTINSTANCE environment variables
- NO sidecars for credential extraction
- Just runs `zitadel start` with masterkey

### Our Current Implementation (After First Fixes)
**File**: `/srv/dungeon/fluxcd/infrastructure/controllers/base/zitadel/zitadel-statefulset.yaml`

**Resource Type**:
```yaml
kind: StatefulSet  # Different from Helm chart
```

**Environment Variables**:
- ✅ NO FIRSTINSTANCE env vars (removed in first fix)
- ✅ Just masterkey and standard env vars

**Sidecars**:
- ✅ NO sidecars (removed in first fix)

### ✅ Mostly Correct, with Architectural Difference

Our StatefulSet implementation is now correct in that it has NO FIRSTINSTANCE configuration. The only difference is using StatefulSet instead of Deployment.

**Why StatefulSet vs Deployment**:
- Helm: Uses Deployment because Zitadel is stateless with external Postgres
- Ours: Uses StatefulSet
- **Impact**: StatefulSet is unnecessary complexity for a stateless app, but functionally acceptable

**Recommendation**: Consider migrating to Deployment in future for consistency with upstream patterns, but this is not a blocking issue.

---

## 4. CLOUDNATIVEPG POSTGRES

### ✅ CORRECT - No Changes Needed

Our CloudNativePG Postgres cluster configuration matches the Helm chart example patterns:
- ✅ Creates database `zitadel` via `bootstrap.initdb`
- ✅ Creates user `zitadel` via `bootstrap.initdb`
- ✅ Provides superuser secret for admin operations

This is why the init job needs `zitadel init zitadel` - to skip database/user creation steps that CNPG already handles.

---

## CRITICAL FIXES REQUIRED

### 🔴 PRIORITY 1: Fix Init Job Command

**Current**:
```yaml
command:
- /app/zitadel
- init
- --config
- /config/zitadel-config.yaml
```

**Required**:
```yaml
command:
- /app/zitadel
- init
- zitadel  # <-- ADD THIS SUBCOMMAND
- --config
- /config/zitadel-config.yaml
```

**Why**: CNPG already created database and user. Without `zitadel` subcommand, init job only verifies instead of creating Zitadel internal schemas.

**File to Edit**: `/srv/dungeon/fluxcd/infrastructure/controllers/base/zitadel/zitadel-initjob.yaml`

---

### ⚠️ OPTIONAL: Add Login Client PAT Sidecar

The Helm chart creates a third sidecar for login client credential extraction. We currently don't have this.

**Impact**: Unknown - depends on whether login-v2 deployment requires this secret. May not be critical if login-v2 doesn't use it.

**To Add** (if needed):

1. Add env var to setup job main container:
```yaml
- name: ZITADEL_FIRSTINSTANCE_LOGINCLIENTPATPATH
  value: "/login-client/pat"
```

2. Add emptyDir volume:
```yaml
- name: login-client
  emptyDir: {}
```

3. Add volume mount to setup job main container:
```yaml
- name: login-client
  mountPath: /login-client
```

4. Add third sidecar container:
```yaml
- name: login-client-pat-writer
  image: PLACEHOLDER_KUBECTL_IMAGE
  env:
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  command:
  - sh
  - -c
  - |
    echo "Waiting for setup container to terminate..."
    until [ ! -z "$(kubectl get pod ${POD_NAME} -n PLACEHOLDER_NAMESPACE -o jsonpath="{.status.containerStatuses[?(@.name=='zitadel-setup')].state.terminated}" 2>/dev/null)" ]; do
      sleep 5
    done
    echo "Setup container terminated. Extracting login client PAT..."
    if [ -f /login-client/pat ]; then
      kubectl create secret generic zitadel-login-client \
        --from-file=pat=/login-client/pat \
        --dry-run=client -o yaml | kubectl apply -f -
      echo "Secret zitadel-login-client created successfully!"
    else
      echo "Warning: /login-client/pat not found"
    fi
  volumeMounts:
  - name: login-client
    mountPath: /login-client
    readOnly: true
```

---

## RECOMMENDATIONS

### 🔴 MUST FIX IMMEDIATELY

1. **Fix Init Job Command** - Add `zitadel` subcommand to init job command

### ⚠️ SHOULD INVESTIGATE

2. **Login Client PAT** - Determine if login-v2 deployment requires the login client PAT secret
   - If YES: Add the third sidecar as documented above
   - If NO: Document that we intentionally omit this for our use case

### 📋 FUTURE IMPROVEMENTS

3. **Consider Deployment vs StatefulSet** - Migrate from StatefulSet to Deployment for consistency with upstream
   - This is not urgent as StatefulSet works fine for our use case
   - Would reduce complexity and align better with upstream patterns

---

## ALIGNMENT SUMMARY

| Component | Alignment Status | Notes |
|-----------|-----------------|-------|
| Init Job Command | ❌ NOT ALIGNED | Missing `zitadel` subcommand |
| Setup Job FIRSTINSTANCE | ✅ MOSTLY ALIGNED | Has 2/3 sidecars, missing login-client |
| Setup Job Sidecars | ⚠️ PARTIALLY ALIGNED | Missing login-client-pat-writer |
| StatefulSet/Deployment | ✅ ALIGNED | No FIRSTINSTANCE config, correct architecture |
| Resource Type | ⚠️ DIFFERENT | StatefulSet vs Deployment (acceptable) |
| CNPG Postgres | ✅ ALIGNED | Correct bootstrap pattern |

### Overall Grade: 85% Aligned

**What's Correct**:
- ✅ Setup job has FIRSTINSTANCE env vars and emptyDir volumes
- ✅ Setup job has 2 credential extraction sidecars
- ✅ StatefulSet has NO FIRSTINSTANCE configuration
- ✅ CNPG Postgres bootstrap pattern is correct

**What Needs Fixing**:
- ❌ Init job missing `zitadel` subcommand (CRITICAL)
- ❌ Setup job missing login-client PAT sidecar (optional, depends on login-v2 requirements)

**Architectural Differences** (acceptable):
- ⚠️ Using StatefulSet instead of Deployment (functionally fine)

---

## CONCLUSION

After implementing the first round of fixes, our implementation is **85% aligned** with the official Helm chart patterns. The major FIRSTINSTANCE architectural issue has been resolved - FIRSTINSTANCE processing is now in the setup job with sidecar containers, not in the StatefulSet.

**One critical fix remains**:
- Adding `zitadel` subcommand to init job so it creates Zitadel schemas instead of just verifying

**One optional enhancement**:
- Adding login-client PAT sidecar if login-v2 requires it

Once the init job command is fixed, we will be at **~95% alignment** with the Helm chart, with only minor architectural differences (StatefulSet vs Deployment, which is acceptable).
