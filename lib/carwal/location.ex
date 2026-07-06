defmodule CarWal.Location do
  @moduledoc """
  Live-location context. Persists nothing, ever (AD-8): shares and
  positions live only in process state / Phoenix.Presence. No Ecto
  schema, no table, no log line containing coordinates.
  """
end
