# Old base image ON PURPOSE: gives the image scans OS-package findings.
FROM node:18.12.0-alpine3.16
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts
COPY src ./src
CMD ["node", "src/index.js"]
