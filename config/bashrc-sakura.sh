# ✿ sakura mono
export EDITOR=nano
alias ll='ls -lah --color=auto --group-directories-first'
alias ff='fastfetch'
alias update='sudo pacman -Syu'
HISTSIZE=10000; HISTCONTROL=ignoreboth:erasedups; shopt -s histappend autocd
[[ "$TERM" == "xterm-kitty" && -z "$NO_FETCH" ]] && fastfetch
eval "$(starship init bash)"

# ✿ terminal eye candy (type "fun" for the list)
alias vis='cava'
alias matrix='cmatrix -b -u 3 -C magenta'
alias clock='tty-clock -c -s -b -C 5'
alias bonsai='cbonsai -l -i -t 0.04'
alias pipes='pipes.sh -t 1 -c 5 -c 13 -c 7 -p 3 -r 3000'
alias aquarium='asciiquarium'
alias nyan='nyancat'
alias train='sl -e'
hello() { figlet -f slant "${*:-sakura}" | lolcat -p 0.8; }
fun() {
  printf '\n  \e[35m✿ terminal toys\e[0m\n\n'
  printf '  \e[1mvis\e[0m       music visualizer (play something!)\n'
  printf '  \e[1mmatrix\e[0m    pink matrix rain\n'
  printf '  \e[1mclock\e[0m     big clock\n'
  printf '  \e[1mbonsai\e[0m    a bonsai tree grows\n'
  printf '  \e[1mpipes\e[0m     pipes screensaver\n'
  printf '  \e[1maquarium\e[0m  fish tank\n'
  printf '  \e[1mnyan\e[0m      nyan cat\n'
  printf '  \e[1mtrain\e[0m     steam train\n'
  printf '  \e[1mhello\e[0m     big rainbow text: hello anything\n'
  printf '  \e[1mff\e[0m        fastfetch\n\n  quit any of them with q or Ctrl+C\n\n'
}
