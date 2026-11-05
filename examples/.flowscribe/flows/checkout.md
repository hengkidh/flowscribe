---
flowscribe: 1
type: flow
id: checkout
title: Checkout
summary: Customer turns a cart into a paid order; stock is held for 15 minutes while payment is pending.
status: active
updated: 2026-11-05
actor: customer
trigger: Customer presses "Pay" on the cart page
modules: [orders, payments]
files:
  - app/Http/Controllers/OrderController.php
  - app/Services/StockService.php
  - resources/js/Pages/Cart.vue
  - resources/js/Pages/Pay.vue
steps:
  - id: cart
    kind: screen
    title: Review cart
    screen: { route: /cart, name: Cart }
    action: Press "Pay"
    calls: [POST /api/orders]
    caption: One tap from cart to checkout
    next: hold-stock
  - id: hold-stock
    kind: system
    title: Hold stock for 15 minutes
    calls:
      - { type: db, target: stock_holds }
      - { type: job, target: ReleaseExpiredHolds }
    next: pay
  - id: pay
    kind: screen
    title: Choose payment method
    screen: { route: "/pay/:order", name: Pay }
    calls:
      - POST /api/payments
      - { type: webhook, target: payment-gateway, note: may arrive before the redirect }
    states: [pending, paid, failed]
    caption: Pay with any method
    next:
      - { when: payment paid, to: done }
      - { when: payment failed or expired, to: failed }
  - id: done
    kind: screen
    title: Order confirmed
    screen: { route: "/orders/:order", name: Order detail }
    end: success
    caption: Done — order confirmed
  - id: failed
    kind: screen
    title: Payment failed
    screen: { route: "/orders/:order", name: Order detail }
    end: failure
---

# Checkout

The order is created **before** payment so that stock can be held while the customer pays.
Without the hold, two customers could pay for the last item at the same time.

## Gotchas
- The payment webhook can arrive before the customer is redirected back. Order status is read
  from the webhook result, never from the redirect query string.
- Expired holds are released by `ReleaseExpiredHolds`; if the scheduler is down, stock stays locked.
