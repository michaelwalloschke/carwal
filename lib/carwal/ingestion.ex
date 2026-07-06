defmodule CarWal.Ingestion do
  @moduledoc """
  Context owning feed state (AD-1): iCal + IMAP pollers, occurrence
  materialization (AD-5), idempotent diffed upserts (AD-6).

  Writes entries only via the `CarWal.Entries` public API — never its
  tables directly.
  """
end
