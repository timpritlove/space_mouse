defmodule SpaceMouse.MixProject do
  use Mix.Project

  def project do
    [
      app: :space_mouse,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:native] ++ Mix.compilers(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SpaceMouse.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:usb, "~> 0.2.1"}
    ]
  end

  defp aliases do
    [
      "compile.native": &compile_native/1,
      "clean.native": &clean_native/1
    ]
  end

  defp compile_native(_) do
    case :os.type() do
      {:unix, :darwin} ->
        case System.cmd("bash", ["priv/platform/macos/build.sh"], 
                       into: IO.stream(:stdio, :line)) do
          {_, 0} -> 
            IO.puts("Native compilation successful")
          {_, exit_code} -> 
            raise("Native compilation failed with exit code #{exit_code}")
        end
        
      {:unix, :linux} ->
        # Future Linux support
        IO.puts("Linux native compilation not yet implemented")
        
      _ ->
        IO.puts("Native compilation not supported on this platform")
    end
  end
  
  defp clean_native(_) do
    priv_dir = "_build/#{Mix.env()}/lib/space_mouse/priv"
    if File.exists?(priv_dir) do
      File.rm_rf!(priv_dir)
      IO.puts("Cleaned native binaries")
    end
  end
end
