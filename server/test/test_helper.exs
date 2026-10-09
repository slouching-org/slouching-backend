ExUnit.start()

Ecto.Migrator.run(SlouchingServer.Repo, :up, all: true, log: false)
