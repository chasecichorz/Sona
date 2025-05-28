@echo off
setlocal enabledelayedexpansion

:: Configure Git user
git config --global user.name "chasecichorz"
git config --global user.email "you@example.com"

:: Init and push repo
git init
git remote add origin https://github.com/chasecichorz/sona.git
git add .
git commit -m "Initial commit with full SONA project"
git branch -M main
git push -u origin main
pause
