ExUnit.start()

repo = Application.fetch_env!(:slouching_server, :repo_module)
Ecto.Migrator.run(repo, :up, all: true, log: false)
