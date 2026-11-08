@echo off
title Deploy Grimorio su Cloudflare Pages
echo ========================================================
echo   Aggiornamento file di produzione nella cartella dist...
echo ========================================================
call npm run build

echo.
echo ========================================================
echo   Pubblicazione della nuova versione su Cloudflare Pages...
echo ========================================================
npx wrangler pages deploy dist
echo.
echo Operazione completata.
pause
