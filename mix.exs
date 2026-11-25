defmodule Elixlsx.Mixfile do
  use Mix.Project

  @source_url "https://github.com/tmepple/elixlsx"
  @version "0.7.0"

  def project do
    [
      app: :elixlsx,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      description: "Elixlsx is a writer for the MS Excel OpenXML format (`.xlsx`).",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:xmerl]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:propcheck, "~> 1.4", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end

  defp docs do
    [
      extras: ["CHANGELOG.md", "README.md"],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      maintainers: ["Nikolai Weh <niko.weh@gmail.com>"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "https://hexdocs.pm/elixlsx/changelog.html",
        "GitHub" => @source_url
      }
    ]
  end
end
