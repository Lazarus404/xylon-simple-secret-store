defmodule XylonSimpleSecretStore.MixProject do
  use Mix.Project

  def project do
    [
      app: :xylon_simple_secret_store,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Disposable ETS shared-secret store for Xylon lab demos."
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {XylonSimpleSecretStore.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.6"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"}
    ]
  end
end
