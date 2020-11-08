Set-StrictMode -Version Latest

choco upgrade -y all
vagrant plugin update

nodist + 10
nodist + 12
nodist + 14
nodist + 15
nodist global 15

npm install -g npm@latest
npm upgrade -g
npm install -g windows-build-tools@latest yarn@latest
