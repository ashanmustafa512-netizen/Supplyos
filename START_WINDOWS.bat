@echo off
setlocal
cd /d "%~dp0"
title SupplyOS - Local Website

echo.
echo ======================================
echo     SupplyOS - Local Website Runner
echo ======================================
echo.
where node >nul 2>nul
if errorlevel 1 (
  echo ERROR: Node.js is not installed or not on PATH.
  echo Install Node.js 22 LTS from https://nodejs.org/ then reopen this folder.
  pause
  exit /b 1
)
node -e "const [a,b]=process.versions.node.split('.').map(Number);process.exit(a>20||(a===20&&b>=9)?0:1)"
if errorlevel 1 (
  echo ERROR: This project needs Node.js 20.9 or newer. Node.js 22 LTS is recommended.
  node -v
  pause
  exit /b 1
)
node -v
if not exist "node_modules" (
  echo.
  echo First run: installing website dependencies from npm. Internet is required.
  call npm install --no-audit --no-fund
  if errorlevel 1 (
    echo.
    echo ERROR: Dependency installation failed. Check internet access and run npm install manually.
    pause
    exit /b 1
  )
)
if not exist ".env.local" (
  echo.
  echo NOTE: .env.local is not present. The server can still start and will show /setup.
  echo Add your Supabase URL and publishable key to .env.local to enable login and data.
)
echo.
echo Starting SupplyOS at http://localhost:3000
echo Leave this window open while using the website. Press Ctrl+C to stop it.
echo.
call npm run dev
if errorlevel 1 (
  echo.
  echo The server stopped with an error. Read the messages above and see START_HERE.md.
  pause
)
endlocal
