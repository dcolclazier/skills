# When to Mock

Mock at **system boundaries** only:

- External APIs (payment, email, etc.)
- Databases (sometimes — prefer test DB)
- Time/randomness
- File system (sometimes)

*Why only at boundaries:* mocks of internal collaborators couple your tests to your *implementation structure*. When you refactor — split a class, rename a method, change which collaborator owns which responsibility — internal mocks break even though behavior didn't change. Boundaries (network, disk, clock) don't shift during refactor; mocks there stay valid. Same north-star principle as `tests.md`: test what survives.

Don't mock:

- Your own classes/modules
- Internal collaborators
- Anything you control

## Designing for Mockability

At system boundaries, design interfaces that are easy to mock:

**1. Use dependency injection**

Pass external dependencies in rather than creating them internally:

```typescript
// Easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// Hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

Go gives you DI naturally via interfaces — define what you depend on, accept any implementation:

```go
// Easy to mock — accept the interface
type PaymentClient interface {
    Charge(amount Money) error
}

func ProcessPayment(order Order, client PaymentClient) error {
    return client.Charge(order.Total)
}

// Hard to mock — constructs its dependency
func ProcessPayment(order Order) error {
    client := stripe.NewClient(os.Getenv("STRIPE_KEY"))
    return client.Charge(order.Total)
}
```

In tests, pass any type that satisfies `PaymentClient` — including a fake that records calls or returns canned responses. No mocking framework needed.

**2. Prefer SDK-style interfaces over generic fetchers**

Create specific functions for each external operation instead of one generic function with conditional logic:

```typescript
// GOOD: Each function is independently mockable
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: Mocking requires conditional logic inside the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK approach means:
- Each mock returns one specific shape
- No conditional logic in test setup
- Easier to see which endpoints a test exercises
- Type safety per endpoint
