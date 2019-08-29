Set-StrictMode -Version Latest

choco upgrade -y all

nodist + 8
nodist + 10
nodist + 12
nodist global 12

npm install -g npm@latest
npm upgrade -g
npm install -g @aws-amplify/cli@latest exp@latest serverless@latest windows-build-tools@latest yarn@latest
