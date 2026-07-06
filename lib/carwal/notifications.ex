defmodule CarWal.Notifications do
  @moduledoc """
  Context owning `push_subscriptions` (AD-1). Sole sender of Web Push
  (AD-7): seeded role-default routing, minimal payloads, one pipeline
  keyed `(user_id, endpoint)` per device (AD-13). Schema lands in
  Story 1.4.
  """
end
