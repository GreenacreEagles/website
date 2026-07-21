# Super Administrator Bootstrap

The platform must not grant super-administrator access to the first public signup.

Super-admin bootstrap is a deliberate database administration action after the foundation migration has been applied.

## Preconditions

1. The foundation migration has been applied successfully.
2. The intended administrator has signed up through Supabase Auth.
3. The signup trigger has created a `profiles` row for that user.
4. There is no existing active `super_administrator` assignment.

## Find The User ID

Use Supabase Dashboard Auth user search, or a trusted SQL query run by an owner/admin. Do not expose service-role keys in browser code.

Example SQL:

```sql
select id, email, created_at
from auth.users
where email = 'admin@example.com';
```

## Bootstrap Command

Run this in the Supabase SQL editor as a trusted database administrator, replacing the UUID and reason:

```sql
select app_private.bootstrap_super_admin(
  '00000000-0000-0000-0000-000000000000',
  'Initial Greenacre Eagles platform administrator approved by committee'
);
```

## Safety Controls

- The function is in `app_private`, not the exposed public API schema.
- It is not granted to `anon` or `authenticated`.
- It requires a trusted database administrator session.
- It refuses to run if an active super administrator already exists.
- It records an audit event.
- It does not depend on frontend code, user metadata, or service-role keys in the browser.

## After Bootstrap

Use the admin portal role assignment process for future administrators.

Only an active super administrator can grant or remove the `super_administrator` role after bootstrap.
