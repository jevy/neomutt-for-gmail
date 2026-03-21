{ writeShellApplication, goobook, notmuch, gawk, coreutils, fzf, gnugrep }:
writeShellApplication {
  name = "query-contacts";
  runtimeInputs = [ goobook notmuch gawk coreutils fzf gnugrep ];
  text = builtins.readFile ./query-contacts.sh;
}
