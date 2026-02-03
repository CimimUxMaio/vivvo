# Vivvo

**Vivvo** is a multi-role property management platform designed to streamline communication, payments, and financial transparency between **Tenants**, **Property Owners**, and **Managers**.

The app centralizes rent, expenses, contracts, and analytics into a single system, reducing friction and improving visibility for all parties involved.

For a detailed description of the platform, user roles, and features, see [VIVVO.md](VIVVO.md).

---

## Quickstart

### Prerequisites

* Elixir (see `.tool-versions` for version)
* Docker (for PostgreSQL database)
* Mix dependencies

### Setup

1. Install Elixir dependencies:
   ```bash
   mix deps.get
   ```

2. Start the PostgreSQL database container:
   ```bash
   make db.up
   ```

3. Set up the database (create, migrate, seed):
   ```bash
   make db.setup
   ```

4. Run the development server:
   ```bash
   make dev.start
   ```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

### Common Makefile Commands

| Command | Description |
|---------|-------------|
| `make` or `make dev.start` | Run the development server with IEx |
| `make dev.test` | Run the test suite |
| `make dev.precommit` | Run formatting, static analysis (credo), and tests |
| `make db.up` | Start the PostgreSQL Docker container |
| `make db.setup` | Create database, run migrations, and seed data |
| `make db.down` | Stop and remove the database container |
| `make help` | Display all available commands |

---

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
