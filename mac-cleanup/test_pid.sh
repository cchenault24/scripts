#!/bin/zsh

echo "Parent PID: $$"

result=$(echo "Subshell PID: $$")
echo "$result"
