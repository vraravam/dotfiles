# IEx.configure colors: [enabled: true]
# IEx.configure colors: [ eval_result: [ :cyan, :bright ] ]

# Note: Put these 2 lines in each specific project's `.iex.exs` file
# global_settings = System.get_env("HOME") <> "/.iex.exs"
# if File.exists?(global_settings), do: Code.require_file(global_settings)

IO.puts IO.ANSI.red_background() <> IO.ANSI.white() <> " ❄❄❄ Good Luck with Elixir ❄❄❄ " <> IO.ANSI.reset

Application.put_env(:elixir, :ansi_enabled, true)

IEx.configure(
 colors: [
   eval_result: [:cyan, :bright] ,
   eval_error: [[:red,:bright,"\n▶▶▶Bug Bug ..!!\n"]],
   eval_info: [:yellow, :bright ],
 ],
 default_prompt: [
   "\e[G",    # ANSI CHAR, move cursor to column 1
    :white,
    "I",
    :red,
    "❤" ,       # plain string
    :green,
    "%prefix", :white, " | ",
    :yellow,
    "%counter", :white, " | ",
    :red,
    "▶" ,         # plain string
    :yellow,
    "❤ ❤-»",  # plain string
    :reset
  ] |> IO.ANSI.format |> IO.chardata_to_string
)
