# AppFlowy Database Configuration Notes

## Critical: GoTrue DATABASE_URL Must Include search_path

The gotrue authentication service **requires** `?search_path=auth` in its DATABASE_URL:

```
DATABASE_URL=postgres://appflowy:password@host:5432/appflowy?search_path=auth
```

**Why:**
- GoTrue creates all objects (tables, enums, indexes) in the `auth` schema
- Without `search_path=auth`, PostgreSQL defaults to `public` schema
- Migrations fail with: `ERROR: type "auth.factor_type" does not exist`

## Other Services (No search_path needed)

- `APPFLOWY_DATABASE_URL`: `postgres://appflowy:password@host:5432/appflowy`
- `APPFLOWY_WORKER_DATABASE_URL`: `postgres://appflowy:password@host:5432/appflowy`
- `AI_DATABASE_URL`: `postgresql+psycopg://appflowy:password@host:5432/appflowy`

## PostgreSQL Ownership Requirements

GoTrue migrations need to modify enum types in the auth schema. The init script must transfer ownership:

```sql
ALTER SCHEMA auth OWNER TO appflowy;
ALTER TYPE auth.aal_level OWNER TO appflowy;
ALTER TYPE auth.factor_status OWNER TO appflowy;
ALTER TYPE auth.factor_type OWNER TO appflowy;
```

**Why:**
- CloudNativePG creates initial auth schema objects as `postgres` superuser
- GoTrue runs as `appflowy` user
- PostgreSQL requires ownership to alter enum types
- Without this: `ERROR: must be owner of type factor_type`

## Success Indicators

Gotrue pod logs should show:
```
{"msg":"Migrations already up to date, nothing to apply"}
{"msg":"GoTrue migrations applied successfully"}
{"msg":"GoTrue API started on: :9999"}
```
