# Good and Bad Tests

## Good Tests

**Integration-style**: Test through real interfaces, not mocks of internal parts.

```typescript
// GOOD: Tests observable behavior
test("user can checkout with valid cart", async () => {
  const cart = createCart();
  cart.add(product);
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe("confirmed");
});
```

Characteristics:

- Tests behavior users/callers care about
- Uses public API only
- Survives internal refactors
- Describes WHAT, not HOW
- One logical assertion per test

## Bad Tests

**Implementation-detail tests**: Coupled to internal structure.

```typescript
// BAD: Tests implementation details
test("checkout calls paymentService.process", async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});
```

Red flags:

- Mocking internal collaborators
- Testing private methods
- Asserting on call counts/order
- Test breaks when refactoring without behavior change
- Test name describes HOW not WHAT
- Verifying through external means instead of interface

```typescript
// BAD: Bypasses interface to verify
test("createUser saves to database", async () => {
  await createUser({ name: "Alice" });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ["Alice"]);
  expect(row).toBeDefined();
});

// GOOD: Verifies through interface
test("createUser makes user retrievable", async () => {
  const user = await createUser({ name: "Alice" });
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe("Alice");
});
```

## Same pattern in another language

The principle is language-universal. Python (pytest) example:

```python
# BAD: bypasses the interface, verifies via internal mock
def test_create_user_calls_db_insert(mocker):
    mock_db = mocker.patch("users.db.insert")
    create_user({"name": "Alice"})
    mock_db.assert_called_once()  # tests HOW, not WHAT

# GOOD: verifies through the public interface
def test_create_user_makes_user_retrievable():
    user = create_user({"name": "Alice"})
    retrieved = get_user(user.id)
    assert retrieved.name == "Alice"
```

Whatever language, the test should describe behaviour that's observable through the public surface — not the internal collaborators that happen to deliver that behaviour today.
