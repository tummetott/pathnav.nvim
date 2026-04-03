docs:
    nvim -N -u NONE -i NONE -n -E -s -V1 -c "helptags $(pwd)/doc" +quit!

list:
    @just --list
