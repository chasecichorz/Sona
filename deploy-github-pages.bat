@echo off
setlocal

echo Pushing GitHub Pages site from /docs...

git checkout -B gh-pages
git add docs
git commit -m "Deploy SONA Linux site to GitHub Pages"
git push origin gh-pages --force

echo Done. Your site should be live shortly at:
echo https://chasecichorz.github.io/sona/
pause
