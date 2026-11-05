---
flowscribe: 1
type: module
id: payments
title: Payments
summary: Creates payment sessions with the payment gateway and turns its webhooks into order status changes.
status: active
updated: 2026-11-05
kind: feature
files:
  - app/Http/Controllers/PaymentController.php
  - app/Http/Controllers/PaymentWebhookController.php
  - app/Services/Payments/**
entrypoints:
  - app/Services/Payments/PaymentService.php
depends_on: [orders]
env: [PAYMENT_SERVER_KEY, PAYMENT_CLIENT_KEY, PAYMENT_IS_PRODUCTION]
data: [payments, payment_events]
---

# Payments

`PaymentService` is the only class that talks to the gateway; controllers never call it directly.

## Gotchas
- Webhooks are verified by signature before anything else. A request with a bad signature is
  logged with its event id only, never with its payload.
- Webhooks are idempotent on `payment_events.gateway_event_id`; the gateway retries on timeouts.
