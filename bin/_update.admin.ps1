Set-StrictMode -Version Latest

choco upgrade -y all

nodist + 8
nodist + 10
nodist + 12
nodist global 12

npm upgrade -g
npm install -g npm
npm install -g exp serverless windows-build-tools yarn
