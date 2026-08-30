# J&Z testing guide

## Smoke test

Start the stack, then:

```bash
./tests/smoke.sh
```

## Backend checks

Validate:

- registration validation
- duplicate account handling
- login failure/success
- session expiry/revocation
- permission middleware
- node credential rotation
- HMAC timestamp rejection
- invalid node signatures
- allocation locking
- concurrent server creation
- lifecycle queueing
- worker failure state

## Wings checks

On a Linux Docker node:

```bash
curl http://127.0.0.1:8080/health
```

Then verify authenticated Docker actions from the worker. Never test by exposing Docker's TCP socket publicly.

## Failure injection

Test at least:

1. PostgreSQL unavailable.
2. Redis unavailable.
3. Wings offline during server creation.
4. Docker unavailable on a node.
5. Browser disconnect during console activity.
6. Duplicate allocation claims.
7. Backup storage unavailable.
8. Update backup failure.
9. Plugin compatibility failure.
10. Node clock skew beyond the request-signature window.
