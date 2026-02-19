# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# This script creates comprehensive demo data for testing:
# - 1 dual-role user (owner + tenant): demo@example.com / demo12345678
# - 3 tenant-only users
# - 6 properties (all owned by demo user)
# - 6 contracts (various statuses: active, expired, upcoming)
# - ~50 payments (accepted, pending, rejected, partial)

alias Vivvo.Repo
alias Vivvo.Accounts.{User, Scope}
alias Vivvo.Properties
alias Vivvo.Properties.Property
alias Vivvo.Contracts
alias Vivvo.Contracts.Contract
alias Vivvo.Payments
alias Vivvo.Payments.Payment

import Ecto.Query

IO.puts("Starting database seeding...")

# Clear existing data (for idempotency)
IO.puts("Clearing existing data...")
Repo.delete_all(Payment)
Repo.delete_all(Contract)
Repo.delete_all(Property)
Repo.delete_all(User)

# Helper function to create a user with password
create_user = fn attrs ->
  password = Map.get(attrs, :password, "password123456")

  {:ok, user} =
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()

  # Set password and confirm the user
  user
  |> User.password_changeset(%{password: password})
  |> Repo.update!()
  |> User.confirm_changeset()
  |> Repo.update!()
end

IO.puts("Creating users...")

# Create demo user (dual-role: owner + tenant)
demo_user =
  create_user.(%{
    email: "demo@example.com",
    password: "demo12345678",
    first_name: "Demo",
    last_name: "User",
    phone_number: "+1-555-0100",
    preferred_roles: [:owner, :tenant],
    current_role: :owner
  })

# Create tenant-only users
tenant1 =
  create_user.(%{
    email: "tenant1@example.com",
    password: "password123456",
    first_name: "Alice",
    last_name: "Johnson",
    phone_number: "+1-555-0101",
    preferred_roles: [:tenant],
    current_role: :tenant
  })

tenant2 =
  create_user.(%{
    email: "tenant2@example.com",
    password: "password123456",
    first_name: "Bob",
    last_name: "Smith",
    phone_number: "+1-555-0102",
    preferred_roles: [:tenant],
    current_role: :tenant
  })

tenant3 =
  create_user.(%{
    email: "tenant3@example.com",
    password: "password123456",
    first_name: "Carol",
    last_name: "Williams",
    phone_number: "+1-555-0103",
    preferred_roles: [:tenant],
    current_role: :tenant
  })

IO.puts("Created #{Repo.aggregate(User, :count, :id)} users")

# Create scope for demo user (as owner)
demo_scope = %Scope{user: demo_user}

IO.puts("Creating properties...")

# Create 6 properties (all owned by demo user)
properties = [
  %{
    name: "Sunset Apartments Unit 101",
    address: "123 Sunset Blvd, Apt 101, Los Angeles, CA 90001",
    area: 850,
    rooms: 2,
    notes: "Great view, recently renovated"
  },
  %{
    name: "Downtown Loft",
    address: "456 Main St, Loft 3B, New York, NY 10001",
    area: 600,
    rooms: 1,
    notes: "Modern loft in the heart of the city"
  },
  %{
    name: "Garden Villa",
    address: "789 Oak Lane, Miami, FL 33101",
    area: 1200,
    rooms: 3,
    notes: "Spacious villa with private garden"
  },
  %{
    name: "City View Penthouse",
    address: "321 High Rise Ave, Penthouse, Chicago, IL 60601",
    area: 950,
    rooms: 2,
    notes: "Luxury penthouse with skyline views"
  },
  %{
    name: "Cozy Studio",
    address: "654 Pine St, Studio 12, Seattle, WA 98101",
    area: 400,
    rooms: 1,
    notes: "Compact studio, perfect for singles"
  },
  %{
    name: "Suburban House",
    address: "987 Maple Dr, Austin, TX 78701",
    area: 1800,
    rooms: 4,
    notes: "Family home with large backyard"
  }
]

created_properties =
  Enum.map(properties, fn prop_attrs ->
    {:ok, property} = Properties.create_property(demo_scope, prop_attrs)
    property
  end)

[sunset_apt, downtown_loft, garden_villa, city_penthouse, cozy_studio, suburban_house] =
  created_properties

IO.puts("Created #{length(created_properties)} properties")

IO.puts("Creating contracts...")

today = Date.utc_today()

# Contract 1: Active - Property 1 (Sunset Apts) → Tenant1
# 6 months ago → 6 months future, rent $1200, expires 5th
contract1_start = Date.add(today, -180)
contract1_end = Date.add(today, 180)

{:ok, contract1} =
  Contracts.create_contract(demo_scope, %{
    start_date: contract1_start,
    end_date: contract1_end,
    expiration_day: 5,
    rent: Decimal.new("1200.00"),
    property_id: sunset_apt.id,
    tenant_id: tenant1.id,
    notes: "Standard 1-year lease"
  })

IO.puts("Created Contract 1 (Active: Sunset Apts → Tenant1)")

# Create payments for Contract 1
# 6 months of payments: payments 1-4 accepted on time, payment 5 rejected then accepted, payment 6 pending
for month <- 1..6 do
  due_date = Contracts.calculate_due_date(contract1, month)
  submitted_at = DateTime.new!(due_date, ~T[10:00:00])

  cond do
    month <= 4 ->
      # Accepted on time (with small random delay 0-3 days)
      delay = Enum.random(0..3)
      submitted_at = DateTime.add(submitted_at, delay, :day)

      {:ok, payment} =
        Payments.create_payment(
          %Scope{user: tenant1},
          %{
            payment_number: month,
            amount: Decimal.new("1200.00"),
            contract_id: contract1.id,
            notes: "Rent for month #{month}"
          }
        )

      Payments.accept_payment(demo_scope, payment)

      # Update timestamp
      Repo.update_all(
        from(p in Payment, where: p.id == ^payment.id),
        set: [inserted_at: submitted_at, updated_at: submitted_at]
      )

    month == 5 ->
      # Rejected then re-accepted with delay
      {:ok, payment} =
        Payments.create_payment(
          %Scope{user: tenant1},
          %{
            payment_number: month,
            amount: Decimal.new("1200.00"),
            contract_id: contract1.id,
            notes: "Initial submission - rejected"
          }
        )

      Payments.reject_payment(demo_scope, payment, "Insufficient funds")

      rejected_at = DateTime.add(submitted_at, 1, :day)

      Repo.update_all(
        from(p in Payment, where: p.id == ^payment.id),
        set: [inserted_at: rejected_at, updated_at: rejected_at]
      )

      # Re-submit and accept
      {:ok, payment2} =
        Payments.create_payment(
          %Scope{user: tenant1},
          %{
            payment_number: month,
            amount: Decimal.new("1200.00"),
            contract_id: contract1.id,
            notes: "Resubmitted after rejection"
          }
        )

      Payments.accept_payment(demo_scope, payment2)

      resubmitted_at = DateTime.add(submitted_at, 5, :day)

      Repo.update_all(
        from(p in Payment, where: p.id == ^payment2.id),
        set: [inserted_at: resubmitted_at, updated_at: resubmitted_at]
      )

    month == 6 ->
      # Current month - 50% chance of being pending, 50% chance accepted
      if :rand.uniform() > 0.5 do
        # Pending - create payment but don't accept or reject
        {:ok, _payment} =
          Payments.create_payment(
            %Scope{user: tenant1},
            %{
              payment_number: month,
              amount: Decimal.new("1200.00"),
              contract_id: contract1.id,
              notes: "Rent for month #{month} - pending approval"
            }
          )

        # No accept/reject call - leaves it pending
      else
        # Accepted
        {:ok, payment} =
          Payments.create_payment(
            %Scope{user: tenant1},
            %{
              payment_number: month,
              amount: Decimal.new("1200.00"),
              contract_id: contract1.id,
              notes: "Rent for month #{month}"
            }
          )

        Payments.accept_payment(demo_scope, payment)

        Repo.update_all(
          from(p in Payment, where: p.id == ^payment.id),
          set: [inserted_at: submitted_at, updated_at: submitted_at]
        )
      end
  end
end

# Contract 2: Active - Property 2 (Downtown Loft) → Tenant2
# 3 months ago → 9 months future, rent $1500, expires 10th
contract2_start = Date.add(today, -90)
contract2_end = Date.add(today, 270)

{:ok, contract2} =
  Contracts.create_contract(demo_scope, %{
    start_date: contract2_start,
    end_date: contract2_end,
    expiration_day: 10,
    rent: Decimal.new("1500.00"),
    property_id: downtown_loft.id,
    tenant_id: tenant2.id,
    notes: "Furnished loft, utilities included"
  })

IO.puts("Created Contract 2 (Active: Downtown Loft → Tenant2)")

# Create payments for Contract 2
# 3 months: payments 1-2 accepted on time, payment 3 partial then completed
for month <- 1..3 do
  due_date = Contracts.calculate_due_date(contract2, month)
  submitted_at = DateTime.new!(due_date, ~T[09:30:00])

  cond do
    month <= 2 ->
      # Accepted on time
      {:ok, payment} =
        Payments.create_payment(
          %Scope{user: tenant2},
          %{
            payment_number: month,
            amount: Decimal.new("1500.00"),
            contract_id: contract2.id,
            notes: "Rent for month #{month}"
          }
        )

      Payments.accept_payment(demo_scope, payment)

      Repo.update_all(
        from(p in Payment, where: p.id == ^payment.id),
        set: [inserted_at: submitted_at, updated_at: submitted_at]
      )

    month == 3 ->
      # 50% chance of pending for the latest payment
      if :rand.uniform() > 0.5 do
        # Pending - create payment but don't accept or reject
        {:ok, _payment} =
          Payments.create_payment(
            %Scope{user: tenant2},
            %{
              payment_number: month,
              amount: Decimal.new("1500.00"),
              contract_id: contract2.id,
              notes: "Rent for month #{month} - pending approval"
            }
          )

        # No accept/reject call - leaves it pending
      else
        # Partial payment ($900 of $1500), then additional payment
        {:ok, payment1} =
          Payments.create_payment(
            %Scope{user: tenant2},
            %{
              payment_number: month,
              amount: Decimal.new("900.00"),
              contract_id: contract2.id,
              notes: "Partial payment - will pay rest later"
            }
          )

        Payments.accept_payment(demo_scope, payment1)

        Repo.update_all(
          from(p in Payment, where: p.id == ^payment1.id),
          set: [inserted_at: submitted_at, updated_at: submitted_at]
        )

        # Second payment to complete
        second_submitted = DateTime.add(submitted_at, 3, :day)

        {:ok, payment2} =
          Payments.create_payment(
            %Scope{user: tenant2},
            %{
              payment_number: month,
              amount: Decimal.new("600.00"),
              contract_id: contract2.id,
              notes: "Remaining balance for month #{month}"
            }
          )

        Payments.accept_payment(demo_scope, payment2)

        Repo.update_all(
          from(p in Payment, where: p.id == ^payment2.id),
          set: [inserted_at: second_submitted, updated_at: second_submitted]
        )
      end
  end
end

# Contract 3: Active (Ending Soon) - Property 3 (Garden Villa) → Demo user as tenant
# 10 months ago → 2 months future, rent $2000, expires 15th
contract3_start = Date.add(today, -300)
contract3_end = Date.add(today, 60)

{:ok, contract3} =
  Contracts.create_contract(demo_scope, %{
    start_date: contract3_start,
    end_date: contract3_end,
    expiration_day: 15,
    rent: Decimal.new("2000.00"),
    property_id: garden_villa.id,
    tenant_id: demo_user.id,
    notes: "Demo user's own rental - ending soon"
  })

IO.puts("Created Contract 3 (Ending Soon: Garden Villa → Demo User)")

# Create payments for Contract 3 (demo user paying themselves - for demo purposes)
# 10 months of payments, mix of on-time and slightly late
for month <- 1..10 do
  due_date = Contracts.calculate_due_date(contract3, month)
  # Random delay: 50% on time, 50% 1-5 days late
  delay = if :rand.uniform() > 0.5, do: 0, else: Enum.random(1..5)
  submitted_at = DateTime.new!(due_date, ~T[14:00:00]) |> DateTime.add(delay, :day)

  {:ok, payment} =
    Payments.create_payment(
      demo_scope,
      %{
        payment_number: month,
        amount: Decimal.new("2000.00"),
        contract_id: contract3.id,
        notes:
          "Rent for month #{month} - #{demo_user.first_name} #{demo_user.last_name} (self-payment)"
      }
    )

  Payments.accept_payment(demo_scope, payment)

  Repo.update_all(
    from(p in Payment, where: p.id == ^payment.id),
    set: [inserted_at: submitted_at, updated_at: submitted_at]
  )
end

# Month 11 - 50% chance of pending for the latest payment
due_date_11 = Contracts.calculate_due_date(contract3, 11)
submitted_at_11 = DateTime.new!(due_date_11, ~T[14:00:00])

if :rand.uniform() > 0.5 do
  # Pending - create payment but don't accept or reject
  {:ok, _payment} =
    Payments.create_payment(
      demo_scope,
      %{
        payment_number: 11,
        amount: Decimal.new("2000.00"),
        contract_id: contract3.id,
        notes: "Rent for month 11 - pending approval"
      }
    )

  # No accept/reject call - leaves it pending
else
  # Accepted
  {:ok, payment} =
    Payments.create_payment(
      demo_scope,
      %{
        payment_number: 11,
        amount: Decimal.new("2000.00"),
        contract_id: contract3.id,
        notes: "Rent for month 11"
      }
    )

  Payments.accept_payment(demo_scope, payment)

  Repo.update_all(
    from(p in Payment, where: p.id == ^payment.id),
    set: [inserted_at: submitted_at_11, updated_at: submitted_at_11]
  )
end

# Contract 4: Expired - Property 4 (City Penthouse) → Tenant2
# 15 months ago → 3 months ago, rent $1800
contract4_start = Date.add(today, -450)
contract4_end = Date.add(today, -90)

{:ok, contract4} =
  Contracts.create_contract(demo_scope, %{
    start_date: contract4_start,
    end_date: contract4_end,
    expiration_day: 5,
    rent: Decimal.new("1800.00"),
    property_id: city_penthouse.id,
    tenant_id: tenant2.id,
    notes: "Completed 1-year lease"
  })

IO.puts("Created Contract 4 (Expired: City Penthouse → Tenant2)")

# Create payments for Contract 4 (12 months, all paid, 2 late payments)
for month <- 1..12 do
  due_date = Contracts.calculate_due_date(contract4, month)

  # Months 7 and 12 were paid late (but month 12 has 50% chance of pending)
  delay =
    cond do
      month == 7 -> 7
      month == 12 -> 12
      true -> Enum.random(0..2)
    end

  submitted_at = DateTime.new!(due_date, ~T[11:00:00]) |> DateTime.add(delay, :day)

  if month == 12 && :rand.uniform() > 0.5 do
    # Pending - create payment but don't accept or reject
    {:ok, _payment} =
      Payments.create_payment(
        %Scope{user: tenant2},
        %{
          payment_number: month,
          amount: Decimal.new("1800.00"),
          contract_id: contract4.id,
          notes: "Rent for month #{month} - pending approval"
        }
      )

    # No accept/reject call - leaves it pending
  else
    {:ok, payment} =
      Payments.create_payment(
        %Scope{user: tenant2},
        %{
          payment_number: month,
          amount: Decimal.new("1800.00"),
          contract_id: contract4.id,
          notes: "Rent for month #{month}"
        }
      )

    Payments.accept_payment(demo_scope, payment)

    Repo.update_all(
      from(p in Payment, where: p.id == ^payment.id),
      set: [inserted_at: submitted_at, updated_at: submitted_at]
    )
  end
end

# Contract 5: Active - Property 5 (Cozy Studio) → Tenant3
# 2 months ago → 10 months future, rent $900, expires 5th
contract5_start = Date.add(today, -60)
contract5_end = Date.add(today, 300)

{:ok, contract5} =
  Contracts.create_contract(demo_scope, %{
    start_date: contract5_start,
    end_date: contract5_end,
    expiration_day: 5,
    rent: Decimal.new("900.00"),
    property_id: cozy_studio.id,
    tenant_id: tenant3.id,
    notes: "Budget-friendly studio"
  })

IO.puts("Created Contract 5 (Active: Cozy Studio → Tenant3)")

# Create payments for Contract 5
# Payment 1: accepted on time
# Payment 2: accepted, 1 day late
# Payment 3: pending (current month)
for month <- 1..2 do
  due_date = Contracts.calculate_due_date(contract5, month)
  delay = if month == 2, do: 1, else: 0
  submitted_at = DateTime.new!(due_date, ~T[08:00:00]) |> DateTime.add(delay, :day)

  {:ok, payment} =
    Payments.create_payment(
      %Scope{user: tenant3},
      %{
        payment_number: month,
        amount: Decimal.new("900.00"),
        contract_id: contract5.id,
        notes: "Rent for month #{month}"
      }
    )

  Payments.accept_payment(demo_scope, payment)

  Repo.update_all(
    from(p in Payment, where: p.id == ^payment.id),
    set: [inserted_at: submitted_at, updated_at: submitted_at]
  )
end

# Month 3 - 50% chance of pending for the latest payment
due_date_c5m3 = Contracts.calculate_due_date(contract5, 3)
submitted_at_c5m3 = DateTime.new!(due_date_c5m3, ~T[08:00:00])

if :rand.uniform() > 0.5 do
  # Pending - create payment but don't accept or reject
  {:ok, _payment} =
    Payments.create_payment(
      %Scope{user: tenant3},
      %{
        payment_number: 3,
        amount: Decimal.new("900.00"),
        contract_id: contract5.id,
        notes: "Rent for month 3 - pending approval"
      }
    )

  # No accept/reject call - leaves it pending
else
  {:ok, payment} =
    Payments.create_payment(
      %Scope{user: tenant3},
      %{
        payment_number: 3,
        amount: Decimal.new("900.00"),
        contract_id: contract5.id,
        notes: "Rent for month 3"
      }
    )

  Payments.accept_payment(demo_scope, payment)

  Repo.update_all(
    from(p in Payment, where: p.id == ^payment.id),
    set: [inserted_at: submitted_at_c5m3, updated_at: submitted_at_c5m3]
  )
end

# Contract 6: Upcoming - Property 6 (Suburban House) → Tenant1
# Starts in 2 months → 1 year future, rent $2500
contract6_start = Date.add(today, 60)
contract6_end = Date.add(today, 425)

{:ok, _contract6} =
  Contracts.create_contract(demo_scope, %{
    start_date: contract6_start,
    end_date: contract6_end,
    expiration_day: 10,
    rent: Decimal.new("2500.00"),
    property_id: suburban_house.id,
    tenant_id: tenant1.id,
    notes: "Family home lease starting soon"
  })

IO.puts("Created Contract 6 (Upcoming: Suburban House → Tenant1)")

# No payments for upcoming contract

# Summary statistics
IO.puts("\n" <> String.duplicate("=", 50))
IO.puts("SEEDING COMPLETED SUCCESSFULLY")
IO.puts(String.duplicate("=", 50))

user_count = Repo.aggregate(User, :count, :id)
property_count = Repo.aggregate(Property, :count, :id)
contract_count = Repo.aggregate(Contract, :count, :id)
payment_count = Repo.aggregate(Payment, :count, :id)

IO.puts("""
Summary:
  Users:      #{user_count}
  Properties: #{property_count}
  Contracts:  #{contract_count}
  Payments:   #{payment_count}

Demo Credentials:
  Email:    demo@example.com
  Password: demo12345678

Test Users:
  - tenant1@example.com / password123456
  - tenant2@example.com / password123456
  - tenant3@example.com / password123456

Contract Statuses:
  - Active (4 contracts): Various payment scenarios including rejected, partial, and pending payments
  - Expired (1 contract): Fully paid 12-month lease
  - Upcoming (1 contract): Not yet started

Payment Scenarios:
  - Most payments accepted and on time
  - Some late payments (1-12 days)
  - Rejected then re-accepted payment (Contract 1, month 5)
  - Partial payment split across two submissions (Contract 2, month 3)
  - Pending payments (50% chance for latest payment of each contract)
""")
