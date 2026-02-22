FROM node:22-bookworm-slim AS build

WORKDIR /app

COPY package.json ./
RUN npm install

# apps/backend/tsconfig.json extends ../../tsconfig.base.json.
# In container build context we materialize an equivalent file at /tsconfig.base.json.
RUN printf '%s\n' \
  '{' \
  '  "compilerOptions": {' \
  '    "target": "ES2022",' \
  '    "module": "NodeNext",' \
  '    "moduleResolution": "NodeNext",' \
  '    "strict": true,' \
  '    "skipLibCheck": true,' \
  '    "forceConsistentCasingInFileNames": true,' \
  '    "resolveJsonModule": true,' \
  '    "esModuleInterop": true,' \
  '    "verbatimModuleSyntax": true,' \
  '    "outDir": "dist"' \
  '  }' \
  '}' \
  > /tsconfig.base.json

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-bookworm-slim AS runtime

WORKDIR /app

ENV NODE_ENV=production

COPY package.json ./
RUN npm install --omit=dev

COPY --from=build /app/dist ./dist

EXPOSE 8080

CMD ["node", "dist/index.js"]
